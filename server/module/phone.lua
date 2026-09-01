-- Fase de llamadas de Proyecto Voz (ver VOZ.md) -- aislada detras de
-- `voice_useNativeCalls` (0 por defecto). Motivacion documentada: la doc
-- oficial de Enhanced dice que con `voice_internal` la capa de compatibilidad
-- Mumble degrada `MUMBLE_SET_VOICE_TARGET`/`MUMBLE_CLEAR_VOICE_TARGET` a "as
-- if there is only a single voice target" -- justo lo que usa pma-voice para
-- las llamadas, y por eso no eran fiables (ver VOZ.md, entrada 2026-09-01).
-- Un canal NON_SPATIAL (modo 0, sin caida por distancia -- una llamada suena
-- igual sin importar donde este cada uno) por llamada activa resuelve esto
-- sin depender de voice targets en absoluto.
local nativeCallChannels = {} -- [callChannel] = channelId

local function isNativeCallsActive()
	return GetConvarInt('voice_useNativeCalls', 0) == 1
end

--- removes a player from the call for everyone in the call.
---@param source number the player to remove from the call
---@param callChannel number the call channel to remove them from
function removePlayerFromCall(source, callChannel)
	logger.verbose('[call] Removed %s from call %s', source, callChannel)

	callData[callChannel] = callData[callChannel] or {}
	for player, _ in pairs(callData[callChannel]) do
		TriggerClientEvent('pma-voice:removePlayerFromCall', player, source)
	end
	callData[callChannel][source] = nil
	voiceData[source] = voiceData[source] or defaultTable(source)
	voiceData[source].call = 0

	if isNativeCallsActive() then
		local channelId = nativeCallChannels[callChannel]
		if channelId then
			removePlayerFromNativeChannel(channelId, source)
			if not next(callData[callChannel]) then
				-- Llamada vacia -- borrar el canal, no dejarlo huerfano
				-- esperando a la siguiente llamada con este mismo numero.
				deleteNativeChannel(channelId)
				nativeCallChannels[callChannel] = nil
			end
		end
	end
end

--- adds a player to a call
---@param source number the player to add to the call
---@param callChannel number the call channel to add them to
function addPlayerToCall(source, callChannel)
	logger.verbose('[call] Added %s to call %s', source, callChannel)
	-- check if the channel exists, if it does set the varaible to it
	-- if not create it (basically if not callData make callData)
	callData[callChannel] = callData[callChannel] or {}
	for player, _ in pairs(callData[callChannel]) do
		-- don't need to send to the source because they're about to get sync'd!
		if player ~= source then
			TriggerClientEvent('pma-voice:addPlayerToCall', player, source)
		end
	end
	callData[callChannel][source] = true
	voiceData[source] = voiceData[source] or defaultTable(source)
	voiceData[source].call = callChannel
	TriggerClientEvent('pma-voice:syncCallData', source, callData[callChannel])

	if isNativeCallsActive() then
		local channelId = nativeCallChannels[callChannel]
		if not channelId then
			channelId = createNativeChannel(NATIVE_VOICE_MODE.NON_SPATIAL, 0.0)
			if channelId then
				nativeCallChannels[callChannel] = channelId
				logger.info('[call] Llamada %s -> canal nativo %s', callChannel, channelId)
			end
		end
		if channelId then
			addPlayerToNativeChannel(channelId, source)
		end
	end
end

--- set the players call channel
---@param source number the player to set the call off
---@param _callChannel number the channel to set the player to (or 0 to remove them from any call channel)
function setPlayerCall(source, _callChannel)
	if GetConvarInt('voice_enableCalls', 1) ~= 1 then return end
	voiceData[source] = voiceData[source] or defaultTable(source)
	local isResource = GetInvokingResource()
	local plyVoice = voiceData[source]
	local callChannel = tonumber(_callChannel)
	if not callChannel then
		-- only full error if its sent from another server-side resource
		if isResource then
			error(("'callChannel' expected 'number', got: %s"):format(type(_callChannel)))
		else
			return logger.warn("%s sent a invalid call, 'callChannel' expected 'number', got: %s", source,
				type(_callChannel))
		end
	end
	if isResource then
		-- got set in a export, need to update the client to tell them that their call
		-- changed
		TriggerClientEvent('pma-voice:clSetPlayerCall', source, callChannel)
	end

	Player(source).state.callChannel = callChannel

	if callChannel ~= 0 and plyVoice.call == 0 then
		addPlayerToCall(source, callChannel)
	elseif callChannel == 0 then
		removePlayerFromCall(source, plyVoice.call)
	elseif plyVoice.call > 0 then
		removePlayerFromCall(source, plyVoice.call)
		addPlayerToCall(source, callChannel)
	end
end

exports('setPlayerCall', setPlayerCall)

RegisterNetEvent('pma-voice:setPlayerCall', function(callChannel)
	setPlayerCall(source, callChannel)
end)
