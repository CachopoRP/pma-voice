-- Fase 2 de Proyecto Voz -- ver VOZ.md. Capa de proximidad nativa, aislada
-- del camino real (client/init/proximity.lua sigue intacto, sobre Mumble).
--
-- Reescrito 2026-09-01 tras confirmar contra la documentacion oficial de
-- Cfx.re ("Documentacion oficial completa" en VOZ.md) que:
--   1. El modo SPATIAL calcula quien recibe segun distancia real a
--      `maxDistance`, en vivo, sin que nosotros tengamos que recalcular nada
--      -- el canal "sigue" al jugador solo, no hace falta reposicionarlo.
--   2. No existe ninguna native para cambiar el `maxDistance` de un canal ya
--      creado -- por eso el diseño original (Fase 2 v1: 3 canales fijos
--      compartidos, uno por tramo) no podia dar un radio *por hablante*, solo
--      un radio igual para todos los que estuvieran en Susurro a la vez.
--   3. El modo TEMPORARY (3) hereda todo el comportamiento de SPATIAL y se
--      autoborra solo cuando se vacia -- resuelve la fuga de canales del
--      diseño "un canal por jugador" sin necesitar limpieza manual aparte de
--      la que ya hacemos en desconexion (ver mas abajo).
--
-- Diseño v2 ("burbuja por jugador"): cada jugador activo en proximidad nativa
-- tiene su PROPIO canal TEMPORARY, cuyo `maxDistance` es el radio de SU tramo
-- actual (Susurro/Normal/Grito) -- esto es fiel al comportamiento real de
-- Mumble que sustituye (`MumbleSetTalkerProximity` es el radio del que
-- HABLA, no del que escucha). Todos los demas jugadores activos son
-- miembros de esa burbuja; el engine decide solo, en vivo, quien esta lo
-- bastante cerca para recibir audio de verdad. Al ciclar de tramo (GRAVE) no
-- hay forma de cambiar el radio del canal existente, asi que se borra y se
-- crea uno nuevo con el radio correcto, repoblado con los mismos miembros --
-- esto pasa solo al cambiar de tramo (evento), no en un bucle por posicion.

local playerBubbleChannel = {} -- [source] = channelId (burbuja propia, radio = su tramo actual)
local playerTierIndex = {}     -- [source] = indice en Cfg.voiceModes de su tramo actual
local activePlayers = {}       -- [source] = true, jugadores con proximidad nativa activa ahora mismo

--- (Re)crea la burbuja de `source` con el radio del tramo `tierIndex`, la
--- rellena con todos los demas jugadores activos (para que reciban audio de
--- `source` si el engine decide que estan dentro del radio) y borra la
--- burbuja anterior si existia.
---@param source number
---@param tierIndex number
---@return boolean
local function rebuildBubble(source, tierIndex)
	local tierData = Cfg.voiceModes[tierIndex]
	if not tierData then
		logger.warn('[native_proximity] Tramo invalido %s para %s', tierIndex, source)
		return false
	end

	local newChannel = createNativeChannel(NATIVE_VOICE_MODE.TEMPORARY, tierData[1] + 0.0)
	if not newChannel then
		logger.error('[native_proximity] No se pudo crear burbuja para %s (tramo %s, %s)', source, tierIndex,
			tierData[2])
		return false
	end

	addPlayerToNativeChannel(newChannel, source)
	for otherSource in pairs(activePlayers) do
		if otherSource ~= source then
			addPlayerToNativeChannel(newChannel, otherSource)
		end
	end

	local oldChannel = playerBubbleChannel[source]
	if oldChannel then
		deleteNativeChannel(oldChannel)
	end

	playerBubbleChannel[source] = newChannel
	playerTierIndex[source] = tierIndex
	logger.info('[native_proximity] Burbuja de %s -> tramo %s (%s, %sm) -> canal nativo %s', source, tierIndex,
		tierData[2], tierData[1], newChannel)
	return true
end

--- Activa/actualiza la proximidad nativa de un jugador en el tramo dado. Si
--- es la primera vez que se activa para este jugador en la sesion, tambien
--- lo mete en la burbuja de todos los demas jugadores ya activos (para que
--- ellos empiecen a poder oirle a el tambien, no solo el a ellos).
---@param source number
---@param tierIndex number indice en Cfg.voiceModes (1=Susurro, 2=Normal, 3=Grito por defecto)
---@return boolean
function joinNativeProximityTier(source, tierIndex)
	local wasActive = activePlayers[source]
	activePlayers[source] = true

	if not wasActive then
		for otherSource, channelId in pairs(playerBubbleChannel) do
			if otherSource ~= source then
				addPlayerToNativeChannel(channelId, source)
			end
		end
	end

	return rebuildBubble(source, tierIndex)
end

exports('joinNativeProximityTier', joinNativeProximityTier)

--- Saca a un jugador de la proximidad nativa por completo (desconexion, o al
--- volver al camino de Mumble): borra su burbuja propia y lo quita de las
--- burbujas ajenas en las que estuviera.
---@param source number
function leaveNativeProximity(source)
	activePlayers[source] = nil
	playerTierIndex[source] = nil

	local ownChannel = playerBubbleChannel[source]
	if ownChannel then
		deleteNativeChannel(ownChannel)
		playerBubbleChannel[source] = nil
	end

	for otherSource, channelId in pairs(playerBubbleChannel) do
		if otherSource ~= source then
			removePlayerFromNativeChannel(channelId, source)
		end
	end
end

exports('leaveNativeProximity', leaveNativeProximity)

-- Nota: la documentacion oficial confirma que el engine ya saca solo a un
-- jugador desconectado de todos los canales en los que estuviera ("When a
-- player disconnects, they are automatically removed from all channels they
-- were in") -- este handler sigue haciendo falta igualmente para: borrar SU
-- burbuja propia (que si no, quedaria huerfana y no vacia, TEMPORARY no la
-- autoborraria) y limpiar nuestras tablas locales (`activePlayers` etc.).
AddEventHandler('playerDropped', function()
	local source = source
	leaveNativeProximity(source)
end)

-- Disparados por el cliente (client/events.lua, client/commands.lua,
-- client/init/proximity.lua) cuando voice_useNativeProximity esta activa --
-- ver Fase 2 en VOZ.md.
RegisterNetEvent('pma-voice:server:joinNativeProximityTier', function(tierIndex)
	local source = source
	joinNativeProximityTier(source, tierIndex)
end)

RegisterNetEvent('pma-voice:server:leaveNativeProximity', function()
	local source = source
	leaveNativeProximity(source)
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
