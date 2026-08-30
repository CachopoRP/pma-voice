# CLAUDE_LOG — pma-voice

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
