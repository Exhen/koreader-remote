-- Lightweight gettext wrapper for plugin locale/*.po.
-- Install before requiring gettext in plugin modules.

local logger = require("logger")

local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.+/)") or "./")
local installed = false
local translations = nil

local function unescape_po(s)
    return s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
end

local function parse_po(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local map = {}
    local msgid = nil
    local msgstr = nil
    local current = nil

    local function flush()
        if msgid and msgid ~= "" and msgstr and msgstr ~= "" then
            map[msgid] = msgstr
        end
        msgid = nil
        msgstr = nil
        current = nil
    end

    for line in f:lines() do
        local text = line:match("^%s*(.-)%s*$")
        if text == "" then
            flush()
        elseif text:match("^#") then
            -- comment
        elseif text:match('^msgid%s+"') then
            flush()
            msgid = unescape_po(text:match('^msgid%s+"(.*)"') or "")
            current = "msgid"
        elseif text:match('^msgstr%s+"') then
            msgstr = unescape_po(text:match('^msgstr%s+"(.*)"') or "")
            current = "msgstr"
        elseif text:match('^"') then
            local cont = unescape_po(text:match('^"(.*)"') or "")
            if current == "msgid" then
                msgid = (msgid or "") .. cont
            elseif current == "msgstr" then
                msgstr = (msgstr or "") .. cont
            end
        end
    end
    flush()
    f:close()
    return map
end

local function detect_lang()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    if type(lang) == "string" and lang ~= "" then
        return lang
    end
    local lc = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    return lc:match("^([a-zA-Z_]+)") or "en"
end

local function load_translations()
    local lang = detect_lang()
    if lang == "C" or lang == "en" or lang:match("^en[_-]") then
        return nil
    end

    local function try(name)
        if not name or name == "" then
            return nil
        end
        local path = plugin_dir .. "locale/" .. name .. ".po"
        local entries = parse_po(path)
        if entries and next(entries) then
            logger.info("KOReaderRemote i18n: loaded locale", path)
            return entries
        end
        return nil
    end

    local normalized = lang:gsub("-", "_")
    local primary = normalized:match("^([a-zA-Z]+)")

    return try(normalized)
        or try(lang)
        or (primary == "zh" and try("zh_CN"))
        or (primary and try(primary))
end

local function install()
    if installed then
        return true
    end

    translations = load_translations()
    if not translations then
        return false
    end

    local orig_gettext = package.loaded["gettext"]
    if not orig_gettext then
        local ok, gt = pcall(require, "gettext")
        if not ok or not gt then
            logger.warn("KOReaderRemote i18n: cannot load gettext")
            return false
        end
        orig_gettext = gt
    end

    local wrapper = setmetatable({}, {
        __call = function(_, msgid)
            local translated = translations[msgid]
            if translated then
                return translated
            end
            if type(orig_gettext) == "table" and getmetatable(orig_gettext)
                and type(getmetatable(orig_gettext).__call) == "function" then
                return orig_gettext(msgid)
            elseif type(orig_gettext) == "function" then
                return orig_gettext(msgid)
            end
            return msgid
        end,
        __index = orig_gettext,
    })

    package.loaded["gettext"] = wrapper
    installed = true
    logger.info("KOReaderRemote i18n: gettext wrapper installed")
    return true
end

return {
    install = install,
}
