if not _G.Skada then return end

local L = LibStub("AceLocale-3.0"):NewLocale("Skada", "enUS")
if L then
	L["Improvement"] = true
	L["Improvement modes"] = true
	L["Improvement comparison"] = true
	L["Do you want to reset your improvement data?"] = true
	L["%s's overall data"] = true
	return
end

L = LibStub("AceLocale-3.0"):NewLocale("Skada", "ruRU")
if L then
	L["Improvement"] = "Улучшение"
	L["Improvement modes"] = "Режимы улучшения"
	L["Improvement comparison"] = "Сравнение улучшений"
	L["Do you want to reset your improvement data?"] = "Вы хотите сбросить данные об улучшении?"
	L["%s's overall data"] = "%s - Данные об улучшении"

	-- Ukrainian overlay (mod by Kappa). The 3.3.5a client has no ukUA game
	-- locale, so on a Russian client this ruRU block is the one that runs and
	-- fills the plugin's strings with Russian ("Улучшение", ...). Skada overlays
	-- Ukrainian in Core\Init.lua, but this addon depends on Skada and loads
	-- *after* it, re-registering Russian on top. So right here, after the
	-- Russian strings are set (and before this block returns), we overwrite them
	-- with Ukrainian, gated on the same account-wide toggle Skada uses: nil
	-- means "default on", only an explicit false disables it.
	if not (SkadaDB and SkadaDB.global and SkadaDB.global.uklang == false) then
		L["Improvement"] = "Покращення"
		L["Improvement modes"] = "Режими покращення"
		L["Improvement comparison"] = "Порівняння покращення"
		L["Do you want to reset your improvement data?"] = "Бажаєте скинути дані про покращення?"
		L["%s's overall data"] = "%s - загальні дані"
	end
	return
end
