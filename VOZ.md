# 🎙️ Proyecto Voz — pma-voice nativo para Enhanced

> Documento de proyecto de la migración de `pma-voice` de las natives de Mumble (deprecadas,
> corriendo sobre el parche de compatibilidad `sv_mumble true`) a la API de voz nativa de GTAV
> Enhanced (`voice_internal` + `CreateVoiceChannel`/`AddPlayerToVoiceChannel`/...). No confundir
> con `CLAUDE_LOG.md` (historial de cambios ya hechos) — este es el plan/estado del proyecto,
> mismo criterio que `VINEWAVE.md` en `qbx_phone`. Se trabaja en la rama `crp-experimental`
> (nombre de convención de todo el catálogo, lo exige `deploy-experimental.yml`), sin tocar
> `cachoporp` (producción) hasta tener algo probado en vivo.

## Por qué

Al pulsar la tecla de ciclar proximidad (`GRAVE`, `cycleproximity`), el juego crashea con
timeout. Investigado en profundidad (ver conversación 2026-08-31):

- `sv_mumble true` es, según la documentación oficial de Cfx.re, un parche de compatibilidad
  para mantener vivas las natives de Mumble **deprecadas** — no la vía soportada de verdad en
  Enhanced. El propio aviso en consola ya lo decía ("removed in a future update").
- `pma-voice` (`AvarianKnight/pma-voice`, nuestro upstream) está construido 100% sobre esas
  natives — cero soporte, cero mención de la API nueva en su repo.
- Revisado el código de `pma-voice` a fondo (`client/init/proximity.lua`, `client/commands.lua`):
  no hay ningún bucle sin ceder CPU que explique un hang por sí solo — el propio recurso ya
  maneja con normalidad el caso de Mumble desconectado (`Wait(100)` en su bucle principal). Esto
  descarta un bug obvio nuestro y apunta a que el problema está en la propia vía deprecada/shim,
  no en el código de `pma-voice` en sí.
- **Sin log de crash en vivo** que lo confirme al 100% — la certeza es alta pero no total.

## Qué trae Enhanced en su lugar

Confirmado contra la documentación oficial (`docs.fivem.net/docs/scripting-manual/voice/`):

- `voice_internal` en `server.cfg` — voz gestionada dentro del propio FXServer, **sin ningún
  proceso ni servidor aparte**.
- Natives nuevas, todas server-side (cierra el fallo de seguridad de Mumble donde un cliente
  modificado podía unirse a canales ajenos): `CreateVoiceChannel(mode, maxDistance)`,
  `AddPlayerToVoiceChannel`, `RemovePlayerFromVoiceChannel`, `DeleteVoiceChannel`,
  `SetPlayerMutedInVoiceChannel`, `SetPlayerDeafInVoiceChannel`. Modos: `0` no-espacial/2D
  (radios), `1` espacial/3D (proximidad), `2` custom, `3` temporal.
- **No hay proximidad automática de fábrica** — activar `voice_internal` no basta, algún script
  tiene que crear el canal y gestionar altas/bajas. Por eso sigue haciendo falta un recurso.
- **Sin ningún recurso comunitario ya migrado** encontrado (búsqueda 2026-08-31) — de ahí que
  construyamos el nuestro en vez de adoptar uno de terceros.
- **Activación** — server-side, en `server.cfg`: `setr voice_internal` (voz gestionada dentro del
  propio FXServer, sin proceso/servidor aparte). También existe `voice_external_host`/
  `voice_external_connect` (servidor de voz externo, marcado como **experimental** en la
  documentación, con clave de licencia que debe coincidir en ambos lados) — no aplica a nuestro
  caso, no hace falta escalar a un proceso separado.
- **Calidad de audio de fábrica** (no había que construirlo nosotros): cancelación de ruido y de
  eco, y manejo gradual de pérdida de paquetes — mejor que lo que ofrecía Mumble por defecto.
- `sv_mumble true` sigue existiendo solo por compatibilidad hacia atrás y la propia documentación
  advierte que permite "client-controlled voice channels" (el cliente decide a qué canal
  pertenece) — justo el modelo de seguridad que la API nueva elimina a propósito, moviendo todo el
  control de membership/mute/deaf al servidor. Confirma que no es solo una migración de APIs, es
  también un problema real de seguridad que arreglamos de paso.

## 📄 Documentación oficial completa de la nueva API de voz (pegada por Oscar 2026-09-01)

Referencia guardada íntegra porque no está indexada donde la buscamos al principio del
proyecto (ver corrección a Fase 0 más abajo) y es la base de todo el resto del plan.
**Consultar esto antes de asumir nada sobre el comportamiento de las natives.**

### ConVars eliminadas en Enhanced (⚠️ afecta a `shared.lua` de pma-voice)

> The following ConVars from the Mumble system are no longer available in FiveM for GTAV
> Enhanced: `voice_use2dAudio`, `voice_use3dAudio`, `voice_useSendingRangeOnly`,
> `voice_useNativeAudio`.

`shared.lua:47` sigue leyendo `voice_useNativeAudio` para elegir entre dos tablas de
`Cfg.voiceModes` (1.5/3/6 "audio nativo" vs 3/7/15 normal) y `client/init/proximity.lua:15` lo
usa para un multiplicador ×3 en `orig_addProximityCheck`. **Como el convar ya no existe en el
engine, `GetConvar` solo devuelve lo que haya puesto a mano en el `server.cfg` (`true`) sin
ningún efecto real en el motor** — la rama "audio nativo" es un vestigio muerto en Enhanced, no
algo calibrado a propósito para este engine (era una distinción real en Legacy/Gen8, no aquí).
Pendiente: recalibrar `Cfg.voiceModes` sin depender de este convar.

### Modos de canal, confirmados oficialmente

| Modo | Nombre | Comportamiento oficial |
|---|---|---|
| `0` | Non-spatial | 2D. El posicionamiento 2D lo controla la API de voz de cliente. Quién recibe se calcula por pertenencia al canal — todos oyen a todos igual, sin caída por distancia. Ideal para radios/llamadas. |
| `1` | Spatial | 3D automático, el engine posiciona el audio de cada miembro solo. **"Receiving clients are calculated based on proximity within maxDistance"** — el propio engine decide quién recibe según la distancia real al `maxDistance` del canal, no es solo atenuación. |
| `2` | Custom | Requiere streaming propio. Sin API todavía para alimentarlo (no usar en este proyecto). |
| `3` | Temporary | **Hereda todo el comportamiento de Spatial, pero el canal se autoborra cuando se queda vacío.** Resuelve la fuga de canales para diseños tipo "un canal por jugador/conversación" sin necesitar `onResourceStop`. |

Ejemplo oficial citado en la doc: `CreateVoiceChannel(1, 15.0)` para "a 3D proximity channel
that hears speakers within 15.0 units" — un canal de proximidad normal ronda los 15.0 de
`maxDistance`, muy lejos de los 1.5/3/6 que usa hoy la rama muerta de `voice_useNativeAudio`.

### Otros detalles confirmados que corrigen suposiciones ya escritas en este proyecto

- **La limpieza al desconectar es automática del engine**: *"When a player disconnects, they
  are automatically removed from all channels they were in."* — el bucle `playerDropped` que ya
  tenemos en `native_channels.lua`/`native_proximity.lua` es redundante (inofensivo, pero no
  hace falta para que funcione).
- **`AddPlayerToVoiceChannel` sobre alguien ya presente resetea su estado muted/deaf** — cuidado
  si se usa para "refrescar" membership, cualquier mute/deaf manual puesto antes se pierde.
- **`DeleteVoiceChannel` funciona con el canal vacío o no** — no hace falta vaciarlo antes de
  borrarlo.
- IDs de canal empiezan en `0`, máximo 65535 canales, `65535` de vuelta = sin canales libres
  (ya coincide con el check que tenemos en `native_channels.lua:28`).
- El equivalente 1:1 de radios/walkie con la API nueva es un único script server-side (ejemplo
  completo en la doc, con `getOrCreateChannel`/`leaveAllChannels` sobre canales modo `0`) — nos
  sirve como plantilla directa para la Fase de radios (`server/module/radio.lua` nuevo).
- Escuchar sin poder hablar (equivalente a `MumbleAddVoiceChannelListen`) = meter al jugador con
  `AddPlayerToVoiceChannel` y luego `SetPlayerMutedInVoiceChannel(..., true)`.

### Corrección a "Fase 0" (más abajo en este documento)

Donde dice que las natives "no aparecen en el índice general de natives (`natives.json`)" —
correcto que no están ahí, pero **sí están documentadas oficialmente**, solo que en la guía en
prosa de voz de `docs.fivem.net` (sección "FiveM for GTAV Enhanced"), no en el índice
autogenerado de natives clásico que se busca con las herramientas de lookup habituales. No es
una API no soportada ni experimental — es la vía oficial y recomendada, con ejemplos completos
de radio incluidos. Corrige la cautela que veníamos arrastrando desde el inicio del proyecto.

## Alternativas descartadas (y por qué)

- **Seguir en `sv_mumble true`**: es lo que causa el crash de hoy. Descartado.
- **SaltyChat / YaCA / TokoVOIP** (basados en TeamSpeak 3 real): exigen levantar o pagar un
  servidor TS3 aparte, **1 slot TS por jugador conectado** (no hay pool compartido), y la
  licencia gratuita de TeamSpeak tope en 32 slots — el programa "Non-Profit" que daba hasta 512
  gratis está descontinuado desde 2018, sustituido por un programa de "Sponsorship" selectivo
  (marcas/influencers), no un trámite garantizado. Coste real para 100 slots: ~$150-200/año
  autoalojado (licencia oficial ~$100/año/128 slots + VPS barato) hasta ~$400-1.100/año con
  hosting gestionado. Descartado por coste recurrente + dependencia externa, a favor de construir
  la vía nativa (sin coste, sin servidor aparte, first-class soportada por Cfx.re).

## Superficie a preservar (para no romper nada fuera de este recurso)

Revisado quién llama a `exports['pma-voice']` en todo el catálogo (2026-08-31) — el
acoplamiento es fino, todo vía export, nada interno:

| Recurso | Exports usados |
|---|---|
| `src-payphone/client.lua` | `addPlayerToCall`, `removePlayerFromCall` |
| `qbx_phone/client/feature/notification.lua` | `addPlayerToCall`, `removePlayerFromCall` |
| `qbx_adminmenu` (server+client) | `setPlayerRadio`, `getPlayersInRadioChannel`, `toggleMutePlayer` |
| `ps-mdt` | **ya trae abstracción multi-sistema** (`Config.Radio.VoiceSystem`, ver `ps-mdt/config.lua:894-945`) — soporta `pma-voice`/`saltychat`/`yaca` por perfil, cero cambio de código si mantenemos el nombre `pma-voice` y el comando `+radiotalk`/`-radiotalk` |

**Objetivo:** mientras el recurso nuevo exponga los mismos nombres de export (y el mismo
comando `+radiotalk`/`-radiotalk` para PTT), ninguno de estos 4 recursos necesita tocarse.

## Alcance del trabajo

1. **Proximidad + ciclo de rango** — canal 3D vía `CreateVoiceChannel(1, distancia)`, alta/baja
   de jugadores al conectar/desconectar, tecla de ciclar rango (sustituye a `cycleproximity`).
2. **Radios** — múltiples canales no-espaciales, entrar/salir, PTT, exports
   `setPlayerRadio`/`getPlayersInRadioChannel`/`setRadioChannel` con la misma firma que hoy.
   La pieza más grande del proyecto.
3. **Llamadas de teléfono** — canal aislado por llamada, exports `addPlayerToCall`/
   `removePlayerFromCall` igual que hoy.
4. **Mute/deaf de admin** — más simple que antes, las natives nuevas lo traen de fábrica
   (`SetPlayerMutedInVoiceChannel`/`SetPlayerDeafInVoiceChannel`), sin tener que simular el
   volumen a mano como hacía Mumble.
5. **UI** (indicador de quién habla, clics de micro) — a valorar reutilizar el HTML/JS de
   `pma-voice` tal cual (no depende de Mumble, solo consume eventos NUI).
6. **Efecto de estática de radio** — usa natives de audio de GTA (`CreateAudioSubmix`,
   `SetAudioSubmixEffectRadioFx`), no son de Mumble — portable casi tal cual.

## Estado

**2026-08-31** — Rama `crp-experimental` creada desde `cachoporp`. Sin código nuevo todavía.

**2026-08-31 (2) — Crash confirmado en vivo, causa = `sv_mumble true`.** Oscar quitó
`sv_mumble true` en caliente vía txAdmin (cambio no reflejado todavía en el `server.cfg`
trackeado de `FiveM-Enhanced` — pendiente de decidir y aplicar en el repo). Resultado
confirmado en vivo:
- **Sin `sv_mumble`:** la tecla de proximidad (`GRAVE`) ya NO crashea el juego.
- **Pero:** la voz no funciona en absoluto (los jugadores no se oyen) — esperable, ya que
  `sv_mumble true` es justo lo que mantiene operativas las natives de Mumble que usa
  `pma-voice` por debajo.

**Conclusión:** con la arquitectura actual (`pma-voice` sobre Mumble) no hay término medio en
Enhanced — o se activa `sv_mumble` y crashea, o se desactiva y no hay voz. Confirma que la
migración a la API nativa (este proyecto) no es una mejora opcional, es la única forma de tener
voz funcional y estable en Enhanced con lo que tenemos hoy.

**2026-08-31 (3) — Confirmado en consola: sin backend de voz activo.** El cliente reporta
`Network voice initialization disabled` al conectar — mensaje esperable, ya documentado arriba:
ni `sv_mumble` (desactivado a propósito) ni `voice_internal` (nunca llegó a activarse en
`server.cfg`) están corriendo, así que no hay ningún backend. Oscar va a añadir `setr
voice_internal` al `server.cfg` de `FiveM-Enhanced` — eso por sí solo NO da proximidad/radios/
llamadas (ver arriba, no hay nada automático de fábrica), pero es el primer paso obligatorio antes
de que el recurso nuevo de este proyecto pueda crear canales con `CreateVoiceChannel`.

**2026-08-31 (4) — Resuelto sin migración: faltaba `voice_internal` junto a `sv_mumble true`.**
Añadidas ambas convars en `FiveM-Enhanced/config/server.cfg` (línea `voice_internal` sin `setr`,
más `setr sv_mumble true` reactivado). Oscar confirma en vivo: la voz funciona, y la tecla GRAVE
(`cycleproximity`) — la que originaba el crash — **ya no crashea** con ambas convars activas a la
vez. El crash original no era `sv_mumble true` en solitario, era la falta de `voice_internal`
(sin el motor nativo activado, las natives de Mumble deprecadas quedaban en un estado no
soportado). Incidente cerrado.

**Proyecto Voz queda aparcado** — la combinación actual resuelve el problema real (crash + sin
voz) sin necesidad de reescribir `pma-voice`. Se retoma este proyecto solo si hace falta de
verdad más adelante (el crash reaparece, o se quiere cerrar el hueco de seguridad de
client-controlled voice channels que sigue existiendo mientras `sv_mumble true` esté activo — ver
sección "Qué trae Enhanced en su lugar" arriba).

**2026-09-01 — Retomado: las llamadas de teléfono no funcionan de verdad.** Confirmado en vivo
(Oscar + Jose se oyen por proximidad, pero la llamada de teléfono entre ellos no conecta).
Investigado contra la documentación oficial, sección **"Limitations of the compatibility
layer"**:

> `MUMBLE_CLEAR_VOICE_TARGET`, `MUMBLE_SET_VOICE_TARGET`, and any natives that accept voice
> targets behave as if there is only a single voice target.

`pma-voice` construye tanto llamadas como radios sobre exactamente esas natives
(`MumbleAddVoiceTargetPlayerByServerId`, `client/init/main.lua:toggleVoice`/`addVoiceTargets`) —
con `voice_internal` activo, esa capa de compatibilidad queda degradada a un solo target
simultáneo, así que el "apuntado" de audio a alguien fuera de proximidad (justo lo que hace
falta para una llamada) no es fiable. La documentación no ofrece ningún convar ni workaround —
avisan de que van a **eliminar del todo** las natives de Mumble en el futuro. Ya no es "por si
acaso", es la única vía real y duradera.

## Plan de migración por fases

Objetivo: sustituir el motor de `pma-voice` (Mumble deprecado) por las natives nativas de
Enhanced, **sin tocar la superficie pública** (exports/eventos/comandos de la tabla de arriba),
para que `src-payphone`, `qbx_phone`, `qbx_adminmenu` y `ps-mdt` sigan funcionando sin cambios.
Proximidad ya funciona hoy (vía `voice_internal` + `sv_mumble true`) — el resto no, o no de forma
fiable.

### Fase 0 — Verificación en vivo de las natives nuevas ✅ **CONFIRMADO 2026-09-01**
Antes de escribir nada real: comprobar en `crp-experimental` que `CreateVoiceChannel` y el resto
de natives de canal (`AddPlayerToVoiceChannel`, `RemovePlayerFromVoiceChannel`,
`SetPlayerMutedInVoiceChannel`, `SetPlayerDeafInVoiceChannel`, `DeleteVoiceChannel`) existen de
verdad en el build actual del server — documentadas en la guía oficial, pero **no aparecen en el
índice general de natives** (`natives.json`) ni en `ext/native-decls` del propio repo de
FXServer (confirmado buscando ahí a fondo, cero mención, cero hilo de foro de la comunidad
usándolas). Antes de fiarse solo de la documentación, se probó en vivo con un recurso
desechable (`voice_native_test`, un comando `/testvoicechannel`) directamente en el server de
Oscar. **Resultado: las 5 natives responden de verdad**:

```
CreateVoiceChannel(1, 15.0) -> OK, resultado: 2
AddPlayerToVoiceChannel(2, 1) -> OK, resultado: 1
SetPlayerMutedInVoiceChannel(2, 1, false) -> OK, resultado: 1
RemovePlayerFromVoiceChannel(2, 1) -> OK, resultado: 1
DeleteVoiceChannel(2) -- limpieza -> OK, resultado: 1
```

Existen y funcionan aunque todavía no estén documentadas en el índice oficial de natives (pasa a
veces con FXServer: la implementación llega antes que la declaración/doc-comment que genera el
índice). Vía libre para el resto del plan.

### Fase 1 — Núcleo de canales (server) — ✅ CONFIRMADO 2026-09-01
Módulo nuevo, propio de este proyecto (no toca `server/module/radio.lua` ni `phone.lua`
existentes todavía): una capa fina sobre las natives de canal — crear/borrar canales, llevar la
cuenta de qué canal RAGE (`CreateVoiceChannel`) corresponde a qué "canal lógico" nuestro (número
de radio, ID de llamada, proximidad). Sin esto, las fases siguientes no tienen dónde apoyarse.

Construido en `server/module/native_channels.lua` (aislado, cero impacto en el comportamiento
actual del recurso) y validado en vivo con `/testnativechannels`, las 6 funciones del módulo
respondieron correctamente de punta a punta:
```
[native_channels] createNativeChannel -> 3
[native_channels] addPlayerToNativeChannel -> true
[native_channels] getNativeChannelsForPlayer -> 1 canal(es)
[native_channels] setPlayerMutedInNativeChannel -> true
[native_channels] removePlayerFromNativeChannel -> true
[native_channels] deleteNativeChannel -> true
```
Comando de prueba ya retirado del código. Vía libre para Fase 2.

### Fase 2 — Proximidad nativa — 🔧 reescrita ("burbuja por jugador") 2026-09-01 (2), detrás de convar apagada por defecto, pendiente de prueba en vivo

**Reescritura 2026-09-01 (2) tras probar en vivo el diseño v1 (3 canales fijos compartidos):**
el resultado en vivo fue que los 3 tramos sonaban exactamente igual (audible y atenuado hasta
~20m incluso en Susurro) — pegado en este documento contra la "Documentación oficial completa"
de arriba, la causa más probable NO era la native (que sí documenta filtrar por `maxDistance`),
sino que un radio compartido por TODOS los que estuvieran en un tramo a la vez no puede modelar
un radio *por hablante* (que es como funciona `MumbleSetTalkerProximity` de verdad). Rediseñado
como **"burbuja por jugador"**: cada jugador activo tiene su propio canal `TEMPORARY` (hereda
todo el comportamiento `SPATIAL` + se autoborra al vaciarse, confirmado oficialmente — ver
"Documentación oficial completa" arriba), con `maxDistance` = el radio de SU tramo actual. Todos
los demás jugadores activos son miembros de esa burbuja; el engine decide solo, en vivo, quién
está lo bastante cerca para recibir audio — sin polling de posición nuestro, el canal "sigue" al
jugador automáticamente (confirmado por la doc). Al ciclar de tramo (no existe native para
cambiar el `maxDistance` de un canal ya creado) se borra la burbuja vieja y se crea una nueva con
el radio correcto, repoblada con los mismos miembros — esto pasa solo al cambiar de tramo
(evento), no en un bucle. Implementado en `server/module/native_proximity.lua` (reescrito
íntegro). `onResourceStop` en `native_channels.lua` purga todos los canales (burbujas incluidas)
si se reinicia solo el recurso — ver "Documentación oficial completa" arriba.

`Cfg.voiceModes` (`shared.lua`) recalibrado de paso: la rama "audio nativo" (1.5/3/6) dependía de
`voice_useNativeAudio`, que la doc oficial confirma **eliminada en Enhanced** — vestigio muerto,
no una calibración real. Tabla única ahora: Susurro 2.0 / Normal 6.0 / Grito 15.0 (sobre el
ejemplo oficial de `CreateVoiceChannel(1, 15.0)`).
Migrar `client/init/proximity.lua` de las natives de Mumble a canales espaciales nativos
(`CreateVoiceChannel(1, distancia)`).

**Motivación reforzada:** la doc oficial de voice para GTAV Enhanced avisa de que `sv_mumble`
(necesaria hoy para que las natives Mumble deprecadas sigan funcionando) *"allows client-controlled
voice channels. Any client can join any channel and listen to any conversation."* — un cliente
modificado puede en teoría unirse a cualquier canal y escuchar cualquier conversación mientras
`sv_mumble` siga activa. El objetivo final de Proyecto Voz es migrar TODO (proximidad, llamadas,
radios, mute/deaf) a las natives de canal nuevas para poder apagar `sv_mumble` del todo y cerrar
ese hueco. `sv_mumble` es una única convar de servidor — no se puede apagar "por fases", solo
cuando las Fases 2-5 estén TODAS confirmadas en vivo y promovidas a producción.

**Ajuste de diseño frente a la idea original del plan:** `MumbleSetTalkerProximity` es un radio
que cada CLIENTE ajusta por su cuenta; `CreateVoiceChannel` es un canal del SERVIDOR con un único
radio compartido por todos sus miembros, y no existe ninguna native para cambiarle el radio a un
canal ya creado (mismo hueco que ya documentaba `native_channels.lua`). Así que "un canal que
cicla de rango" no es viable tal cual — en su lugar, `server/module/native_proximity.lua` crea
**3 canales fijos, uno por cada tramo de `Cfg.voiceModes`** (Susurro/Normal/Grito) al arrancar el
recurso, y ciclar el rango pasa a ser "cambiar de canal" (sacar al jugador del canal de su tramo
actual, meterlo en el del nuevo) en vez de "cambiar el radio de un canal". Mismo principio de
"pocos canales fijos y de larga duración" que ya recomendaba la Fase 1 para acotar el problema de
canales huérfanos al reiniciar.

**Cableado real, pero detrás de la convar `voice_useNativeProximity` (0 por defecto, o sea
apagada):**
- `client/events.lua` (`handleInitialState`, se llama al conectar y al volver de una llamada) y
  `client/commands.lua` (`setProximityState`, se llama al ciclar F11/GRAVE): con la convar activa,
  ponen `MumbleSetTalkerProximity(0)` (para que la proximidad "de base" del engine no se solape con
  el canal nativo) y avisan al servidor (`pma-voice:server:joinNativeProximityTier`) del tramo
  actual.
- `client/init/proximity.lua` (`addNearbyPlayers`): con la convar activa, se salta el bucle que
  añadía a cada jugador cercano como target de Mumble (el canal nativo ya hace la caída por
  distancia solo) — el bucle de llamadas (`callData`) sigue igual, eso es Fase 3.
- `client/init/proximity.lua` (`exports("setVoiceState", ...)`): al entrar en una llamada, el
  jugador sale de su canal nativo de proximidad (`pma-voice:server:leaveNativeProximity`) para no
  oír de fondo a la gente cercana mientras dura la llamada; al volver, `handleInitialState` lo
  vuelve a meter en su tramo.
- Con la convar en 0 (default), absolutamente nada de esto se ejecuta — el camino real sigue siendo
  100% Mumble, igual que hoy. Cero riesgo hasta que se active a propósito.

**Cómo probarlo en vivo** (mismo criterio que Fase 0/1 — confirmar antes de promover):
1. En `crp-experimental` (nunca en `cachoporp` todavía): `setr voice_useNativeProximity 1` en el
   `server.cfg` de ese entorno, `restart pma-voice`.
2. Confirmar que los 3 canales se crean al arrancar (log `[native_proximity] Tramo N (...) -> canal
   nativo N`).
3. Con 2 jugadores conectados, comprobar que se oyen o no según la distancia real y el tramo actual
   (F11/GRAVE para ciclar) — sin doble audio, sin eco.
4. Probar una llamada de teléfono mientras tanto: confirmar que durante la llamada NO se oye
   proximidad nativa de fondo, y que al colgar la proximidad vuelve sola.
5. Solo si 2-4 salen limpios: promover (mismo convar en `cachoporp`) y repetir la prueba ahí antes
   de dar la Fase 2 por definitivamente buena.

### Fase 3 — Llamadas de teléfono — 🔧 cableada 2026-09-01 (2), detrás de `voice_useNativeCalls` (0 por defecto), pendiente de prueba en vivo
Motivación exacta: la doc oficial confirma que con `voice_internal` la capa de compatibilidad
degrada `MUMBLE_SET_VOICE_TARGET`/`MUMBLE_CLEAR_VOICE_TARGET` a "as if there is only a single
voice target" — justo lo que usaban las llamadas, de ahí que no conectaran de verdad (ver entrada
2026-09-01 más arriba). Implementado en `server/module/phone.lua`: un canal `NON_SPATIAL`
(`CreateVoiceChannel(0, 0.0)`) por llamada activa, creado al primer `addPlayerToCall` y borrado
cuando se vacía (nada de voice targets, la pertenencia al canal ya basta). `client/module/
phone.lua` se salta `addVoiceTargets`/`MumbleClearVoiceTargetPlayers` cuando la convar está
activa — `toggleVoice` (submix/volumen, cosmético) se mantiene igual. Mismos exports
(`addPlayerToCall`/`removePlayerFromCall`) sin tocar, `src-payphone` y `qbx_phone/client/feature/
notification.lua` no necesitan ningún cambio.

### Fase 4 — Radios — 🔧 cableada 2026-09-01 (2), detrás de `voice_useNativeRadio` (0 por defecto), pendiente de prueba en vivo
Un canal `NON_SPATIAL` fijo por frecuencia realmente usada (creado en el primer `setPlayerRadio`
a esa frecuencia, no una de más), implementado en `server/module/radio.lua`. PTT
(`+radiotalk`/`-radiotalk`) sigue disparando `pma-voice:setTalkingOnRadio` al servidor exactamente
igual que hoy — con la convar activa, el servidor traduce ese evento a
`SetPlayerMutedInVoiceChannel` (silenciado por defecto al entrar al canal, destapado mientras se
mantiene pulsado) en vez de que el cliente ande apuntando voice targets de Mumble. `client/
module/radio.lua` se salta `addVoiceTargets`/`MumbleClearVoiceTargetPlayers` cuando la convar
está activa; toda la lógica de UI, animación y mic-clicks queda intacta. Mismos exports que hoy
(`setPlayerRadio`/`getPlayersInRadioChannel`/`setRadioChannel`) para que `qbx_adminmenu` y la
abstracción multi-sistema de `ps-mdt` (`Config.Radio.VoiceSystem`) sigan funcionando sin tocarlas.
Pendiente (no bloqueante para probar en vivo): `getPlayersInRadioChannel` y el multi-canal
simultáneo (`TODO` ya anotado en el archivo original) siguen sin tocar, funcionan igual que hoy.

### Cómo probar Fases 2-4 en vivo (2026-09-01 (2), todavía sin probar)

En `crp-experimental` únicamente, nunca en `cachoporp`:

1. `setr voice_useNativeProximity 1`, `setr voice_useNativeRadio 1`, `setr voice_useNativeCalls 1`
   en el `server.cfg` de ese entorno (las tres convars son independientes, se pueden activar/
   probar por separado si se prefiere ir paso a paso). `restart pma-voice`.
2. Proximidad: con `voice_debugMode 1`, confirmar en consola `[native_proximity] Burbuja de %s ->
   tramo...` al conectar y al ciclar GRAVE. Con 2 jugadores, comprobar que el corte de audio pasa
   cerca del radio real de cada tramo (2/6/15m) y que SÍ hay diferencia perceptible entre tramos
   (a diferencia del diseño v1).
3. Radio: `/setvoiceintent` aparte, entrar dos jugadores a la misma frecuencia
   (`exports['pma-voice']:setRadioChannel(1)` o el comando que use el job de turno), mantener
   `+radiotalk` (LMENU) y confirmar que se oyen sin importar la distancia real entre ellos (canal
   no-espacial). Confirmar en consola `[radio] Frecuencia %s -> canal nativo %s`.
4. Llamadas: iniciar una llamada de teléfono entre los mismos 2 jugadores estando lejos el uno
   del otro (fuera de proximidad) — confirmar que SÍ conecta y se oyen (esto es justo lo que
   fallaba con Mumble puro, ver entrada 2026-09-01 más arriba). Confirmar en consola `[call]
   Llamada %s -> canal nativo %s`.
5. Colgar/salir de radio y confirmar que el canal nativo correspondiente se limpia (sin errores en
   consola al volver a entrar).
6. Solo si 2-5 salen limpios en las tres piezas: promover las convars a `cachoporp` y repetir ahí
   antes de dar Proyecto Voz por definitivamente bueno y plantear apagar `sv_mumble`.

### Fase 5 — Mute/deaf de admin
Con las natives nuevas esto es casi gratis (`SetPlayerMutedInVoiceChannel`/
`SetPlayerDeafInVoiceChannel` de fábrica, sin simular volumen a mano como hacía el shim de
Mumble). Se hace justo después de radios porque reutiliza los mismos canales ya creados en la
Fase 4.

### Fase 6 — Efecto de estática de radio + UI
Migrar `client/init/submix.lua` (hoy usa `MumbleSetSubmixForServerId`, hay que confirmar si el
motor nativo tiene equivalente o si hace falta otra vía) y valorar reutilizar el HTML/JS de
`pma-voice` tal cual para el indicador de "quién habla" (no depende de Mumble, solo consume
eventos NUI).

### Fase 7 — 🔊 Megáfono (función nueva, la idea que le gustó a Oscar)
No existe en `pma-voice` original — se construye desde cero sobre el motor nuevo, aprovechando
que ya tenemos canales espaciales con radio configurable:

- **Mecánica**: un comando/item (a decidir: item craftable, o restringido a `police`/`ems` como
  `ps-mdt` ya distingue por job) mete al jugador en un **segundo canal espacial temporal**
  (`CreateVoiceChannel(1, radioAmpliado)`, radio bastante mayor que la proximidad normal — p.ej.
  30-50m frente a los ~5-15m habituales) mientras está activo, sin sacarlo de su canal de
  proximidad normal (para playd que sigan usando radio/llamada con normalidad a la vez).
- **Efecto de sonido**: `SetAudioSubmixEffectRadioFx` (confirmado real, ver arriba) sobre el
  submix del jugador mientras el megáfono está activo — mismo mecanismo que ya usa el efecto de
  estática de radio (Fase 6), solo que aplicado a proximidad ampliada en vez de a un canal de
  radio. Da el sonido característico de "voz por altavoz" a quien lo oye.
- **Activación**: tecla mantenida o toggle (a decidir con Oscar) + notificación en pantalla
  mientras está activo, para que el propio jugador sepa que se le oye más lejos y distorsionado.
- **Sin depender de animación/prop de terceros**: los `.ycd` de megáfono que hay en el catálogo
  (`rpemotes-reborn`, `scully_emotemenu`) son assets de esos recursos de emotes, no de
  `pma-voice` — si se quiere un prop/animación visual, se dispara como llamada opcional a esos
  recursos (acoplamiento débil, ver si tienen export), nunca como dependencia dura de este
  proyecto. El mecanismo de voz funciona igual con o sin animación.
- Riesgo bajo de romper nada existente — es aditivo, no modifica proximidad/radio/llamadas.

### Fase 8 — Pruebas en vivo y despliegue progresivo
Cada fase se prueba en `crp-experimental` antes de pasar a la siguiente (mismo criterio que el
resto de "Proyecto Savia" — no se fusiona a `cachoporp` hasta confirmar en vivo). Orden de
despliegue sugerido: Fase 2 (proximidad, ya validada hoy, menor riesgo de sorpresas) → Fase 3
(llamadas, el problema real de hoy) → Fase 4+5 (radios, la pieza grande) → Fase 6 (pulido) →
Fase 7 (megáfono, cuando el resto esté estable).
