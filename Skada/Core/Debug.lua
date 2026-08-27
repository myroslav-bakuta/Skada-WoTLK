-- Debug.lua
-- Diagnostic log written to SavedVariables.
--
-- The 3.3.5 client gives addons no way to write a file, so the log is kept in
-- memory and lands in WTF\Account\<account>\SavedVariables\Skada.lua when the
-- client saves, that is on /reload or on logout.

local folder, ns = ...
local Private = ns.Private

local format, tostring, type = string.format, tostring, type
local tinsert, tconcat, wipe = table.insert, table.concat, wipe
local date, time, GetTime = date, time, GetTime
local select, pairs = select, pairs
local band = bit.band

-- keep the saved variable from growing without bound. a full 25 man raid night,
-- twelve bosses and the trash between them, runs to roughly 20k lines with the
-- roster snapshots deduplicated, so one session has room for a whole night.
local MAX_LINES = 50000 -- per session
local MAX_SESSIONS = 3 -- kept in the saved variable
local MAX_TOTAL_LINES = 90000 -- across all kept sessions, whatever their count
local MAX_ONCE_KEYS = 2000 -- distinct deduplicated keys per session
local MAX_TRACE = 400 -- raw combat log events per segment, verbose only

local log = nil -- current session's line list
local once = nil -- keys already logged once
local once_count = 0
local trace_left = 0
local enabled = false
local verbose = false
local start_clock = 0 -- GetTime() when the session started
local start_time = 0 -- time() when the session started
local last_roster = nil -- the last roster snapshot written, to skip repeats

-------------------------------------------------------------------------------
-- combat log flag decoding

local AFFILIATION = {
	[COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001] = "MINE",
	[COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002] = "PARTY",
	[COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004] = "RAID",
	[COMBATLOG_OBJECT_AFFILIATION_OUTSIDER or 0x00000008] = "OUTSIDER"
}
local REACTION = {
	[COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010] = "FRIENDLY",
	[COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x00000020] = "NEUTRAL",
	[COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040] = "HOSTILE"
}
local CONTROL = {
	[COMBATLOG_OBJECT_CONTROL_PLAYER or 0x00000100] = "CTRL_PLAYER",
	[COMBATLOG_OBJECT_CONTROL_NPC or 0x00000200] = "CTRL_NPC"
}
local UNITTYPE = {
	[COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400] = "PLAYER",
	[COMBATLOG_OBJECT_TYPE_NPC or 0x00000800] = "NPC",
	[COMBATLOG_OBJECT_TYPE_PET or 0x00001000] = "PET",
	[COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000] = "GUARDIAN",
	[COMBATLOG_OBJECT_TYPE_OBJECT or 0x00004000] = "OBJECT"
}

local function decode_group(t, flags, out)
	for bit, name in pairs(t) do
		if band(flags, bit) ~= 0 then
			out[#out + 1] = name
		end
	end
end

-- "0x0514(MINE|FRIENDLY|CTRL_PLAYER|PLAYER)"
function Private.DecodeFlags(flags)
	if type(flags) ~= "number" then return tostring(flags) end

	local out = {}
	decode_group(AFFILIATION, flags, out)
	decode_group(REACTION, flags, out)
	decode_group(CONTROL, flags, out)
	decode_group(UNITTYPE, flags, out)
	return format("0x%04X(%s)", flags, #out > 0 and tconcat(out, "|") or "none")
end

-------------------------------------------------------------------------------
-- the log itself

-- both halves come from GetTime, the only monotonic clock we have. taking
-- the seconds from date() and the fraction from GetTime let the two drift,
-- so lines logged milliseconds apart could print out of order.
local function stamp()
	local elapsed = GetTime() - start_clock
	return format("%s.%03d", date("%H:%M:%S", start_time + elapsed), elapsed % 1 * 1000)
end

-- writes one line. never errors: a broken format string must not break combat.
function ns:LogDebug(cat, fmt, ...)
	if not enabled or not log then return end

	if #log >= MAX_LINES then
		if #log == MAX_LINES then
			log[#log + 1] = format("%s [log] line cap %d reached, nothing more recorded", stamp(), MAX_LINES)
		end
		return
	end

	local msg
	if select("#", ...) > 0 then
		local ok, res = pcall(format, fmt, ...)
		msg = ok and res or ("<bad format: " .. tostring(fmt) .. ">")
	else
		msg = tostring(fmt)
	end

	log[#log + 1] = format("%s [%s] %s", stamp(), cat, msg)
end

-- writes one line the first time it is called with this key.
function ns:LogDebugOnce(key, cat, fmt, ...)
	if not enabled or not log or not key then return end
	if once[key] then return end

	if once_count >= MAX_ONCE_KEYS then return end
	once[key] = true
	once_count = once_count + 1

	self:LogDebug(cat, fmt, ...)
end

-- bounded raw combat log trace, verbose mode only.
function ns:LogDebugTrace(cat, fmt, ...)
	if not verbose or trace_left <= 0 then return end
	trace_left = trace_left - 1
	self:LogDebug(cat, fmt, ...)
end

function ns:LogDebugEnabled()
	return enabled
end

function ns:LogDebugResetTrace()
	trace_left = verbose and MAX_TRACE or 0
end

-------------------------------------------------------------------------------
-- session handling

local function new_session(db)
	log, once, once_count = {}, {}, 0
	last_roster = nil -- a fresh session logs the roster in full again
	start_clock, start_time = GetTime(), time()

	db.sessions = db.sessions or {}
	tinsert(db.sessions, {started = date("%Y-%m-%d %H:%M:%S"), lines = log})

	while #db.sessions > MAX_SESSIONS do
		table.remove(db.sessions, 1)
	end

	-- a raid sized session is worth several short ones, so bound the file by
	-- the lines it holds too. the current session is never dropped.
	local total = 0
	for i = 1, #db.sessions do
		local lines = db.sessions[i].lines
		total = total + (lines and #lines or 0)
	end
	while #db.sessions > 1 and total > MAX_TOTAL_LINES do
		local lines = db.sessions[1].lines
		total = total - (lines and #lines or 0)
		table.remove(db.sessions, 1)
	end
end

-- called from Skada:OnInitialize, once the saved variable exists.
function Private.SetupDebugLog()
	_G.SkadaDebugLog = _G.SkadaDebugLog or {}
	local db = _G.SkadaDebugLog

	enabled = db.enabled and true or false
	verbose = db.verbose and true or false
	ns.debuglog_on = enabled -- cheap flag for the combat log hot path

	if not enabled then
		log, once = nil, nil
		return
	end

	new_session(db)
	ns:LogDebugResetTrace()
	Private.LogDebugHeader()
end

function Private.ToggleDebugLog(on, be_verbose)
	local db = _G.SkadaDebugLog or {}
	_G.SkadaDebugLog = db

	db.enabled = on and true or false
	if be_verbose ~= nil then
		db.verbose = be_verbose and true or false
	end

	enabled = db.enabled
	verbose = db.verbose and true or false
	ns.debuglog_on = enabled

	if enabled and not log then
		new_session(db)
		Private.LogDebugHeader()
	end
	ns:LogDebugResetTrace()

	return enabled, verbose
end

function Private.ClearDebugLog()
	local db = _G.SkadaDebugLog
	if not db then return end

	db.sessions = nil
	log, once, once_count = nil, nil, 0

	if enabled then
		new_session(db)
		ns:LogDebugResetTrace()
		Private.LogDebugHeader()
	end
end

function Private.DebugLogStatus()
	local db = _G.SkadaDebugLog
	local lines = log and #log or 0
	local sessions = (db and db.sessions) and #db.sessions or 0
	return enabled, verbose, lines, sessions
end

-------------------------------------------------------------------------------
-- session header: everything that describes the environment once

function Private.LogDebugHeader()
	if not enabled or not log then return end

	ns:LogDebug("init", "Skada %s (%s)", tostring(ns.version), tostring(ns.date))
	ns:LogDebug("init", "client locale=%s realm=%s player=%s (%s) class=%s level=%s",
		tostring(GetLocale and GetLocale()),
		tostring(GetRealmName and GetRealmName()),
		tostring(ns.userName), tostring(ns.userGUID), tostring(ns.userClass),
		tostring(UnitLevel and UnitLevel("player")))

	-- which LibBossIDs actually won the LibStub race, and how big it is
	local LBI = LibStub and LibStub("LibBossIDs-1.0", true)
	local count = 0
	if LBI and LBI.BossIDs then
		for _ in pairs(LBI.BossIDs) do count = count + 1 end
	end
	ns:LogDebug("init", "LibBossIDs-1.0 minor=%s entries=%d",
		tostring(LibStub and LibStub.minors and LibStub.minors["LibBossIDs-1.0"]), count)

	ns:LogDebug("init", "AceTimer-3.0 minor=%s AceGUI-3.0 minor=%s",
		tostring(LibStub and LibStub.minors and LibStub.minors["AceTimer-3.0"]),
		tostring(LibStub and LibStub.minors and LibStub.minors["AceGUI-3.0"]))

	-- boss mod version: mod tables differ between builds, and a fight the mod
	-- registers without a creature id is exactly what breaks defeat detection.
	local DBM = _G.DBM
	ns:LogDebug("init", "bossmod=%s DBM=%s (version=%s rev=%s) BigWigs=%s",
		tostring(ns.bossmod), tostring(DBM ~= nil),
		DBM and tostring(DBM.DisplayVersion or DBM.Version) or "-",
		DBM and tostring(DBM.Revision) or "-",
		tostring(_G.BigWigs ~= nil))

	local P = ns.profile
	if P then
		ns:LogDebug("init",
			"profile onlykeepbosses=%s alwayskeepbosses=%s setstokeep=%s setslimit=%s",
			tostring(P.onlykeepbosses), tostring(P.alwayskeepbosses),
			tostring(P.setstokeep), tostring(P.setslimit))
		ns:LogDebug("init",
			"profile smartstop=%s smartwait=%s autostop=%s tentativecombatstart=%s",
			tostring(P.smartstop), tostring(P.smartwait),
			tostring(P.autostop), tostring(P.tentativecombatstart))
		ns:LogDebug("init", "profile stalecombat=%s stalecombattime=%s combatgrace=%s",
			tostring(P.stalecombat), tostring(P.stalecombattime), tostring(P.combatgrace))
		ns:LogDebug("init", "profile autostopclose=%s bosssplit=%s bosssplittime=%s",
			tostring(P.autostopclose), tostring(P.bosssplit), tostring(P.bosssplittime))
		ns:LogDebug("init",
			"profile timemesure=%s minsetlength=%s updatefrequency=%s hidesolo=%s syncoff=%s",
			tostring(P.timemesure), tostring(P.minsetlength),
			tostring(P.updatefrequency), tostring(P.hidesolo), tostring(P.syncoff))

		local blocked = {}
		if P.modulesBlocked then
			for name, is_blocked in pairs(P.modulesBlocked) do
				if is_blocked then blocked[#blocked + 1] = name end
			end
		end
		ns:LogDebug("init", "blocked modules: %s", #blocked > 0 and tconcat(blocked, ", ") or "none")
	end

	-- other combat meters loaded alongside us
	if GetNumAddOns then
		local others = {}
		for i = 1, GetNumAddOns() do
			local name, _, _, loadable = GetAddOnInfo(i)
			if name and IsAddOnLoaded(i) then
				local lname = name:lower()
				if lname:find("recount") or lname:find("details") or lname:find("skada")
					or lname:find("dbm-core") or lname:find("bigwigs") or lname:find("omen") then
					others[#others + 1] = format("%s(%s)", name, tostring(GetAddOnMetadata(i, "Version")))
				end
			end
		end
		ns:LogDebug("init", "related addons: %s", #others > 0 and tconcat(others, ", ") or "none")
	end
end

-------------------------------------------------------------------------------
-- one line per distinct combat log actor, with every verdict Skada makes about
-- it. this is what says why somebody never shows up in a segment.

-- guidToClass holds the owner's guid for a pet, not a class, so say which one
-- it is: a bare guid in the class column reads like a broken lookup.
local function cached_class(guid)
	local class = Private.guidToClass[guid]
	if class == nil then return "nil" end

	local ownerName = Private.guidToName[class]
	if ownerName == nil then return tostring(class) end

	return format("%s (owner %s)", class, ownerName)
end

function Private.LogDebugActors(t)
	if not enabled or not log then return end

	local guidToName = Private.guidToName

	local guid = t.srcGUID
	if guid and not once["src:" .. guid] then
		ns:LogDebugOnce("src:" .. guid, "actor",
			"SRC %-16s guid=%s flags=%s inGroup=%s noPets=%s isPet=%s groupPet=%s cachedName=%s cachedClass=%s (via %s)",
			tostring(t.srcName), guid, Private.DecodeFlags(t.srcFlags),
			tostring(t:SourceInGroup()), tostring(t:SourceInGroup(true)),
			tostring(t:SourceIsPet()), tostring(t:SourceIsPet(true)),
			tostring(guidToName[guid]), cached_class(guid), tostring(t.event))
	end

	guid = t.dstGUID
	if guid and not once["dst:" .. guid] then
		ns:LogDebugOnce("dst:" .. guid, "actor",
			"DST %-16s guid=%s flags=%s inGroup=%s noPets=%s isPet=%s cachedName=%s cachedClass=%s (via %s)",
			tostring(t.dstName), guid, Private.DecodeFlags(t.dstFlags),
			tostring(t:DestInGroup()), tostring(t:DestInGroup(true)),
			tostring(t:DestIsPet()),
			tostring(guidToName[guid]), cached_class(guid), tostring(t.event))
	end
end

-------------------------------------------------------------------------------
-- who keeps IsGroupInCombat() true while we are out of combat ourselves.
-- rate limited: it walks the whole group and the tick runs every second.

local COMBAT_HOLDER_EVERY = 5 -- ticks

function Private.LogDebugCombatHolders(tick)
	if not enabled or not log then return end
	if not tick or tick % COMBAT_HOLDER_EVERY ~= 0 then return end
	if not ns.UnitIterator or not UnitAffectingCombat then return end

	local holders = {}
	for unit, owner in ns.UnitIterator() do
		if UnitAffectingCombat(unit) then
			holders[#holders + 1] = format("%s[%s%s%s]", tostring(UnitName(unit)), unit,
				owner and ",pet" or "",
				(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) and ",dead" or "")
		end
	end

	ns:LogDebug("combat", "we are out of combat, the group is not: held by %s",
		#holders > 0 and tconcat(holders, ", ") or "nobody, the flag is stale")
end

-------------------------------------------------------------------------------
-- roster snapshot: the table every "is this actor in my group" check reads

-- the roster is re-read on every group and zone change, and in a raid a full
-- snapshot is thirty lines. an unchanged one collapses to a single line so a
-- whole raid night still fits in the log.
function Private.LogDebugRoster(reason)
	if not enabled or not log then return end

	local guidToName = Private.guidToName
	local guidToClass = Private.guidToClass
	local guidToOwner = Private.guidToOwner

	local names, classes, owners = 0, 0, 0
	for _ in pairs(guidToName) do names = names + 1 end
	for _ in pairs(guidToClass) do classes = classes + 1 end
	for _ in pairs(guidToOwner) do owners = owners + 1 end

	local units, seen = nil, 0
	if ns.UnitIterator then
		units = {}
		for unit, owner in ns.UnitIterator() do
			seen = seen + 1
			units[seen] = format("  unit=%-10s owner=%-10s name=%-14s guid=%s class=%s cached=%s",
				tostring(unit), tostring(owner), tostring(UnitName(unit)),
				tostring(UnitGUID(unit)), tostring(select(2, UnitClass(unit))),
				tostring(guidToName[UnitGUID(unit) or ""] ~= nil))
		end
	end

	local snapshot = units and tconcat(units, "|") or ""
	if snapshot ~= "" and snapshot == last_roster then
		ns:LogDebug("roster", "update (%s): unchanged, %d units, guidToName=%d guidToClass=%d guidToOwner=%d",
			tostring(reason), seen, names, classes, owners)
		return
	end
	last_roster = snapshot

	ns:LogDebug("roster", "update (%s): IsInGroup=%s IsInRaid=%s GetNumGroupMembers=%s",
		tostring(reason), tostring(ns.IsInGroup and ns.IsInGroup()),
		tostring(ns.IsInRaid and ns.IsInRaid()),
		tostring(ns.GetNumGroupMembers and ns.GetNumGroupMembers()))
	ns:LogDebug("roster", "caches: guidToName=%d guidToClass=%d guidToOwner=%d", names, classes, owners)

	if units then
		for i = 1, seen do
			ns:LogDebug("roster", "%s", units[i])
		end
		ns:LogDebug("roster", "  units walked: %d", seen)
	end
end
