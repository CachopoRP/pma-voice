-- Fase 1 de Proyecto Voz -- ver VOZ.md. Capa fina sobre las natives nativas
-- de canal de Enhanced (CreateVoiceChannel/AddPlayerToVoiceChannel/...),
-- confirmadas funcionando en vivo el 2026-09-01 y documentadas oficialmente
-- por Cfx.re (guia en prosa de voz, no el indice `natives.json` clasico --
-- ver VOZ.md "Documentacion oficial completa").
--
-- Usado por server/module/native_proximity.lua (Fase 2), server/module/
-- radio.lua (Fase 4, detras de voice_useNativeRadio) y server/module/
-- phone.lua (Fase 3, detras de voice_useNativeCalls) -- todas isladas
-- detras de convars apagadas por defecto, cero impacto en el camino Mumble
-- mientras esten en 0.

nativeChannels = nativeChannels or {} -- [channelId] = { mode, maxDistance, members = {[source]=true} }
adminMutedPlayers = adminMutedPlayers or {} -- [source] = true -- ver setPlayerAdminMuted

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
	-- Mute de admin (ver setPlayerAdminMuted mas abajo) -- si a este jugador
	-- se le silencio de forma persistente, hay que re-aplicar el mute cada
	-- vez que entra en un canal nuevo (cambia de tramo de proximidad, entra
	-- en un radio, recibe una llamada...), si no el mute se "olvidaria" al
	-- primer cambio de canal.
	if adminMutedPlayers[source] then
		pcall(SetPlayerMutedInVoiceChannel, channelId, source, true)
	end
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

-- Mute de admin (2026-09-05) -- decision de Oscar: moderacion completa de
-- verdad, no personal (el jugador no puede hablar en NINGUN canal, para
-- NADIE, no solo "yo no le oigo"). No existe una native de mute global
-- independiente de canal en la API nueva (a diferencia de la vieja
-- MumbleSetPlayerMuted) -- se simula silenciando al jugador en TODOS los
-- canales nativos en los que este ahora mismo, y reforzando el mute cada vez
-- que entra en uno nuevo (ver el hook en addPlayerToNativeChannel arriba).
---@param source number
---@param muted boolean
function setPlayerAdminMuted(source, muted)
	adminMutedPlayers[source] = muted or nil
	for _, channelId in ipairs(getNativeChannelsForPlayer(source)) do
		setPlayerMutedInNativeChannel(channelId, source, muted)
	end
	logger.info('[native_channels] %s -> mute de admin: %s', source, muted)
end

exports('setPlayerAdminMuted', setPlayerAdminMuted)

---@param source number
---@return boolean
function isPlayerAdminMuted(source)
	return adminMutedPlayers[source] == true
end

exports('isPlayerAdminMuted', isPlayerAdminMuted)

-- Modo espectador (2026-09-05) -- equivalente nativo de
-- MumbleAddVoiceChannelListen, documentado en VOZ.md: unir al oyente a los
-- canales del objetivo pero SIEMPRE silenciado (oye, no puede hablar en
-- ellos). A diferencia de un miembro normal, esto no representa una
-- transmision propia del oyente -- solo escucha lo que ya se transmite ahi.
-- MISMA limitacion de seguridad que ya tenia el MumbleAddVoiceChannelListen
-- original: quien dispara esto es el CLIENTE (ver client/init/proximity.lua),
-- sin validacion server-side de que de verdad este en modo espectador -- no
-- es una regresion nueva, el native viejo tenia exactamente el mismo hueco.
---@param listenerSource number
---@param targetSource number
function addNativeChannelListener(listenerSource, targetSource)
	for _, channelId in ipairs(getNativeChannelsForPlayer(targetSource)) do
		if addPlayerToNativeChannel(channelId, listenerSource) then
			setPlayerMutedInNativeChannel(channelId, listenerSource, true)
		end
	end
end

exports('addNativeChannelListener', addNativeChannelListener)

---@param listenerSource number
---@param targetSource number
function removeNativeChannelListener(listenerSource, targetSource)
	for _, channelId in ipairs(getNativeChannelsForPlayer(targetSource)) do
		removePlayerFromNativeChannel(channelId, listenerSource)
	end
end

exports('removeNativeChannelListener', removeNativeChannelListener)

RegisterNetEvent('pma-voice:server:addNativeChannelListener', function(targetSource)
	addNativeChannelListener(source, targetSource)
end)

RegisterNetEvent('pma-voice:server:removeNativeChannelListener', function(targetSource)
	removeNativeChannelListener(source, targetSource)
end)

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
--
-- Mitigacion 2026-09-01: si se reinicia el PROCESO ENTERO del FXServer (no
-- solo el recurso), el contador interno de la native se resetea solo -- es
-- memoria nueva. El riesgo real es solo `restart pma-voice` sin reiniciar el
-- server entero detras. Para ese caso, purgamos aqui todos los canales que
-- este recurso haya creado (burbujas de proximidad, radios, llamadas -- lo
-- que sea, todo pasa por `createNativeChannel` y queda en `nativeChannels`)
-- justo antes de pararse. `DeleteVoiceChannel` funciona con el canal vacio o
-- no (confirmado en la doc oficial), no hace falta vaciarlo antes.
AddEventHandler('onResourceStop', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then return end
	local purged = 0
	for channelId in pairs(nativeChannels) do
		local ok = pcall(DeleteVoiceChannel, channelId)
		if ok then purged = purged + 1 end
	end
	if purged > 0 then
		logger.info('[native_channels] onResourceStop: %s canal(es) nativo(s) purgado(s) antes de reiniciar.', purged)
	end
end)
