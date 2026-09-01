-- Fase 2 de Proyecto Voz -- ver VOZ.md. Capa de proximidad nativa, aislada
-- del camino real (client/init/proximity.lua sigue intacto, sobre Mumble).
--
-- Diseno: MumbleSetTalkerProximity es un radio POR JUGADOR (cada cliente
-- ajusta el suyo). CreateVoiceChannel(1=SPATIAL, maxDistance) es un canal
-- del SERVIDOR con un unico radio compartido por todos sus miembros -- no
-- hay una native para cambiar el radio de un canal ya creado. Por eso la
-- migracion no es "un canal que cambia de radio", es "unos pocos canales
-- fijos, uno por cada tramo de Cfg.voiceModes (Susurro/Normal/Grito), y
-- cada jugador pertenece al canal de su tramo actual" -- mismo patron que
-- ya recomienda native_channels.lua para no acumular canales huerfanos.

local tierChannels = {} -- [tierIndex] = channelId
local playerTier = {}   -- [source] = tierIndex actualmente asignado

--- Crea los canales fijos (uno por tramo de Cfg.voiceModes). Se llama una
--- sola vez al arrancar el recurso -- si falla algun canal, los tramos
--- fallidos quedan sin numero y joinNativeProximityTier los ignora.
local function setupTierChannels()
	for i = 1, #Cfg.voiceModes do
		local distance = Cfg.voiceModes[i][1]
		local channelId = createNativeChannel(NATIVE_VOICE_MODE.SPATIAL, distance + 0.0)
		if channelId then
			tierChannels[i] = channelId
			logger.info('[native_proximity] Tramo %s (%s, %sm) -> canal nativo %s', i, Cfg.voiceModes[i][2], distance,
				channelId)
		else
			logger.error('[native_proximity] No se pudo crear el canal nativo para el tramo %s (%s)', i,
				Cfg.voiceModes[i][2])
		end
	end
end

--- Mete a un jugador en el canal nativo de un tramo, sacandolo antes del
--- que tuviera asignado (un jugador solo pertenece a un tramo a la vez).
---@param source number
---@param tierIndex number indice en Cfg.voiceModes (1=Susurro, 2=Normal, 3=Grito por defecto)
---@return boolean
function joinNativeProximityTier(source, tierIndex)
	local channelId = tierChannels[tierIndex]
	if not channelId then
		logger.warn('[native_proximity] Tramo %s sin canal nativo (fallo al crear o indice invalido)', tierIndex)
		return false
	end

	local previousTier = playerTier[source]
	if previousTier and previousTier ~= tierIndex and tierChannels[previousTier] then
		removePlayerFromNativeChannel(tierChannels[previousTier], source)
	end

	local ok = addPlayerToNativeChannel(channelId, source)
	if ok then
		playerTier[source] = tierIndex
	end
	return ok
end

exports('joinNativeProximityTier', joinNativeProximityTier)

--- Saca a un jugador de cualquier tramo de proximidad nativa (desconexion,
--- o al volver por completo al camino de Mumble).
---@param source number
function leaveNativeProximity(source)
	local tierIndex = playerTier[source]
	if not tierIndex or not tierChannels[tierIndex] then return end
	removePlayerFromNativeChannel(tierChannels[tierIndex], source)
	playerTier[source] = nil
end

exports('leaveNativeProximity', leaveNativeProximity)

AddEventHandler('playerDropped', function()
	local source = source
	leaveNativeProximity(source)
end)

CreateThread(function()
	-- despues de native_channels.lua (mismo recurso, sin orden garantizado
	-- entre archivos server_scripts salvo el orden del fxmanifest) -- espera
	-- un tick para asegurar que createNativeChannel ya existe.
	Wait(0)
	setupTierChannels()
end)

-- Prueba manual de Fase 2 -- NO toca el camino real de proximidad (Mumble
-- sigue intacto). Uso: /testnativeproximity <tramo 1-3> desde el chat (como
-- jugador) o /testnativeproximity <tramo> <serverId> desde la consola.
-- Borrar cuando la Fase 2 se de por buena, igual que el comando de la Fase 1.
RegisterCommand('testnativeproximity', function(source, args)
	local tierIndex = tonumber(args[1])
	local targetId = tonumber(args[2]) or (source ~= 0 and source or nil)
	if not tierIndex or not targetId then
		print('[native_proximity] Uso: /testnativeproximity <tramo 1-3> [serverId desde consola]')
		return
	end
	print(('[native_proximity] joinNativeProximityTier(%s, %s) -> %s'):format(targetId, tierIndex,
		tostring(joinNativeProximityTier(targetId, tierIndex))))
end, false)
