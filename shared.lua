Cfg = {}

voiceTarget = 1

gameVersion = GetGameName()

-- these are just here to satisfy linting
if not IsDuplicityVersion() then
	LocalPlayer = LocalPlayer
	playerServerId = GetPlayerServerId(PlayerId())

	if gameVersion == "redm" then
		function CreateAudioSubmix(name)
			return Citizen.InvokeNative(0x658d2bc8, name, Citizen.ResultAsInteger())
		end

		function AddAudioSubmixOutput(submixId, outputSubmixId)
			Citizen.InvokeNative(0xAC6E290D, submixId, outputSubmixId)
		end

		function MumbleSetSubmixForServerId(serverId, submixId)
			Citizen.InvokeNative(0xFE3A3054, serverId, submixId)
		end

		function SetAudioSubmixEffectParamFloat(submixId, effectSlot, paramIndex, paramValue)
			Citizen.InvokeNative(0x9A209B3C, submixId, effectSlot, paramIndex, paramValue)
		end

		function SetAudioSubmixEffectParamInt(submixId, effectSlot, paramIndex, paramValue)
			Citizen.InvokeNative(0x77FAE2B8, submixId, effectSlot, paramIndex, paramValue)
		end

		function SetAudioSubmixEffectRadioFx(submixId, effectSlot)
			Citizen.InvokeNative(0xAAA94D53, submixId, effectSlot)
		end

		function SetAudioSubmixOutputVolumes(submixId, outputSlot, frontLeftVolume, frontRightVolume, rearLeftVolume,
											 rearRightVolume, channel5Volume, channel6Volume)
			Citizen.InvokeNative(0x825DC0D1, submixId, outputSlot, frontLeftVolume, frontRightVolume, rearLeftVolume,
				rearRightVolume, channel5Volume, channel6Volume)
		end
	end
end
Player = Player
Entity = Entity

-- `voice_useNativeAudio` esta en la lista oficial de convars eliminadas en
-- Enhanced (ver VOZ.md, "Documentacion oficial completa") -- la distincion
-- "audio nativo vs normal" que habia aqui era un vestigio muerto (el motor ya
-- no la lee, solo devolvia lo que hubiera a mano en el server.cfg). Una sola
-- tabla, calibrada sobre el ejemplo oficial de CreateVoiceChannel(1, 15.0).
Cfg.voiceModes = {
	{ 2.0,  "Whisper" },  -- Whisper speech distance in gta distance units
	{ 6.0,  "Normal" },   -- Normal speech distance in gta distance units
	{ 15.0, "Shouting" }, -- Shout speech distance in gta distance units
}

logger = {
	log = function(message, ...)
		print((message):format(...))
	end,
	info = function(message, ...)
		if GetConvarInt('voice_debugMode', 0) >= 1 then
			print(('[info] ' .. message):format(...))
		end
	end,
	warn = function(message, ...)
		print(('[^1WARNING^7] ' .. message):format(...))
	end,
	error = function(message, ...)
		error((message):format(...))
	end,
	verbose = function(message, ...)
		if GetConvarInt('voice_debugMode', 0) >= 4 then
			print(('[verbose] ' .. message):format(...))
		end
	end,
}


function tPrint(tbl, indent)
	indent = indent or 0
	for k, v in pairs(tbl) do
		local tblType = type(v)
		local formatting = string.rep("  ", indent) .. k .. ": "

		if tblType == "table" then
			print(formatting)
			tPrint(v, indent + 1)
		elseif tblType == 'boolean' then
			print(formatting .. tostring(v))
		elseif tblType == "function" then
			print(formatting .. tostring(v))
		else
			print(formatting .. v)
		end
	end
end

local function types(args)
	local argType = type(args[1])
	for i = 2, #args do
		local arg = args[i]
		if argType == arg then
			return true, argType
		end
	end
	return false, argType
end

--- does a type check and errors if an invalid type is sent
---@param ... table a table with the variable being the first argument and the expected type being the second
function type_check(...)
	local vars = { ... }
	for i = 1, #vars do
		local var = vars[i]
		local matchesType, varType = types(var)
		if not matchesType then
			table.remove(var, 1)
			error(("Invalid type sent to argument #%s, expected %s, got %s"):format(i, table.concat(var, "|"), varType))
		end
	end
end
