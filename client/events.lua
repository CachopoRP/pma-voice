isInitialized = false

function handleInitialState()
	local voiceModeData = Cfg.voiceModes[mode]
	-- Fase 2 de Proyecto Voz (ver VOZ.md): con native proximity, el radio de
	-- audicion lo da la pertenencia al canal nativo del tramo, no el radio de
	-- Mumble -- ponerlo a 0 evita que la proximidad "de base" del engine se
	-- solape con el canal nativo (doble audio).
	local useNativeProximity = GetConvarInt('voice_useNativeProximity', 0) == 1
	local useNativeCalls = GetConvarInt('voice_useNativeCalls', 0) == 1
	if not useNativeProximity then
		MumbleSetTalkerProximity(voiceModeData[1] + 0.0)
	end
	if useNativeProximity then
		TriggerServerEvent('pma-voice:server:joinNativeProximityTier', mode)
	end

	-- Mismo canal base "assignedChannel" que addNearbyPlayers salta cuando
	-- alguna de las dos convars nativas esta activa (ver
	-- pma-voice/CLAUDE_LOG.md, 2026-09-02 (8)) -- esto es la version de
	-- conexion inicial del mismo bloque, se salta igual para no llamar
	-- natives Mumble que de todas formas se van a pisar/ignorar.
	if not useNativeCalls and not useNativeProximity then
		MumbleClearVoiceTarget(voiceTarget)
		MumbleSetVoiceTarget(voiceTarget)
		MumbleSetVoiceChannel(LocalPlayer.state.assignedChannel)

		while MumbleGetVoiceChannelFromServerId(playerServerId) ~= LocalPlayer.state.assignedChannel do
			Wait(100)
			MumbleSetVoiceChannel(LocalPlayer.state.assignedChannel)
		end

		MumbleAddVoiceTargetChannel(voiceTarget, LocalPlayer.state.assignedChannel)
	end

	isInitialized = true

	addNearbyPlayers()
end

AddEventHandler('mumbleConnected', function(address, isReconnecting)
	logger.info('Connected to mumble server with address of %s, is this a reconnect %s',
		GetConvarInt('voice_hideEndpoints', 1) == 1 and 'HIDDEN' or address, isReconnecting)

	logger.log('Connecting to mumble, setting targets.')
	-- don't try to set channel instantly, we're still getting data.
	local voiceModeData = Cfg.voiceModes[mode]
	LocalPlayer.state:set('proximity', {
		index = mode,
		distance = voiceModeData[1],
		mode = voiceModeData[2],
	}, true)

	handleInitialState()

	logger.log('Finished connection logic')
end)

AddEventHandler('mumbleDisconnected', function(address)
	isInitialized = false
	logger.info('Disconnected from mumble server with address of %s',
		GetConvarInt('voice_hideEndpoints', 1) == 1 and 'HIDDEN' or address)
end)

-- TODO: Convert the last Cfg to a Convar, while still keeping it simple.
AddEventHandler('pma-voice:settingsCallback', function(cb)
	cb(Cfg)
end)
