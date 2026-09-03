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

-- 2026-09-02 (ver pma-voice/CLAUDE_LOG.md): `pma-voice:setPlayerCall` acepta
-- el callChannel directamente del cliente sin ninguna comprobacion de
-- pertenencia -- a diferencia de las radios (`canJoinChannel`/
-- `addChannelCheck` en radio.lua), cualquiera podia adivinar/probar el
-- call_id de una llamada ajena y unirse a escucharla, y con canales nativos
-- reales por debajo eso significa audio real, no solo un flag en una tabla.
-- Mismo patron que radio.lua: opt-in (si nadie registra un check para un
-- callChannel, se permite -- compatibilidad con quien use pma-voice sin
-- integrar esto), quien crea la llamada (qbx_phone) registra quienes son los
-- dos source legitimos en el momento en que la llamada conecta de verdad.
local callChecks = {} -- [callChannel] = cb(source): boolean

--- comprueba si `source` puede unirse al callChannel dado
---@param source number
---@param callChannel number
---@return boolean
function canJoinCall(source, callChannel)
	if callChecks[callChannel] then
		return callChecks[callChannel](source)
	end
	return true
end

--- registra un check de quien puede unirse a un callChannel (mismo patron
--- que addChannelCheck en radio.lua). Lo llama el recurso de telefono al
--- conectar la llamada, con los dos source reales.
---@param callChannel number
---@param cb function
function addCallCheck(callChannel, cb)
	local channelType = type(callChannel)
	local cbType = type(cb)
	if channelType ~= "number" then
		error(("'callChannel' expected 'number' got '%s'"):format(channelType))
	end
	if cbType ~= 'table' or not cb.__cfx_functionReference then
		error(("'cb' expected 'function' got '%s'"):format(cbType))
	end
	callChecks[callChannel] = cb
	logger.info("%s added a check to call %s", GetInvokingResource(), callChannel)
end

exports('addCallCheck', addCallCheck)

--- quita el check de un callChannel (limpieza manual opcional -- tambien se
--- limpia solo en removePlayerFromCall cuando la llamada se vacia)
---@param callChannel number
function removeCallCheck(callChannel)
	-- 2026-09-03 (ver CLAUDE_LOG.md): a diferencia de addCallCheck, esta no
	-- comprobaba el tipo antes de indexar -- crash real en vivo
	-- ("table index is nil") cuando qbx_phone llamaba con call_id nil (la
	-- ruta de "llamada sin respuesta" en notification.lua nunca lo incluye).
	-- Es limpieza defensiva, no un fallo de integracion -- no-op en vez de
	-- error si no es un numero valido.
	if type(callChannel) ~= 'number' then return end
	callChecks[callChannel] = nil
end

exports('removeCallCheck', removeCallCheck)

-- Fase 2 del plan de Telefono (ver qbx_phone/CLAUDE_LOG.md): silenciar en
-- llamada. qbx_phone solo conoce el callChannel (su propio call_id), no el
-- channelId nativo interno (nativeCallChannels es local a este modulo) --
-- export dedicado para no tener que exponer esa tabla entera hacia fuera.
--- silencia/des-silencia a `source` en la llamada `callChannel`. No-op (y
--- devuelve false) si las llamadas nativas no estan activas o la llamada no
--- tiene canal nativo todavia -- el mute por Mumble puro no esta cableado.
---@param source number
---@param callChannel number
---@param muted boolean
---@return boolean
function muteInCall(source, callChannel, muted)
	if not isNativeCallsActive() then return false end
	local channelId = nativeCallChannels[callChannel]
	if not channelId then return false end
	return setPlayerMutedInNativeChannel(channelId, source, muted)
end

exports('muteInCall', muteInCall)

-- Altavoz de verdad (no solo cosmetico, ver conversacion 2026-09-03): la
-- gente cerca de quien tiene la llamada en altavoz debe OIR la conversacion
-- (las dos partes), pero no poder hablar dentro de ella. SPATIAL/TEMPORARY
-- no vale para esto -- su caida de audio por distancia la calcula el motor
-- sobre la posicion real de CADA miembro del canal, y el interlocutor remoto
-- normalmente no esta fisicamente cerca (podria estar al otro lado del
-- mapa) -- meterlo en un canal SPATIAL lo silenciaria tambien para quien
-- SI esta en la llamada. Por eso esto añade oyentes al mismo canal
-- NON_SPATIAL de la llamada (sin caida por distancia) a mano, con un hilo de
-- proximidad real sobre la posicion de quien tiene el altavoz -- y los
-- silencia con setPlayerMutedInNativeChannel en cuanto entran (oyen, no
-- transmiten).
local SPEAKER_RADIUS = 6.0
local speakerState = {} -- [callChannel] = { holder = source, members = {[source]=true} }

local function clearCallSpeaker(callChannel)
	local state = speakerState[callChannel]
	if not state then return end
	local channelId = nativeCallChannels[callChannel]
	if channelId then
		for member in pairs(state.members) do
			removePlayerFromNativeChannel(channelId, member)
		end
	end
	speakerState[callChannel] = nil
end

--- activa/desactiva el altavoz de `source` en la llamada `callChannel` --
--- mientras este activo, los jugadores que se acerquen a `source` entran
--- (silenciados) al canal de la llamada, y salen al alejarse.
---@param source number
---@param callChannel number
---@param enabled boolean
---@return boolean
function setCallSpeaker(source, callChannel, enabled)
	if not isNativeCallsActive() then return false end
	if not nativeCallChannels[callChannel] then return false end

	if enabled then
		speakerState[callChannel] = { holder = source, members = {} }
	else
		clearCallSpeaker(callChannel)
	end
	return true
end

exports('setCallSpeaker', setCallSpeaker)

CreateThread(function()
	while true do
		if not next(speakerState) then
			Wait(2000)
			goto continue
		end

		for callChannel, state in pairs(speakerState) do
			local channelId = nativeCallChannels[callChannel]
			local holderPed = channelId and GetPlayerPed(state.holder) or 0

			if not channelId or holderPed == 0 then
				-- Llamada colgada o el que tenia el altavoz se desconecto --
				-- limpiar en vez de dejarlo intentando cada tick.
				clearCallSpeaker(callChannel)
				goto continue_call
			end

			local holderCoords = GetEntityCoords(holderPed)
			local nearby = {}
			for _, plyIdStr in ipairs(GetPlayers()) do
				local ply = tonumber(plyIdStr)
				if ply and ply ~= state.holder and not (callData[callChannel] and callData[callChannel][ply]) then
					local ped = GetPlayerPed(ply)
					if ped ~= 0 then
						local dist = #(holderCoords - GetEntityCoords(ped))
						if dist <= SPEAKER_RADIUS then
							nearby[ply] = true
						end
					end
				end
			end

			for ply in pairs(nearby) do
				if not state.members[ply] then
					addPlayerToNativeChannel(channelId, ply)
					setPlayerMutedInNativeChannel(channelId, ply, true)
					state.members[ply] = true
				end
			end
			for ply in pairs(state.members) do
				if not nearby[ply] then
					removePlayerFromNativeChannel(channelId, ply)
					state.members[ply] = nil
				end
			end

			::continue_call::
		end

		Wait(1000)
		::continue::
	end
end)

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

	if not next(callData[callChannel]) then
		-- Llamada vacia -- limpiar tambien su check de autorizacion y su
		-- altavoz (si tenia), no dejarlos huerfanos esperando a la
		-- siguiente llamada con este mismo numero (independiente de si las
		-- llamadas nativas estan activas -- clearCallSpeaker es un no-op
		-- seguro si nunca hubo altavoz).
		callChecks[callChannel] = nil
		clearCallSpeaker(callChannel)
	end
end

--- adds a player to a call
---@param source number the player to add to the call
---@param callChannel number the call channel to add them to
function addPlayerToCall(source, callChannel)
	if not canJoinCall(source, callChannel) then
		logger.warn('[call] %s intento unirse a la llamada %s sin autorizacion (addCallCheck lo rechazo)', source,
			callChannel)
		return false
	end
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
			local ok = addPlayerToNativeChannel(channelId, source)
			print(('[call debug] addPlayerToNativeChannel(canal=%s, source=%s) -> %s (llamada=%s, miembros ahora=%s)')
				:format(channelId, source, tostring(ok), callChannel, json.encode(callData[callChannel])))
		end
	end

	return true
end

-- Debug temporal (ver pma-voice/CLAUDE_LOG.md) -- para ver si dos jugadores
-- en la misma llamada de verdad acaban en el mismo canal nativo. Quitar
-- cuando se confirme resuelto.
RegisterCommand('callvoicedebug', function()
	print('[call debug] nativeCallChannels = ' .. json.encode(nativeCallChannels))
	print('[call debug] callData = ' .. json.encode(callData))
end, false)

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

	-- 2026-09-02: usa el resultado real de addPlayerToCall (puede rechazar
	-- por canJoinCall) en vez de asumir que siempre entra -- mismo patron que
	-- setPlayerRadio/wasAdded en radio.lua.
	if callChannel ~= 0 and plyVoice.call == 0 then
		local wasAdded = addPlayerToCall(source, callChannel)
		Player(source).state.callChannel = wasAdded and callChannel or 0
	elseif callChannel == 0 then
		removePlayerFromCall(source, plyVoice.call)
		Player(source).state.callChannel = 0
	elseif plyVoice.call > 0 then
		removePlayerFromCall(source, plyVoice.call)
		local wasAdded = addPlayerToCall(source, callChannel)
		Player(source).state.callChannel = wasAdded and callChannel or 0
	end
end

exports('setPlayerCall', setPlayerCall)

RegisterNetEvent('pma-voice:setPlayerCall', function(callChannel)
	setPlayerCall(source, callChannel)
end)
