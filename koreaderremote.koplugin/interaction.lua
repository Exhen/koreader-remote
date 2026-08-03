-- KOReader Remote interaction bridge.
--
-- Adds remote note editing to KOReader's highlight dialog and exposes a
-- conservative "open next footnote" action for reflowable documents.

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local mime = require("mime")
local _ = require("gettext")

local Interaction = {}
Interaction.__index = Interaction

local MAX_NOTE_BYTES = 12 * 1024
local MAX_BOOKMARK_ITEMS = 300
local MAX_BOOKMARK_EXCERPT_BYTES = 1200
local MAX_BOOKMARK_NOTE_BYTES = 3000
local MAX_TOC_ITEMS = 800
local MAX_TOC_TITLE_BYTES = 400
local NOTE_SESSION_TTL_SECONDS = 30 * 60
local HIGHLIGHT_ACTION_ID = "04a_koreader_remote_note"
local session_counter = 0

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function speechFingerprint(value)
    local text = tostring(value or "")
    if text == "" then
        return "0"
    end

    local hash = 5381
    for index = 1, #text do
        hash = (hash * 33 + string.byte(text, index)) % 2147483647
    end
    return tostring(hash)
end

local function utf8Prefix(value, maximum_bytes)
    value = tostring(value or "")

    if #value <= maximum_bytes then
        return value
    end

    local boundary = maximum_bytes
    while boundary > 0 do
        local byte = value:byte(boundary)
        if not byte or byte < 0x80 or byte >= 0xC0 then
            break
        end
        boundary = boundary - 1
    end

    if boundary <= 0 then
        return "…"
    end

    return value:sub(1, boundary - 1) .. "…"
end

local function annotationType(ui, annotation)
    if ui.bookmark and ui.bookmark.getBookmarkType then
        return ui.bookmark.getBookmarkType(annotation)
    end

    if annotation.drawer then
        return annotation.note and "note" or "highlight"
    end

    return "bookmark"
end

local function basename(path)
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "")
end

local function annotationIdentity(index, ui, annotation)
    local source = table.concat({
        tostring(index),
        tostring(annotation.datetime or ""),
        tostring(annotation.datetime_updated or ""),
        tostring(annotation.page or ""),
        tostring(annotation.pos0 or ""),
        tostring(annotation.pos1 or ""),
        annotationType(ui, annotation),
    }, "\0")

    -- This token only detects that the list changed between loading and
    -- tapping an item; it is not an authentication token.
    local hash = 5381
    for position = 1, #source do
        hash = (hash * 33 + source:byte(position)) % 4294967296
    end

    return string.format("%d-%08x", index, hash)
end

local function decodeBase64(encoded)
    encoded = trim(encoded)

    -- An empty Base64 value represents an empty note. This is needed so a
    -- phone can clear an existing note intentionally.
    if encoded == "" then
        return ""
    end

    if #encoded % 4 ~= 0 then
        return nil, "The encoded note is invalid."
    end

    local data = encoded
    local padding_count = 0
    local first_padding = encoded:find("=", 1, true)

    if first_padding then
        local padding = encoded:sub(first_padding)

        if padding ~= "=" and padding ~= "==" then
            return nil, "The encoded note contains invalid padding."
        end

        data = encoded:sub(1, first_padding - 1)
        padding_count = #padding
    end

    if data:find("[^A-Za-z0-9+/]") then
        return nil, "The encoded note contains invalid characters."
    end

    local ok, decoded = pcall(mime.unb64, encoded)
    if not ok or type(decoded) ~= "string" then
        return nil, "The encoded note could not be decoded."
    end

    local expected_bytes = (#encoded / 4) * 3 - padding_count
    if #decoded ~= expected_bytes then
        return nil, "The encoded note has an invalid length."
    end

    return decoded
end

function Interaction:new(options)
    options = options or {}

    local instance = setmetatable({}, self)
    instance.get_owner = assert(options.get_owner)
    instance.ensure_server = options.ensure_server
    instance.session = nil
    instance.bookmark_return = nil
    instance.footnote_page_key = nil
    instance.footnote_cursor = 0

    return instance
end

function Interaction:getUI()
    local owner = self.get_owner()
    return owner and owner.ui or nil
end

function Interaction:getCapabilities()
    local ui = self:getUI()
    local notes = ui ~= nil
        and ui.document ~= nil
        and ui.highlight ~= nil
        and ui.annotation ~= nil
        and ui.bookmark ~= nil

    local footnotes = ui ~= nil
        and ui.document ~= nil
        and ui.rolling ~= nil
        and ui.link ~= nil
        and type(ui.document.getPageLinks) == "function"
        and type(ui.link.showAsFootnotePopup) == "function"

    local toc = ui ~= nil
        and ui.document ~= nil
        and ui.toc ~= nil
        and type(ui.toc.fillToc) == "function"

    local page_text = ui ~= nil
        and ui.document ~= nil
        and (
            type(ui.document.getTextFromPositions) == "function"
            or type(ui.document.getTextBoxes) == "function"
            or type(ui.document.getTextFromXPointers) == "function"
            or type(ui.document.getPageXPointer) == "function"
        )

    local book_cover = ui ~= nil
        and ui.document ~= nil
        and (
            type(ui.document.getCoverPageImage) == "function"
            or ui.document.file ~= nil
        )

    return {
        remote_notes = notes,
        bookmarks = notes,
        footnotes = footnotes,
        toc = toc,
        remote_input = true,
        page_text = page_text,
        page_text_peek = page_text,
        tts = page_text,
        book_cover = book_cover,
        page_jump = ui ~= nil and ui.document ~= nil,
    }
end

function Interaction:showNoteActionError(err)
    logger.err(
        "KOReaderRemote: remote note action failed:",
        tostring(err)
    )

    UIManager:show(InfoMessage:new{
        text = _(
            "The remote note could not be prepared.\n\n"
            .. "KOReader Remote stayed active. Please try again after "
            .. "reopening the book."
        ),
    })
end

function Interaction:runNoteAction(callback)
    local ok, result = xpcall(callback, debug.traceback)

    if not ok then
        self:showNoteActionError(result)
        return false
    end

    return result ~= false
end

function Interaction:startNewNoteSession(highlight)
    local function startSavedNote(saved_index)
        return self:runNoteAction(function()
            if not saved_index then
                UIManager:show(InfoMessage:new{
                    text = _(
                        "The selected text could not be saved as a highlight."
                    ),
                })
                return false
            end

            return self:startNoteSession(
                highlight,
                saved_index,
                true
            )
        end)
    end

    -- Older and development KOReader builds may still expose the optional
    -- highlight prompt callback. KOReader 2026.03 saves highlights directly,
    -- so support both interfaces.
    if type(highlight.showHighlightPrompt) == "function" then
        highlight:showHighlightPrompt(function(saved_index)
            startSavedNote(saved_index)
        end)
        return true
    end

    if type(highlight.saveHighlight) ~= "function" then
        error("KOReader does not expose a compatible highlight save method.")
    end

    local saved_index = highlight:saveHighlight(true)

    if type(highlight.onClose) == "function" then
        highlight:onClose()
    end

    return startSavedNote(saved_index)
end

function Interaction:attachUI(ui)
    if not ui or not ui.highlight or not ui.highlight.addToHighlightDialog then
        return false
    end

    if ui.highlight._koreader_remote_note_action then
        return true
    end

    local bridge = self

    ui.highlight:addToHighlightDialog(
        HIGHLIGHT_ACTION_ID,
        function(highlight, index)
            local has_selection = highlight.selected_text ~= nil
                and highlight.selected_text.pos0 ~= nil
                and highlight.selected_text.pos1 ~= nil

            return {
                text = index and _("Edit note on phone")
                    or _("Write note on phone"),
                enabled = index ~= nil or has_selection,
                callback = function()
                    bridge:runNoteAction(function()
                        if index then
                            local started = bridge:startNoteSession(
                                highlight,
                                index,
                                false
                            )

                            if started
                                and type(highlight.onClose) == "function" then
                                highlight:onClose(true)
                            end

                            return started
                        end

                        return bridge:startNewNoteSession(highlight)
                    end)
                end,
            }
        end
    )

    ui.highlight._koreader_remote_note_action = true
    return true
end

function Interaction:findAnnotationIndex(ui, annotation)
    if not ui or not ui.annotation or not ui.annotation.annotations then
        return nil
    end

    for index, candidate in ipairs(ui.annotation.annotations) do
        if candidate == annotation then
            return index
        end
    end
end

function Interaction:refreshSessionDraft(session_id)
    local session = self.session

    if not session or (session_id and session.id ~= session_id) then
        return nil, "NO_NOTE_SESSION", "No note is selected on the reader."
    end

    local dialog = session.input_dialog
    if not dialog or type(dialog.getInputText) ~= "function" then
        return nil,
            "NOTE_DIALOG_CLOSED",
            "The Kindle note editor is no longer open."
    end

    local ok, draft = pcall(dialog.getInputText, dialog)
    if not ok then
        return nil,
            "NOTE_DIALOG_CLOSED",
            "The Kindle note editor could not be read."
    end

    draft = tostring(draft or "")

    if draft ~= session.last_draft then
        session.last_draft = draft
        session.revision = session.revision + 1
        session.updated_at = os.time()
        session.expires_at = session.updated_at + NOTE_SESSION_TTL_SECONDS
    end

    return session
end

function Interaction:closeNoteDialog(session)
    local dialog = session and session.input_dialog
    if not dialog then
        return
    end

    session.input_dialog = nil

    local ok, err = pcall(function()
        UIManager:close(dialog, "flashui")
    end)

    if not ok then
        logger.warn(
            "KOReaderRemote: could not close remote note dialog:",
            err
        )
    end
end

function Interaction:discardNewHighlight(session)
    if not session or not session.is_new_note or session.saved then
        return
    end

    local index = self:findAnnotationIndex(session.ui, session.annotation)
    if not index then
        return
    end

    local bookmark = session.ui and session.ui.bookmark
    if bookmark and type(bookmark.removeItemByIndex) == "function" then
        bookmark:removeItemByIndex(index)
    end
end

function Interaction:cancelNoteSession(reason, close_dialog, discard_new)
    local session = self.session
    if not session then
        return false
    end

    logger.info(
        "KOReaderRemote: closing note session",
        session.id,
        reason or "cancelled"
    )

    self.session = nil

    if close_dialog then
        self:closeNoteDialog(session)
    end

    if discard_new then
        self:discardNewHighlight(session)
    end

    self.last_note_result = {
        result = "cancelled",
        at = os.time(),
    }

    return true
end

function Interaction:onUIClosed(ui)
    if self.session and self.session.ui == ui then
        self:cancelNoteSession(
            "document closed",
            false,
            true
        )
    end

    if self.bookmark_return and self.bookmark_return.ui == ui then
        self.bookmark_return = nil
    end
end

function Interaction:openNoteDialog(session)
    local bridge = self
    local session_id = session.id
    local input_dialog

    input_dialog = InputDialog:new{
        title = _("Remote note"),
        description = _(
            "Type here or continue in KOReader Remote on your phone."
        ),
        input = session.last_draft,
        allow_newline = true,
        add_scroll_buttons = true,
        use_available_height = true,
        edited_callback = function()
            bridge:refreshSessionDraft(session_id)
        end,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        bridge:runNoteAction(function()
                            bridge:cancelNoteSession(
                                "cancelled on Kindle",
                                true,
                                true
                            )
                            return true
                        end)
                    end,
                },
                {
                    text = _("Paste"),
                    callback = function()
                        input_dialog:addTextToInput(
                            session.annotation.text or ""
                        )
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        bridge:runNoteAction(function()
                            local ok, result, message =
                                bridge:saveNoteSession(
                                    nil,
                                    session_id,
                                    "kindle"
                                )

                            if not ok then
                                UIManager:show(InfoMessage:new{
                                    text = message
                                        or _("The note could not be saved."),
                                })
                            end

                            return ok
                        end)
                    end,
                },
            },
        },
    }

    session.input_dialog = input_dialog
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Interaction:startNoteSession(highlight, index, is_new_note)
    if self.session then
        self:cancelNoteSession("replaced", true, true)
    end

    local ui = highlight and highlight.ui
    local annotations = ui
        and ui.annotation
        and ui.annotation.annotations
    local annotation = annotations and annotations[index]

    if not annotation then
        UIManager:show(InfoMessage:new{
            text = _("The selected note is no longer available."),
        })
        return false
    end

    session_counter = session_counter + 1
    local now = os.time()

    self.last_note_result = nil
    self.session = {
        id = string.format("%x-%x", now, session_counter),
        ui = ui,
        highlight = highlight,
        annotation = annotation,
        document_file = ui.document and ui.document.file,
        created_at = now,
        updated_at = now,
        expires_at = now + NOTE_SESSION_TTL_SECONDS,
        revision = 1,
        last_draft = annotation.note or "",
        saved_note = annotation.note or "",
        saved_note_present = annotation.note ~= nil,
        type_before = annotationType(ui, annotation),
        is_new_note = is_new_note == true,
        saved = false,
    }

    if self.ensure_server then
        local ok, err = pcall(self.ensure_server)
        if not ok then
            logger.warn(
                "KOReaderRemote: could not ensure note server:",
                err
            )
        end
    end

    self:openNoteDialog(self.session)
    return true
end

function Interaction:resolveSession()
    local session = self.session
    if not session then
        return nil, "NO_NOTE_SESSION", "No note is selected on the reader."
    end

    if os.time() > session.expires_at then
        self:cancelNoteSession("expired", true, true)
        return nil, "NOTE_SESSION_EXPIRED", "The note session expired."
    end

    local ui = self:getUI()
    if not ui
        or ui ~= session.ui
        or not ui.document
        or ui.document.file ~= session.document_file then
        self:cancelNoteSession("document changed", false, true)
        return nil,
            "NO_NOTE_SESSION",
            "The selected document is no longer open."
    end

    local index = self:findAnnotationIndex(ui, session.annotation)
    if not index then
        self:cancelNoteSession("annotation removed", true, false)
        return nil, "NO_NOTE_SESSION", "The selected note no longer exists."
    end

    session.index = index

    local refreshed, code, message = self:refreshSessionDraft(session.id)
    if not refreshed then
        self:cancelNoteSession("dialog closed", false, true)
        return nil, code, message
    end

    local current_saved_note = session.annotation.note or ""
    local current_saved_present = session.annotation.note ~= nil

    if current_saved_note ~= session.saved_note
        or current_saved_present ~= session.saved_note_present then
        session.saved_note = current_saved_note
        session.saved_note_present = current_saved_present
        session.revision = session.revision + 1
        session.updated_at = os.time()
    end

    return session
end

function Interaction:sessionState(session)
    if not session then
        local result = self.last_note_result
        if result and os.time() - result.at <= 30 then
            return {
                active = false,
                result = result.result,
            }
        end

        return {
            active = false,
        }
    end

    return {
        active = true,
        id = session.id,
        excerpt = utf8Prefix(session.annotation.text or "", 2200),
        note = session.last_draft,
        draft = session.last_draft,
        saved_note = session.saved_note,
        revision = session.revision,
        has_note = session.last_draft ~= "",
        has_saved_note = session.saved_note_present,
        dirty = session.last_draft ~= session.saved_note
            or (session.last_draft == "" and session.saved_note_present),
        expires_in = math.max(0, session.expires_at - os.time()),
    }
end

function Interaction:getNoteSessionState()
    local session = self:resolveSession()
    return self:sessionState(session)
end

function Interaction:decodeAndValidateNote(encoded)
    if type(encoded) ~= "string" then
        return nil, "MISSING_NOTE", "The note header is missing."
    end

    if #encoded > math.ceil(MAX_NOTE_BYTES / 3) * 4 + 8 then
        return nil, "NOTE_TOO_LARGE", "The note is too large."
    end

    local note, decode_err = decodeBase64(encoded)
    if not note then
        return nil, "INVALID_NOTE", decode_err
    end

    if #note > MAX_NOTE_BYTES then
        return nil,
            "NOTE_TOO_LARGE",
            string.format(
                "Notes are limited to %d bytes.",
                MAX_NOTE_BYTES
            )
    end

    if note:find("%z") then
        return nil,
            "INVALID_NOTE",
            "The note must not contain NUL characters."
    end

    return note
end

function Interaction:pushEncodedNote(encoded, expected_revision)
    local note, decode_code, decode_message =
        self:decodeAndValidateNote(encoded)

    if note == nil then
        return false, decode_code, decode_message
    end

    local session, code, message = self:resolveSession()
    if not session then
        return false, code, message
    end

    expected_revision = tonumber(expected_revision)
    if not expected_revision
        or expected_revision ~= session.revision then
        return false,
            "NOTE_CONFLICT",
            "The Kindle draft changed. Pull the latest version first.",
            self:sessionState(session)
    end

    local dialog = session.input_dialog
    local ok, set_err = pcall(
        dialog.setInputText,
        dialog,
        note,
        true,
        false
    )

    if not ok then
        return false,
            "NOTE_DIALOG_CLOSED",
            "The Kindle note editor could not be updated: "
                .. tostring(set_err)
    end

    session.last_draft = note
    session.revision = session.revision + 1
    session.updated_at = os.time()
    session.expires_at = session.updated_at + NOTE_SESSION_TTL_SECONDS

    return true, self:sessionState(session)
end

function Interaction:commitNoteSession(session, source)
    local ui = session.ui
    local annotation = session.annotation
    local value = session.last_draft ~= "" and session.last_draft or nil
    local type_before = session.type_before

    session.highlight:writePdfAnnotation(
        "content",
        annotation,
        value or ""
    )

    annotation.note = value
    local type_after = annotationType(ui, annotation)
    local event_payload = {
        annotation,
        index_modified = session.index,
    }

    if type_before ~= type_after then
        if type_before == "highlight" then
            event_payload.nb_highlights_added = -1
            event_payload.nb_notes_added = 1
        else
            event_payload.nb_highlights_added = 1
            event_payload.nb_notes_added = -1
        end
    end

    ui:handleEvent(Event:new("AnnotationsModified", event_payload))

    if session.highlight.view
        and session.highlight.view.highlight
        and session.highlight.view.highlight.note_mark then
        UIManager:setDirty(session.highlight.dialog, "ui")
    end

    session.saved = true
    session.saved_note = value or ""
    session.saved_note_present = value ~= nil
    self.session = nil
    self.last_note_result = {
        result = "saved",
        at = os.time(),
    }

    self:closeNoteDialog(session)

    UIManager:show(Notification:new{
        text = source == "phone"
            and _("Note saved from phone.")
            or _("Note saved."),
    })

    return {
        active = false,
        result = "saved",
    }
end

function Interaction:saveNoteSession(
    expected_revision,
    session_id,
    source
)
    local session, code, message = self:resolveSession()
    if not session then
        return false, code, message
    end

    if session_id and session.id ~= session_id then
        return false,
            "NOTE_CONFLICT",
            "A different note is now open on the reader.",
            self:sessionState(session)
    end

    if expected_revision ~= nil then
        expected_revision = tonumber(expected_revision)

        if not expected_revision
            or expected_revision ~= session.revision then
            return false,
                "NOTE_CONFLICT",
                "The Kindle draft changed. Pull the latest version first.",
                self:sessionState(session)
        end
    end

    return true, self:commitNoteSession(session, source)
end


function Interaction:getBookTitle(ui)
    if ui and ui.doc_props and ui.doc_props.display_title then
        return tostring(ui.doc_props.display_title)
    end

    return basename(ui and ui.document and ui.document.file)
end

--- Export current book cover as PNG bytes for lock-screen / Now Playing artwork.
function Interaction:getBookCoverImageBytes()
    local ui = self:getUI()
    if not ui or not ui.document then
        return false, "NO_DOCUMENT_OPEN"
    end

    local file = ui.document.file
    local cover_bb = nil
  local owned_bb = nil

    local ok_custom, custom_cover = pcall(function()
        local DocSettings = require("docsettings")
        return DocSettings:findCustomCoverFile(file)
    end)
    if ok_custom and custom_cover then
        local ok_doc, DocumentRegistry = pcall(require, "document/documentregistry")
        if ok_doc then
            local cover_doc = DocumentRegistry:openDocument(custom_cover)
            if cover_doc then
                local ok_img, bb = pcall(function()
                    return cover_doc:getCoverPageImage()
                end)
                if ok_img and bb then
                    cover_bb = bb
                    owned_bb = bb
                end
                cover_doc:close()
            end
        end
    end

    if not cover_bb and type(ui.document.getCoverPageImage) == "function" then
        local ok_img, bb = pcall(function()
            return ui.document:getCoverPageImage()
        end)
        if ok_img and bb then
            cover_bb = bb
            owned_bb = bb
        end
    end

    if not cover_bb and file then
        local ok_doc, DocumentRegistry = pcall(require, "document/documentregistry")
        if ok_doc then
            local doc = DocumentRegistry:openDocument(file)
            if doc then
                if type(doc.loadDocument) == "function" then
                    pcall(doc.loadDocument, doc, false)
                end
                local ok_img, bb = pcall(function()
                    return doc:getCoverPageImage()
                end)
                if ok_img and bb then
                    cover_bb = bb
                    owned_bb = bb
                end
                doc:close()
            end
        end
    end

    if not cover_bb then
        return false, "NO_COVER"
    end

    local max_dim = 512
    local w = cover_bb:getWidth()
    local h = cover_bb:getHeight()
    local bb = cover_bb
    if w > max_dim or h > max_dim then
        local ok_scale, RenderImage = pcall(require, "ui/renderimage")
        if ok_scale then
            local scale = math.min(max_dim / w, max_dim / h)
            local scaled = RenderImage:scaleBlitBuffer(
                cover_bb,
                math.max(1, math.floor(w * scale)),
                math.max(1, math.floor(h * scale))
            )
            if scaled then
                bb = scaled
                if owned_bb then
                    owned_bb:free()
                    owned_bb = nil
                end
                owned_bb = scaled
            end
        end
    end

    local DataStorage = require("datastorage")
    local util = require("util")
    local cache_dir = DataStorage:getDataDir() .. "/cache"
    util.makePath(cache_dir)
    local tmp = string.format(
        "%s/koreaderremote_cover_%d_%d.png",
        cache_dir,
        os.time(),
        math.random(10000, 99999)
    )

    local written = false
    if type(bb.writeToFile) == "function" then
        written = bb:writeToFile(tmp, "png", 85) == true
    else
        local ok_device, Device = pcall(require, "device")
        if ok_device
            and Device.screen
            and Device.screen.bb
            and type(Device.screen.bb.writePNG) == "function" then
            written = Device.screen.bb:writePNG(tmp, false, bb) == true
        end
    end

    if owned_bb then
        owned_bb:free()
        owned_bb = nil
    end

    if not written or not util.pathExists(tmp) then
        return false, "ENCODE_FAILED"
    end

    local fh = io.open(tmp, "rb")
    if not fh then
        os.remove(tmp)
        return false, "READ_FAILED"
    end
    local bytes = fh:read("*a")
    fh:close()
    os.remove(tmp)

    if not bytes or #bytes == 0 then
        return false, "EMPTY_COVER"
    end

    return true, bytes
end

function Interaction:getBookmarkPageLabel(ui, annotation)
    if annotation.pageref ~= nil and annotation.pageref ~= "" then
        return tostring(annotation.pageref)
    end

    if annotation.pageno ~= nil and annotation.pageno ~= "" then
        return tostring(annotation.pageno)
    end

    if ui.bookmark
        and type(ui.bookmark.getBookmarkPageString) == "function" then
        local ok, page = pcall(
            ui.bookmark.getBookmarkPageString,
            ui.bookmark,
            annotation.page
        )

        if ok and page ~= nil then
            return tostring(page)
        end
    end

    return tostring(annotation.page or "")
end

function Interaction:getCurrentReadingPage(ui, location)
    if ui.rolling and type(location) == "table" and location.xpointer then
        return tostring(location.xpointer)
    end

    if ui.paging and type(location) == "table"
        and location[1] and location[1].page ~= nil then
        return tostring(location[1].page)
    end

    if ui.rolling and type(location) == "table"
        and location.xpointer
        and ui.document
        and type(ui.document.getPageFromXPointer) == "function" then
        local ok, page = pcall(
            ui.document.getPageFromXPointer,
            ui.document,
            location.xpointer
        )

        if ok and page ~= nil then
            return tostring(page)
        end
    end

    local ok, page = pcall(function()
        return ui.document:getCurrentPage()
    end)

    return ok and page ~= nil and tostring(page) or ""
end

function Interaction:getDisplayPageNumber(ui, location)
    if ui.paging and type(location) == "table"
        and location[1] and location[1].page ~= nil then
        return tostring(location[1].page)
    end

    if ui.rolling and type(location) == "table"
        and location.xpointer
        and ui.document
        and type(ui.document.getPageFromXPointer) == "function" then
        local ok, page = pcall(
            ui.document.getPageFromXPointer,
            ui.document,
            location.xpointer
        )
        if ok and page ~= nil then
            return tostring(page)
        end
    end

    local ok, page = pcall(function()
        return ui.document:getCurrentPage()
    end)

    return ok and page ~= nil and tostring(page) or ""
end

function Interaction:getPageJumpInfo()
    local ui = self:getUI()
    if not ui or not ui.document then
        return false, "NO_DOCUMENT_OPEN"
    end

    local snap_ok, snap = self:getReadingSnapshot()
    if not snap_ok then
        return false, "NO_DOCUMENT_OPEN"
    end

    local current_page = tonumber(snap.page) or tonumber(snap.page_key)
    local page_count = nil
    if type(ui.document.getPageCount) == "function" then
        local ok, count = pcall(ui.document.getPageCount, ui.document)
        if ok and type(count) == "number" and count > 0 then
            page_count = math.floor(count)
        end
    end

    return true, {
        current_page = current_page,
        page_count = page_count,
        page_label = snap.page,
        page_key = snap.page_key,
    }
end

function Interaction:gotoPageNumber(page_number)
    local ui = self:getUI()
    if not ui or not ui.document then
        return false, "NO_DOCUMENT_OPEN", "Open a book on the reader first."
    end

    page_number = tonumber(page_number)
    if not page_number or page_number < 1 or page_number % 1 ~= 0 then
        return false,
            "INVALID_PAGE",
            "Enter a positive whole page number."
    end
    page_number = math.floor(page_number)

    if type(ui.document.getPageCount) == "function" then
        local ok, count = pcall(ui.document.getPageCount, ui.document)
        if ok and type(count) == "number" and page_number > count then
            return false,
                "PAGE_OUT_OF_RANGE",
                string.format(
                    "Page %d is beyond the end (%d).",
                    page_number,
                    count
                )
        end
    end

    local before_ok, before = self:getReadingSnapshot()
    local before_key = before_ok and before.page_key or nil

    local ok, err = pcall(ui.handleEvent, ui, Event:new("GotoPage", page_number))
    if not ok then
        logger.err("KOReaderRemote: page jump failed:", err)
        return false,
            "GOTO_FAILED",
            "KOReader could not jump to that page."
    end

    local after_ok, after = self:getReadingSnapshot()
    if after_ok and before_key and after.page_key == before_key then
        -- Reflowable books may still move without changing page_key; accept if label changed.
        local before_label = before_ok and tostring(before.page or "") or ""
        local after_label = tostring(after.page or "")
        if before_label ~= "" and before_label == after_label then
            return false,
                "GOTO_FAILED",
                "The reader did not move to the requested page."
        end
    end

    if after_ok then
        return true, {
            action = "page_jump",
            page = after.page,
            page_key = after.page_key,
            target = page_number,
        }
    end

    return true, {
        action = "page_jump",
        target = page_number,
    }
end

function Interaction:getReadingSnapshot()
    local ui = self:getUI()
    if not ui or not ui.document then
        return false, "NO_DOCUMENT_OPEN"
    end

    local location = nil
    if ui.link and type(ui.link.getCurrentLocation) == "function" then
        local ok, value = pcall(ui.link.getCurrentLocation, ui.link)
        if ok then
            location = value
        end
    end

    local page_key = self:getCurrentReadingPage(ui, location)
    local display_page = self:getDisplayPageNumber(ui, location)
    local ok, result = self:getCurrentPageText()
    if not ok then
        return true, {
            page_key = page_key,
            page = display_page ~= "" and display_page or page_key,
            content_hash = "0",
            empty = true,
        }
    end

    return true, {
        page_key = result.page_key,
        page = result.page,
        content_hash = result.content_hash or "0",
        empty = result.empty == true,
    }
end

--- Lightweight position for polling (no page-text extraction).
function Interaction:getReadingPosition()
    local ui = self:getUI()
    if not ui or not ui.document then
        return false, "NO_DOCUMENT_OPEN"
    end

    local location = nil
    if ui.link and type(ui.link.getCurrentLocation) == "function" then
        local ok, value = pcall(ui.link.getCurrentLocation, ui.link)
        if ok then
            location = value
        end
    end

    local page_key = self:getCurrentReadingPage(ui, location)
    local display_page = self:getDisplayPageNumber(ui, location)
    if type(page_key) ~= "string" or page_key == "" then
        return false, "NO_PAGE"
    end

    return true, {
        page_key = page_key,
        page = display_page ~= "" and display_page or page_key,
    }
end

function Interaction:validateBookmarkUI()
    local ui = self:getUI()

    if not ui
        or not ui.document
        or not ui.annotation
        or type(ui.annotation.annotations) ~= "table"
        or not ui.bookmark then
        return nil,
            "NO_DOCUMENT_OPEN",
            "Open a book on the reader first."
    end

    return ui
end

function Interaction:resolveBookmark(id)
    if type(id) ~= "string" or id == "" then
        return nil,
            nil,
            nil,
            nil,
            "MISSING_BOOKMARK",
            "The bookmark identifier is missing."
    end

    local ui, code, message = self:validateBookmarkUI()
    if not ui then
        return nil, nil, nil, nil, code, message
    end

    for index, annotation in ipairs(ui.annotation.annotations) do
        if annotationIdentity(index, ui, annotation) == id then
            return ui,
                annotation,
                index,
                annotationType(ui, annotation)
        end
    end

    return nil,
        nil,
        nil,
        nil,
        "BOOKMARK_CHANGED",
        "The bookmark list changed. Refresh it and try again."
end

function Interaction:getBookmarkReturnState(ui)
    local saved = self.bookmark_return

    if not saved then
        return {
            available = false,
        }
    end

    if not ui
        or saved.ui ~= ui
        or not ui.document
        or ui.document.file ~= saved.document_file then
        self.bookmark_return = nil
        return {
            available = false,
        }
    end

    return {
        available = true,
        page = saved.page or "",
        created_at = saved.created_at,
    }
end

function Interaction:beginBookmarkExcursion(ui)
    local current_state = self:getBookmarkReturnState(ui)
    if current_state.available then
        return true, current_state
    end

    if not ui.link or type(ui.link.getCurrentLocation) ~= "function" then
        return false,
            "RETURN_NOT_SUPPORTED",
            "KOReader could not capture the current reading position."
    end

    local ok, location = pcall(
        ui.link.getCurrentLocation,
        ui.link
    )

    if not ok or type(location) ~= "table" then
        return false,
            "RETURN_NOT_SUPPORTED",
            "KOReader could not capture the current reading position."
    end

    local saved = {
        ui = ui,
        document_file = ui.document.file,
        location = location,
        page = self:getCurrentReadingPage(ui, location),
        created_at = os.time(),
        added_to_history = false,
    }

    if type(ui.link.addCurrentLocationToStack) == "function" then
        local stack_ok, stack_err = pcall(
            ui.link.addCurrentLocationToStack,
            ui.link,
            location
        )

        if stack_ok then
            saved.added_to_history = true
        else
            logger.warn(
                "KOReaderRemote: could not add return point to history:",
                stack_err
            )
        end
    end

    self.bookmark_return = saved
    return true, self:getBookmarkReturnState(ui)
end

function Interaction:removeBookmarkReturnFromHistory(ui, saved)
    if not saved.added_to_history
        or not ui.link
        or type(ui.link.location_stack) ~= "table" then
        return
    end

    for index = #ui.link.location_stack, 1, -1 do
        if ui.link.location_stack[index] == saved.location then
            table.remove(ui.link.location_stack, index)
            return
        end
    end
end

function Interaction:returnToReadingPosition()
    local ui, code, message = self:validateBookmarkUI()
    if not ui then
        return false, code, message
    end

    local saved = self.bookmark_return
    local state = self:getBookmarkReturnState(ui)

    if not saved or not state.available then
        return false,
            "NO_RETURN_POSITION",
            "No reading position is currently saved."
    end

    local controller
    if ui.rolling
        and type(ui.rolling.onRestoreBookLocation) == "function" then
        controller = ui.rolling
    elseif ui.paging
        and type(ui.paging.onRestoreBookLocation) == "function" then
        controller = ui.paging
    end

    if not controller then
        return false,
            "RETURN_NOT_SUPPORTED",
            "KOReader cannot restore this reading position."
    end

    local ok, err = pcall(
        controller.onRestoreBookLocation,
        controller,
        saved.location
    )

    if not ok then
        logger.err(
            "KOReaderRemote: return to reading position failed:",
            err
        )
        return false,
            "RETURN_FAILED",
            "KOReader could not restore the saved reading position."
    end

    self:removeBookmarkReturnFromHistory(ui, saved)
    self.bookmark_return = nil

    return true, {
        action = "reading_position_restored",
        page = saved.page or "",
        return_position = {
            available = false,
        },
    }
end

function Interaction:getBookmarks()
    local ui, code, message = self:validateBookmarkUI()
    if not ui then
        return false, code, message
    end

    local annotations = ui.annotation.annotations
    local items = {}
    local counts = {
        all = #annotations,
        bookmark = 0,
        highlight = 0,
        note = 0,
    }

    for index, annotation in ipairs(annotations) do
        local item_type = annotationType(ui, annotation)
        counts[item_type] = (counts[item_type] or 0) + 1

        if #items < MAX_BOOKMARK_ITEMS then
            items[#items + 1] = {
                id = annotationIdentity(index, ui, annotation),
                order = index,
                type = item_type,
                page = self:getBookmarkPageLabel(ui, annotation),
                chapter = utf8Prefix(
                    annotation.chapter or "",
                    400
                ),
                excerpt = utf8Prefix(
                    annotation.text or "",
                    MAX_BOOKMARK_EXCERPT_BYTES
                ),
                note = utf8Prefix(
                    annotation.note or "",
                    MAX_BOOKMARK_NOTE_BYTES
                ),
                datetime = tostring(annotation.datetime or ""),
                datetime_updated = tostring(
                    annotation.datetime_updated or ""
                ),
                can_edit_note = item_type == "highlight"
                    or item_type == "note",
                can_delete = true,
            }
        end
    end

    return true, {
        title = self:getBookTitle(ui),
        count = #annotations,
        returned = #items,
        truncated = #annotations > #items,
        counts = counts,
        return_position = self:getBookmarkReturnState(ui),
        items = items,
    }
end

function Interaction:openBookmark(id)
    local ui, selected, _, selected_type, code, message =
        self:resolveBookmark(id)

    if not ui then
        return false, code, message
    end

    if type(ui.bookmark.gotoBookmark) ~= "function" then
        return false,
            "BOOKMARK_OPEN_FAILED",
            "KOReader cannot open bookmarks in this view."
    end

    local return_ok, return_result, return_message =
        self:beginBookmarkExcursion(ui)

    if not return_ok then
        return false, return_result, return_message
    end

    local ok, err = pcall(
        ui.bookmark.gotoBookmark,
        ui.bookmark,
        selected.page,
        selected.pos0
    )

    if not ok then
        logger.err("KOReaderRemote: bookmark navigation failed:", err)
        return false,
            "BOOKMARK_OPEN_FAILED",
            "KOReader could not open the selected bookmark."
    end

    return true, {
        action = "bookmark_opened",
        type = selected_type,
        page = self:getBookmarkPageLabel(ui, selected),
        return_position = return_result,
    }
end

function Interaction:editBookmarkNote(id)
    local ui, _, index, item_type, code, message =
        self:resolveBookmark(id)

    if not ui then
        return false, code, message
    end

    if item_type == "bookmark" then
        return false,
            "NOTE_NOT_SUPPORTED",
            "Page bookmarks do not have an editable highlight note."
    end

    if self.session then
        return false,
            "NOTE_SESSION_ACTIVE",
            "Save or cancel the currently open remote note first."
    end

    if not ui.highlight then
        return false,
            "NOTE_NOT_SUPPORTED",
            "KOReader cannot edit this note in the current view."
    end

    local started = self:startNoteSession(
        ui.highlight,
        index,
        false
    )

    if not started then
        return false,
            "NOTE_OPEN_FAILED",
            "The note editor could not be opened."
    end

    return true, {
        action = "note_editor_opened",
        session = self:getNoteSessionState(),
    }
end

function Interaction:deleteBookmarkNote(id)
    local ui, selected, index, selected_type, code, message =
        self:resolveBookmark(id)

    if not ui then
        return false, code, message
    end

    if selected_type ~= "note" or selected.note == nil then
        return false,
            "NOTE_NOT_FOUND",
            "This annotation does not contain a note."
    end

    if self.session and self.session.annotation == selected then
        self:cancelNoteSession(
            "note deleted from bookmarks",
            true,
            false
        )
    end

    if ui.highlight
        and type(ui.highlight.writePdfAnnotation) == "function" then
        local pdf_ok, pdf_err = pcall(
            ui.highlight.writePdfAnnotation,
            ui.highlight,
            "content",
            selected,
            ""
        )

        if not pdf_ok then
            logger.warn(
                "KOReaderRemote: could not clear PDF note content:",
                pdf_err
            )
        end
    end

    selected.note = nil

    if type(ui.handleEvent) == "function" then
        ui:handleEvent(Event:new("AnnotationsModified", {
            selected,
            index_modified = index,
            nb_highlights_added = 1,
            nb_notes_added = -1,
        }))
    end

    if ui.highlight
        and ui.highlight.view
        and ui.highlight.view.highlight
        and ui.highlight.view.highlight.note_mark
        and ui.highlight.dialog then
        UIManager:setDirty(ui.highlight.dialog, "ui")
    end

    return true, {
        action = "note_deleted",
        type = "highlight",
        return_position = self:getBookmarkReturnState(ui),
    }
end

function Interaction:deleteBookmark(id)
    local ui, selected, index, selected_type, code, message =
        self:resolveBookmark(id)

    if not ui then
        return false, code, message
    end

    if self.session and self.session.annotation == selected then
        self:cancelNoteSession(
            "annotation deleted from phone",
            true,
            false
        )
    end

    if type(ui.bookmark.removeItem) ~= "function" then
        return false,
            "DELETE_NOT_SUPPORTED",
            "KOReader cannot delete this annotation in the current view."
    end

    local ok, err = pcall(
        ui.bookmark.removeItem,
        ui.bookmark,
        selected,
        index
    )

    if not ok then
        logger.err("KOReaderRemote: annotation deletion failed:", err)
        return false,
            "DELETE_FAILED",
            "KOReader could not delete the selected annotation."
    end

    return true, {
        action = "bookmark_deleted",
        type = selected_type,
        return_position = self:getBookmarkReturnState(ui),
    }
end

function Interaction:getFootnotePageKey(ui)
    local ok, page = pcall(function()
        return ui.document:getCurrentPage()
    end)

    if ok and page ~= nil then
        return tostring(page)
    end

    local xpointer_ok, xpointer = pcall(function()
        return ui.document:getXPointer()
    end)

    return xpointer_ok and tostring(xpointer) or "current"
end

function Interaction:makeFootnoteCandidate(ui, link)
    if not link or not link.section then
        return nil
    end

    local from_xpointer
    if link.a_xpointer and ui.link.isXpointerCoherent then
        local ok, coherent = pcall(
            ui.link.isXpointerCoherent,
            ui.link,
            link.a_xpointer
        )
        if ok and coherent then
            from_xpointer = link.a_xpointer
        end
    end

    local link_y = link.end_y
    if link.segments and #link.segments > 0 then
        link_y = link.segments[#link.segments].y1
    end

    return {
        xpointer = link.section,
        marker_xpointer = link.section,
        from_xpointer = from_xpointer,
        a_xpointer = link.a_xpointer,
        link_y = link_y,
    }
end

function Interaction:getFootnoteDetectionFlags(trust_source_xpointer)
    -- Keep these flags aligned with ReaderLink:showAsFootnotePopup().
    local flags = 0

    if G_reader_settings:isTrue("link_prefer_footnote") then
        flags = flags + 0x0001
    end

    if trust_source_xpointer then
        flags = flags + 0x0002
    end

    flags = flags + 0x0004
    flags = flags + 0x0008
    flags = flags + 0x0010

    if not G_reader_settings:isTrue("link_prefer_footnote") then
        flags = flags + 0x0020
    end

    flags = flags + 0x0040
    flags = flags + 0x0100
    flags = flags + 0x0200
    flags = flags + 0x0400
    flags = flags + 0x0800
    flags = flags + 0x1000
    flags = flags + 0x4000
    flags = flags + 0x8000

    return flags
end

function Interaction:normalizeFootnoteText(value, max_length)
    if type(value) ~= "string" then
        return ""
    end

    local text = value
        :gsub("<[^>]+>", " ")
        :gsub("&nbsp;", " ")
        :gsub("&amp;", "&")
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&quot;", '"')
        :gsub("&#%d+;", " ")
        :gsub("&%w+;", " ")
        :gsub("%s+", " ")
        :match("^%s*(.-)%s*$") or ""

    max_length = tonumber(max_length) or 160
    if #text > max_length then
        text = text:sub(1, max_length - 1) .. "…"
    end

    return text
end

function Interaction:getFootnoteMarkerText(ui, link, candidate, index)
    local marker = ""

    if candidate and candidate.from_xpointer
        and type(ui.document.getTextFromXPointer) == "function" then
        local ok, text = pcall(
            ui.document.getTextFromXPointer,
            ui.document,
            candidate.from_xpointer
        )
        if ok then
            marker = self:normalizeFootnoteText(text, 40)
        end
    end

    if marker == "" and link and link.a_xpointer
        and type(ui.document.getTextFromXPointer) == "function" then
        local ok, text = pcall(
            ui.document.getTextFromXPointer,
            ui.document,
            link.a_xpointer
        )
        if ok then
            marker = self:normalizeFootnoteText(text, 40)
        end
    end

    if marker == "" then
        marker = tostring(index)
    end

    return marker
end

function Interaction:getFootnotePreviewText(ui, candidate, ext_start, ext_end)
    if type(ui.document.getTextFromXPointers) == "function"
        and ext_start and ext_end then
        local ok, text = pcall(
            ui.document.getTextFromXPointers,
            ui.document,
            ext_start,
            ext_end,
            false
        )
        if ok then
            local preview = self:normalizeFootnoteText(text, 180)
            if preview ~= "" then
                return preview
            end
        end
    end

    if type(ui.document.getHTMLFromXPointer) == "function"
        and candidate and candidate.xpointer then
        local ok, html = pcall(
            ui.document.getHTMLFromXPointer,
            ui.document,
            candidate.xpointer,
            0x1001,
            true
        )
        if ok then
            return self:normalizeFootnoteText(html, 180)
        end
    end

    return ""
end

function Interaction:collectCurrentPageFootnotes()
    local capabilities = self:getCapabilities()
    if not capabilities.footnotes then
        return false,
            "NOT_SUPPORTED",
            "Automatic footnote opening is available only for supported reflowable documents."
    end

    local ui = self:getUI()
    local ok, links = pcall(
        ui.document.getPageLinks,
        ui.document,
        true
    )

    if not ok or type(links) ~= "table" then
        links = {}
    end

    table.sort(links, function(left, right)
        local left_y = tonumber(left.start_y or left.end_y) or 0
        local right_y = tonumber(right.start_y or right.end_y) or 0
        if left_y == right_y then
            local left_x = tonumber(left.start_x or left.end_x) or 0
            local right_x = tonumber(right.start_x or right.end_x) or 0
            return left_x < right_x
        end
        return left_y < right_y
    end)

    local footnotes = {}
    local page_key = self:getFootnotePageKey(ui)

    for _, link in ipairs(links) do
        local candidate = self:makeFootnoteCandidate(ui, link)
        if candidate then
            local source_xpointer = candidate.from_xpointer or candidate.a_xpointer
            if source_xpointer and candidate.xpointer then
                local flags = self:getFootnoteDetectionFlags(
                    candidate.from_xpointer ~= nil
                )
                local detected_ok, is_footnote, _reason, _stop, ext_start, ext_end =
                    pcall(
                        ui.document.isLinkToFootnote,
                        ui.document,
                        source_xpointer,
                        candidate.xpointer,
                        flags,
                        10000
                    )

                if detected_ok and is_footnote then
                    local index = #footnotes + 1
                    footnotes[index] = {
                        id = index,
                        marker = self:getFootnoteMarkerText(
                            ui,
                            link,
                            candidate,
                            index
                        ),
                        preview = self:getFootnotePreviewText(
                            ui,
                            candidate,
                            ext_start,
                            ext_end
                        ),
                        candidate = candidate,
                    }
                end
            end
        end
    end

    return true, {
        page_key = page_key,
        footnotes = footnotes,
        popup_open = self:isFootnotePopupOpen(),
    }
end

function Interaction:isFootnotePopupWidget(widget)
    return type(widget) == "table"
        and type(widget.html) == "string"
        and widget.covers_footer == true
        and type(widget.onTapClose) == "function"
        and type(widget.onFollow) == "function"
end

function Interaction:isFootnotePopupOpen()
    for widget in UIManager:topdown_widgets_iter() do
        if self:isFootnotePopupWidget(widget) then
            return true
        end
    end

    return false
end

function Interaction:closeFootnotePopup()
    local to_close = {}

    for widget in UIManager:topdown_widgets_iter() do
        if self:isFootnotePopupWidget(widget) then
            to_close[#to_close + 1] = widget
        end
    end

    if #to_close == 0 then
        return false,
            "NO_FOOTNOTE_POPUP",
            "No footnote popup is currently open."
    end

    for _, widget in ipairs(to_close) do
        if type(widget.onClose) == "function" then
            pcall(widget.onClose, widget)
        else
            UIManager:close(widget)
        end
    end

    return true, {
        action = "footnote_closed",
        closed = #to_close,
        popup_open = false,
    }
end

function Interaction:listFootnotes()
    local ok, result, message = self:collectCurrentPageFootnotes()
    if not ok then
        return false, result, message
    end

    local items = {}
    for _, footnote in ipairs(result.footnotes) do
        items[#items + 1] = {
            id = footnote.id,
            marker = footnote.marker,
            preview = footnote.preview,
        }
    end

    return true, {
        page_key = result.page_key,
        count = #items,
        footnotes = items,
        popup_open = result.popup_open,
    }
end

function Interaction:openFootnoteById(footnote_id)
    local ok, result, message = self:collectCurrentPageFootnotes()
    if not ok then
        return false, result, message
    end

    local footnotes = result.footnotes
    if #footnotes == 0 then
        return false,
            "NO_FOOTNOTE_FOUND",
            "No footnote was detected on the current page."
    end

    local selected = nil
    if footnote_id ~= nil then
        local id = tonumber(footnote_id)
        if not id or id < 1 or id % 1 ~= 0 or not footnotes[id] then
            return false,
                "INVALID_FOOTNOTE",
                "Choose a footnote from the current page list."
        end
        selected = footnotes[id]
    else
        local page_key = result.page_key
        if page_key ~= self.footnote_page_key then
            self.footnote_page_key = page_key
            self.footnote_cursor = 0
        end

        local index = (self.footnote_cursor % #footnotes) + 1
        selected = footnotes[index]
    end

    self:closeFootnotePopup()

    local ui = self:getUI()
    local shown_ok, shown = pcall(
        ui.link.showAsFootnotePopup,
        ui.link,
        selected.candidate,
        false
    )

    if not shown_ok or not shown then
        return false,
            "NO_FOOTNOTE_FOUND",
            "No footnote was detected on the current page."
    end

    self.footnote_page_key = result.page_key
    self.footnote_cursor = selected.id

    return true, {
        action = "footnote_opened",
        id = selected.id,
        marker = selected.marker,
        popup_open = true,
    }
end

function Interaction:openNextFootnote()
    return self:openFootnoteById(nil)
end

function Interaction:validateTocUI()
    local ui = self:getUI()

    if not ui or not ui.document then
        return nil,
            "NO_DOCUMENT_OPEN",
            "Open a book on the reader first."
    end

    if not ui.toc or type(ui.toc.fillToc) ~= "function" then
        return nil,
            "TOC_NOT_SUPPORTED",
            "Table of contents is not available in this view."
    end

    return ui
end

function Interaction:tocIdentity(index, item)
    return string.format(
        "%d:%s:%s:%s",
        tonumber(index) or 0,
        tostring(item and item.page or ""),
        tostring(item and item.depth or ""),
        tostring(item and (item.xpointer or item.title) or "")
    )
end

function Interaction:getTocTitleText(ui, item)
    local title = tostring(item and item.title or "")

    if ui.toc and type(ui.toc.cleanUpTocTitle) == "function" then
        local ok, cleaned = pcall(
            ui.toc.cleanUpTocTitle,
            ui.toc,
            title,
            true
        )
        if ok and cleaned ~= nil then
            title = tostring(cleaned)
        end
    end

    title = trim(title)
    if title == "" then
        title = _("Untitled")
    end

    return utf8Prefix(title, MAX_TOC_TITLE_BYTES)
end

function Interaction:collectTocEntries(ui)
    local fill_ok, fill_err = pcall(ui.toc.fillToc, ui.toc)
    if not fill_ok then
        logger.err("KOReaderRemote: fillToc failed:", fill_err)
        return nil,
            "TOC_LOAD_FAILED",
            "KOReader could not load the table of contents."
    end

    local toc = ui.toc.toc
    if type(toc) ~= "table" then
        toc = {}
    end

    return toc
end

function Interaction:getToc()
    local ui, code, message = self:validateTocUI()
    if not ui then
        return false, code, message
    end

    local toc, load_code, load_message = self:collectTocEntries(ui)
    if not toc then
        return false, load_code, load_message
    end

    local items = {}
    local current_index = nil

    if type(ui.toc.getTocIndexByPage) == "function" then
        local ok, index = pcall(
            ui.toc.getTocIndexByPage,
            ui.toc,
            ui.toc.pageno or (ui.paging and ui.paging.current_page)
        )
        if ok and type(index) == "number" then
            current_index = index
        end
    end

    for index, entry in ipairs(toc) do
        if #items < MAX_TOC_ITEMS then
            local depth = tonumber(entry.depth) or 1
            if depth < 1 then
                depth = 1
            end

            items[#items + 1] = {
                id = self:tocIdentity(index, entry),
                order = index,
                title = self:getTocTitleText(ui, entry),
                page = tostring(entry.page or ""),
                depth = depth,
                current = current_index == index,
            }
        end
    end

    return true, {
        title = self:getBookTitle(ui),
        count = #toc,
        returned = #items,
        truncated = #toc > #items,
        current_index = current_index,
        return_position = self:getBookmarkReturnState(ui),
        items = items,
    }
end

function Interaction:resolveTocEntry(id)
    local ui, code, message = self:validateTocUI()
    if not ui then
        return nil, nil, nil, code, message
    end

    if type(id) ~= "string" or id == "" then
        return nil,
            nil,
            nil,
            "MISSING_TOC_ENTRY",
            "Choose an entry from the table of contents."
    end

    local toc, load_code, load_message = self:collectTocEntries(ui)
    if not toc then
        return nil, nil, nil, load_code, load_message
    end

    for index, entry in ipairs(toc) do
        if self:tocIdentity(index, entry) == id then
            return ui, entry, index
        end
    end

    return nil,
        nil,
        nil,
        "TOC_CHANGED",
        "The table of contents changed. Refresh it and try again."
end

function Interaction:openTocEntry(id)
    local ui, entry, index, code, message = self:resolveTocEntry(id)

    if not ui then
        return false, code, message
    end

    local return_ok, return_result, return_message =
        self:beginBookmarkExcursion(ui)

    if not return_ok then
        return false, return_result, return_message
    end

    local ok, err
    if entry.xpointer and entry.xpointer ~= "" then
        ok, err = pcall(
            ui.handleEvent,
            ui,
            Event:new("GotoXPointer", entry.xpointer, entry.xpointer)
        )
    elseif entry.page ~= nil then
        ok, err = pcall(
            ui.handleEvent,
            ui,
            Event:new("GotoPage", entry.page)
        )
    else
        return false,
            "TOC_OPEN_FAILED",
            "The selected contents entry has no usable location."
    end

    if not ok then
        logger.err("KOReaderRemote: TOC navigation failed:", err)
        return false,
            "TOC_OPEN_FAILED",
            "KOReader could not open the selected contents entry."
    end

    return true, {
        action = "toc_opened",
        id = self:tocIdentity(index, entry),
        title = self:getTocTitleText(ui, entry),
        page = tostring(entry.page or ""),
        return_position = return_result,
    }
end

function Interaction:findActiveInputTarget()
    for widget in UIManager:topdown_widgets_iter() do
        if widget
            and widget.name == "VirtualKeyboard"
            and widget.inputbox then
            local box = widget.inputbox
            local parent = box.parent
            if parent
                and type(parent.setInputText) == "function"
                and type(parent.getInputText) == "function" then
                return parent, box
            end
            return nil, box
        end
    end

    for widget in UIManager:topdown_widgets_iter() do
        if widget
            and type(widget.setInputText) == "function"
            and type(widget.getInputText) == "function"
            and widget._input_widget then
            return widget, widget._input_widget
        end
    end

    return nil, nil
end

function Interaction:describeInputTarget(dialog, box)
    local target = box
    if not target and dialog then
        target = dialog._input_widget
    end

    if type(target) ~= "table" then
        return {
            available = false,
        }
    end

    local text = ""
    if dialog and type(dialog.getInputText) == "function" then
        local ok, value = pcall(dialog.getInputText, dialog)
        if ok and value ~= nil then
            text = tostring(value)
        end
    elseif type(target.getText) == "function" then
        local ok, value = pcall(target.getText, target)
        if ok and value ~= nil then
            text = tostring(value)
        end
    end

    local editable = true
    if type(target.isTextEditable) == "function" then
        local ok, value = pcall(target.isTextEditable, target)
        if ok then
            editable = value and true or false
        end
    elseif target.readonly == true then
        editable = false
    end

    local is_password = target.is_password_type == true
        or target.text_type == "password"

    return {
        available = true,
        editable = editable and not is_password,
        is_password = is_password,
        is_multi = type(dialog) == "table"
            and type(dialog.input_fields) == "table",
        text = utf8Prefix(text, 2200),
        length = #text,
    }
end

function Interaction:getInputStatus()
    local dialog, box = self:findActiveInputTarget()
    return true, self:describeInputTarget(dialog, box)
end

function Interaction:pushInputText(encoded, mode)
    mode = mode == "append" and "append" or "replace"

    local text, decode_code, decode_message =
        self:decodeAndValidateNote(encoded)

    if text == nil then
        return false, decode_code, decode_message
    end

    local dialog, box = self:findActiveInputTarget()
    if not dialog and not box then
        return false,
            "NO_INPUT",
            "Open an input box on the reader first."
    end

    local target = box
    if not target and dialog then
        target = dialog._input_widget
    end

    if type(target) ~= "table" then
        return false,
            "NO_INPUT",
            "Open an input box on the reader first."
    end

    if target.is_password_type == true
        or target.text_type == "password" then
        return false,
            "PASSWORD_FIELD",
            "Refusing to write into a password field."
    end

    if target.readonly == true then
        return false,
            "NOT_EDITABLE",
            "The input field is not editable."
    end

    if type(target.isTextEditable) == "function" then
        local ok_editable, editable = pcall(target.isTextEditable, target)
        if ok_editable and not editable then
            return false,
                "NOT_EDITABLE",
                "The input field is not editable."
        end
    end

    local ok, set_err
    if dialog then
        if mode == "append" then
            ok, set_err = pcall(dialog.addTextToInput, dialog, text)
        else
            ok, set_err = pcall(
                dialog.setInputText,
                dialog,
                text,
                true,
                false
            )
        end
    elseif mode == "append" then
        ok, set_err = pcall(target.addChars, target, text)
    else
        ok, set_err = pcall(target.setText, target, text, true)
        if ok then
            target.is_text_edited = true
        end
    end

    if not ok then
        logger.err("KOReaderRemote: input injection failed:", set_err)
        return false,
            "INPUT_CLOSED",
            "The reader input box closed before the text could be applied."
    end

    return true, {
        action = mode == "append" and "input_appended" or "input_replaced",
        mode = mode,
        input = self:describeInputTarget(dialog, box),
    }
end

local MAX_PAGE_TEXT_BYTES = 100 * 1024

function Interaction:extractPagingPageText(ui, page_number)
    local document = ui.document
    local page_text = nil

    if type(document.getTextBoxes) == "function" then
        local ok, text_boxes = pcall(document.getTextBoxes, document, page_number)
        if ok and type(text_boxes) == "table" and #text_boxes > 0 then
            local lines = {}
            for _, line in ipairs(text_boxes) do
                if type(line) == "table" then
                    local words = {}
                    for _, word_box in ipairs(line) do
                        if type(word_box) == "table" and word_box.word then
                            words[#words + 1] = tostring(word_box.word)
                        end
                    end
                    if #words > 0 then
                        lines[#lines + 1] = table.concat(words, " ")
                    end
                end
            end
            if #lines > 0 then
                page_text = table.concat(lines, "\n")
            end

            if (not page_text or page_text == "")
                and type(document.getTextFromPositions) == "function" then
                local first_line = text_boxes[1]
                local last_line = text_boxes[#text_boxes]
                if type(first_line) == "table" and #first_line > 0
                    and type(last_line) == "table" and #last_line > 0 then
                    local first_word = first_line[1]
                    local last_word = last_line[#last_line]
                    if type(first_word) == "table" and type(last_word) == "table" then
                        local pos0 = {
                            x = first_word.x0 or 0,
                            y = first_word.y0 or 0,
                            page = page_number,
                        }
                        local pos1 = {
                            x = last_word.x1 or 0,
                            y = last_word.y1 or 0,
                            page = page_number,
                        }
                        local pos_ok, pos_result = pcall(
                            document.getTextFromPositions,
                            document,
                            pos0,
                            pos1
                        )
                        if pos_ok and type(pos_result) == "table" and pos_result.text then
                            page_text = pos_result.text
                        end
                    end
                end
            end
        end
    end

    return page_text
end

function Interaction:extractCrePageText(ui)
    local document = ui.document
    local page_text = nil

    -- Prefer the currently visible screen contents.
    local view_dimen = ui.view and ui.view.dimen
    if view_dimen and type(document.getTextFromPositions) == "function" then
        local pos0 = { x = 0, y = 0 }
        local pos1 = { x = view_dimen.w or 0, y = view_dimen.h or 0 }
        local ok, pos_result = pcall(
            document.getTextFromPositions,
            document,
            pos0,
            pos1,
            true
        )
        if ok and type(pos_result) == "table"
            and type(pos_result.text) == "string"
            and pos_result.text ~= "" then
            page_text = pos_result.text
        end
    end

    -- Fallback: current page xpointer range.
    if (not page_text or page_text == "")
        and type(document.getPageXPointer) == "function"
        and type(document.getTextFromXPointers) == "function"
        and type(document.getCurrentPage) == "function"
        and type(document.getPageCount) == "function" then
        local page_ok, current_page = pcall(document.getCurrentPage, document)
        local count_ok, page_count = pcall(document.getPageCount, document)
        if page_ok and count_ok
            and type(current_page) == "number"
            and type(page_count) == "number"
            and current_page >= 1 then
            local start_ok, start_xp = pcall(
                document.getPageXPointer,
                document,
                current_page
            )
            local end_page = math.min(current_page + 1, page_count + 1)
            local end_ok, end_xp = pcall(
                document.getPageXPointer,
                document,
                end_page
            )
            if start_ok and end_ok and start_xp and end_xp then
                local text_ok, text = pcall(
                    document.getTextFromXPointers,
                    document,
                    start_xp,
                    end_xp,
                    false
                )
                if text_ok and type(text) == "string" and text ~= "" then
                    page_text = text
                end
            end
        end
    end

    if (not page_text or page_text == "")
        and type(document.getTextFromXPointer) == "function"
        and type(document.getXPointer) == "function" then
        local xp_ok, xp = pcall(document.getXPointer, document)
        if xp_ok and xp then
            local text_ok, text = pcall(
                document.getTextFromXPointer,
                document,
                xp
            )
            if text_ok and type(text) == "string" and text ~= "" then
                page_text = text
            end
        end
    end

    return page_text
end

function Interaction:extractCrePageTextByNumber(ui, page_number)
    local document = ui.document
    if type(page_number) ~= "number" or page_number < 1 then
        return nil
    end
    if type(document.getPageXPointer) ~= "function"
        or type(document.getTextFromXPointers) ~= "function" then
        return nil
    end

    local page_count = nil
    if type(document.getPageCount) == "function" then
        local ok, value = pcall(document.getPageCount, document)
        if ok and type(value) == "number" then
            page_count = value
        end
    end
    if page_count and page_number > page_count then
        return nil
    end

    local end_page = page_number + 1
    if type(document.getNextPage) == "function" then
        local ok_next, next_page = pcall(document.getNextPage, document, page_number)
        if ok_next and type(next_page) == "number" and next_page > 0 then
            end_page = next_page
        elseif page_count then
            end_page = math.min(page_number + 1, page_count + 1)
        end
    elseif page_count then
        end_page = math.min(page_number + 1, page_count + 1)
    end

    local start_ok, start_xp = pcall(document.getPageXPointer, document, page_number)
    local end_ok, end_xp = pcall(document.getPageXPointer, document, end_page)
    if not (start_ok and end_ok and start_xp and end_xp) then
        return nil
    end

    local text_ok, text = pcall(
        document.getTextFromXPointers,
        document,
        start_xp,
        end_xp,
        false
    )
    if text_ok and type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

function Interaction:resolveRelativePageNumber(ui, delta)
    delta = tonumber(delta) or 1
    if delta == 0 then
        local ok, page = pcall(function()
            return ui.document:getCurrentPage()
        end)
        if ok and type(page) == "number" then
            return page
        end
        return nil, "INVALID_PAGE"
    end

    local document = ui.document
    local ok, current = pcall(function()
        return document:getCurrentPage()
    end)
    if not ok or type(current) ~= "number" then
        return nil, "INVALID_PAGE"
    end

    local page = current
    local step = delta > 0 and 1 or -1
    local remaining = math.abs(delta)

    while remaining > 0 do
        if step > 0 and type(document.getNextPage) == "function" then
            local next_ok, next_page = pcall(document.getNextPage, document, page)
            if not next_ok or type(next_page) ~= "number" or next_page <= 0 then
                return nil, "END_OF_BOOK"
            end
            page = next_page
        elseif step < 0 and type(document.getPrevPage) == "function" then
            local prev_ok, prev_page = pcall(document.getPrevPage, document, page)
            if not prev_ok or type(prev_page) ~= "number" or prev_page <= 0 then
                return nil, "END_OF_BOOK"
            end
            page = prev_page
        else
            page = page + step
            if page < 1 then
                return nil, "END_OF_BOOK"
            end
            if type(document.getPageCount) == "function" then
                local count_ok, count = pcall(document.getPageCount, document)
                if count_ok and type(count) == "number" and page > count then
                    return nil, "END_OF_BOOK"
                end
            end
        end
        remaining = remaining - 1
    end

    return page
end

function Interaction:buildPageTextPayload(ui, page_text, page_key, display_page, engine)
    page_text = trim(page_text or "")
    local truncated = false
    if #page_text > MAX_PAGE_TEXT_BYTES then
        page_text = utf8Prefix(page_text, MAX_PAGE_TEXT_BYTES)
        truncated = true
    end

    local title = nil
    if ui.doc_settings and type(ui.doc_settings.readSetting) == "function" then
        title = ui.doc_settings:readSetting("title")
    end
    if (not title or title == "") and ui.document and ui.document.file then
        title = basename(ui.document.file)
    end

    local speech_text = self:normalizeTextForSpeech(page_text)
    display_page = tostring(display_page or "")
    if display_page == "" then
        display_page = tostring(page_key or "")
    end

    return {
        page_key = page_key ~= nil and tostring(page_key) ~= ""
            and tostring(page_key)
            or tostring(os.time()),
        page = display_page,
        title = title or "",
        text = page_text,
        speech_text = speech_text,
        char_count = #page_text,
        truncated = truncated,
        engine = engine or "unknown",
        empty = page_text == "",
        content_hash = speechFingerprint(speech_text),
    }
end

function Interaction:getCurrentPageText()
    local capabilities = self:getCapabilities()
    if not capabilities.page_text then
        return false,
            "NOT_SUPPORTED",
            "Current page text extraction is not available for this document."
    end

    local ui = self:getUI()
    if not ui or not ui.document then
        return false,
            "NO_DOCUMENT_OPEN",
            "Open a book on the reader first."
    end

    local location = nil
    if ui.link and type(ui.link.getCurrentLocation) == "function" then
        local ok, value = pcall(ui.link.getCurrentLocation, ui.link)
        if ok then
            location = value
        end
    end

    local page_key = self:getCurrentReadingPage(ui, location)
    local engine = ui.rolling and "cre" or (ui.paging and "paging" or "unknown")
    local page_text = nil

    if ui.rolling or type(ui.document.getXPointer) == "function" then
        page_text = self:extractCrePageText(ui)
        if (not page_text or page_text == "") and ui.view and ui.view.state
            and ui.view.state.page then
            page_text = self:extractPagingPageText(ui, ui.view.state.page)
        end
    else
        local page_number = tonumber(page_key)
            or (ui.view and ui.view.state and ui.view.state.page)
            or 1
        page_text = self:extractPagingPageText(ui, page_number)
    end

    local display_page = self:getDisplayPageNumber(ui, location)
    return true, self:buildPageTextPayload(
        ui,
        page_text,
        page_key,
        display_page,
        engine
    )
end

-- Peek page text relative to the current position without turning the view.
function Interaction:getRelativePageText(delta)
    local capabilities = self:getCapabilities()
    if not capabilities.page_text then
        return false,
            "NOT_SUPPORTED",
            "Current page text extraction is not available for this document."
    end

    local ui = self:getUI()
    if not ui or not ui.document then
        return false,
            "NO_DOCUMENT_OPEN",
            "Open a book on the reader first."
    end

    delta = tonumber(delta) or 1
    if delta == 0 then
        return self:getCurrentPageText()
    end

    local engine = ui.rolling and "cre" or (ui.paging and "paging" or "unknown")
    local target_page, err = self:resolveRelativePageNumber(ui, delta)
    if not target_page then
        return false, err or "END_OF_BOOK", "Reached the end of the document."
    end

    local page_text = nil
    if ui.paging and not ui.rolling then
        page_text = self:extractPagingPageText(ui, target_page)
    else
        page_text = self:extractCrePageTextByNumber(ui, target_page)
        if (not page_text or page_text == "") then
            page_text = self:extractPagingPageText(ui, target_page)
        end
    end

    local payload = self:buildPageTextPayload(
        ui,
        page_text,
        tostring(target_page),
        tostring(target_page),
        engine
    )
    payload.relative_delta = delta
    return true, payload
end

-- Find the next non-empty page text without turning. Returns turn_count needed later.
function Interaction:peekNextSpeakablePageText(max_skip)
    max_skip = tonumber(max_skip) or 12
    if max_skip < 1 then
        max_skip = 1
    end

    for turn_count = 1, max_skip do
        local ok, result, message = self:getRelativePageText(turn_count)
        if not ok then
            if result == "END_OF_BOOK" then
                return true, {
                    end_of_book = true,
                    turn_count = turn_count,
                }
            end
            return false, result, message
        end
        if not result.empty and result.speech_text ~= "" then
            result.end_of_book = false
            result.turn_count = turn_count
            return true, result
        end
    end

    return true, {
        end_of_book = true,
        turn_count = max_skip,
        empty = true,
    }
end

function Interaction:normalizeTextForSpeech(value)
    local text = tostring(value or "")
    if text == "" then
        return ""
    end

    -- Soft hyphen / zero-width / NBSP cleanup.
    text = text:gsub("\194\173", "") -- U+00AD soft hyphen in UTF-8
    text = text:gsub("\226\128\139", "") -- U+200B
    text = text:gsub("\226\128\140", "") -- U+200C
    text = text:gsub("\226\128\141", "") -- U+200D
    text = text:gsub("\194\160", " ") -- NBSP
    text = text:gsub("\t", " ")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")

    local has_cjk = text:find("[\228-\233][\128-\191][\128-\191]") ~= nil
    if has_cjk then
        -- Paragraph / line breaks become light spoken pauses instead of long silences.
        text = text:gsub("\n\n+", "。")
        text = text:gsub("\n", "，")
    else
        text = text:gsub("\n\n+", ". ")
        text = text:gsub("\n", ", ")
    end

    text = text:gsub(" +", " ")
    text = text:gsub("，+", "，")
    text = text:gsub("。+", "。")
    text = text:gsub(",+", ",")
    text = text:gsub("%.+", ".")
    text = trim(text)
    return text
end

return Interaction
