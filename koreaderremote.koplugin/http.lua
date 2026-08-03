-- HTTP parsing, responses, and API routing for KOReader Remote.
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local M = {}

function M.attach(Remote, context)
    local runtime = context.runtime
    local VERSION = context.version
    local BUILD = context.build
    local INDEX_FILE = context.index_file
    local WEB_DIR = context.web_dir
        or (INDEX_FILE and INDEX_FILE:match("^(.*)/[^/]+$"))
        or "."
    local HTTP_STATUS = context.http_status
    local RECOVERY_RETRY_SECONDS = context.recovery_retry_seconds
    local function jsonEscape(value)
        value = tostring(value)
        value = value:gsub("\\", "\\\\")
        value = value:gsub('"', '\\"')
        value = value:gsub("\b", "\\b")
        value = value:gsub("\f", "\\f")
        value = value:gsub("\n", "\\n")
        value = value:gsub("\r", "\\r")
        value = value:gsub("\t", "\\t")
        value = value:gsub("[%z\1-\31]", function(character)
            return string.format("\\u%04x", string.byte(character))
        end)
        return '"' .. value .. '"'
    end

    local function jsonEncode(value)
        local value_type = type(value)

        if value_type == "nil" then
            return "null"
        elseif value_type == "boolean" then
            return value and "true" or "false"
        elseif value_type == "number" then
            if value ~= value or value == math.huge or value == -math.huge then
                return "null"
            end
            return tostring(value)
        elseif value_type == "string" then
            return jsonEscape(value)
        elseif value_type ~= "table" then
            return jsonEscape(tostring(value))
        end

        local is_array = true
        local maximum_index = 0
        local item_count = 0

        for key in pairs(value) do
            item_count = item_count + 1
            if type(key) ~= "number"
                or key < 1
                or key % 1 ~= 0 then
                is_array = false
                break
            end
            if key > maximum_index then
                maximum_index = key
            end
        end

        if is_array and maximum_index == item_count then
            local parts = {}
            for index = 1, maximum_index do
                parts[index] = jsonEncode(value[index])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end

        local keys = {}
        for key in pairs(value) do
            table.insert(keys, tostring(key))
        end
        table.sort(keys)

        local parts = {}
        for _, key in ipairs(keys) do
            table.insert(
                parts,
                jsonEscape(key) .. ":" .. jsonEncode(value[key])
            )
        end

        return "{" .. table.concat(parts, ",") .. "}"
    end

    local function urlDecode(value)
        value = tostring(value or "")
        value = value:gsub("%+", " ")
        return value:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
    end

    local function parseRequestURI(raw_uri)
        local path, query = raw_uri:match("^([^?]*)%??(.*)$")
        local params = {}

        if query and query ~= "" then
            for pair in query:gmatch("[^&]+") do
                local key, value = pair:match("^([^=]+)=?(.*)$")
                if key then
                    params[urlDecode(key)] = urlDecode(value)
                end
            end
        end

        return path or raw_uri, params
    end

    local function parseHeaders(data)
        local headers = {}

        for line in tostring(data or ""):gmatch("[^\r\n]+") do
            local name, value = line:match("^([^:]+):%s*(.*)$")
            if name then
                headers[name:lower()] = value
            end
        end

        return headers
    end

    local function parseBoolean(value)
        if value == true
            or value == "true"
            or value == "1"
            or value == "on" then
            return true
        end

        if value == false
            or value == "false"
            or value == "0"
            or value == "off" then
            return false
        end

        return nil
    end

function Remote:sendResponse(request_id, status, content_type, body, counts_as_input)
    status = status or 500
    body = body or ""

    local headers = {
        string.format(
            "HTTP/1.0 %d %s",
            status,
            HTTP_STATUS[status] or "Unspecified"
        ),
        "Connection: close",
        "Cache-Control: no-store",
        -- 允许独立静态前端（Hub）跨域直连本机 API
        "Access-Control-Allow-Origin: *",
        "Access-Control-Allow-Methods: GET, POST, OPTIONS",
        "Access-Control-Allow-Headers: Content-Type, Accept, X-KOReader-Input-Base64, X-KOReader-Input-Mode, Access-Control-Request-Private-Network, Access-Control-Request-Headers",
        "Access-Control-Max-Age: 86400",
        "Access-Control-Allow-Private-Network: true",
        "Private-Network-Access-Name: koreader-remote",
        "Private-Network-Access-ID: 00:00:00:43:91:70",
    }

    if content_type then
        table.insert(headers, "Content-Type: " .. content_type)
    end

    table.insert(headers, "Content-Length: " .. tostring(#body))
    table.insert(headers, "")
    table.insert(headers, body)

    if runtime.http_socket then
        runtime.http_socket:send(table.concat(headers, "\r\n"), request_id)
    end

    if counts_as_input then
        return Event:new("InputEvent")
    end
end


function Remote:sendJSON(request_id, status, payload, counts_as_input)
    return self:sendResponse(
        request_id,
        status,
        "application/json; charset=utf-8",
        jsonEncode(payload),
        counts_as_input
    )
end

function Remote:sendControlError(request_id, status, code, message)
    return self:sendJSON(request_id, status, {
        ok = false,
        error = code,
        message = message,
    })
end

function Remote:readIndex()
    local file, err = io.open(INDEX_FILE, "rb")
    if not file then
        return nil, err
    end

    local body = file:read("*all")
    file:close()
    return body
end

local STATIC_MIME = {
    css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8",
    html = "text/html; charset=utf-8",
    htm = "text/html; charset=utf-8",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    svg = "image/svg+xml",
    ico = "image/x-icon",
    json = "application/json; charset=utf-8",
    map = "application/json; charset=utf-8",
    txt = "text/plain; charset=utf-8",
    woff = "font/woff",
    woff2 = "font/woff2",
}

function Remote:readWebStatic(relative_name)
    if type(relative_name) ~= "string" or relative_name == "" then
        return nil, "empty"
    end
    -- Only simple filenames under web/, no path traversal.
    if relative_name:find("[/\\]") or relative_name:find("%.%.") then
        return nil, "invalid path"
    end
    if not relative_name:match("^[%w%._%-]+$") then
        return nil, "invalid name"
    end

    local path = WEB_DIR .. "/" .. relative_name
    -- Web zh_CN catalog lives with other plugin locales.
    if relative_name == "i18n-zh_CN.json" then
        local plugin_dir = WEB_DIR:match("^(.*)/[^/]+$") or "."
        path = plugin_dir .. "/locale/web_zh_CN.json"
    end

    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local body = file:read("*all")
    file:close()
    if type(body) ~= "string" then
        return nil, "read failed"
    end

    local ext = relative_name:match("%.([%w]+)$")
    ext = ext and ext:lower() or ""
    local mime = STATIC_MIME[ext] or "application/octet-stream"
    return body, nil, mime
end

function Remote:hasOpenDocument()
    local owner = runtime.owner
    runtime.document_open = owner ~= nil
        and owner.ui ~= nil
        and owner.ui.document ~= nil
    return runtime.document_open == true
end

function Remote:turnPage(delta)
    if not self:hasOpenDocument() then
        return false
    end

    UIManager:nextTick(function()
        UIManager:sendEvent(Event:new("GotoViewRel", delta))
    end)
    return true
end

-- Wait until KOReader has applied the page turn before answering HTTP.
-- Without this, clients can fetch /page-text while the view is still stale.
function Remote:turnPageWhenReady(delta, callback)
    if type(callback) ~= "function" then
        return self:turnPage(delta)
    end

    if not self:hasOpenDocument() then
        callback(false, "NO_DOCUMENT_OPEN")
        return false
    end

    local before_key = nil
    local before_hash = nil
    local function readSnapshot()
        local ok_call, snap_ok, snap =
            pcall(runtime.interaction.getReadingSnapshot, runtime.interaction)
        if ok_call and snap_ok and type(snap) == "table" then
            return snap
        end
        return nil
    end

    local before = readSnapshot()
    if before then
        before_key = before.page_key
        before_hash = before.content_hash
    end

    UIManager:nextTick(function()
        UIManager:sendEvent(Event:new("GotoViewRel", delta))

        local attempts = 0
        local max_attempts = 12

        local function waitForAppliedTurn()
            attempts = attempts + 1

            local after = readSnapshot()
            local after_key = after and after.page_key or nil
            local after_hash = after and after.content_hash or nil

            local changed = false
            if before_key and after_key and after_key ~= before_key then
                changed = true
            elseif before_hash and after_hash and after_hash ~= before_hash then
                changed = true
            elseif not before_key and not before_hash and attempts >= 3 then
                changed = true
            end

            if changed or attempts >= max_attempts then
                callback(true)
                return
            end

            UIManager:nextTick(waitForAppliedTurn)
        end

        UIManager:nextTick(waitForAppliedTurn)
    end)
    return true
end

function Remote:augmentDeviceState(state)
    state = state or {}
    state.idle_timeout_minutes = self:getIdleTimeoutMinutes()
    state.idle_timeout_seconds_remaining = self:getIdleTimeoutRemainingSeconds()
    return state
end

function Remote:onRequestUnsafe(data, request_id)
    local method, raw_uri = data:match(
        "^(%u+)%s+([^%s]+)%s+HTTP/%d%.%d"
    )

    if not method or not raw_uri then
        return self:sendResponse(
            request_id,
            400,
            "text/plain; charset=utf-8",
            "Invalid HTTP request"
        )
    end

    local uri, params = parseRequestURI(raw_uri)
    local headers = parseHeaders(data)
    logger.dbg("KOReaderRemote:", method, uri)

    -- 浏览器跨域预检（静态 Hub / 局域网页面直连）
    if method == "OPTIONS" then
        return self:sendResponse(request_id, 204, nil, "")
    end

    if uri ~= "/"
        and uri ~= "/index.html"
        and uri ~= "/styles.css"
        and uri ~= "/app.js"
        and uri ~= "/api/ping"
        and uri ~= "/api/v1/capabilities"
        and uri ~= "/api/v1/device-state"
        and uri ~= "/api/v1/note-session"
        and uri ~= "/api/v1/bookmarks"
        and uri ~= "/api/v1/footnotes"
        and uri ~= "/api/v1/toc"
        and uri ~= "/api/v1/input"
        and uri ~= "/api/v1/book-cover"
        and uri ~= "/api/v1/page-jump"
        and uri ~= "/favicon.ico" then
        self:markActivity()
    end

    if method ~= "GET" and method ~= "POST" then
        return self:sendResponse(
            request_id,
            405,
            "text/plain; charset=utf-8",
            "Only GET and POST are supported"
        )
    end

    if uri == "/" or uri == "/index.html" then
        if method ~= "GET" then
            return self:sendResponse(
                request_id,
                405,
                "text/plain; charset=utf-8",
                "Only GET is supported for this resource"
            )
        end

        local body, err = self:readIndex()
        if not body then
            logger.err("KOReaderRemote: could not read index.html:", err)
            return self:sendResponse(
                request_id,
                500,
                "text/plain; charset=utf-8",
                "Remote UI file is missing"
            )
        end

        return self:sendResponse(
            request_id,
            200,
            "text/html; charset=utf-8",
            body,
            true
        )
    end

    -- 静态前端资源：/styles.css /app.js 等（与 index 同目录）
    do
        local static_name = uri:match("^/([%w%._%-]+)$")
        if static_name
            and static_name ~= "api"
            and method == "GET"
        then
            local body, err, mime = self:readWebStatic(static_name)
            if body then
                return self:sendResponse(
                    request_id,
                    200,
                    mime,
                    body,
                    false
                )
            end
            if err ~= "invalid path" and err ~= "invalid name" and err ~= "empty" then
                logger.dbg("KOReaderRemote: static miss", static_name, err)
            end
        end
    end

    if uri == "/api/ping" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local Device = require("device")
        local device_name = Device.model
        if type(device_name) ~= "string" or device_name == "" then
            local ok, info = pcall(function()
                return Device:info()
            end)
            if ok and type(info) == "string" and info ~= "" then
                device_name = info
            else
                device_name = "KOReader"
            end
        end

        local book_title = nil
        local page_key = nil
        local page = nil
        if self:hasOpenDocument()
            and runtime.interaction then
            if type(runtime.interaction.getBookTitle) == "function" then
                local owner = runtime.owner
                local title = runtime.interaction:getBookTitle(owner and owner.ui)
                if type(title) == "string" and title ~= "" then
                    book_title = title
                end
            end
            if type(runtime.interaction.getReadingPosition) == "function" then
                local ok_call, snap_ok, snap = pcall(
                    runtime.interaction.getReadingPosition,
                    runtime.interaction
                )
                if ok_call and snap_ok and type(snap) == "table" then
                    if type(snap.page_key) == "string" and snap.page_key ~= "" then
                        page_key = snap.page_key
                    end
                    if type(snap.page) == "string" and snap.page ~= "" then
                        page = snap.page
                    elseif page_key then
                        page = page_key
                    end
                end
            end
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            version = VERSION,
            channel = BUILD.channel,
            source = BUILD.source,
            release_version = BUILD.release_version,
            build_id = BUILD.build_id,
            commit = BUILD.commit,
            device_name = device_name,
            book_title = book_title,
            page_key = page_key,
            page = page,
            state = runtime.state,
            port = runtime.running_port or self:getPort(),
            autostart = runtime.autostart == true,
            manual_session = runtime.manual_session == true,
            document_open = self:hasOpenDocument(),
            ip = runtime.local_ip,
            url = runtime.connection_url,
            url_revision = runtime.connection_revision,
            recovery_retry_seconds = RECOVERY_RETRY_SECONDS,
            idle_timeout_minutes = self:getIdleTimeoutMinutes(),
            idle_timeout_seconds_remaining =
                self:getIdleTimeoutRemainingSeconds(),
            note_session_active = runtime.interaction
                and runtime.interaction:getNoteSessionState().active
                or false,
        })
    end

    if uri == "/api/next" or uri == "/api/previous" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for legacy page-turn endpoints."
            )
        end

        local delta = uri == "/api/next" and 1 or -1
        local action = delta == 1 and "next" or "previous"

        if not self:turnPageWhenReady(delta, function(success, code)
            if not success then
                self:sendControlError(
                    request_id,
                    409,
                    code or "NO_DOCUMENT_OPEN",
                    "Open a book on the reader first."
                )
                return
            end

            self:sendJSON(
                request_id,
                200,
                { ok = true, action = action },
                true
            )
        end) then
            return self:sendControlError(
                request_id,
                409,
                "NO_DOCUMENT_OPEN",
                "Open a book on the reader first."
            )
        end
        return
    end

    local controls = runtime.device_controls

    if uri == "/api/v1/page-jump" then
        if method ~= "GET" and method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET or POST for this endpoint."
            )
        end

        if not runtime.interaction then
            return self:sendControlError(
                request_id,
                501,
                "NOT_SUPPORTED",
                "Page jump is not available."
            )
        end

        local target = tonumber(params.page or params.target)
        if target == nil then
            local ok, result, message = runtime.interaction:getPageJumpInfo()
            if not ok then
                return self:sendControlError(
                    request_id,
                    409,
                    result,
                    message or "Open a book on the reader first."
                )
            end
            return self:sendJSON(request_id, 200, {
                ok = true,
                jump = result,
            })
        end

        local ok, result, message = runtime.interaction:gotoPageNumber(target)
        if not ok then
            local status = 409
            if result == "INVALID_PAGE" or result == "PAGE_OUT_OF_RANGE" then
                status = 400
            elseif result == "GOTO_FAILED" then
                status = 409
            end
            return self:sendControlError(
                request_id,
                status,
                result,
                message or "Could not jump to that page."
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            action = result.action,
            page = result.page,
            page_key = result.page_key,
            target = result.target,
        }, true)
    end

    if uri == "/api/v1/book-cover" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        if not runtime.interaction
            or type(runtime.interaction.getBookCoverImageBytes) ~= "function" then
            return self:sendControlError(
                request_id,
                501,
                "NOT_SUPPORTED",
                "Book cover export is not available."
            )
        end

        local ok, result = runtime.interaction:getBookCoverImageBytes()
        if not ok then
            local code = tostring(result or "NO_COVER")
            local status = code == "NO_DOCUMENT_OPEN" and 409 or 404
            return self:sendControlError(
                request_id,
                status,
                code,
                "No book cover is available for the current document."
            )
        end

        return self:sendResponse(request_id, 200, "image/png", result)
    end

    if uri == "/api/v1/capabilities" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local capabilities = {}
        for name, supported in pairs(controls:getCapabilities()) do
            capabilities[name] = supported
        end
        for name, supported in pairs(
            runtime.interaction:getCapabilities()
        ) do
            capabilities[name] = supported
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            version = VERSION,
            channel = BUILD.channel,
            source = BUILD.source,
            release_version = BUILD.release_version,
            build_id = BUILD.build_id,
            commit = BUILD.commit,
            capabilities = capabilities,
        })
    end

    if uri == "/api/v1/device-state" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            version = VERSION,
            channel = BUILD.channel,
            source = BUILD.source,
            release_version = BUILD.release_version,
            build_id = BUILD.build_id,
            commit = BUILD.commit,
            state = self:augmentDeviceState(controls:getState()),
        })
    end

    if uri == "/api/v1/idle-stop" then
        if method == "GET" then
            return self:sendJSON(request_id, 200, {
                ok = true,
                minutes = self:getIdleTimeoutMinutes(),
                idle_timeout_seconds_remaining =
                    self:getIdleTimeoutRemainingSeconds(),
            })
        end

        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET or POST for this endpoint."
            )
        end

        local minutes = tonumber(params.minutes)
        if not minutes or minutes < 0 or minutes > 1440
            or minutes * 2 % 1 ~= 0 then
            return self:sendControlError(
                request_id,
                400,
                "INVALID_IDLE_TIMEOUT",
                "Idle stop must be a number from 0 to 1440 minutes in 30-second steps."
            )
        end

        self:setIdleTimeoutMinutes(minutes)
        return self:sendJSON(request_id, 200, {
            ok = true,
            minutes = self:getIdleTimeoutMinutes(),
            idle_timeout_seconds_remaining =
                self:getIdleTimeoutRemainingSeconds(),
        })
    end

    if uri == "/api/v1/note-session" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            session = runtime.interaction:getNoteSessionState(),
        })
    end

    if uri == "/api/v1/note-session/push" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message, session =
            runtime.interaction:pushEncodedNote(
                headers["x-koreader-note-base64"],
                headers["x-koreader-note-revision"]
            )

        if not ok then
            local status = 400
            if result == "NOTE_CONFLICT"
                or result == "NO_NOTE_SESSION"
                or result == "NOTE_SESSION_EXPIRED" then
                status = 409
            elseif result == "NOTE_TOO_LARGE" then
                status = 413
            end

            return self:sendJSON(request_id, status, {
                ok = false,
                error = result,
                message = message,
                session = session,
            })
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = "note_draft_updated",
                session = result,
            },
            true
        )
    end

    if uri == "/api/v1/note-session/save" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message, session =
            runtime.interaction:saveNoteSession(
                headers["x-koreader-note-revision"],
                nil,
                "phone"
            )

        if not ok then
            local status = 400
            if result == "NOTE_CONFLICT"
                or result == "NO_NOTE_SESSION"
                or result == "NOTE_SESSION_EXPIRED"
                or result == "NOTE_DIALOG_CLOSED" then
                status = 409
            end

            return self:sendJSON(request_id, status, {
                ok = false,
                error = result,
                message = message,
                session = session,
            })
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = "note_saved",
                session = result,
            },
            true
        )
    end

    if uri == "/api/v1/note-session/cancel" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        runtime.interaction:cancelNoteSession(
            "cancelled from phone",
            true,
            true
        )
        return self:sendJSON(request_id, 200, {
            ok = true,
            action = "note_session_cancelled",
        })
    end

    if uri == "/api/v1/bookmarks" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:getBookmarks()

        if not ok then
            return self:sendControlError(
                request_id,
                409,
                result,
                message
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            book = result,
        })
    end

    if uri == "/api/v1/toc" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local ok, result, message = runtime.interaction:getToc()

        if not ok then
            local status = 409
            if result == "TOC_NOT_SUPPORTED" then
                status = 501
            elseif result == "NO_DOCUMENT_OPEN" then
                status = 409
            end

            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            toc = result,
        })
    end

    if uri == "/api/v1/toc/open" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:openTocEntry(params.id)

        if not ok then
            local status = 409
            if result == "MISSING_TOC_ENTRY" then
                status = 400
            elseif result == "TOC_NOT_SUPPORTED" then
                status = 501
            end

            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                id = result.id,
                title = result.title,
                page = result.page,
                return_position = result.return_position,
            },
            true
        )
    end

    if uri == "/api/v1/toc/return" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:returnToReadingPosition()

        if not ok then
            local status = result == "NO_RETURN_POSITION" and 404 or 409
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                page = result.page,
                return_position = result.return_position,
            },
            true
        )
    end

    if uri == "/api/v1/input" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local ok, result = runtime.interaction:getInputStatus()
        if not ok then
            return self:sendControlError(
                request_id,
                500,
                "INPUT_STATUS_FAILED",
                "Could not inspect the reader input box."
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            input = result,
        })
    end

    if uri == "/api/v1/input/push" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local mode = params.mode or headers["x-koreader-input-mode"]
        local ok, result, message = runtime.interaction:pushInputText(
            headers["x-koreader-input-base64"],
            mode
        )

        if not ok then
            local status = 400
            if result == "NO_INPUT"
                or result == "PASSWORD_FIELD"
                or result == "NOT_EDITABLE"
                or result == "INPUT_CLOSED" then
                status = 409
            elseif result == "NOTE_TOO_LARGE" then
                status = 413
            elseif result == "MISSING_NOTE" then
                status = 400
            end

            return self:sendJSON(request_id, status, {
                ok = false,
                error = result,
                message = message,
            })
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                mode = result.mode,
                input = result.input,
            },
            true
        )
    end

    if uri == "/api/v1/bookmarks/open" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:openBookmark(params.id)

        if not ok then
            local status = result == "MISSING_BOOKMARK" and 400 or 409

            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                type = result.type,
                page = result.page,
                return_position = result.return_position,
            },
            true
        )
    end

    if uri == "/api/v1/bookmarks/return" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:returnToReadingPosition()

        if not ok then
            return self:sendControlError(
                request_id,
                409,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                page = result.page,
                return_position = result.return_position,
            },
            true
        )
    end

    if uri == "/api/v1/bookmarks/edit-note" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:editBookmarkNote(params.id)

        if not ok then
            local status = result == "MISSING_BOOKMARK" and 400 or 409
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                session = result.session,
            },
            true
        )
    end

    if uri == "/api/v1/bookmarks/delete-note" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:deleteBookmarkNote(params.id)

        if not ok then
            local status = result == "MISSING_BOOKMARK" and 400 or 409
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                type = result.type,
                return_position = result.return_position,
            },
            true
        )
    end

    if uri == "/api/v1/bookmarks/delete" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:deleteBookmark(params.id)

        if not ok then
            local status = result == "MISSING_BOOKMARK" and 400 or 409
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                type = result.type,
                return_position = result.return_position,
            },
            true
        )
    end

    if uri == "/api/v1/footnotes" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:listFootnotes()

        if not ok then
            local status = result == "NOT_SUPPORTED" and 501 or 404
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            page_key = result.page_key,
            count = result.count,
            footnotes = result.footnotes,
            popup_open = result.popup_open,
        }, true)
    end

    if uri == "/api/v1/page-turn" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local delta = tonumber(params.delta) or 1
        if delta ~= 1 and delta ~= -1 then
            return self:sendControlError(
                request_id,
                400,
                "INVALID_DELTA",
                "delta must be 1 or -1."
            )
        end

        local include_text = params.include_text == "1"
            or params.include_text == "true"
        local action = delta == 1 and "next" or "previous"

        if not self:turnPageWhenReady(delta, function(success, code)
            if not success then
                self:sendControlError(
                    request_id,
                    409,
                    code or "NO_DOCUMENT_OPEN",
                    "Open a book on the reader first."
                )
                return
            end

            local payload = {
                ok = true,
                action = action,
            }

            if include_text then
                local ok, result, message =
                    runtime.interaction:getCurrentPageText()
                if ok then
                    payload.page = result
                else
                    payload.page_error = message
                    payload.page_error_code = result
                end
            else
                local ok, snapshot = runtime.interaction:getReadingSnapshot()
                if ok then
                    payload.page_key = snapshot.page_key
                    payload.page = snapshot.page
                    payload.content_hash = snapshot.content_hash
                end
            end

            self:sendJSON(request_id, 200, payload, true)
        end) then
            return self:sendControlError(
                request_id,
                409,
                "NO_DOCUMENT_OPEN",
                "Open a book on the reader first."
            )
        end
        return
    end

    if uri == "/api/v1/page-text" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:getCurrentPageText()

        if not ok then
            local status = 404
            if result == "NOT_SUPPORTED" then
                status = 501
            elseif result == "NO_DOCUMENT_OPEN" then
                status = 409
            end
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            page = result,
        }, true)
    end

    if uri == "/api/v1/page-text/peek" then
        if method ~= "GET" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use GET for this endpoint."
            )
        end

        local max_skip = tonumber(params.max_skip) or 12
        local ok, result, message =
            runtime.interaction:peekNextSpeakablePageText(max_skip)

        if not ok then
            local status = 404
            if result == "NOT_SUPPORTED" then
                status = 501
            elseif result == "NO_DOCUMENT_OPEN" then
                status = 409
            end
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        if result.end_of_book then
            return self:sendJSON(request_id, 200, {
                ok = true,
                end_of_book = true,
                turn_count = result.turn_count or 0,
            }, true)
        end

        return self:sendJSON(request_id, 200, {
            ok = true,
            end_of_book = false,
            turn_count = result.turn_count or 1,
            page = result,
        }, true)
    end

    if uri == "/api/v1/footnote/open" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:openFootnoteById(params.id)

        if not ok then
            local status = 404
            if result == "NOT_SUPPORTED" then
                status = 501
            elseif result == "INVALID_FOOTNOTE" then
                status = 400
            end

            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                id = result.id,
                marker = result.marker,
                popup_open = result.popup_open,
            },
            true
        )
    end

    if uri == "/api/v1/footnote/close" then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for this endpoint."
            )
        end

        local ok, result, message =
            runtime.interaction:closeFootnotePopup()

        if not ok then
            return self:sendControlError(
                request_id,
                404,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = result.action,
                closed = result.closed,
                popup_open = result.popup_open,
            },
            true
        )
    end

    if uri:match("^/api/v1/") then
        if method ~= "POST" then
            return self:sendControlError(
                request_id,
                405,
                "METHOD_NOT_ALLOWED",
                "Use POST for device-control actions."
            )
        end

        local ok, result, message
        local action

        if uri == "/api/v1/frontlight/toggle" then
            action = "frontlight_toggle"
            ok, result, message = controls:toggleFrontlight()
        elseif uri == "/api/v1/frontlight" then
            action = "frontlight"
            local enabled = parseBoolean(params.enabled)
            if enabled == nil then
                return self:sendControlError(
                    request_id,
                    400,
                    "INVALID_VALUE",
                    "The enabled parameter must be true or false."
                )
            end
            ok, result, message = controls:setFrontlight(enabled)
        elseif uri == "/api/v1/brightness" then
            action = "brightness"
            ok, result, message = controls:setBrightness(params.value)
        elseif uri == "/api/v1/warmth" then
            action = "warmth"
            ok, result, message = controls:setWarmth(params.value)
        elseif uri == "/api/v1/night-mode/toggle" then
            action = "night_mode_toggle"
            ok, result, message = controls:toggleNightMode()
        elseif uri == "/api/v1/night-mode" then
            action = "night_mode"
            local enabled = parseBoolean(params.enabled)
            if enabled == nil then
                return self:sendControlError(
                    request_id,
                    400,
                    "INVALID_VALUE",
                    "The enabled parameter must be true or false."
                )
            end
            ok, result, message = controls:setNightMode(enabled)
        elseif uri == "/api/v1/full-refresh" then
            action = "full_refresh"
            ok, result, message = controls:fullRefresh()
        else
            return self:sendControlError(
                request_id,
                404,
                "NOT_FOUND",
                "Unknown device-control endpoint."
            )
        end

        if not ok then
            local status = result == "NOT_SUPPORTED" and 501 or 400
            return self:sendControlError(
                request_id,
                status,
                result,
                message
            )
        end

        return self:sendJSON(
            request_id,
            200,
            {
                ok = true,
                action = action,
                state = result,
            },
            true
        )
    end

    if uri == "/favicon.ico" then
        return self:sendResponse(request_id, 204, nil, "")
    end

    return self:sendResponse(
        request_id,
        404,
        "text/plain; charset=utf-8",
        "Not found"
    )
end

-- Keep unexpected KOReader/API failures inside the request boundary. A bad
-- document or device state must produce one response, not escape the server
-- callback and potentially break later requests.
function Remote:onRequest(data, request_id)
    local ok, result = xpcall(function()
        return self:onRequestUnsafe(data, request_id)
    end, debug.traceback)

    if ok then
        return result
    end

    logger.err("KOReaderRemote: unhandled HTTP request error:", result)
    return self:sendControlError(
        request_id,
        500,
        "INTERNAL_ERROR",
        "The reader could not handle this request."
    )
end



end

return M
