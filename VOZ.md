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

### Fase 2 — Proximidad nativa
Migrar `client/init/proximity.lua` de las natives de Mumble a un único canal espacial
(`CreateVoiceChannel(1, distancia)`) que se cicla de rango con la tecla `GRAVE` (sustituye a
`cycleproximity`). Menor riesgo — ya sabemos que la proximidad funciona hoy vía el shim de
Mumble, así que hay margen para comparar comportamiento antes/después en vivo.

### Fase 3 — Llamadas de teléfono
La pieza que motiva retomar el proyecto ahora mismo. Canal aislado por llamada
(`CreateVoiceChannel(0, ...)`, no espacial), altas/bajas vía `AddPlayerToVoiceChannel`/
`RemovePlayerFromVoiceChannel`. Mismos exports (`addPlayerToCall`/`removePlayerFromCall`) para
que `src-payphone` y `qbx_phone/client/feature/notification.lua` no necesiten ningún cambio.

### Fase 4 — Radios
La pieza más grande. Un canal no-espacial por número de radio, PTT (`+radiotalk`/`-radiotalk`),
múltiples canales simultáneos si se puede (a valorar frente a "TODO: permitir multi-canal" que
ya está anotado en el `server/module/radio.lua` actual). Mismos exports que hoy
(`setPlayerRadio`/`getPlayersInRadioChannel`/`setRadioChannel`) para que `qbx_adminmenu` y la
abstracción multi-sistema de `ps-mdt` (`Config.Radio.VoiceSystem`) sigan funcionando sin tocarlas.

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
