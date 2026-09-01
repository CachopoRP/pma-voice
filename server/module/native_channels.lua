-- Fase 1 de Proyecto Voz -- ver VOZ.md. Capa fina sobre las natives nativas
-- de canal de Enhanced (CreateVoiceChannel/AddPlayerToVoiceChannel/...),
-- confirmadas funcionando en vivo el 2026-09-01 (no aparecen en el indice
-- oficial de natives, pero responden de verdad -- ver VOZ.md Fase 0).
--
-- Aislado a proposito: este archivo NO sustituye nada todavia. Proximidad,
-- radios y llamadas siguen sobre las natives de Mumble (server/main.lua,
-- server/module/radio.lua, server/module/phone.lua) hasta que cada fase
-- del plan los migre uno a uno. Anadir este modulo no cambia el
-- comportamiento actual del recurso en absoluto.

nativeChannels = nativeChannels or {} -- [channelId] = { mode, maxDistance, members = {[source]=true} }

--- Modos de CreateVoiceChannel (docs.fivem.net/docs/scripting-manual/voice/).
NATIVE_VOICE_MODE = {
	NON_SPATIAL = 0, -- radios, canales 2D sin caida por distancia
	SPATIAL = 1,     -- proximidad 3D, la native se encarga de la caida por distancia
	CUSTOM = 2,       -- streaming personalizado, no lo usamos en este proyecto
	TEMPORARY = 3,    -- se autoborra cuando se queda vacio
}

--- Crea un canal nativo nuevo y lo registra localmente.
---@param mode number uno de NATIVE_VOICE_MODE
---@param maxDistance number? radio en metros -- solo aplica a SPATIAL, opcional en el resto
---@return number|nil channelId nil si la native fallo o devolvio el limite (65535 = sin canales libres)
function createNativeChannel(mode, maxDistance)
	local ok, channelId = pcall(CreateVoiceChannel, mode, maxDistance or 0.0)
	if not ok or channelId == nil or channelId == 65535 then
		logger.error('[native_channels] CreateVoiceChannel fallo (mode=%s, maxDistance=%s): %s', mode, maxDistance,
			tostring(channelId))
		return nil
	end
	nativeChannels[channelId] = { mode = mode, maxDistance = maxDistance, members = {} }
	logger.verbose('[native_channels] Canal %s creado (mode=%s, maxDistance=%s)', channelId, mode, maxDistance)
	return channelId
end

exports('createNativeChannel', createNativeChannel)

--- Anade un jugador a un canal nativo ya creado con createNativeChannel.
---@param channelId number
---@param source number
---@return boolean
function addPlayerToNativeChannel(channelId, source)
	if not nativeChannels[channelId] then
		logger.warn('[native_channels] addPlayerToNativeChannel: el canal %s no existe', channelId)
		return false
	end
	local ok, result = pcall(AddPlayerToVoiceChannel, channelId, source)
	if not ok or not result then
		logger.error('[native_channels] AddPlayerToVoiceChannel fallo (canal=%s, source=%s)', channelId, source)
		return false
	end
	nativeChannels[channelId].members[source] = true
	return true
end

exports('addPlayerToNativeChannel', addPlayerToNativeChannel)

--- Quita a un jugador de un canal nativo. No lo borra si se queda vacio
--- (para eso esta el modo TEMPORARY o deleteNativeChannel explicito).
---@param channelId number
---@param source number
---@return boolean
function removePlayerFromNativeChannel(channelId, source)
	if not nativeChannels[channelId] then return false end
	local ok = pcall(RemovePlayerFromVoiceChannel, channelId, source)
	nativeChannels[channelId].members[source] = nil
	return ok
end

exports('removePlayerFromNativeChannel', removePlayerFromNativeChannel)

--- Borra un canal nativo entero (expulsa a todos los miembros implicitamente).
---@param channelId number
---@return boolean
function deleteNativeChannel(channelId)
	if not nativeChannels[channelId] then return false end
	local ok = pcall(DeleteVoiceChannel, channelId)
	nativeChannels[channelId] = nil
	return ok
end

exports('deleteNativeChannel', deleteNativeChannel)

---@param channelId number
---@param source number
---@param muted boolean oye pero no puede hablar
function setPlayerMutedInNativeChannel(channelId, source, muted)
	if not nativeChannels[channelId] then return false end
	return (pcall(SetPlayerMutedInVoiceChannel, channelId, source, muted))
end

exports('setPlayerMutedInNativeChannel', setPlayerMutedInNativeChannel)

---@param channelId number
---@param source number
---@param deaf boolean puede hablar pero no oye
function setPlayerDeafInNativeChannel(channelId, source, deaf)
	if not nativeChannels[channelId] then return false end
	return (pcall(SetPlayerDeafInVoiceChannel, channelId, source, deaf))
end

exports('setPlayerDeafInNativeChannel', setPlayerDeafInNativeChannel)

--- En que canales nativos (de los creados por este modulo) esta un jugador.
--- Para limpiar al desconectar sin tener que recordar el canal desde fuera.
---@param source number
---@return number[]
function getNativeChannelsForPlayer(source)
	local result = {}
	for channelId, data in pairs(nativeChannels) do
		if data.members[source] then
			result[#result + 1] = channelId
		end
	end
	return result
end

exports('getNativeChannelsForPlayer', getNativeChannelsForPlayer)

-- Limpieza al desconectar -- independiente del cleanup de radio/llamada de
-- Mumble que sigue en server/main.lua sin tocar en esta fase.
AddEventHandler('playerDropped', function()
	local source = source
	for _, channelId in ipairs(getNativeChannelsForPlayer(source)) do
		removePlayerFromNativeChannel(channelId, source)
	end
end)

-- LIMITACION CONOCIDA: no hay ninguna native para listar los canales
-- nativos que ya existen en el server. Si este recurso se reinicia, los
-- canales creados en la sesion anterior quedan huerfanos (CreateVoiceChannel
-- lleva su propio contador interno que nosotros no controlamos ni podemos
-- resetear). Por eso las fases siguientes deben usar POCOS canales fijos y
-- de larga duracion (p.ej. un unico canal de proximidad para todo el
-- server, uno por numero de radio) en vez de crear uno nuevo por jugador o
-- por uso puntual -- asi el problema de fugas al reiniciar queda acotado a
-- un puñado de canales, no a miles.

-- Prueba rapida del modulo (no de las natives en crudo, eso ya se confirmo
-- en la Fase 0) -- borrar este comando cuando la Fase 1 se de por buena.
-- Uso: /testnativechannels en el chat, o /testnativechannels <serverId>
-- desde la consola.
RegisterCommand('testnativechannels', function(source, args)
	local targetId = tonumber(args[1]) or (source ~= 0 and source or nil)
	if not targetId then
		print('[native_channels] Ejecuta desde el chat (como jugador) o pasa un serverId.')
		return
	end
	print('[native_channels] === Prueba del modulo (no de las natives en crudo) ===')
	local channelId = createNativeChannel(NATIVE_VOICE_MODE.NON_SPATIAL)
	print(('[native_channels] createNativeChannel -> %s'):format(tostring(channelId)))
	if not channelId then return end
	print(('[native_channels] addPlayerToNativeChannel -> %s'):format(tostring(addPlayerToNativeChannel(channelId, targetId))))
	print(('[native_channels] getNativeChannelsForPlayer -> %s canal(es)'):format(#getNativeChannelsForPlayer(targetId)))
	print(('[native_channels] setPlayerMutedInNativeChannel -> %s'):format(tostring(setPlayerMutedInNativeChannel(channelId, targetId, false))))
	print(('[native_channels] removePlayerFromNativeChannel -> %s'):format(tostring(removePlayerFromNativeChannel(channelId, targetId))))
	print(('[native_channels] deleteNativeChannel -> %s'):format(tostring(deleteNativeChannel(channelId))))
	print('[native_channels] === Prueba terminada ===')
end, false)
