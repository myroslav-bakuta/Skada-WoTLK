-- SkadaLocale.lua
-- Holds nothing but Skada's language setting.

SkadaLocaleDB = SkadaLocaleDB or {}

-- nil means "not set yet", which the reader treats as Ukrainian (the default).
if SkadaLocaleDB.uklang == nil then
	SkadaLocaleDB.uklang = true
end
