local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.+/)") or "./")
local i18n_loader = loadfile(plugin_dir .. "i18n.lua")
if i18n_loader then
    local i18n_ok, i18n = pcall(i18n_loader)
    if i18n_ok and type(i18n) == "table" and i18n.install then
        i18n.install()
    end
end

local _ = require("gettext")

return {
    fullname = _("KOReader Remote"),
    description = _([[Control KOReader page turns, device settings, footnotes, and selected-text notes from a phone with QR pairing and reliable Wi-Fi recovery.]]),
}
