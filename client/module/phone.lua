local callChannel = 0

-- Fase de llamadas de Proyecto Voz (ver VOZ.md). Con `voice_useNativeCalls`
-- activa, el servidor mete/saca al jugador del canal nativo de la llamada
-- (ver server/module/phone.lua) -- eso ya basta para transmitir/recibir en
-- un canal NON_SPATIAL, no hace falta apuntar voice targets de Mumble.
local function isNativeCallsActive()
	return GetConvarInt('voice_useNativeCalls', 0) == 1
end

-- CORREGIDO 2026-09-02 (ver CLAUDE_LOG.md): `toggleVoice` NO es cosmetico
-- como se penso al principio -- confirmado en vivo con un arnes de pruebas
-- aislado (server/module/voice_native_test.lua) que el canal NON_SPATIAL
-- puro se oye perfecto sin tocar nada de esto, y que el mismo canal +
-- burbuja de proximidad a la vez TAMBIEN se oye perfecto -- la unica
-- diferencia real con la llamada rota de pma-voice es que esta SI llama a
-- `toggleVoice` (MumbleSetVolumeOverrideByServerId/MumbleSetSubmixForServerId,
-- ambas natives de Mumble) sobre un jugador cuyo audio ya no viaja por
-- Mumble. Se salta toggleVoice del todo cuando el modo nativo esta activo.
RegisterNetEvent('pma-voice:syncCallData', function(callTable, channel)
	callData = callTable
	handleRadioAndCallInit()
end)

RegisterNetEvent('pma-voice:addPlayerToCall', function(plySource)
	if not isNativeCallsActive() then
		toggleVoice(plySource, true, 'call')
	end
	callData[plySource] = true
end)

RegisterNetEvent('pma-voice:removePlayerFromCall', function(plySource)
	if plySource == playerServerId then
		if not isNativeCallsActive() then
			for tgt, _ in pairs(callData) do
				if tgt ~= playerServerId then
					toggleVoice(tgt, false, 'call')
				end
			end
		end
		callData = {}
		if not isNativeCallsActive() then
			MumbleClearVoiceTargetPlayers(voiceTarget)
			addVoiceTargets((radioPressed and isRadioEnabled()) and radioData or {}, callData)
		end
	else
		callData[plySource] = nil
		if not isNativeCallsActive() then
			toggleVoice(plySource, radioData[plySource], 'call')
		end
		if not isNativeCallsActive() and MumbleIsPlayerTalking(PlayerId()) then
			MumbleClearVoiceTargetPlayers(voiceTarget)
			addVoiceTargets((radioPressed and isRadioEnabled()) and radioData or {}, callData)
		end
	end
end)

function setCallChannel(channel)
	if GetConvarInt('voice_enableCalls', 1) ~= 1 then return end
	TriggerServerEvent('pma-voice:setPlayerCall', channel)
	callChannel = channel
	sendUIMessage({
		callInfo = channel
	})
end

exports('setCallChannel', setCallChannel)
exports('SetCallChannel', setCallChannel)

exports('addPlayerToCall', function(_call)
	local call = tonumber(_call)
	if call then
		setCallChannel(call)
	end
end)
exports('removePlayerFromCall', function()
	setCallChannel(0)
end)

RegisterNetEvent('pma-voice:clSetPlayerCall', function(_callChannel)
	if GetConvarInt('voice_enableCalls', 1) ~= 1 then return end
	callChannel = _callChannel
end)
