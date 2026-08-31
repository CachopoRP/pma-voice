# 🎙️ Proyecto Voz — pma-voice nativo para Enhanced

> Documento de proyecto de la migración de `pma-voice` de las natives de Mumble (deprecadas,
> corriendo sobre el parche de compatibilidad `sv_mumble true`) a la API de voz nativa de GTAV
> Enhanced (`voice_internal` + `CreateVoiceChannel`/`AddPlayerToVoiceChannel`/...). No confundir
> con `CLAUDE_LOG.md` (historial de cambios ya hechos) — este es el plan/estado del proyecto,
> mismo criterio que `VINEWAVE.md` en `qbx_phone`. Se trabaja en la rama `crp-voz-experimental`,
> sin tocar `cachoporp` (producción) hasta tener algo probado en vivo.

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

**2026-08-31** — Rama `crp-voz-experimental` creada desde `cachoporp`. Sin código nuevo todavía.
