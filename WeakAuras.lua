local ADDON_NAME = "WeakAuras";
local timer = LibStub("AceTimer-3.0");

SLASH_WEAKAURAS1, SLASH_WEAKAURAS2 = "/weakauras", "/wa";
function SlashCmdList.WEAKAURAS(msg)
  if not(IsAddOnLoaded("WeakAurasOptions")) then
    local loaded, reason = LoadAddOn("WeakAurasOptions");
    if not(loaded) then
      print("WeakAurasOptions could not be loaded:", reason);
    end
  end
  WeakAuras.ToggleOptions(msg == "force");
end

local paused = false;
local squelch_actions = true;

WeakAuras.regions = {};
local regions = WeakAuras.regions;
WeakAuras.auras = {};
local auras = WeakAuras.auras;
WeakAuras.events = {};
local events = WeakAuras.events;
WeakAuras.loaded = {};
local loaded = WeakAuras.loaded;

WeakAuras.regionTypes = {};
local regionTypes = WeakAuras.regionTypes;

WeakAuras.forceable_events = {};
    
local from_files = {};

local timers = {};

local loaded_events = {};
WeakAuras.loaded_events = loaded_events;
local loaded_auras = {};
WeakAuras.loaded_auras = loaded_auras;
local loaded_conditions = {};
WeakAuras.loaded_conditions = loaded_conditions;

WeakAuras.animations = {};
local animations = WeakAuras.animations;
WeakAuras.pending_controls = {};
local pending_controls = WeakAuras.pending_controls;
local pending_conditions_check;

WeakAuras.spellCooldownCache = {};
WeakAuras.spellCooldownReadyTimers = {};
WeakAuras.itemCooldownCache = {};
WeakAuras.itemCooldownReadyTimers = {};

local function_strings = WeakAuras.function_strings;
local anim_function_strings = WeakAuras.anim_function_strings;
local anim_presets = WeakAuras.anim_presets;
local load_prototype = WeakAuras.load_prototype;
local event_prototypes = WeakAuras.event_prototypes;
local conditions = WeakAuras.conditions;

function WeakAuras.validate(input, default)
  for field, defaultValue in pairs(default) do
    if(type(defaultValue) == "table" and type(input[field]) ~= "table") then
      input[field] = {};
    elseif(input[field] == nil) then
      input[field] = defaultValue;
    elseif(type(input[field]) ~= type(defaultValue)) then
      input[field] = defaultValue;
    end
    
    if(type(input[field]) == "table") then
      WeakAuras.validate(input[field], defaultValue);
    end
  end
end

local function_cache = {};
function WeakAuras.LoadFunction(string)
  if(function_cache[string]) then
    return function_cache[string];
  else
    local func;
    local loadedFunction, errorString = loadstring(string);
    if(errorString) then
      print(errorString);
    else
      func = assert(loadedFunction)();
      function_cache[string] = func;
    end
    return func;
  end
end

local aura_cache = {};
do
  aura_cache.raid = {};
  aura_cache.raid.max = 0;
  aura_cache.raid.watched = {};
  aura_cache.raid.players = {};
  aura_cache.party = {};
  aura_cache.party.max = 0;
  aura_cache.party.watched = {};
  aura_cache.party.players = {};
  
  aura_cache.raid.ForceUpdate = function() WeakAuras.ScanAurasRaid() end;
  aura_cache.party.ForceUpdate = function() WeakAuras.ScanAurasParty() end;
  
  local function Watch(self, auraname)
    self.watched[auraname] = self.watched[auraname] or {};
    self.watched[auraname].number = self.watched[auraname].number or 0;
    self.watched[auraname].players = self.watched[auraname].players or {};
    self:ForceUpdate()
  end
  aura_cache.raid.Watch = Watch;
  aura_cache.party.Watch = Watch;
  
  local function Unwatch(self, auraname)
    self.watched[auraname] = nil;
  end
  aura_cache.raid.Unwatch = Unwatch;
  aura_cache.party.Unwatch = Unwatch;
  
  local function GetMaxNumber(self)
    return self.max;
  end
  aura_cache.raid.GetMaxNumber = GetMaxNumber;
  aura_cache.party.GetMaxNumber = GetMaxNumber;
  
  local function GetNumber(self, names)
    if(#names == 1) then
      return self.watched[names[1]] and self.watched[names[1]].number;
    else
      local num = 0;
      for playername, _ in pairs(self.players) do
        local active = false;
        for index, auraname in pairs(names) do
          if(self.watched[auraname].players[playername]) then
            active = true;
            break;
          end
        end
        if(active) then
          num = num + 1;
        end
      end
      
      return num;
    end
  end
  aura_cache.raid.GetNumber = GetNumber;
  aura_cache.party.GetNumber = GetNumber;
  
  local function AssertAura(self, auraname, playername)
    if not(self.watched[auraname].players[playername]) then
      self.watched[auraname].players[playername] = true;
      self.watched[auraname].number = self.watched[auraname].number + 1;
    end
  end
  aura_cache.raid.AssertAura = AssertAura;
  aura_cache.party.AssertAura = AssertAura;
  
  local function DeassertAura(self, auraname, playername)
    if(self.watched[auraname] and self.watched[auraname].players[playername]) then
      self.watched[auraname].players[playername] = nil;
      self.watched[auraname].number = self.watched[auraname].number - 1;
    end
  end
  aura_cache.raid.DeassertAura = DeassertAura;
  aura_cache.party.DeassertAura = DeassertAura;
  
  local function AssertMember(self, playername, forceupdate)
    if not(self.players[playername]) then
      self.players[playername] = true;
      self.max = self.max + 1;
    end
    
    if(forceupdate) then
      self:ForceUpdate();
    end
  end
  aura_cache.raid.AssertMember = AssertMember;
  aura_cache.party.AssertMember = AssertMember;
  
  local function DeassertMember(self, playername)
    if(self.players[playername]) then
      self.players[playername] = nil;
      for auraname, _ in pairs(self.watched) do
        self:DeassertAura(auraname, playername);
      end
      self.max = self.max - 1;
    end
  end
  aura_cache.raid.DeassertMember = DeassertMember;
  aura_cache.party.DeassertMember = DeassertMember;
  
  local function AssertMemberList(self, playernames)
    local toAdd = {};
    local toDelete = {};
    for playername, _ in pairs(playernames) do
      if not(self.players[playername]) then
        toAdd[playername] = true;
      end
    end
    for playername, _ in pairs(self.players) do
      if not(playernames[playername]) then
        toDelete[playername] = true;
      end
    end
    
    for playername, _ in pairs(toDelete) do
      self:DeassertMember(playername);
    end
    for playername, _ in pairs(toAdd) do
      self:AssertMember(playername);
    end
    self:ForceUpdate();
  end
  aura_cache.raid.AssertMemberList = AssertMemberList;
  aura_cache.party.AssertMemberList = AssertMemberList;
end
WeakAuras.aura_cache = aura_cache;

local groupFrame = CreateFrame("FRAME");
groupFrame:RegisterEvent("RAID_ROSTER_UPDATE");
groupFrame:RegisterEvent("PARTY_MEMBERS_CHANGED");
groupFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
groupFrame:SetScript("OnEvent", function()
  local numRaid = GetNumRaidMembers();
  local numParty = GetNumPartyMembers();
  local raidMembers = {};
  local partyMembers = {[GetUnitName("player")] = true};
  
  local groupCutoff = 8;
  if(numRaid > 0 and IsInInstance()) then
    local difficulty = GetRaidDifficulty();
    if(difficulty == 1 or difficulty == 3) then
      groupCutoff = 2;
    elseif(difficulty == 2 or difficulty == 4) then
      groupCutoff = 5;
    end
  end
  
  for i=1,numRaid do
    local name, _, subgroup = GetRaidRosterInfo(i);
    if(name and subgroup <= groupCutoff) then
      raidMembers[name] = true;
    end
  end
  aura_cache.raid:AssertMemberList(raidMembers);
  
  for i=1,numParty do
    local uid = "party"..i;
    partyMembers[GetUnitName(uid)] = true;
  end
  aura_cache.party:AssertMemberList(partyMembers);
end);

local duration_cache = {};
do
  function duration_cache:SetDurationInfo(id, duration, expirationTime)
    duration_cache[id] = duration_cache[id] or {};
    duration_cache[id].duration = duration;
    duration_cache[id].expirationTime = expirationTime;
  end
  
  function duration_cache:GetDurationInfo(id)
    if(duration_cache[id]) then
      return duration_cache[id].duration, duration_cache[id].expirationTime;
    else
      return 0, math.huge;
    end
  end
end
WeakAuras.duration_cache = duration_cache;

function WeakAuras.ParseNumber(numString)
  if not(numString and type(numString) == "string") then
    if(type(numString) == "number") then
      return numString, "notastring";
    else
      return nil;
    end
  elseif(numString:sub(-1) == "%") then
    local percent = tonumber(numString:sub(0, -2));
    if(percent) then
      return percent / 100, "percent";
    else
      return nil;
    end
  else
    --Matches any string with two integers separated by a forward slash
    --Captures the two integers
    local _, _, numerator, denominator = numString:find("(%d+)%s*/%s*(%d+)");
    numerator, denominator = tonumber(numerator), tonumber(denominator);
    if(numerator and denominator) then
      if(denominator == 0) then
        return nil;
      else
        return numerator / denominator, "fraction";
      end
    else
      local num = tonumber(numString)
      if(num) then
        if(math.floor(num) ~= num) then
          return num, "decimal";
        else
          return num, "whole";
        end
      else
        return nil;
      end
    end
  end
end

function WeakAuras.ConstructFunction(prototype, data, triggernum, subPrefix, subSuffix, field, inverse)
  local trigger;
  if(field == "load") then
    trigger = data.load;
  elseif(field == "untrigger") then
    if(triggernum == 0) then
      data.untrigger = data.untrigger or {};
      trigger = data.untrigger;
    else
      trigger = data.additional_triggers[triggernum].untrigger;
    end
  else
    if(triggernum == 0) then
      trigger = data.trigger;
    else
      trigger = data.additional_triggers[triggernum].trigger;
    end
  end
  local input = {"event"};
  local required = {};
  local tests = {};
  local init;
  if(prototype.init) then
    init = prototype.init(trigger);
  else
    init = "";
  end
  for index, arg in pairs(prototype.args) do
    local enable = true;
    if(type(arg.enable) == "function") then
      enable = arg.enable(trigger);
    end
    if(enable) then
      local name = arg.name;
      if not(arg.name or arg.hidden) then
        tinsert(input, "_");
      else
        if(arg.init == "arg") then
          tinsert(input, name);
        end
        if(arg.hidden or arg.type == "tristate" or arg.type == "toggle" or ((trigger["use_"..name] or arg.required) and trigger[name])) then
          if(arg.init and arg.init ~= "arg") then
            init = init.."local "..name.." = "..arg.init.."\n";
          end
          local number = tonumber(trigger[name]);
          local test;
          if(arg.type == "tristate") then
            if(trigger["use_"..name] == false) then
              test = "(not "..name..")";
            elseif(trigger["use_"..name]) then
              if(arg.test) then
                test = "("..arg.test:format(trigger[name])..")";
              else
                test = name;
              end
            end
          elseif(arg.type == "toggle") then
            if(trigger["use_"..name]) then
              if(arg.test) then
                test = "("..arg.test:format(trigger[name])..")";
              else
                test = name;
              end
            end
          elseif(arg.test) then
            test = "("..arg.test:format(trigger[name])..")";
          elseif(arg.type == "longstring" and trigger[name.."_operator"]) then
            if(trigger[name.."_operator"] == "==") then
              test = "("..name.."=='"..trigger[name].."')";
            else
              test = "("..name..":"..trigger[name.."_operator"]:format(trigger[name])..")";
            end
          else
            test = "("..name..(trigger[name.."_operator"] or "==")..(number or "'"..trigger[name].."'")..")";
          end
          if(arg.required) then
            tinsert(required, test);
          else
            tinsert(tests, test);
          end
        end
      end
    end
  end
  local ret = "return function("..table.concat(input, ", ")..")\n";
  ret = ret..init;
  ret = ret.."if(";
  ret = ret..((#required > 0) and table.concat(required, " and ").." and " or "");
  if(inverse) then
    ret = ret.."not ("..(#tests > 0 and table.concat(tests, " and ") or "true")..")";
  else
    ret = ret..(#tests > 0 and table.concat(tests, " and ") or "true");
  end
  ret = ret..") then\nreturn true else return false end end";
  return ret;
end

local pending_aura_scans = {};

local db;
local frame = CreateFrame("FRAME", "WeakAurasFrame", UIParent);
frame:SetAllPoints(UIParent);
local loadedFrame = CreateFrame("FRAME");
loadedFrame:RegisterEvent("ADDON_LOADED");
loadedFrame:SetScript("OnEvent", function(self, event, addon)
  if(addon == ADDON_NAME) then
    frame:RegisterEvent("PLAYER_TARGET_CHANGED");
    frame:RegisterEvent("UNIT_AURA");
    frame:SetScript("OnEvent", WeakAuras.HandleEvent);
    frame:SetScript("OnUpdate", WeakAuras.UpdateAll);
    
    WeakAurasSaved = WeakAurasSaved or {};
    db = WeakAurasSaved;
    
    --Deprecated fields with *lots* of data, clear them out
    db.iconCache = nil;
    db.iconHash = nil;
    
    db.tempIconCache = db.tempIconCache or {};

    db.displays = db.displays or {};
    local toAdd = {};
    for id, data in pairs(db.displays) do
      if(id == data.id) then
        tinsert(toAdd, data);
      else
        error("Corrupt entry in WeakAuras saved displays");
      end
    end
    WeakAuras.AddMany(unpack(toAdd));
    WeakAuras.AddIfNecessary(from_files);
    
    WeakAuras.Resume();
    
    WeakAuras.conditionsFrame = CreateFrame("FRAME");
    for type, data in pairs(conditions) do
      for index, event in pairs(data.events) do
        WeakAuras.conditionsFrame:RegisterEvent(event);
      end
    end
    WeakAuras.conditionsFrame:SetScript("OnEvent", function(self, event) if not(paused) then pending_conditions_check = GetTime(); end end);
    
    WeakAuras.ScanForLoads();
    WeakAuras.ScanAuras("player");
    WeakAuras.ScanAuras("target");
    WeakAuras.ScanAuras("focus");
    WeakAuras.ScanAurasParty();
    WeakAuras.ScanAurasRaid();
    WeakAuras.ForceEvents();
    
    squelch_actions = false;
  end
end);

function WeakAuras.Pause()
  paused = true;
  --Forcibly hide all displays, and clear all trigger information (it will be restored on Resume due to forced events)
  for id, region in pairs(regions) do
    region.region:Collapse();
    region.region.trigger_count = 0;
    region.region.triggers = 0;
  end
end

function WeakAuras.Resume()
  paused = false;
  WeakAuras.ScanAll();
end

function WeakAuras.Toggle()
  if(paused) then
    WeakAuras.Resume();
  else
    WeakAuras.Pause();
  end
end

function WeakAuras.ScanAurasParty()
  local numParty = GetNumPartyMembers();
  if(numParty > 0) then
    for i=1,numParty do
      local uid = "party"..i;
      WeakAuras.ScanAuras(uid);
    end
  end
  WeakAuras.ScanAuras("player");
end

function WeakAuras.ScanAurasRaid()
  local numRaid = GetNumRaidMembers();
  if(numRaid > 0) then
    for i=1,numRaid do
      local uid = "raid"..i;
      WeakAuras.ScanAuras(uid);
    end
  elseif(loaded_auras["raid"]) then
    for id, triggers in pairs(loaded_auras["raid"]) do
      for triggernum, data in pairs(triggers) do
        WeakAuras.SetAuraVisibility(id, triggernum, data, nil, unit, 0, math.huge);
      end
    end
  end
end

function WeakAuras.ScanAll()
  for id, region in pairs(regions) do
    region.region:Collapse();
    region.region.trigger_count = 0;
    region.region.triggers = 0;
  end
  WeakAuras.ReloadAll();
  for unit, auras in pairs(loaded_auras) do
    if(unit == "party") then
      WeakAuras.ScanAurasParty();
    elseif(unit == "raid") then
      WeakAuras.ScanAurasRaid();
    else
      WeakAuras.ScanAuras(unit);
    end
  end
  for eventName, events in pairs(loaded_events) do
    if(eventName == "COMBAT_LOG_EVENT_UNFILTERED") then
      for subeventName, subevents in pairs(events) do
        for id, triggers in pairs(subevents) do
          for triggernum, eventData in pairs(triggers) do
            if(eventData.region.active and WeakAuras.PassesConditionChecks(id)) then
              eventData.region:Expand();
              WeakAuras.SetEventDynamics(id, triggernum, eventData);
            end
          end
        end
      end
    else
      for id, triggers in pairs(events) do
        for triggernum, eventData in pairs(triggers) do
          if(eventData.region.active and WeakAuras.PassesConditionChecks(id)) then
            eventData.region:Expand();
            WeakAuras.SetEventDynamics(id, triggernum, eventData);
          end
        end
      end
    end
  end
  WeakAuras.ForceEvents();
end

function WeakAuras.ForceEvents()
  for event, v in pairs(WeakAuras.forceable_events) do
    if(type(v) == "table") then
      for index, arg1 in pairs(v) do
        WeakAuras.ScanEvents(event, arg1);
      end
    else
      WeakAuras.ScanEvents(event);
    end
  end
end

function WeakAuras.HandleEvent(frame, event, arg1, arg2, ...)
  if not(paused) then
    if(event == "PLAYER_TARGET_CHANGED") then
      WeakAuras.ScanAuras("target");
    elseif(event == "UNIT_AURA") then
      --This throttles aura scans to only happen at most once per frame
      if(loaded_auras[arg1]) then
        pending_aura_scans[arg1] = true;
      elseif(loaded_auras["raid"] and arg1:sub(0, 4) == "raid") then
        pending_aura_scans[arg1] = true;
      elseif(loaded_auras["party"] and arg1:sub(0, 5) == "party") then
        pending_aura_scans[arg1] = true;
      end
    end
    if(event == "COMBAT_LOG_EVENT_UNFILTERED") then
      if(loaded_events[event] and loaded_events[event][arg2]) then
        WeakAuras.ScanEvents(event, arg1, arg2, ...);
      end
    else
      if(loaded_events[event]) then
        WeakAuras.ScanEvents(event, arg1, arg2, ...);
      end
    end
  end
end

function WeakAuras.ScanEvents(event, arg1, arg2, ...)
  local event_list = loaded_events[event];
  if(event_list) then
    if(event == "COMBAT_LOG_EVENT_UNFILTERED") then
      event_list = event_list[arg2];
    end
    for id, triggers in pairs(event_list) do
      for triggernum, data in pairs(triggers) do
        if(data.trigger) then
          if(data.trigger(event, arg1, arg2, ...)) then
            WeakAuras.ActivateEvent(id, triggernum, data);
          else
            if(data.untrigger and data.untrigger(event, arg1, arg2, ...)) then
              WeakAuras.EndEvent(id, triggernum);
            end
          end
        end
      end
    end
  end
end

function WeakAuras.ActivateEvent(id, triggernum, data)
  if(WeakAuras.PassesConditionChecks(id)) then
    if(data.numAdditionalTriggers > 0) then
      if(data.region:EnableTrigger(triggernum)) then
        data.region.active = true;
      end
    else
      data.region.active = true;
      data.region:Expand();
    end
  end
  WeakAuras.SetEventDynamics(id, triggernum, data);
end

function WeakAuras.SetEventDynamics(id, triggernum, data)
  local trigger;
  if(triggernum == 0) then
    trigger = db.displays[id] and db.displays[id].trigger;
  else
    trigger = db.displays[id] and db.displays[id].additional_triggers
              and db.displays[id].additional_triggers[triggernum]
              and db.displays[id].additional_triggers[triggernum].trigger;
  end
  if(trigger) then
    if(data.duration) then
      WeakAuras.ActivateEventTimer(id, triggernum, data.duration);
      if(triggernum == 0) then
        if(data.region.SetDurationInfo) then
          data.region:SetDurationInfo(data.duration, GetTime() + data.duration);
        end
        duration_cache:SetDurationInfo(id, data.duration, GetTime() + data.duration);
      end
    else
      if(data.durationFunc) then
        local duration, expirationTime, static = data.durationFunc(trigger);
        if(duration > 0.01 and not static) then
          local hideOnExpire = true;
          if(data.expiredHideFunc) then
            hideOnExpire = data.expiredHideFunc(trigger);
          end
          if(hideOnExpire) then
            WeakAuras.ActivateEventTimer(id, triggernum, expirationTime - GetTime());
          end
        end
        if(triggernum == 0) then
          if(data.region.SetDurationInfo) then
            data.region:SetDurationInfo(duration, expirationTime, static);
          end
          duration_cache:SetDurationInfo(id, duration, expirationTime);
        end
      elseif(triggernum == 0) then
        if(data.region.SetDurationInfo) then
          data.region:SetDurationInfo(0, math.huge);
        end
        duration_cache:SetDurationInfo(id, 0, math.huge);
      end
    end
    if(triggernum == 0) then
      if(data.region.SetName) then
        if(data.nameFunc) then
          data.region:SetName(data.nameFunc(trigger));
        else
          data.region:SetName();
        end
      end
      if(data.region.SetIcon) then
        if(data.iconFunc) then
          data.region:SetIcon(data.iconFunc(trigger));
        else
          data.region:SetIcon();
        end
      end
      if(data.region.SetStacks) then
        if(data.stacksFunc) then
          data.region:SetStacks(data.stacksFunc(trigger));
        else
          data.region:SetStacks();
        end
      end
    end
  else
    error("Event with id \""..id.." and trigger number "..triggernum.." tried to activate, but does not exist");
  end
end

function WeakAuras.ActivateEventTimer(id, triggernum, duration)
  if(timers[id] and timers[id][triggernum]) then
    timer:CancelTimer(timers[id][triggernum], true);
  end
  timers[id] = timers[id] or {};
  timers[id][triggernum] = timer:ScheduleTimer(function() WeakAuras.EndEvent(id, triggernum) end, duration);
end

function WeakAuras.EndEvent(id, triggernum)
  local data = events[id] and events[id][triggernum];
  if(data) then
    if(data.numAdditionalTriggers > 0) then
      if(data.region:DisableTrigger(triggernum)) then
        data.region.active = nil;
      end
    else
      data.region.active = nil;
      data.region:Collapse();
    end
    if(timers[id] and timers[id][triggernum]) then
      timer:CancelTimer(timers[id][triggernum], true);
      timers[id][triggernum] = nil;
    end
  end
end

local anim_delay = 0;
frame.elapsed = 0;
function WeakAuras.UpdateAll(frame, elapsed)
  frame.elapsed = frame.elapsed + elapsed;
  if(frame.elapsed > anim_delay) then
    frame.elapsed = frame.elapsed - anim_delay;
    WeakAuras.UpdateAnimations(elapsed);
  end
  for unit, _ in pairs(pending_aura_scans) do
    pending_aura_scans[unit] = nil;
    WeakAuras.ScanAuras(unit);
  end
  if(pending_conditions_check and GetTime() - pending_conditions_check > 0.5) then
    pending_conditions_check = nil;
    WeakAuras.ConditionsChanged();
  end
end

function WeakAuras.ScanForLoads()
  local typefunc = type;
  local player, class, zone, spec = UnitName("player"), UnitClass("player"), GetRealZoneText(), GetPrimaryTalentTree();
  local _, type, difficultyIndex, _, maxPlayers, dynamicDifficulty, isDynamic = GetInstanceInfo();
  local size, difficulty;
  size = type;
  if(type == "raid") then
    if(maxPlayers == 10) then
      size = "ten";
    elseif(maxPlayers == 25) then
      size = "twentyfive";
    end
  elseif(WeakAuras.group_types) then
    if not(WeakAuras.group_types[type]) then
      print("You have entered an instance whose type is not supported by WeakAuras. That type is '"..type.."'. Please report this as a bug.");
    end
  end
  if(isDynamic) then
    if(dynamicDifficulty == 0) then
      difficulty = "normal";
    elseif(dynamicDifficulty == 1) then
      difficulty = "heroic";
    else
      print("Your have entered an instance whose difficulty could not be correctly understood by WeakAuras. Please report this as a bug.");
    end
  else
    if(difficultyIndex == 1 or difficultyIndex == 2) then
      difficulty = "normal";
    elseif(difficultyIndex == 3 or difficultyIndex == 4) then
      difficulty = "heroic";
    else
      print("Your have entered an instance whose difficulty could not be correctly understood by WeakAuras. Please report this as a bug.");
    end
  end
  local shouldBeLoaded;
  for id, triggers in pairs(auras) do
    local _, data = next(triggers);
    shouldBeLoaded = data.load and data.load("ScanForLoads_Auras", player, class, spec, zone, size, difficulty);
    if(shouldBeLoaded and not loaded[id]) then
      WeakAuras.LoadAura(id, triggers);
    end
    if(loaded[id] and not shouldBeLoaded) then
      WeakAuras.UnloadAura(id);
      data.region:Collapse();
    end
  end
  for id, triggers in pairs(events) do
    local _, data = next(triggers);
    shouldBeLoaded = data.load and data.load("ScanForLoads_Events", player, class, spec, zone, size, difficulty);
    if(shouldBeLoaded and not loaded[id]) then
      WeakAuras.LoadEvent(id, triggers);
    end
    if(loaded[id] and not shouldBeLoaded) then
      WeakAuras.UnloadEvent(id);
      data.region:Collapse();
    end
  end
  for id, data in pairs(db.displays) do
    if(data.controlledChildren) then
      if(#data.controlledChildren > 0) then
        local any_loaded;
        for index, childId in pairs(data.controlledChildren) do
          if(loaded[childId]) then
            any_loaded = true;
          end
        end
        loaded[id] = any_loaded;
      else
        loaded[id] = true;
      end
    end
  end
end

WeakAuras.loadFrame = CreateFrame("FRAME");
WeakAuras.loadFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
WeakAuras.loadFrame:RegisterEvent("ZONE_CHANGED");
WeakAuras.loadFrame:RegisterEvent("ZONE_CHANGED_INDOORS");
WeakAuras.loadFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
WeakAuras.loadFrame:SetScript("OnEvent", WeakAuras.ScanAll);

function WeakAuras.ReloadAll()
  WeakAuras.UnloadAll();
  WeakAuras.ScanForLoads();
end

function WeakAuras.UnloadAll()
  wipe(loaded_events);
  wipe(loaded_auras);
  wipe(loaded);
end

function WeakAuras.LoadAura(id, triggers)
  loaded[id] = true;
  
  for triggernum, data in pairs(triggers) do
    loaded_auras[data.unit] = loaded_auras[data.unit] or {};
    loaded_auras[data.unit][id] = loaded_auras[data.unit][id] or {};
    loaded_auras[data.unit][id][triggernum] = data;
  end
end

function WeakAuras.UnloadAura(id)
  loaded[id] = nil;
  for unitname, auras in pairs(loaded_auras) do
    auras[id] = nil;
  end
end

function WeakAuras.LoadEvent(id, triggers)
  loaded[id] = true;
  
  for triggernum, data in pairs(triggers) do
    local events = event_prototypes[data.event] and event_prototypes[data.event].events or {}
    for index, event in pairs(events) do
      loaded_events[event] = loaded_events[event] or {};
      if(event == "COMBAT_LOG_EVENT_UNFILTERED" and data.subevent) then
        loaded_events[event][data.subevent] = loaded_events[event][data.subevent] or {};
        loaded_events[event][data.subevent][id] = loaded_events[event][data.subevent][id] or {}
        loaded_events[event][data.subevent][id][triggernum] = data;
      else
        loaded_events[event][id] = loaded_events[event][id] or {};
        loaded_events[event][id][triggernum] = data;
      end
    end
  end
end

function WeakAuras.UnloadEvent(id)
  loaded[id] = nil;
  for eventname, events in pairs(loaded_events) do
    if(eventname == "COMBAT_LOG_EVENT_UNFILTERED") then
      for subeventname, subevents in pairs(events) do
        subevents[id] = nil;
      end
    else
      events[id] = nil;
    end
  end
end

function WeakAuras.PassesConditionChecks(id)
  local data = db.displays[id];
  if(data and data.conditions) then
    for type, positive in pairs(data.conditions) do
      if(positive and not conditions[type].func()) then
        return false;
      end
      if((not positive) and conditions[type].func()) then
        return false;
      end
    end
  else
    return false;
  end
  
  return true;
end

function WeakAuras.ScanAuras(unit)
  if(unit == "raid") then error("incorrect unit 'raid'!") end
  local aura_list, aura_object;
  if(unit:sub(0, 4) == "raid") then
    if(aura_cache.raid.players[GetUnitName(unit, true)]) then
      aura_list = loaded_auras["raid"];
      aura_object = aura_cache.raid;
    end
  elseif(unit:sub(0, 5) == "party") then
    aura_list = loaded_auras["party"];
    aura_object = aura_cache.party;
  else
    if(unit == "player" and loaded_auras["party"]) then
      WeakAuras.ScanAuras("party0");
    end
    aura_list = loaded_auras[unit];
  end
  
  if(aura_list) then
    unit = unit == "party0" and "player" or unit;
    local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = true;
    for id,triggers in pairs(aura_list) do
      for triggernum, data in pairs(triggers) do
        local filter = data.debuffType..(data.ownOnly and "|PLAYER" or "");
        local active = false;
        for index, checkname in pairs(data.names) do
          name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitAura(unit, checkname, nil, filter);
          if(name and data.count(count)) then
            active = true;
            db.tempIconCache[name] = icon;
            if(aura_object) then
              aura_object:AssertAura(checkname, GetUnitName(unit, true));
            else
              WeakAuras.SetAuraVisibility(id, triggernum, data, true, unit, duration, expirationTime, name, icon, count);
              break;
            end
          elseif(aura_object) then
            aura_object:DeassertAura(checkname, GetUnitName(unit, true));
          end
        end
        if(aura_object) then
          if(data.group_count) then
            local count, max = aura_object:GetNumber(data.names), aura_object:GetMaxNumber();
            local satisfies_count = data.group_count(count, max);
            if(satisfies_count) then
              WeakAuras.SetAuraVisibility(id, triggernum, data, true, unit, 0, math.huge);
            else
              WeakAuras.SetAuraVisibility(id, triggernum, data, nil, unit, 0, math.huge);
            end
          else
            error("Group-based aura \""..id.."\" does not have a group counting function.");
          end
        elseif not(active) then
          WeakAuras.SetAuraVisibility(id, triggernum, data, nil, unit, 0, math.huge);
        end
      end
    end
  end
end

function WeakAuras.SetAuraVisibility(id, triggernum, data, active, unit, duration, expirationTime, name, icon, count)
  local show;
  if(active ~= nil) then
    if(data.inverse) then
      show = false;
    else
      show = true;
    end
  else
    if(data.inverse) then
      show = true;
    else
      show = false;
    end
  end
  
  if not(WeakAuras.PassesConditionChecks(id)) then
    show = false;
  end
  
  if(show) then
    if(triggernum == 0) then
      if(data.region.SetDurationInfo) then
        data.region:SetDurationInfo(duration, expirationTime);
      end
      duration_cache:SetDurationInfo(id, duration, expirationTime);
      if(data.region.SetName) then
        data.region:SetName(name);
      end
      if(data.region.SetIcon) then
        data.region:SetIcon(icon);
      end
      if(data.region.SetStacks) then
        data.region:SetStacks(count);
      end
    end

    if(data.numAdditionalTriggers > 0) then
      data.region:EnableTrigger(triggernum);
    else
      data.region:Expand();
    end
  else
    if(data.numAdditionalTriggers > 0) then
      data.region:DisableTrigger(triggernum)
    else
      data.region:Collapse();
    end
  end
end

function WeakAuras.ConditionsChanged()
  for id, region in pairs(regions) do
    if(region.region:IsVisible() and not(WeakAuras.PassesConditionChecks(id))) then
      region.region:Collapse();
    end
  end
  for unit, auras in pairs(loaded_auras) do
    if(unit == "raid") then
      WeakAuras.ScanAurasRaid();
    elseif(unit == "party") then
      WeakAuras.ScanAurasParty();
    else
      WeakAuras.ScanAuras(unit);
    end
  end
  WeakAuras.ForceEvents();
  for eventName, events in pairs(loaded_events) do
    if(eventName == "COMBAT_LOG_EVENT_UNFILTERED") then
      for subeventName, subevents in pairs(events) do
        for id, triggers in pairs(subevents) do
          for triggernum, eventData in pairs(triggers) do
            if not(eventData.region) then
              print("No region for", id);
            end
            if(eventData.region.active and WeakAuras.PassesConditionChecks(id)) then
              eventData.region:Expand();
            end
          end
        end
      end
    else
      for id, triggers in pairs(events) do
        for triggernum, eventData in pairs(triggers) do
          if(eventData.region.active and WeakAuras.PassesConditionChecks(id)) then
            eventData.region:Expand();
          end
        end
      end
    end
  end
end

function WeakAuras.RegisterMany(...)
  local table = {...};
  for _, data in ipairs(table) do
    WeakAuras.Register(data);
  end
end

function WeakAuras.Delete(data)
  local id = data.id;
  
  if(data.parent) then
    local parentData = db.displays[data.parent];
    if(parentData and parentData.controlledChildren) then
      for index, childId in pairs(parentData.controlledChildren) do
        if(childId == id) then
          tremove(parentData.controlledChildren, index);
        end
      end
    end
  end
  
  if(data.controlledChildren) then
    for index, childId in pairs(data.controlledChildren) do
      local childData = db.displays[childId];
      if(childData) then
        childData.parent = nil;
      end
    end
  end
  
  regions[id].region:Hide();
  WeakAuras.EndEvent(id);
  
  regions[id] = nil;
  auras[id] = nil;
  events[id] = nil;
  loaded[id] = nil;
  
  for i,v in pairs(loaded_events) do
    v[id] = nil;
  end
  for i,v in pairs(loaded_auras) do
    v[id] = nil;
  end
  
  db.displays[id] = nil;
end

function WeakAuras.Rename(data, newid)
  if(data.parent) then
    local parentData = db.displays[data.parent];
    if(parentData.controlledChildren) then
      for index, childId in pairs(parentData.controlledChildren) do
        if(childId == data.id) then
          parentData.controlledChildren[index] = newid;
        end
      end
    end
  end
  
  WeakAuras.Delete(data);
  data.id = newid;
  WeakAuras.Add(data);
  
  if(data.controlledChildren) then
    for index, childId in pairs(data.controlledChildren) do
      local childData = db.displays[childId];
      if(childData) then
        childData.parent = data.id;
      end
    end
  end
end

function WeakAuras.Copy(sourceid, destid)
  local sourcedata = db.displays[sourceid];
  local destdata = db.displays[destid];
  if(sourcedata and destdata) then
    local oldParent = destdata.parent;
    local oldChildren = destdata.controlledChildren;
    wipe(destdata);
    local function deepcopy(source, dest)
      for i,v in pairs(source) do
        if(type(v) == "table") then
          dest[i] = type(dest[i]) == "table" and dest[i] or {};
          deepcopy(v, dest[i]);
        else
          dest[i] = v;
        end
      end
    end
    deepcopy(sourcedata, destdata);
    destdata.id = destid;
    destdata.parent = oldParent;
    destdata.controlledChildren = oldChildren;
    WeakAuras.Add(destdata);
  end
end

function WeakAuras.Register(data)
  tinsert(from_files, data);
end

function WeakAuras.AddIfNecessary(table)
  for _, data in ipairs(table) do
    local id = data.id;
    if(id) then
      if(db.displays[id]) then
        --This display was already in the saved variables
      else
        WeakAuras.Add(data);
      end
    end
  end
end

function WeakAuras.AddMany(...)
  local table = {...};
  local idtable = {};
  for _, data in ipairs(table) do
    idtable[data.id] = data;
  end
  local loaded = {};
  local function load(id, depends)
    local data = idtable[id];
    if(data.parent) then
      if(idtable[data.parent]) then
        if(tContains(depends, data.parent)) then
          error("Circular dependency in WeakAuras.AddMany between "..table.concat(depends, ", "));
        else
          if not(loaded[data.parent]) then
            local dependsOut = {};
            for i,v in pairs(depends) do
              dependsOut[i] = v;
            end
            tinsert(dependsOut, data.parent);
            load(data.parent, dependsOut);
          end
        end
      else
        data.parent = nil;
      end
    end
    if not(loaded[id]) then
      WeakAuras.Add(data);
      loaded[id] = true;
    end
  end
  for id, data in pairs(idtable) do
    load(id, {});
  end
  for id, data in pairs(idtable) do
    if(data.regionType == "dynamicgroup") then
      WeakAuras.Add(data);
      regions[id].region:ControlChildren();
    end
  end
end

--Dummy add function to protect errors from propagating out of the real add function
function WeakAuras.Add(data)
  local status, err = pcall(WeakAuras.pAdd, data);
  if not(status) then
    print(err);
  end
end

function WeakAuras.pAdd(data)
  local id = data.id;
  if not(id) then
    error("Improper arguments to WeakAuras.Add - id not defined");
  else
    local region = WeakAuras.SetRegion(data);
    
    data.load = data.load or {};
    data.conditions = data.conditions or {};
    data.actions = data.actions or {};
    data.actions.start = data.actions.start or {};
    data.actions.finish = data.actions.finish or {};
    local loadFunc = WeakAuras.LoadFunction(WeakAuras.ConstructFunction(load_prototype, data, nil, nil, nil, "load"));
    
    events[id] = nil;
    auras[id] = nil;
    
    for triggernum=0,9 do
      local trigger, untrigger;
      if(triggernum == 0) then
        trigger = data.trigger;
        untrigger = data.untrigger;
      elseif(data.additional_triggers and data.additional_triggers[triggernum]) then
        trigger = data.additional_triggers[triggernum].trigger;
        untrigger = data.additional_triggers[triggernum].untrigger;
      end
      local triggerType;
      if(trigger and type(trigger) == "table") then
        triggerType = trigger.type;
        if(triggerType == "aura") then
          trigger.names = trigger.names or {};
          trigger.unit = trigger.unit or "player";
          trigger.debuffType = trigger.debuffType or "HELPFUL";
          
          local countFunc, countFuncStr;
          if(trigger.useCount) then
            countFuncStr = function_strings.count:format(trigger.countOperator or ">=", tonumber(trigger.count) or 0);
          else
            countFuncStr = function_strings.always;
          end
          countFunc = WeakAuras.LoadFunction(countFuncStr);
          
          local group_countFunc, group_countFuncStr;
          if(trigger.unit == "raid" or trigger.unit == "party") then
            local count, countType = WeakAuras.ParseNumber(trigger.group_count);
            if(trigger.group_countOperator and count and countType) then
              if(countType == "whole") then
                group_countFuncStr = function_strings.count:format(trigger.group_countOperator, count);
              else
                group_countFuncStr = function_strings.count_fraction:format(trigger.group_countOperator, count);
              end
            else
              group_countFuncStr = function_strings.count:format(">", 0);
            end
            group_countFunc = WeakAuras.LoadFunction(group_countFuncStr);
            for index, auraname in pairs(trigger.names) do
              aura_cache[trigger.unit]:Watch(auraname);
            end
          end
          
          auras[id] = auras[id] or {};
          auras[id][triggernum] = {
            count = countFunc,
            group_count = group_countFunc,
            load = loadFunc,
            bar = data.bar,
            timer = data.timer,
            cooldown = data.cooldown,
            icon = data.icon,
            debuffType = trigger.debuffType,
            names = trigger.names,
            unit = trigger.unit,
            useCount = trigger.useCount,
            ownOnly = trigger.ownOnly,
            inverse = trigger.inverse,
            region = region,
            numAdditionalTriggers = data.additional_triggers and #data.additional_triggers or 0
          };
        elseif(triggerType == "event") then
          if not(trigger.event) then
            error("Improper arguments to WeakAuras.Add - trigger type is \"event\" but event is not defined");
          elseif not(event_prototypes[trigger.event]) then
            if(event_protyptes["Health"]) then
              trigger.event = "Health";
            else
              error("Improper arguments to WeakAuras.Add - no event prototype can be found for event type \""..trigger.event.."\" and default prototype reset failed.");
            end
          elseif(trigger.event == "Combat Log" and not (trigger.subeventPrefix..trigger.subeventSuffix)) then
            error("Improper arguments to WeakAuras.Add - event type is \"Combat Log\" but subevent is not defined");
          else
            local triggerFuncStr, triggerFunc;
            if(trigger.event == "Combat Log") then
              triggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], data, triggernum, trigger.subeventPrefix, trigger.subeventSuffix);
            else
              triggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], data, triggernum);
            end
            --print(id, "trigger")
            --print(triggerFuncStr);
            triggerFunc = WeakAuras.LoadFunction(triggerFuncStr);
            WeakAuras.triggerFunc = triggerFunc;
            WeakAuras.triggerStr = triggerFuncStr;
            
            local untriggerFuncStr, untriggerFunc
            if(trigger.unevent == "custom") then
              if(trigger.event == "Combat Log") then
                untriggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], data, triggernum, trigger.subeventPrefix, trigger.subeventSuffix, "untrigger");
              else
                untriggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], data, triggernum, nil, nil, "untrigger");
              end
            elseif(trigger.unevent == "auto") then
              untriggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], data, triggernum, nil, nil, nil, true);
            end
            if(untriggerFuncStr) then
              --print(id, "untrigger")
              --print(untriggerFuncStr);
              untriggerFunc = WeakAuras.LoadFunction(untriggerFuncStr);
              WeakAuras.untriggerFunc = untriggerFunc;
              WeakAuras.untriggerStr = untriggerFuncStr;
            end
            
            events[id] = events[id] or {};
            events[id][triggernum] = {
              trigger = triggerFunc,
              untrigger = untriggerFunc,
              load = loadFunc,
              bar = data.bar,
              timer = data.timer,
              cooldown = data.cooldown,
              icon = data.icon,
              event = trigger.event,
              subevent = trigger.event == "Combat Log" and trigger.subeventPrefix and trigger.subeventSuffix and (trigger.subeventPrefix..trigger.subeventSuffix);
              unevent = trigger.unevent,
              durationFunc = event_prototypes[trigger.event].durationFunc,
              nameFunc = event_prototypes[trigger.event].nameFunc,
              iconFunc = event_prototypes[trigger.event].iconFunc,
              stacksFunc = event_prototypes[trigger.event].stacksFunc,
              expiredHideFunc = event_prototypes[trigger.event].expiredHideFunc,
              region = region,
              numAdditionalTriggers = data.additional_triggers and #data.additional_triggers or 0
            };

            local prototype = event_prototypes[trigger.event];
            if(prototype) then
              for index, event in pairs(prototype.events) do
                frame:RegisterEvent(event);
                if(prototype.force_events) then
                  WeakAuras.forceable_events[event] = prototype.force_events;
                end
              end
            end

            if(trigger.unevent == "timed") then
              events[id][triggernum].duration = tonumber(data.trigger.duration);
            end
          end
        elseif(triggerType) then
          error("Improper arguments to WeakAuras.Add - display "..id.." trigger type \""..triggerType.."\" is not supported for trigger number "..triggernum);
        else
          print("Improper arguments to WeakAuras.Add - display "..id.." trigger type not defined for trigger number "..triggernum);
        end
      end
    end
    
    if not(temporary) then
      db.displays[id] = data;
    end
    
    if not(paused) then
      region:Collapse();
      WeakAuras.ScanForLoads();
    end
  end
end

function WeakAuras.RegisterRegionType(name, createFunction, modifyFunction, default)
  if not(name) then
    error("Improper arguments to WeakAuras.RegisterRegionType - name is not defined");
  elseif(type(name) ~= "string") then
    error("Improper arguments to WeakAuras.RegisterRegionType - name is not a string");
  elseif not(createFunction) then
    error("Improper arguments to WeakAuras.RegisterRegionType - creation function is not defined");
  elseif(type(createFunction) ~= "function") then
    error("Improper arguments to WeakAuras.RegisterRegionType - creation function is not a function");
  elseif not(modifyFunction) then
    error("Improper arguments to WeakAuras.RegisterRegionType - modification function is not defined");
  elseif(type(modifyFunction) ~= "function") then
    error("Improper arguments to WeakAuras.RegisterRegionType - modification function is not a function")
  elseif not(default) then
    error("Improper arguments to WeakAuras.RegisterRegionType - default options are not defined");
  elseif(type(default) ~= "table") then
    error("Improper arguments to WeakAuras.RegisterRegionType - default options are not a table");
  elseif(regionTypes[name]) then
    error("Improper arguments to WeakAuras.RegisterRegionType - region type \""..name.."\" already defined");
  else
    regionTypes[name] = {
      create = createFunction,
      modify = modifyFunction,
      default = default
    };
  end
end

--Dummy function so that region type options registrations don't return errors if WeakAurasOptions is not loaded
--WeakAurasOptions redefines this function to do something useful
function WeakAuras.RegisterRegionOptions()
end

function WeakAuras.SetRegion(data)
  local regionType = data.regionType;
  if not(regionType) then
    error("Improper arguments to WeakAuras.SetRegion - regionType not defined");
  else
    if(regionTypes[regionType]) then
      local id = data.id;
      if not(id) then
        error("Improper arguments to WeakAuras.SetRegion - id not defined");
      else
        local region;
        if((not regions[id]) or (not regions[id].region) or regions[id].regionType ~= regionType) then
          region = regionTypes[regionType].create(frame);
          regions[id] = {
            regionType = regionType,
            region = region
          };
        else
          region = regions[id].region;
        end
        WeakAuras.validate(data, regionTypes[regionType].default);
        
        local parent = frame;
        if(data.parent) then
          if(regions[data.parent]) then
            parent = regions[data.parent].region;
          else
            data.parent = nil;
          end
        end
        
        local anim_cancelled = WeakAuras.CancelAnimation("display", id, true, true, true);
        
        local pSelfPoint, pAnchor, pAnchorPoint, pX, pY = region:GetPoint(1);
        
        regionTypes[regionType].modify(parent, region, data);
        
        if(data.parent and db.displays[data.parent] and db.displays[data.parent].regionType == "dynamicgroup" and pSelfPoint and pAnchor and pAnchorPoint and pX and pY) then
          region:ClearAllPoints();
          region:SetPoint(pSelfPoint, pAnchor, pAnchorPoint, pX, pY);
        end
        
        data.animation = data.animation or {};
        data.animation.start = data.animation.start or {type = "none"};
        data.animation.main = data.animation.main or {type = "none"};
        data.animation.finish = data.animation.finish or {type = "none"};
        if(WeakAuras.CanHaveDuration(data)) then
          data.animation.start.duration_type = data.animation.start.duration_type or "seconds";
          data.animation.main.duration_type = data.animation.main.duration_type or "seconds";
          data.animation.finish.duration_type = data.animation.finish.duration_type or "seconds";
        else
          data.animation.start.duration_type = "seconds";
          data.animation.main.duration_type = "seconds";
          data.animation.finish.duration_type = "seconds";
        end
        if(data.parent and db.displays[data.parent] and db.displays[data.parent].regionType == "dynamicgroup") then
          parent:PositionChildren();
          function region:Collapse()
            if(region:IsVisible()) then
              parent.toHide[id] = true;
              WeakAuras.PerformActions(data, "finish");
              WeakAuras.Animate("display", id, "finish", data.animation.finish, region, false, function()
                region:Hide();
              end, nil, true)
              parent:ControlChildren();
            end
          end
          function region:Expand()
            parent.toShow[id] = true;
            if(WeakAuras.IsAnimating("display", id) == "finish" or parent.groupHiding[id] or not region:IsVisible()) then
              WeakAuras.PerformActions(data, "start");
              if not(WeakAuras.Animate("display", id, "start", data.animation.start, region, true, function()
                WeakAuras.Animate("display", id, "main", data.animation.main, region, false, nil, true);
              end)) then
                WeakAuras.Animate("display", id, "main", data.animation.main, region, false, nil, true);
              end
            end
            parent:ControlChildren();
          end
        else
          function region:Collapse()
            if(region:IsVisible()) then
              WeakAuras.PerformActions(data, "finish");
              if not(WeakAuras.Animate("display", id, "finish", data.animation.finish, region, false, function()
                region:Hide();
              end, nil, true)) then
                region:Hide();
              end
            end
          end
          function region:Expand()
            if(WeakAuras.IsAnimating("display", id) == "finish" or not region:IsVisible()) then
              region:Show();
              WeakAuras.PerformActions(data, "start");
              if not(WeakAuras.Animate("display", id, "start", data.animation.start, region, true, function()
                WeakAuras.Animate("display", id, "main", data.animation.main, region, false, nil, true);
              end)) then
                WeakAuras.Animate("display", id, "main", data.animation.main, region, false, nil, true);
              end
            end
          end
        end

        if(data.additional_triggers and #data.additional_triggers > 0) then
          region.trigger_count = region.trigger_count or 0;
          region.triggers = region.trigger or {};

          function region:TestTriggers(trigger_count)
            if(trigger_count > #data.additional_triggers) then
              region:Expand();
              return true;
            else
              region:Collapse();
              return false;
            end
          end

          function region:EnableTrigger(triggernum)
            if not(region.triggers[triggernum]) then
              region.triggers[triggernum] = true;
              region.trigger_count = region.trigger_count + 1;
              return region:TestTriggers(region.trigger_count);
            else
              return nil;
            end
          end

          function region:DisableTrigger(triggernum)
            if(region.triggers[triggernum]) then
              region.triggers[triggernum] = nil;
              region.trigger_count = region.trigger_count - 1;
              return not region:TestTriggers(region.trigger_count);
            else
              return nil;
            end
          end
        end
        
        if(anim_cancelled) then
          WeakAuras.Animate("display", id, "main", data.animation.main, region, false, nil, true);
        end
        
        return region;
      end
    else
      error("Improper arguments to WeakAuras.CreateRegion - regionType \""..data.regionType.."\" is not supported");
    end
  end
end

--This function is currently never called if WeakAuras is paused, but it is set up so that it can take a different action
--if it is called while paused. This is simply because it used to need to deal with that contingency and there's no reason
-- to delete that code (it could be useful in the future)
function WeakAuras.Announce(message, output, _, extra, id, type)
  if(paused) then
    local pausedMessage = "WeakAuras would announce \"%s\" to %s because %s %s, but did not because it is paused.";
    pausedMessage = pausedMessage:format(message, output..(extra and " "..extra or ""), id or "error", type == "start" and "was shown" or type == "finish" and "was hidden" or "error");
    DEFAULT_CHAT_FRAME:AddMessage(pausedMessage);
  else
    SendChatMessage(message, output, _, extra);
  end
end

function WeakAuras.PerformActions(data, type)
  if not(paused or squelch_actions) then
    local actions;
    if(type == "start") then
      actions = data.actions.start;
    elseif(type == "finish") then
      actions = data.actions.finish;
    else
      return;
    end
    
    if(actions.do_message and actions.message_type and actions.message) then
      if(actions.message_type == "WHISPER") then
        if(actions.message_dest) then
          if(actions.message_dest == "target" or actions.message_dest == "'target'" or actions.message_dest == "\"target\"" or actions.message_dest == "%t" or actions.message_dest == "'%t'" or actions.message_dest == "\"%t\"") then
            WeakAuras.Announce(actions.message, "WHISPER", nil, UnitName("target"), data.id, type);
          else
            WeakAuras.Announce(actions.message, "WHISPER", nil, actions.message_dest, data.id, type);
          end
        end
      elseif(actions.message_type == "CHANNEL") then
        local channel = actions.message_channel and tonumber(actions.message_channel);
        if(GetChannelName(channel)) then
          WeakAuras.Announce(actions.message, "CHANNEL", nil, channel, data.id, type);
        end
      else
        WeakAuras.Announce(actions.message, actions.message_type, nil, nil, data.id, type);
      end
    end
    
    if(actions.do_sound and actions.sound) then
      if(actions.sound == " custom") then
        if(actions.sound_path) then
          PlaySoundFile(actions.sound_path);
        end
      else
        PlaySoundFile(actions.sound);
      end
    end
    
    if(actions.do_custom and actions.custom) then
      local func = WeakAuras.LoadFunction("return function() "..(actions.custom).." end");
      func();
    end
  end
end

function WeakAuras.Animate(namespace, id, type, anim, region, inverse, onFinished, loop)
  local key = namespace..id;
  local inAnim = anim;
  local valid;
  if(anim and anim.type == "custom" and anim.duration and (anim.use_translate or anim.use_alpha or (anim.use_scale and region.Scale) or (anim.use_rotate and region.Rotate))) then
    valid = true;
  elseif(anim and anim.type == "preset" and anim.preset and anim_presets[anim.preset]) then
    anim = anim_presets[anim.preset];
    valid = true;
  end
  if(valid) then
    local selfPoint, anchor, anchorPoint, startX, startY, startAlpha, startWidth, startHeight, startRotation, translateFunc, alphaFunc, scaleFunc, rotateFunc;
    if(animations[key]) then
      if(animations[key].type == type and not loop) then
        return "no replace";
      end
      anim.x = anim.x or 0;
      anim.y = anim.y or 0;
      selfPoint, anchor, anchorPoint, startX, startY = animations[key].selfPoint, animations[key].anchor, animations[key].anchorPoint, animations[key].startX, animations[key].startY;
      anim.alpha = anim.alpha or 0;
      startAlpha = animations[key].startAlpha;
      anim.scalex = anim.scalex or 1;
      anim.scaley = anim.scaley or 1;
      startWidth, startHeight = animations[key].startWidth, animations[key].startHeight;
      anim.rotate = anim.rotate or 0;
      startRotation = animations[key].startRotation;
    else
      anim.x = anim.x or 0;
      anim.y = anim.y or 0;
      selfPoint, anchor, anchorPoint, startX, startY = region:GetPoint(1);
      anim.alpha = anim.alpha or 0;
      startAlpha = region:GetAlpha();
      anim.scalex = anim.scalex or 1;
      anim.scaley = anim.scaley or 1;
      startWidth, startHeight = region:GetWidth(), region:GetHeight();
      anim.rotate = anim.rotate or 0;
      startRotation = region.GetRotation and region:GetRotation() or 0;
    end
    
    if(anim.use_translate) then
      if not(anim.translateType == "custom" and anim.translateFunc) then
        anim.translateType = anim.translateType or "straightTranslate";
        anim.translateFunc = anim_function_strings[anim.translateType] or anim_function_strings.straightTranslate;
      end
      translateFunc = WeakAuras.LoadFunction(anim.translateFunc);
    else
      region:SetPoint(selfPoint, anchor, anchorPoint, startX, startY);
    end
    if(anim.use_alpha) then
      if not(anim.alphaType == "custom" and anim.alphaFunc) then
        anim.alphaType = anim.alphaType or "straight";
        anim.alphaFunc = anim_function_strings[anim.alphaType] or anim_function_strings.straight;
      end
      alphaFunc = WeakAuras.LoadFunction(anim.alphaFunc);
    else
      region:SetAlpha(startAlpha);
    end
    if(anim.use_scale) then
      if not(anim.scaleType == "custom" and anim.scaleFunc) then
        anim.scaleType = anim.scaleType or "straightScale";
        anim.scaleFunc = anim_function_strings[anim.scaleType] or anim_function_strings.straightScale;
      end
      scaleFunc = WeakAuras.LoadFunction(anim.scaleFunc);
    elseif(region.Scale) then
      region:Scale(1, 1);
    end
    if(anim.use_rotate) then
      if not(anim.rotateType == "custom" and anim.rotateFunc) then
        anim.rotateType = anim.rotateType or "straight";
        anim.rotateFunc = anim_function_strings[anim.rotateType] or anim_function_strings.straight;
      end
      rotateFunc = WeakAuras.LoadFunction(anim.rotateFunc);
    elseif(region.Rotate) then
      region:Rotate(startRotation);
    end
    
    if(loop) then
      onFinished = function() WeakAuras.Animate(namespace, id, type, inAnim, region, inverse, onFinished, loop) end
    end
    
    animations[key] = {
      progress = 0,
      startX = startX,
      startY = startY,
      startAlpha = startAlpha,
      startWidth = startWidth,
      startHeight = startHeight,
      startRotation = startRotation,
      dX = (anim.use_translate and anim.x),
      dY = (anim.use_translate and anim.y),
      dAlpha = (anim.use_alpha and (anim.alpha - startAlpha)),
      scaleX = (anim.use_scale and anim.scalex),
      scaleY = (anim.use_scale and anim.scaley),
      rotate = anim.rotate,
      translateFunc = translateFunc,
      alphaFunc = alphaFunc,
      scaleFunc = scaleFunc,
      rotateFunc = rotateFunc,
      region = region,
      selfPoint = selfPoint,
      anchor = anchor,
      anchorPoint = anchorPoint,
      duration = WeakAuras.ParseNumber(anim.duration) or 0,
      duration_type = anim.duration_type or "seconds",
      inverse = inverse,
      type = type,
      loop = loop,
      onFinished = onFinished,
      name = id
    };
    return true;
  else
    if(animations[key]) then
      if(animations[key].type ~= type or loop) then
        WeakAuras.CancelAnimation(namespace, id, true, true, true, true);
      end
    end
    return false;
  end
end

function WeakAuras.IsAnimating(namespace, id)
  local key = namespace..id;
  local anim = animations[key];
  if(anim) then
    return anim.type;
  else
    return nil;
  end
end

function WeakAuras.CancelAnimation(namespace, id, resetPos, resetAlpha, resetScale, resetRotation, doOnFinished)
  local key = namespace..id;
  local anim = animations[key];
  if(anim) then
    if(resetPos) then
      anim.region:ClearAllPoints();
      anim.region:SetPoint(anim.selfPoint, anim.anchor, anim.anchorPoint, anim.startX, anim.startY);
    end
    if(resetAlpha) then
      anim.region:SetAlpha(anim.startAlpha);
    end
    if(resetScale) then
      if(anim.region.Scale) then
        anim.region:Scale(1, 1);
      else
        anim.region:SetWidth(anim.startWidth);
        anim.region:SetHeight(anim.startHeight);
      end
    end
    if(resetRotation and anim.region.Rotate) then
      anim.region:Rotate(anim.startRotation);
    end
    
    animations[key] = nil;
    if(doOnFinished and anim.onFinished) then
      anim.onFinished();
    end
    return true;
  else
    return false;
  end
end

local last_update = GetTime();
function WeakAuras.UpdateAnimations()
  for groupId, groupRegion in pairs(pending_controls) do
    pending_controls[groupId] = nil;
    groupRegion:DoControlChildren();
  end
  local time = GetTime();
  local elapsed = time - last_update;
  last_update = time;
  for id, anim in pairs(animations) do
    local finished = false;
    if(anim.duration_type == "seconds") then
      anim.progress = anim.progress + (elapsed / anim.duration);
      if(anim.progress >= 1) then
        anim.progress = 1;
        finished = true;
      end
    elseif(anim.duration_type == "relative") then
      local duration, expirationTime = duration_cache:GetDurationInfo(anim.name);
      if(duration < 0.01) then
        anim.progress = 0;
        if(anim.type == "start" or anim.type == "finish") then
          finished = true;
        end
      else
        anim.progress = (1 - ((expirationTime - time) / duration)) / anim.duration;
        local iteration = math.floor(anim.progress);
        anim.progress = anim.progress - iteration;
        if not(anim.iteration) then
          anim.iteration = iteration;
        elseif(anim.iteration ~= iteration) then
          anim.iteration = nil;
          finished = true;
        end
      end
    else
      anim.progress = 1;
    end
    local progress = anim.inverse and (1 - anim.progress) or anim.progress;
    if(anim.translateFunc) then
      anim.region:ClearAllPoints();
      anim.region:SetPoint(anim.selfPoint, anim.anchor, anim.anchorPoint, anim.translateFunc(progress, anim.startX, anim.startY, anim.dX, anim.dY));
    end
    if(anim.alphaFunc) then
      anim.region:SetAlpha(anim.alphaFunc(progress, anim.startAlpha, anim.dAlpha));
    end
    if(anim.scaleFunc) then
      local scaleX, scaleY = anim.scaleFunc(progress, 1, 1, anim.scaleX, anim.scaleY);
      if(anim.region.Scale) then
        anim.region:Scale(scaleX, scaleY);
      else
        anim.region:SetWidth(anim.startWidth * scaleX);
        anim.region:SetHeight(anim.startHeight * scaleY);
      end
    end
    if(anim.rotateFunc and anim.region.Rotate) then
      anim.region:Rotate(anim.rotateFunc(progress, anim.startRotation, anim.rotate));
    end
    if(finished) then
      if not(anim.loop) then
        if(anim.startX) then
          anim.region:SetPoint(anim.selfPoint, anim.anchor, anim.anchorPoint, anim.startX, anim.startY);
        end
        if(anim.startAlpha) then
          anim.region:SetAlpha(anim.startAlpha);
        end
        if(anim.startWidth) then
          if(anim.region.Scale) then
            anim.region:Scale(1, 1);
          else
            anim.region:SetWidth(anim.startWidth);
            anim.region:SetHeight(anim.startHeight);
          end
        end
        if(anim.startRotation) then
          if(anim.region.Rotate) then
            anim.region:Rotate(anim.startRotation);
          end
        end
        animations[id] = nil;
      end
      
      if(anim.onFinished) then
        anim.onFinished();
      end
    end
  end
end

function WeakAuras.GetData(id)
  return db.displays[id];
end

function WeakAuras.CanHaveDuration(data)
  if(
    (
      data.trigger.type == "aura" and not(
        data.trigger.inverse
        or data.trigger.unit == "party"
        or data.trigger.unit == "raid"
      )
    )
    or (
      data.trigger.type == "event"
      and (
        (
          data.trigger.event
          and WeakAuras.event_prototypes[data.trigger.event]
          and WeakAuras.event_prototypes[data.trigger.event].durationFunc
        )
        or (
          data.trigger.unevent == "timed"
          and data.trigger.duration
        )
      )
    )
  ) then
    return true;
  else
    return false;
  end
end

function WeakAuras.CanHaveAuto(data)
  if(
    (
      data.trigger.type == "aura"
      and not (
        data.trigger.inverse
        or data.trigger.unit == "party"
        or data.trigger.unit == "raid"
      )
    )
    or (
      data.trigger.type == "event"
      and data.trigger.event
      and WeakAuras.event_prototypes[data.trigger.event]
      and (
        WeakAuras.event_prototypes[data.trigger.event].iconFunc
        or WeakAuras.event_prototypes[data.trigger.event].nameFunc
      )
    )
  ) then
    return true;
  else
    return false;
  end
end