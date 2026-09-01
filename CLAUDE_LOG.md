# CLAUDE_LOG — pma-voice

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
