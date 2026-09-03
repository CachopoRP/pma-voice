# CLAUDE_LOG — pma-voice

## 2026-09-03 (4) — Diagnostico real: llamadas no conectaban audio porque `voice_useNativeCalls` seguia en 0 -- CONFIRMADO en vivo · Claude

**Reportado por Oscar in-game, tras una sesion larga de descarte:** al aceptar una llamada, las
pantallas se quedaban bien pero **no se oian entre los dos jugadores**. El sintoma sobrevivio a
varias comprobaciones intermedias que descartaron otras causas:
- El aviso "Mumble native functions are deprecated" en consola -- investigado, es ruido esperado
  del nucleo de `pma-voice` (natives Mumble sin fecha de retirada anunciada), no relacionado.
- `Player 2 is not connected.` -- confirmado que era un error del propio Oscar probando el arnes
  de pruebas (`/vtest_b_nonspatial_mas_burbuja`) con serverIds equivocados, no un bug real: con
  los ids correctos el comando conecta perfecto.
- Reinicio de `pma-voice`/`qbx_phone` tras los deploys de hoy -- hecho, confirmado por Oscar, no
  era esto (aunque SI era un problema real y separado, ver mas abajo).
- Bug real de `EndCall` (ver entrada 13 de `qbx_phone/CLAUDE_LOG.md`, "las llamadas vuelven a no
  funcionar" con el mismo par de telefonos) -- corregido y desplegado, pero no explicaba que la
  PRIMERA llamada entre dos personas tampoco conectara audio.

**Causa real:** toda la logica de conexion de canales de una llamada real esta condicionada a la
convar `voice_useNativeCalls` (`0` por defecto, apagada) -- y esa convar **nunca se promovio a
`1`** en el `server.cfg` real, se quedo en el valor por defecto documentado en `VOZ.md` para
produccion. Con la convar en `0`:
- Servidor (`server/module/phone.lua:260`, `addPlayerToCall`): el bloque entero que crea/usa el
  canal nativo (`NON_SPATIAL`) para la llamada se salta -- **no se crea ningun canal nativo**.
- Cliente (`client/module/phone.lua:26`): en vez de confiar en el canal nativo, cae al camino
  viejo -- `toggleVoice(plySource, true, 'call')`, que enruta audio con las natives de Mumble
  deprecadas.

Y ese camino de Mumble puro es **el que ya se documento roto** el 2026-08-31/09-01 (ver entradas
de esas fechas mas abajo): bajo `voice_internal` (que usa Enhanced), la capa de compatibilidad
degrada `MUMBLE_SET_VOICE_TARGET`/`MUMBLE_CLEAR_VOICE_TARGET` a "como si solo hubiera un voice
target" -- exactamente la razon original por la que se construyo todo el sistema de canales
nativos (Proyecto Voz, Fases 0-4). Osea: **la llamada real seguia cayendo en el mismo camino roto
que motivo todo el proyecto**, porque el interruptor que activa el camino nuevo nunca se encendio
en el `server.cfg`.

**Por que el arnes de pruebas (`/vtest_*`, `voice_native_test.lua`) SI conectaba perfecto:** sus
comandos llaman a `createNativeChannel`/`addPlayerToNativeChannel` directamente, sin comprobar
ninguna convar -- por eso confirmaba que las natives de canal en si funcionan bien, pero no podia
detectar que el camino REAL (`addPlayerToCall`/`toggleVoice`) seguia condicionado a un interruptor
apagado. Ambas cosas pueden ser ciertas a la vez: "las natives funcionan" (vtest) y "la llamada
real no las usa" (convar apagada) -- por eso hizo falta revisar la logica de conexion completa en
vez de fiarse solo del resultado del arnes.

**Fix:** ninguno de codigo -- era un `setr voice_useNativeCalls 1` que faltaba en el `server.cfg`
del entorno de pruebas (`crp-experimental`, nunca en produccion todavia) + `restart pma-voice`.
**Oscar lo puso y confirmo en vivo: llamada real con audio funcionando.** Fases 0-3 de Proyecto Voz
(canales/proximidad/llamadas nativas) dadas por buenas en `crp-experimental` para llamadas; Fase 4
(radios, `voice_useNativeRadio`) sigue sin promover/probar.

**Nota para la proxima vez:** cuando "algo no conecta" pero el arnes de pruebas SI funciona, revisar
primero que convars/interruptores de fase estan realmente activos en el `server.cfg` real (no en el
repo, la maquina manda -- ver `rpbase/conclaveclaude.md`) antes de asumir que el bug esta en la
logica -- el codigo puede estar perfectamente bien y seguir sin conectar si el interruptor que lo
activa nunca se encendio.

## 2026-09-03 (3) — Altavoz real: gente cerca oye la llamada, silenciada · Claude

**Contexto:** al revisar el mockup de Teléfono, dije que "Altavoz" era solo cosmético (audio 100%
cliente, sin equivalente real). Oscar preguntó por qué no se podía hacer de verdad -- repensándolo,
sí hay un equivalente real: que la gente cerca de quien activa el altavoz **oiga** la llamada
(como sostener el móvil en alto delante de otros), sin poder **hablar** dentro de ella.

**Por qué no vale un canal SPATIAL/TEMPORARY para esto:** su caída de audio por distancia la
calcula el motor sobre la posición real de CADA miembro del canal -- el interlocutor remoto no
está físicamente cerca de quien tiene el altavoz (podría estar al otro lado del mapa), así que
meterlo en un canal SPATIAL lo silenciaría también para la persona que SÍ está en la llamada.

**Hecho:** `setCallSpeaker(source, callChannel, enabled)` en `server/module/phone.lua`, exportado.
Con el altavoz activo, un hilo (`CreateThread`, 1s de intervalo mientras haya algún altavoz
activo) mide la distancia real entre quien tiene el altavoz y el resto de jugadores online
(`SPEAKER_RADIUS = 6.0`), y añade/quita a los que entran o salen del radio al mismo canal
NON_SPATIAL de la llamada -- silenciándolos con `setPlayerMutedInNativeChannel` en cuanto entran
(oyen, no pueden hablar dentro). Limpieza automática si la llamada termina o si quien tenía el
altavoz se desconecta (`GetPlayerPed` inválido).

**Sin confirmar en vivo todavía.**

## 2026-09-03 (2) — Fase 2 de Teléfono: export `muteInCall` para silenciar · Claude

**Pedido:** siguiendo el plan de fusión Teléfono+Contactos (ver `qbx_phone/CLAUDE_LOG.md`), Fase 2
añade Silenciar/Altavoz a la pantalla de llamada. Altavoz es enrutado de audio 100% cliente, no
toca `pma-voice`. Silenciar sí necesita algo nuevo aquí.

**Hecho:** `muteInCall(source, callChannel, muted)` en `server/module/phone.lua`, exportado. Hacía
falta porque `qbx_phone` solo conoce su propio `call_id` (`callChannel`), no el `channelId` nativo
interno (`nativeCallChannels` es local al módulo) -- resuelve uno a partir del otro y llama a
`setPlayerMutedInNativeChannel` (ya existía, de la Fase 1 de canales nativos). No-op si
`voice_useNativeCalls` está apagado o la llamada no tiene canal nativo todavía -- el mute por
Mumble puro no está cableado, coherente con que todo lo demás de llamadas ya vive detrás de esa
convar.

**Sin confirmar en vivo todavía.**

## 2026-09-03 — Fix: crash real en vivo, `removeCallCheck` indexaba con nil · Claude

**Reportado:** llamada probada en vivo con el fix (9) ya desplegado -- **funcionó, audio
perfecto** (confirmado por el log: canal nativo 4, ambos `miembros ahora=[true,true]`, y
`qbx_phone added a check to call 130135832` mostrando el ACL nuevo en marcha). Al colgar (botón NUI
+ F1), crash real: `@pma-voice/server/module/phone.lua:63: table index is nil`, con
`SCRIPT ERROR` en `qbx_phone` porque el export fallido rompió su callback `EndCall`.

**Causa:** `removeCallCheck` (añadido en el fix (9) de ayer) es el único de los tres exports nuevos
que no comprobaba el tipo del parámetro antes de indexar -- `addCallCheck` sí lo hacía.
`qbx_phone/client/feature/notification.lua:185-186` (la ruta de "llamada sin respuesta", cuando
nadie contesta y el timeout cuelga solo) llama a `EndCall` con `{ to_source = ... }`, **sin
`call_id`** -- ese `body.call_id` nil llegaba tal cual hasta `callChecks[callChannel] = nil` y
Lua no permite indexar una tabla con `nil`.

**Fix:** `removeCallCheck` ahora es no-op si `callChannel` no es un número (es limpieza defensiva,
no un fallo de integración -- no tiene sentido que reviente el flujo de colgar). También guardada
la llamada en `qbx_phone/server/feature/calls.lua:EndCall` (`and body.call_id`) para no gastar el
round-trip cuando no hay nada que limpiar. Aplicado en `crp-experimental` y `cachoporp` (mismo
export nuevo en ambas ramas desde el fix (9)).

**Sin confirmar en vivo todavía** -- pero el resto del fix de llamadas (audio + ACL) ya está
confirmado funcionando.

## 2026-09-02 (9) — Seguridad: `pma-voice:setPlayerCall` aceptaba cualquier call_id sin dueño · Claude

**Pedido:** Oscar, tras revisar que la lógica del sistema de llamadas fuera server-sided, pidió
valorar si `qbx_phone` dejaba algún residuo de Mumble -- no había ninguno, pero apareció un fallo
de autorización real al revisar el camino completo.

**Causa:** `RegisterNetEvent('pma-voice:setPlayerCall', callChannel)` acepta el `callChannel`
directamente del cliente sin comprobar que le pertenezca -- a diferencia de las radios
(`canJoinChannel`/`addChannelCheck` en `radio.lua`), las llamadas no tenían ningún check de
pertenencia. Agravado por `qbx_phone/client/feature/calls.lua:GenerateCallId`: el `call_id` NO es
aleatorio, es `math.ceil((digitos_telefono_A + digitos_telefono_B) / 100)` -- determinista a partir
de los dos números, calculable sin fuerza bruta si se conocen (o se prueban) los dos números. Con
canales nativos reales por debajo, unirse a un `callChannel` ajeno significa audio real, no solo un
flag en una tabla.

**Fix:** `callChecks` + `canJoinCall`/`addCallCheck`/`removeCallCheck` en `server/module/phone.lua`,
mismo patrón que `radioChecks`/`canJoinChannel`/`addChannelCheck` de `radio.lua` (opt-in: si nadie
registra un check para un `callChannel`, se permite -- compatibilidad con otros consumidores).
`addPlayerToCall` ahora rechaza si `canJoinCall` devuelve false; `setPlayerCall` usa el resultado
real (`wasAdded`) en vez de asumir que siempre entra, igual que ya hacía `setPlayerRadio`. El check
se limpia solo cuando la llamada se vacía (en `removePlayerFromCall`), y también expuesto
`removeCallCheck` para limpieza defensiva desde fuera. `qbx_phone/server/feature/calls.lua`:
`AcceptCall` registra el check con los dos `source` reales (el único momento en que el servidor
conoce con certeza quién es cada uno); `EndCall` lo limpia también de forma defensiva.

**Aplicado en ambas ramas de `pma-voice`** (`crp-experimental` y `cachoporp`) porque el fallo existe
también en el camino Mumble normal de producción, no es específico de Proyecto Voz -- `qbx_phone`
solo tiene una rama (`cachoporp`) y llama al export sin comprobar su existencia primero, así que
tenía que estar disponible en ambas.

**Sin confirmar en vivo todavía.**

## 2026-09-02 (8) — Quinto punto de fuga: `assignedChannel` (canal base legado) sin guardar, degradado a un solo voice target · Claude

**Reportado tras el fix (7):** desplegado y reiniciado, nueva llamada probada en vivo con
`voice_useNativeProximity` TAMBIÉN activo (log muestra "Burbuja de 2 -> tramo 2 -> canal nativo 3"
antes de la llamada), servidor confirma otra vez a los dos en el mismo canal nativo, pero sigue
sin oírse. Pregunta de Oscar: "¿cómo puede ser que ayer con los comandos manuales (`vtest_a`/
`vtest_b`, 100% server-side) nos oyéramos y hoy con la llamada real no?"

**Causa:** `addNearbyPlayers()` (el tick de proximidad, corre siempre, en todos los clientes)
tenía un bloque más SIN guardar por ninguna convar, ni siquiera `voice_useNativeProximity`:
`MumbleAddVoiceChannelListen`/`MumbleAddVoiceTargetChannel` sobre `LocalPlayer.state.assignedChannel`
-- el canal base de proximidad del pma-voice original (asignado una vez al conectar,
`server/main.lua:firstFreeChannel()`, nada que ver con llamadas ni burbujas nativas). `VOZ.md`
documenta con cita oficial de Cfx.re que bajo `voice_internal` estas dos natives quedan degradadas
a **un solo voice target** -- este bloque forzaba ese único target de vuelta al canal base en CADA
tick, pisando la ruta de audio real. Explica la pregunta de Oscar: los comandos manuales de ayer
nunca pasan por `client/init/proximity.lua` (son 100% consola/server), así que este bloque nunca
entraba en juego en esa prueba -- solo aparece con el flujo real de llamada/proximidad del cliente.

**Fix:** ese bloque ahora se salta cuando `voice_useNativeCalls` O `voice_useNativeProximity` están
activos (con cualquiera de los dos, el canal base legado es irrelevante).

**Sin confirmar en vivo todavía.**

## 2026-09-02 (7) — Cuarto punto de fuga: `addNearbyPlayers` enrutaba la llamada por Mumble sin guardar · Claude

**Reportado tras el fix (6):** nueva llamada probada en vivo (después de que (6) ya estaba
desplegado, commit `6cf7f69` a las 03:09 del mismo día), servidor confirma otra vez a los dos
jugadores en el mismo canal nativo (`miembros ahora=[true,true]`), pero "no nos escuchamos"
persiste.

**Causa:** los tres fixes anteriores se encontraron con `grep toggleVoice`, pero
`client/init/proximity.lua:addNearbyPlayers()` (el tick de proximidad, se ejecuta constantemente)
tiene su PROPIO bloque de enrutado de llamadas que nunca pasa por `toggleVoice` — busca el canal
Mumble del otro participante de la llamada (`MumbleGetVoiceChannelFromServerId`) y lo mete como
voice target (`MumbleAddVoiceTargetChannel`), lógica del pma-voice original (llamadas 100% Mumble).
No usa `toggleVoice` así que ningún `grep toggleVoice` lo iba a encontrar — sin guardar, corría en
cada tick con `voice_useNativeCalls` activo, pisando con natives Mumble la pertenencia al canal
nativo que el servidor ya había puesto vía `AddPlayerToVoiceChannel`.

**Fix:** ese bloque ahora se salta entero cuando `voice_useNativeCalls` está activo (mismo patrón
de guard que los otros tres puntos).

**Sin confirmar en vivo todavía** — probar llamada de nuevo tras desplegar este commit.

## 2026-09-02 (6) — Segundo (y tercer) punto de entrada de `toggleVoice` sin guardar · Claude

**Reportado tras el fix (5):** llamada probada en vivo, servidor confirma a los dos jugadores en
el mismo canal nativo (`miembros ahora=[true,true]`), pero sigue sin oírse.

**Causa:** el fix (5) solo guardó las llamadas a `toggleVoice` de `client/module/phone.lua`.
Había un segundo punto de entrada sin tocar: `handleRadioAndCallInit()` en
`client/init/main.lua`, que se dispara vía `pma-voice:syncCallData` — justo el evento que recibe
quien **inicia** la llamada, así que el fix anterior no tenía efecto real en el caso probado.
Revisado el resto del recurso (`grep toggleVoice`): `client/module/radio.lua` tiene el mismo
patrón sin guardar en `setTalkingOnRadio`/`removePlayerFromRadio` — nunca se ha probado radio
nativa en vivo todavía, pero tendría el mismo bug en cuanto se probara.

**Fix:** guardadas las tres llamadas restantes (`handleRadioAndCallInit` en `main.lua`,
`setTalkingOnRadio`/`removePlayerFromRadio` en `radio.lua`) detrás de
`voice_useNativeCalls`/`voice_useNativeRadio`, mismo patrón que ya se aplicó en `phone.lua`.

**Sin confirmar en vivo todavía.**

## 2026-09-02 (5) — Causa real encontrada con el arnés de pruebas: `toggleVoice` no es cosmético · Claude

**Probado en vivo con `voice_native_test.lua` (entrada anterior):**
- Escenario A (solo canal `NON_SPATIAL`, sin nada del cliente de `pma-voice` de por medio): "nos
  oímos perfecto" — descarta que `NON_SPATIAL` esté roto.
- Escenario B (el mismo canal + burbuja `TEMPORARY` propia de cada uno a la vez, réplica exacta
  del caso real): "nos oímos perfecto" — descarta el conflicto de estar en dos canales a la vez.

Con las dos hipótesis descartadas, la única diferencia real entre el arnés de pruebas (que
funciona) y la llamada real de `pma-voice` (que no) es que la llamada real sí llama a
`toggleVoice` (`client/init/main.lua`) — que pese a documentarse como "cosmético" en la Fase 3
original, hace `MumbleSetVolumeOverrideByServerId`/`MumbleSetSubmixForServerId`, dos natives con
prefijo Mumble, sobre un jugador cuyo audio ya no viaja por Mumble sino por el canal nativo nuevo.

**Fix:** `client/module/phone.lua` ahora se salta `toggleVoice` por completo cuando
`voice_useNativeCalls` está activo (antes solo se saltaba `addVoiceTargets`/
`MumbleClearVoiceTargetPlayers`, se asumía que `toggleVoice` no hacía falta tocarlo). Se pierde el
efecto cosmético de submix de llamada (EQ tipo teléfono) mientras el modo nativo esté activo — se
puede retomar más adelante con una alternativa que no dependa de natives Mumble, no bloqueante
para que la llamada se oiga.

**Sin confirmar en vivo todavía** — el arnés de pruebas (`voice_native_test.lua`) se deja por
ahora para poder seguir aislando si hiciera falta; borrar cuando esto se confirme resuelto.

## 2026-09-02 (4) — Arnés de pruebas aislado para las natives de canal (`voice_native_test.lua`) · Claude

**Contexto:** tras confirmar (entrada 3) que el canal `NON_SPATIAL` de una llamada sí tiene a
los dos jugadores como miembros (`miembros ahora=[true,true]`) pero siguen sin oírse, y agotar
la investigación por documentación oficial (sin encontrar ninguna native real para "2D output
positioning" que la propia doc menciona pero no nombra en ningún sitio), se pidió un arnés de
pruebas para aislar el problema de toda la lógica de `pma-voice` y probar escenarios concretos
directamente contra las natives.

**Hecho:** `server/module/voice_native_test.lua` (temporal, borrar cuando se termine de
diagnosticar), comandos:
- `/vtest_a_nonspatial_solo <serverId>` — SOLO un canal `NON_SPATIAL`, nada más. Si esto tampoco
  se oye, el problema es del modo `NON_SPATIAL` en sí.
- `/vtest_b_nonspatial_mas_burbuja <serverId>` — el mismo canal de llamada MÁS una burbuja
  `TEMPORARY` propia por jugador (réplica exacta del caso real reportado: llamada + proximidad
  nativa a la vez). Si A funciona y B no, confirma que el problema es estar en dos canales de
  modos distintos simultáneamente.
- `/vtest_c_spatial_solo <serverId>` — solo `TEMPORARY` (control/referencia, ya sabíamos que se
  oye).
- `/vtest_mute`, `/vtest_state`, `/vtest_cleanup`, `/vtest_whoami` — utilidades.

**Pendiente:** probar en vivo A, B y C con 2 jugadores y reportar cuál(es) se oyen.

## 2026-09-02 (3) — Debug en vivo: llamadas sin audio, GRAVE parece ciclar solo 2 estados · Claude

**Reportado (con `voice_useNativeProximity` y `voice_useNativeCalls` activos):**
- GRAVE parece ciclar solo entre 2 estados en vez de los 3 tramos (Susurro/Normal/Grito).
- Las llamadas conectan (se ve/vibra el teléfono) pero no hay audio entre los dos jugadores.

**Investigado sin acceso a consola en vivo:** revisada la lógica de `cycleproximity`
(`client/commands.lua`) y `addPlayerToCall`/`removePlayerFromCall` (`server/module/phone.lua`) —
correcta sobre el papel, sin bug evidente en el código que tocamos esta sesión. Revisado también
`toggleVoice` (`client/init/main.lua`, sin tocar por nosotros) — el gate por `distance` nunca
bloquea nada en la práctica porque `currentTargets` nunca se rellena (asignación ya comentada en
el propio upstream, no es cosa nuestra).

**Sin poder confirmar la causa a ciegas**, añadidos dos debugs temporales para la próxima prueba:
- `client/commands.lua`: print en cada `cycleproximity` con `mode`/`#Cfg.voiceModes` y el tramo
  resultante — para confirmar si el ciclo de verdad pasa por las 3 entradas.
- `server/module/phone.lua`: print en cada `addPlayerToNativeChannel` de una llamada (canal,
  resultado, miembros) + comando `/callvoicedebug` que vuelca `nativeCallChannels`/`callData`
  enteros — para confirmar si los dos participantes de una llamada acaban en el mismo canal
  nativo.

**Pendiente:** repetir la prueba y pegar la consola (ambos jugadores en el ciclo de proximidad +
`/callvoicedebug` durante una llamada activa).

## 2026-09-01 (2) — Sistema completo de voz nativa: proximidad (v2), radio y llamadas · Claude

**Contexto:** Oscar pegó la documentación oficial completa de Cfx.re para la nueva API de voz de
Enhanced (guardada íntegra en `VOZ.md`, sección "Documentación oficial completa"). Corrigió varias
suposiciones del proyecto: `CreateVoiceChannel` y compañía SÍ están documentadas oficialmente
(solo que en la guía en prosa, no en el índice `natives.json`); `voice_useNativeAudio` está en la
lista de convars **eliminadas** en Enhanced (vestigio muerto en `shared.lua`); el modo `TEMPORARY`
(3) hereda todo el comportamiento `SPATIAL` y se autoborra al vaciarse; la limpieza al desconectar
ya la hace el engine solo.

**Hecho, todo detrás de convars apagadas por defecto (`voice_useNativeProximity`,
`voice_useNativeRadio`, `voice_useNativeCalls`), sin tocar el camino Mumble cuando están en 0:**
- `shared.lua`: `Cfg.voiceModes` recalibrado a una sola tabla (Susurro 2.0 / Normal 6.0 / Grito
  15.0), quitada la dependencia del convar muerto. Mismo fix en el multiplicador ×3 de
  `client/init/proximity.lua:orig_addProximityCheck`.
- `server/module/native_proximity.lua` **reescrito entero** — diseño v1 (3 canales fijos
  compartidos por tramo) descartado tras confirmar en vivo que los 3 tramos sonaban igual;
  rediseñado como "burbuja por jugador" (canal `TEMPORARY` propio, radio = tramo actual, se
  recrea solo al cambiar de tramo). Ver detalle completo en `VOZ.md`, Fase 2.
- `server/module/phone.lua` + `client/module/phone.lua`: canal `NON_SPATIAL` por llamada activa
  (Fase 3). Arregla el fallo real de llamadas (voice targets de Mumble degradados a "solo uno" con
  `voice_internal`, ver entrada 2026-09-01 más abajo).
- `server/module/radio.lua` + `client/module/radio.lua`: canal `NON_SPATIAL` por frecuencia, PTT
  traducido a `SetPlayerMutedInVoiceChannel` server-side (Fase 4).
- `server/module/native_channels.lua`: `onResourceStop` que purga todos los canales creados por
  este recurso (burbujas, radios, llamadas) si se reinicia solo el recurso sin reiniciar el
  proceso entero del FXServer — mitiga la fuga de canales ya documentada ahí mismo.
- `fxmanifest.lua`: nuevas entradas `voice_useNativeRadio`/`voice_useNativeCalls` en
  `convar_category`.

**Pendiente:** nada de esto se ha probado en vivo todavía — checklist completo en `VOZ.md`,
sección "Cómo probar Fases 2-4 en vivo".

---

## 2026-08-31 — Proyecto Voz: rama experimental para voz nativa de Enhanced · Claude

**Contexto:** al pulsar la tecla de ciclar proximidad (`GRAVE`), el juego crashea con timeout —
investigado en detalle (ver hilo de conversación, resumen en `VOZ.md`). Causa más probable:
`pma-voice` corre entero sobre las natives de Mumble vía el parche de compatibilidad
`sv_mumble true`, que la propia documentación de Cfx.re marca como deprecado y no soportado de
forma robusta en Enhanced — no una vía first-class. Confirmado además que Enhanced trae un
sistema de voz nativo propio (`voice_internal` + natives `CreateVoiceChannel`,
`AddPlayerToVoiceChannel`, etc.), sin servidor aparte, pero **sin ningún recurso comunitario que
ya lo use** todavía.

**Decisión (Oscar):** en vez de seguir parcheando sobre Mumble o migrar a un sistema basado en
TeamSpeak (SaltyChat/YaCA/TokoVOIP — exigiría licencia de slots + servidor TS3 aparte, coste
recurrente real, ver `VOZ.md`), construir nuestro propio `pma-voice` sobre la API nativa de
Enhanced, replicando los exports que ya consumen otros recursos (`qbx_phone`, `src-payphone`,
`qbx_adminmenu`, `ps-mdt`) para no tener que tocarlos.

**Hecho:** rama `crp-experimental` creada desde `cachoporp` (nombre de convención, requisito de
`deploy-experimental.yml`) — se trabaja aquí sin tocar la
rama de producción hasta tener algo probado en vivo. Ver `VOZ.md` para el plan completo.

---

## 2026-08-30 (2) — Aviso "Mumble native functions are deprecated" — esperado, sin acción · Claude

**Reportado:** en consola aparece `The Mumble native functions are deprecated and will be
removed in a future update. Please use the server controlled voice channels instead.`

**Investigado:** aviso real y documentado por Cfx.re — están deprecando las natives de Mumble
(`MumbleSetVoiceChannel`, `MumbleCreateChannel`, etc., las que usa `pma-voice` por debajo) en
favor de un sistema nuevo 100% server-side (`CreateVoiceChannel`, `AddPlayerToVoiceChannel`,
etc.) que cierra un problema de seguridad real del sistema Mumble antiguo (con `sv_mumble`, un
cliente modificado podía unirse a cualquier canal ajeno y escuchar). **Sin fecha de eliminación
anunciada** (confirmado en la documentación oficial) — mismo aviso que ya dejó anotado
`rpbase/server-enhanced.cfg` el 2026-08-24 ("deprecado pero no roto"). `AvarianKnight/pma-voice`
(upstream de este fork) sigue con commits activos hasta junio 2026, sin ninguna migración a las
natives nuevas todavía.

**Sin acción por ahora.** Cuando Cfx.re retire de verdad las natives de Mumble, lo esperable es
que el propio mantenedor de `pma-voice` migre el recurso primero — en ese momento, traer esa
actualización con el mismo mecanismo de fork que se usa para el resto de recursos de Proyecto
Savia (diff contra upstream, reaplicar personalizaciones si las hay).

---

## 2026-08-30 — Fork creado: nunca se había migrado a Enhanced (jugadores sin voz) · Claude

**Reportado:** "no nos escuchamos" — investigando, se confirmó que **no había ningún sistema de voz configurado en Enhanced en absoluto**: sin `ensure` en `server.cfg`, sin entrada en el catálogo `resources.json`, sin submódulo.

**Causa:** el propio comentario de cabecera de `resources.json` (desde el 2026-08-26) ya lo documentaba: `pma-voice` es uno de los "recursos base de FXServer sin repo propio todavía, quedan fuera hasta que lo tengan" — quedó deliberadamente aparcado durante la migración de Proyecto Savia y nadie volvió a por él.

**Comparado contra `rpbase/pma-voice` (v7.0.1) antes de forkear:** diff byte a byte contra el upstream real ([`AvarianKnight/pma-voice`](https://github.com/AvarianKnight/pma-voice), el fork comunitario activo — el `citizenfx/pma-voice` original está descontinuado) — **sin ninguna personalización propia**, solo desactualizado respecto a la versión actual de upstream: le faltaban un fix real de fuga de memoria en `server/mute.js`, una optimización de serialización de eventos de radio, el export `removeChannelCheck`, soporte de PTT secundario, y un convar para desactivar la radio al disparar. Al no haber nada propio que preservar, se forkeó la versión actual de upstream directamente en vez de portar la copia desactualizada.

**Hecho:**
- Fork `CachopoRP/pma-voice` desde `AvarianKnight/pma-voice` (sin cambios de contenido).
- Rama `cachoporp` creada igual que `main`.
- Añadido como submódulo en `rpbase-enhanced` (`resources/pma-voice`, rama `cachoporp`).
- Registrado en `FiveM-Enhanced/config/resources.json`.
- `server.cfg`: `ensure pma-voice` + convars, justo después de `ensure chat`. Los valores **no son los por defecto** — calcados de `rpbase/txAdminRecipe/voice.cfg` (config real ya usada antes en producción, encontrada al comparar): `voice_defaultCycle "GRAVE"` (en vez de F11), `voice_defaultRadioVolume 60` (en vez de 30), `voice_defaultCallVolume 80` (en vez de 60), `voice_useNativeAudio true` (audio 3D con eco/reverb, recomendado por el propio README de pma-voice, requerido para los submixes).

**Pendiente:** desplegar (`deploy-changed.yml` lo detectará solo al bumpear el puntero del submódulo) y **reinicio completo del server** — el `ensure` nuevo solo se lee al arrancar. Confirmar en vivo que la voz funciona con el rango de proximidad y que la tecla `GRAVE` cicla el modo correctamente.
