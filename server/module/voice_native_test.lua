-- Arnes de pruebas temporal para las natives de canal de voz de Enhanced --
-- ver pma-voice/CLAUDE_LOG.md. Objetivo: aislar escenarios concretos de
-- CreateVoiceChannel/AddPlayerToVoiceChannel fuera de toda la logica de
-- pma-voice (proximidad/radio/llamadas), para saber a que se debe el "conecta
-- pero no se oyen" de las llamadas nativas sin tener que interpretar el
-- comportamiento completo del recurso. Todos los comandos se pueden lanzar
-- desde el chat (como jugador) o la consola del server (pasando el/los
-- serverId de destino a mano). Reutiliza createNativeChannel/
-- addPlayerToNativeChannel/etc. de native_channels.lua (Fase 1), ya cargado
-- antes en el orden de server_scripts (server/**/*.lua, alfabetico:
-- native_channels.lua < voice_native_test.lua).
--
-- BORRAR ESTE ARCHIVO cuando se termine de diagnosticar -- es solo un
-- arnes de pruebas, no parte del recurso real.

local testChannels = {} -- [label] = channelId, para poder limpiar todo con /vtest_cleanup

local function resolveTargets(source, args)
	-- Si se llama desde el chat (source ~= 0), el propio jugador es uno de
	-- los dos objetivos por defecto; el resto de args son los otros.
	local targets = {}
	for _, a in ipairs(args) do
		local id = tonumber(a)
		if id then targets[#targets + 1] = id end
	end
	if source ~= 0 and not (function()
			for _, t in ipairs(targets) do
				if t == source then return true end
			end
		end)() then
		table.insert(targets, 1, source)
	end
	return targets
end

RegisterCommand('vtest_whoami', function(source)
	print(('[vtest] Tu serverId es %s'):format(source))
end, false)

--- Escenario A: UN solo canal NON_SPATIAL con los targets dados, sin ningun
--- otro canal de por medio. Replica justo lo que hace pma-voice para una
--- llamada (createNativeChannel(NATIVE_VOICE_MODE.NON_SPATIAL, 0.0) +
--- addPlayerToNativeChannel para cada uno), pero sin nada mas alrededor --
--- si esto tampoco se oye, el problema es del modo NON_SPATIAL en si, no de
--- pma-voice ni de tener otros canales a la vez.
RegisterCommand('vtest_a_nonspatial_solo', function(source, args)
	local targets = resolveTargets(source, args)
	if #targets < 2 then
		print('[vtest] Uso: /vtest_a_nonspatial_solo <serverId2> [mas ids] (o solo tu id si lo lanzas desde consola con 2+)')
		return
	end

	if testChannels.A then deleteNativeChannel(testChannels.A) end

	local channelId = createNativeChannel(NATIVE_VOICE_MODE.NON_SPATIAL, 0.0)
	if not channelId then
		print('[vtest][A] createNativeChannel fallo')
		return
	end
	testChannels.A = channelId

	for _, t in ipairs(targets) do
		local ok = addPlayerToNativeChannel(channelId, t)
		print(('[vtest][A] addPlayerToNativeChannel(canal=%s, target=%s) -> %s'):format(channelId, t, tostring(ok)))
	end
	print(('[vtest][A] Canal %s listo con %s miembros. Hablad ahora y decid si os oís.'):format(channelId, #targets))
end, false)

--- Escenario B: mismo canal NON_SPATIAL que A, PERO ademas cada target tiene
--- su propio canal TEMPORARY (modo 3, como la burbuja de proximidad real)
--- con el resto de targets metidos dentro -- replica el caso real reportado
--- (llamada + proximidad nativa a la vez). Si A funciona y B no, confirma
--- que el problema es estar en dos canales de modos distintos a la vez.
RegisterCommand('vtest_b_nonspatial_mas_burbuja', function(source, args)
	local targets = resolveTargets(source, args)
	if #targets < 2 then
		print('[vtest] Uso: /vtest_b_nonspatial_mas_burbuja <serverId2> [mas ids]')
		return
	end

	if testChannels.B_call then deleteNativeChannel(testChannels.B_call) end
	for _, t in ipairs(targets) do
		if testChannels['B_bubble_' .. t] then deleteNativeChannel(testChannels['B_bubble_' .. t]) end
	end

	local callChannel = createNativeChannel(NATIVE_VOICE_MODE.NON_SPATIAL, 0.0)
	if not callChannel then
		print('[vtest][B] createNativeChannel (llamada) fallo')
		return
	end
	testChannels.B_call = callChannel
	for _, t in ipairs(targets) do
		addPlayerToNativeChannel(callChannel, t)
	end
	print(('[vtest][B] Canal de llamada %s creado con %s miembros'):format(callChannel, #targets))

	for _, owner in ipairs(targets) do
		local bubbleChannel = createNativeChannel(NATIVE_VOICE_MODE.TEMPORARY, 50.0)
		if bubbleChannel then
			testChannels['B_bubble_' .. owner] = bubbleChannel
			addPlayerToNativeChannel(bubbleChannel, owner)
			for _, other in ipairs(targets) do
				if other ~= owner then
					addPlayerToNativeChannel(bubbleChannel, other)
				end
			end
			print(('[vtest][B] Burbuja propia de %s -> canal %s (50m, TEMPORARY)'):format(owner, bubbleChannel))
		end
	end
	print('[vtest][B] Listo -- cada uno esta en su propia burbuja TEMPORARY Y en el canal de llamada NON_SPATIAL a la vez. Hablad y decid si os oís.')
end, false)

--- Escenario C: solo el canal SPATIAL/TEMPORARY (sin llamada), para
--- confirmar que ESTE modo si se oye solo, como ya sabiamos de la
--- proximidad real -- sirve de control/referencia.
RegisterCommand('vtest_c_spatial_solo', function(source, args)
	local targets = resolveTargets(source, args)
	if #targets < 2 then
		print('[vtest] Uso: /vtest_c_spatial_solo <serverId2> [mas ids]')
		return
	end

	if testChannels.C then deleteNativeChannel(testChannels.C) end
	local channelId = createNativeChannel(NATIVE_VOICE_MODE.TEMPORARY, 50.0)
	if not channelId then
		print('[vtest][C] createNativeChannel fallo')
		return
	end
	testChannels.C = channelId
	for _, t in ipairs(targets) do
		local ok = addPlayerToNativeChannel(channelId, t)
		print(('[vtest][C] addPlayerToNativeChannel(canal=%s, target=%s) -> %s'):format(channelId, t, tostring(ok)))
	end
	print(('[vtest][C] Canal %s (TEMPORARY, 50m) listo. Control/referencia -- ya sabiamos que esto se oye.'):format(channelId))
end, false)

RegisterCommand('vtest_mute', function(source, args)
	local channelId = tonumber(args[1])
	local target = tonumber(args[2])
	local state = args[3] == 'true'
	if not channelId or not target then
		print('[vtest] Uso: /vtest_mute <channelId> <serverId> <true|false>')
		return
	end
	print(('[vtest] setPlayerMutedInNativeChannel(%s, %s, %s) -> %s'):format(channelId, target, state,
		tostring(setPlayerMutedInNativeChannel(channelId, target, state))))
end, false)

RegisterCommand('vtest_state', function()
	print('[vtest] Canales de prueba activos:')
	for label, channelId in pairs(testChannels) do
		print(('  %s -> canal %s (mode=%s, maxDistance=%s, miembros=%s)'):format(
			label, channelId, nativeChannels[channelId] and nativeChannels[channelId].mode,
			nativeChannels[channelId] and nativeChannels[channelId].maxDistance,
			nativeChannels[channelId] and json.encode(nativeChannels[channelId].members)))
	end
end, false)

RegisterCommand('vtest_cleanup', function()
	local n = 0
	for label, channelId in pairs(testChannels) do
		if deleteNativeChannel(channelId) then n = n + 1 end
		testChannels[label] = nil
	end
	print(('[vtest] %s canal(es) de prueba borrado(s)'):format(n))
end, false)
