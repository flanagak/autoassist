--[[
* Addons - Copyright (c) 2021 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name 			= "autoAssist"
addon.author 		= "Original:Ekrividus Ashita v4 port:flanagak"
addon.version 		= "1.0"
addon.desc			= "Automatic Assist";

require ('common');
local chat = require('chat');
local settings = require('settings');

-- Default Settings
local default_settings = T{
  show_debug = false,
  approach = true,
  retreat = true,
	min_range = 1.0,
	max_range = 3.0,
	face_target = true,
	update_time = 0.25,
	assist_target = "",
	engage = true,
	engage_delay = 1,
	reposition = false,
	follow_target = "",
};

-- autoAssist Variables
local autoassist = T{
  settings = settings.load(default_settings),
	running = false,
	approaching = false,
	retreating = false,
	mob = nil,
	start_position = {x=nil, y=nil},
	is_following = false,
	last_check_time = os.clock(),
	next_check_time = 0,
};

function proper_case(s)
    return s:sub(1,1):upper()..s:sub(2)
end

function message(text, isDebugMsg)
	if (isDebugMsg and autoassist.settings.show_debug) then
		print(chat.header(addon.name..":Debug"):append(chat.message(text)));
	else
		if (not isDebugMsg) then
			print(chat.header(addon.name):append(chat.message(text)));
		end
	end
end

function buff_active(id)
	activeBuffs = AshitaCore:GetMemoryManager():GetPlayer():GetBuffs()
	for i = 0, 32 do
		if activeBuffs[i] == id then
			return true
		else
			return false
		end
	end
end

function is_disabled()
	if buff_active(0) == true then -- KO
		return true
	elseif buff_active(2) == true then -- SLEEP
		return true
	elseif buff_active(6) == true then -- SILENCE
		return true
	elseif buff_active(7) == true then -- PETRIFICATION
		return true
	elseif buff_active(10) == true then -- STUN
		return true
	elseif buff_active(14) == true then -- CHARM
		return true
	elseif buff_active(28) == true then -- TERRORIZE
		return true
	elseif buff_active(29) == true then -- MUTE
		return true
	elseif buff_active(193) == true then -- LULLABY
		return true
	elseif buff_active(262) == true then -- OMERTA
		return true
	end
	return false
end

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/aa help','Shows the addon help.' },
    		{ '/aa (start | on | go)','Start assisting the configured target.' },
    		{ '/aa (stop | off | end)','Stop assisting the configured target.' },
    		{ '/aa assist <name>','Set target player to assist.' },
    		{ '/aa follow <name>','Set player to follow. /aa follow "" to disable follow.' },
    		{ '/aa (reposition | reset | return)','Toggle weather to return to anchor point or not.' },
    		{ '/aa (setposition | setpos | position | pos)','Set anchor point to return to after battle.' },
    		{ '/aa engage','Toggle weather to engage or not.' },
    		{ '/aa delay','Set delay before engaging. Minimum of 1 sec.' },
    		{ '/aa approach','Toggle weather to approach enemy or not.' },
    		{ '/aa range','Set range to stand from mob.' },
    		{ '/aa face','Toggle weather to face the enemy or not.' },
    		{ '/aa update','Set how often autoAssist will check for new target.' },
    		{ '/aa debug','Toggle weather to show debug messages or not.' },
    		{ '/aa save','Save the current setting to settings file.' },
    		{ '/aa show','Shows the values of all current settings.' },
        };

    -- Print the command list..
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        autoassist.settings = s;
    end

    -- Save the current settings..
    settings.save();
end

--[[
* Returns the entity that matches the given server id.
*
* @param {number} sid - The entity server id.
* @return {object | nil} The entity on success, nil otherwise.
--]]
local function GetEntityByServerId(sid)
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if (ent ~= nil and ent.ServerId == sid) then
            return ent;
        end
    end
    return nil;
end

--[[
* Returns the entity that matches the given name.
*
* @param {number} sid - The entity server id.
* @return {object | nil} The entity on success, nil otherwise.
--]]
local function GetEntityByName(name)
    for x = 0, 2303 do
        local ent = GetEntity(x);
        if (ent ~= nil and ent.Name == name) then
            return ent;
        end
    end
    return nil;
end

--[[
* Sets (or toggles) the player entity walk mode.
*
* @param {number|nil} flag - Flag used to set the walk mode if given. (Toggles if no value given.)
--]]
local function toggle_walk(flag)
    local player = GetPlayerEntity();
    if (player == nil or player.ActorPointer == 0) then
        return;
    end
    if (flag ~= nil) then
        ashita.memory.write_uint8(player.ActorPointer + 0xFA,  flag == 0 and 0 or 1);
    else
        ashita.memory.write_uint8(player.ActorPointer + 0xFA, ashita.memory.read_uint8(player.ActorPointer + 0xFA) == 0 and 1 or 0);
    end
end

--[[
* Turns the player entity to face the given direction.
*
* @param {number} dir - The direction to face. (In radians.)
--]]
local function turn(dir)
    local player = GetPlayerEntity();
    if (player == nil or player.ActorPointer == 0) then
        return;
    end
    ashita.memory.write_float(player.ActorPointer + 0x48, dir);
end

--[[
* Runs the player.
*
* @param {nil|boolean|number} a - The first param. (See notes below.)
* @param {nil|number} b - The second param. (See notes below.)
* @param {nil|number} c - The first param. (See notes below.)
* @notes
*
* run();
*   Starts moving the player in the direction they are currently facing.
*
* run(true);
* run(false);
*   Starts, or stops, moving the player in the direction they are currently facing.
*
* run(radian)
*   Starts running the player in the direction of the given radian.
*
* run(x, y [, z])
*   Starts running the player in the given direction. (Delta between the target position and the players current position.)
*
*       North   = -math.pi / 2
*       South   = math.pi / 2
*       East    = 0
*       West    = math.pi
*
--]]
local function run(a, b, c)
    local player = GetPlayerEntity();
    if (player == nil or player.ActorPointer == 0) then
        return;
    end

    local delta_x   = 0;
    local delta_y   = 0;
    local follow    = AshitaCore:GetMemoryManager():GetAutoFollow();

    -- Handle: run()
    -- Handle: run(true)
    if (a == nil or a ~= nil and type(a) == 'boolean' and a == true) then
        delta_x = math.cos(player.Movement.LocalPosition.Yaw);
        delta_y = -math.sin(player.Movement.LocalPosition.Yaw);

    -- Handle: run(false)
    elseif (a ~= nil and type(a) == 'boolean' and a == false) then
        follow:SetIsAutoRunning(0);
        follow:SetFollowDeltaX(0.0);
        follow:SetFollowDeltaZ(0.0);
        follow:SetFollowDeltaY(0.0);
        follow:SetFollowDeltaW(1.0);
        return;

    -- Handle: run(radian)
    elseif (a ~= nil and type(a) == 'number' and b == nil) then
        delta_x = math.cos(a);
        delta_y = -math.sin(a);

    -- Handle: run(x, y [, z])
    elseif (a ~= nil and b ~= nil and c ~= nil) then
        delta_x = a;
        delta_y = b;
    end

    follow:SetFollowDeltaX(delta_x);
    follow:SetFollowDeltaZ(0.0);
    follow:SetFollowDeltaY(delta_y);
    follow:SetIsAutoRunning(1);
end

function engage()
	local assist_target = nil
    if (autoassist.settings.assist_target and autoassist.settings.assist_target ~= '') then
        assist_target = GetEntityByName(autoassist.settings.assist_target)
		message("Assisting: " .. autoassist.settings.assist_target,true);
		
		if (assist_target and assist_target.Status == 1) then
			message("Targeted Index: " .. assist_target.TargetedIndex,true)
			mob = GetEntity(assist_target.TargetedIndex)
			if (not mob) then -- or not mob.claim_id or mob.claim_id == 0) then
				return
			end

			-- Assist our assist target and then engage
			local tgt = AshitaCore:GetMemoryManager():GetTarget()
			if (not tgt or tgt.id ~= mob.TargetIndex) then
				AshitaCore:GetChatManager():QueueCommand(1, "/assist \""..autoassist.settings.assist_target.."\"")
				local player = GetPlayerEntity();

				if (autoassist.settings.engage and player.Status == 0) then
					reposition(false)
					approach(false)
					if (autoassist.settings.engage_delay < 1) then
						autoassist.settings.engage_delay = 1
					end 
					(function() AshitaCore:GetChatManager():QueueCommand(1, '/attack on') end):once(autoassist.settings.engage_delay)
				end
			elseif (autoassist.settings.engage and autoassist.player.status == 0) then
				reposition(false)
				approach(false)
				if (autoassist.settings.engage_delay < 1) then
					autoassist.settings.engage_delay = 1
				end 
				(function() AshitaCore:GetChatManager():QueueCommand(1, '/attack on') end):once(autoassist.settings.engage_delay)
			end
		end
    end
end

function is_facing_target()
	local player = GetPlayerEntity();	
	assist_target = GetEntityByName(autoassist.settings.assist_target)
	mob = GetEntity(assist_target.TargetedIndex)	
    if (not mob) then
		return
    end
    
    local angle = (math.atan2((mob.Movement.LocalPosition.Y - player.Movement.LocalPosition.Y), (mob.Movement.LocalPosition.X - player.Movement.LocalPosition.X))*180/math.pi)
    local heading = player.Heading*180/math.pi*-1

    if (math.abs(math.abs(heading) - math.abs(angle)) < 5) then
		return true
    end
    return false
end

function face_target()
    message("Turning to face Target",true)
	local player = GetPlayerEntity();
	assist_target = GetEntityByName(autoassist.settings.assist_target)
	mob = GetEntity(assist_target.TargetedIndex)
    if (not mob) then
        return
    end

    local angle = (math.atan2((mob.Movement.LocalPosition.Y - player.Movement.LocalPosition.Y), (mob.Movement.LocalPosition.X - player.Movement.LocalPosition.X))*180/math.pi)*-1
    local rads = angle:radian()
    turn(rads)
end

function is_in_range()
	message("Checking if in range",true)
    local player = GetPlayerEntity();
	assist_target = GetEntityByName(autoassist.settings.assist_target)
	mob = GetEntity(assist_target.TargetedIndex)
    if (not mob) then
        return nil
    end
    local dist = mob.Distance:sqrt() - (mob.ModelSize/2 + player.ModelSize/2 - 1)
    if (dist > autoassist.settings.max_range) then
		return "approach"
    elseif (dist < autoassist.settings.min_range) then
		return "retreat"
    end
    return nil
end

function approach(start)
    if (start) then
        retreat(false)
        message("Approaching",true)
        local player = GetPlayerEntity();
		assist_target = GetEntityByName(autoassist.settings.assist_target)
		mob = GetEntity(assist_target.TargetedIndex)

        if (not mob) then
            run(false)
            autoassist.approaching = false
            return
        end
    
        local angle = (math.atan2((mob.Movement.LocalPosition.Y - player.Movement.LocalPosition.Y), (mob.Movement.LocalPosition.X - player.Movement.LocalPosition.X))*180/math.pi)*-1
        local rads = angle:radian()

        run(rads)
        autoassist.approaching = true
        return
    else
        run(false)
        autoassist.approaching = false
    end
end

function retreat(start)
    if (start) then
        message("Retreating",true)
        approach(false)
        local player = GetPlayerEntity();
		assist_target = GetEntityByName(autoassist.settings.assist_target)
		mob = GetEntity(assist_target.TargetedIndex)

        if (not mob) then
            run(false)
            autoassist.retreating = false
            return
        end
    
        local angle = (math.atan2((mob.Movement.LocalPosition.Y - player.Movement.LocalPosition.Y), (mob.Movement.LocalPosition.X - player.Movement.LocalPosition.X))*180/math.pi)
        local rads = angle:radian()

        run(rads)
        autoassist.retreating = true
        return
    else
        run(false)
        autoassist.retreating = false
    end
end

function set_position()
	local player = GetPlayerEntity();
    autoassist.start_position.x = player.Movement.LocalPosition.X
    autoassist.start_position.y = player.Movement.LocalPosition.Y
    message("Setting return position to ("..autoassist.start_position.x..", "..autoassist.start_position.y..")",true)
end

function in_position()
	local player = GetPlayerEntity();
    local dist = ((player.Movement.LocalPosition.X - autoassist.start_position.x)^2 + (player.Movement.LocalPosition.Y - autoassist.start_position.y)^2):sqrt()
    if (dist <= 2) then
        reposition(false)
        return true
    end
    return false
end

function reposition(start)
    if (start) then
        message("Repositioning",true)
		local player = GetPlayerEntity();
        local angle = (math.atan2((autoassist.start_position.y - player.Movement.LocalPosition.Y), (autoassist.start_position.x - player.Movement.LocalPosition.X))*180/math.pi)*-1
        local rads = angle:radian()

        run(rads)
        autoassist.returning = true
    else
        run(false)
        autoassist.returning = false
    end
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', update_settings);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    settings.save();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/aa', '/autoassist')) then
        return;
    end
	
	-- Block all related commands..
    e.blocked = true;
	
	-- Handle: /aa help - Shows the addon help.
    if (#args == 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end
	
	-- Handle: /aa ('start','on','go') - Start assisting the configured target.
	if (#args == 2 and args[2]:any('start','on','go')) then
		set_position()
        autoassist.running = true
		message("Starting autoAssist")
        return;
    end
	
	-- Handle: /aa ('stop','off','end') - Stop assisting the configured target.
	if (#args == 2 and args[2]:any('stop','off','end')) then
        autoassist.running = false
		message("Stoping autoAssist")
        return;
    end
	
	-- Handle: /aa assist - Set target player to assist.
	if (#args >= 2 and args[2]:any('assist')) then
        if (#args < 3) then
            message("You need to specify a player to assist.")
            return
        end
		
		local person = proper_case(args[3])
		message("Attempting to set assist target to "..person,true)
        if (GetEntityByName(person) == nil) then
            message("You need to specify a valid player to assist.")
            return
        end
		message("Setting assist target to "..person)
        autoassist.settings.assist_target = person
	end
	
	-- Handle: /aa follow - Set player to follow. /aa follow "" to disable follow.
	if (#args >= 2 and args[2]:any('follow')) then
        if (#args < 3) then
            message("You need to specify a player to follow.")
            return
        end
		
		local person = proper_case(args[3])
		message("Attempting to set follow target to "..person,true)
        if (GetEntityByName(person) == nil) then
            message("You need to specify a valid player to follow.")
            return
        end
		message("Setting follow target to "..person)
        autoassist.settings.follow_target = person
	end
	
	if (#args == 2) then
		-- Handle: /aa ('reposition','reset','return') - Toggle weather to return to anchor point or not.
		if (args[2]:any('reposition','reset','return')) then
			autoassist.settings.reposition = not autoassist.settings.reposition
			message("Will "..(autoassist.settings.reposition and "" or "not ").."reposition after mob death.")
			return;
		-- Handle: /aa ('setposition','setpos','position', 'pos') - Set anchor point to return to after battle.
		elseif (args[2]:any('setposition','setpos','position', 'pos')) then
			set_position()
			message("New return position set.")
			return;
		-- Handle: /aa engage - Toggle weather to engage or not.
		elseif (args[2] == 'engage') then
			autoassist.settings.engage = not autoassist.settings.engage
			message("Will now "..(autoassist.settings.engage and "engage" or "not engage"))
			return;
		-- Handle: /aa delay - Set delay before engaging. Minimum of 1 sec.
		elseif (args[2] == 'delay') then
			autoassist.settings.engage_delay = tonumber(arg[2]) and tonumber(arg[2]) or 1
			message("Engage delay set to "..autoassist.settings.engage_delay.." seconds")
			return;
		-- Handle: /aa approach - Toggle weather to approach enemy or not.
		elseif (args[2] == 'approach') then
			autoassist.settings.approach = not autoassist.settings.approach
			message("Will "..(autoassist.settings.approach and "approach" or "not approach"))
			return;
		-- Handle: /aa range - Set range to stand from mob.
		elseif (args[2] == 'range') then
			autoassist.settings.max_range = tonumber(arg[2]) or 3.5
			message("Will close to "..autoassist.settings.max_range.."'")
			return;
		-- Handle: /aa face - Toggle weather to face the enemy or not.
		elseif (args[2] == 'face') then
			autoassist.settings.face_target = not autoassist.settings.face_target
			message("Will "..(autoassist.settings.face_target and "face target" or "not face target"))
			return;
		-- Handle: /aa update - Set how often autoAssist will check for new target.
		elseif (args[2] == 'update') then
			autoassist.settings.update_time = tonumber(arg[2]) or 2
			message("Time between updates "..autoassist.settings.update_time.." second(s)")
			return;
		-- Handle: /aa debug - Toggle weather to show debug messages or not.
		elseif (args[2] == 'debug') then
			autoassist.settings.show_debug = not autoassist.settings.show_debug
			message("Debug info will "..(autoassist.settings.show_debug and 'be shown' or 'not be shown'))
			return;
		-- Handle: /aa save - Save the current setting to settings file.
		elseif (args[2] == 'save') then
			settings:save()
			message("Settings saved.")
			return;
		-- Handle: /aa show - Shows the values of all current settings.
		elseif (args[2] == 'show') then
			for k,v in pairs(autoassist.settings) do
				message(tostring(k)..": "..tostring(v))
			end
			return;
		end
	end	
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    if (autoassist.approaching) then
        if (not mob or mob.HPPercent <= 0 or is_in_range() ~= 'approach') then
            approach(false)
        end
    elseif (autoassist.retreating) then
        if (not mob or mob.HPPercent <= 0 or is_in_range() ~= 'retreat') then
            retreat(false)
        end
    elseif (autoassist.returning) then
        if (in_position()) then
            reposition(false)
        end
    end
    if (not autoassist.running) then
        next_check_time = 0
        return
    end

    local time = os.clock()
	local delta_time = time - autoassist.last_check_time
	autoassist.last_check_time = time

    if (time < autoassist.next_check_time) then
        return
    end
    autoassist.next_check_time = time + autoassist.settings.update_time

	local player = GetPlayerEntity();
	assist_target = GetEntityByName(autoassist.settings.assist_target)
	mob = GetEntity(assist_target.TargetedIndex)

    if (mob and player.Status == 1) then 
        if (autoassist.is_following and autoassist.settings.follow_target and autoassist.settings.follow_target ~= "") then
            autoassist.is_following = false
        end
        if (not is_facing_target() and autoassist.settings.face_target == true) then
            face_target()
        end
        local should_move = is_in_range()
        if (should_move == "approach" and autoassist.settings.approach == true) then
            approach(true)
        elseif (should_move == "retreat" and autoassist.settings.retreat == true) then
            retreat(true)
        end
        return
    elseif (assist_target and assist_target.Status == 1 and player.Status == 0 and not is_disabled()) then
        engage()
    elseif (player.Status ~= 1 and not autoassist.is_following and autoassist.settings.follow_target and autoassist.settings.follow_target ~= "") then
        message("Enabling follow on "..autoassist.settings.follow_target,true)
		AshitaCore:GetChatManager():QueueCommand(1, "/follow \""..autoassist.settings.follow_target.."\"")
        autoassist.is_following = true
    elseif (player.Status == 0 and not is_disabled() and autoassist.settings.reposition == true and not in_position()) then
        reposition(true)
    end
end);

--[[
* event: packet_in
* desc : Event called when the addon is processing incoming packets.
--]]
ashita.events.register('packet_in', 'packet_in_cb', function (e)
	-- Packet: Zone Leave
    if (e.id == 0x000B) then
        autoassist.running = false;
        return;
    end
	
end);
