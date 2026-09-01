local callChannel = 0

-- Fase de llamadas de Proyecto Voz (ver VOZ.md). Con `voice_useNativeCalls`
-- activa, el servidor mete/saca al jugador del canal nativo de la llamada
-- (ver server/module/phone.lua) -- eso ya basta para transmitir/recibir en
-- un canal NON_SPATIAL, no hace falta apuntar voice targets de Mumble.
-- `toggleVoice` se mantiene igual (submix/volumen, ver client/init/main.lua)
-- porque no es un mecanismo de "target", es cosmetico y sigue funcionando.
local function isNativeCallsActive()
	return GetConvarInt('voice_useNativeCalls', 0) == 1
end

RegisterNetEvent('pma-voice:syncCallData', function(callTable, channel)
	callData = callTable
	handleRadioAndCallInit()
end)

RegisterNetEvent('pma-voice:addPlayerToCall', function(plySource)
	toggleVoice(plySource, true, 'call')
	callData[plySource] = true
end)

RegisterNetEvent('pma-voice:removePlayerFromCall', function(plySource)
	if plySource == playerServerId then
		for tgt, _ in pairs(callData) do
			if tgt ~= playerServerId then
				toggleVoice(tgt, false, 'call')
			end
		end
		callData = {}
		if not isNativeCallsActive() then
			MumbleClearVoiceTargetPlayers(voiceTarget)
			addVoiceTargets((radioPressed and isRadioEnabled()) and radioData or {}, callData)
		end
	else
		callData[plySource] = nil
		toggleVoice(plySource, radioData[plySource], 'call')
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
