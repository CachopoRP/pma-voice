let mutedPlayers = {}
// this is implemented in JS due to Lua's lack of a ClearTimeout
// muteply instead of mute because mute conflicts with rp-radio
//
// CachopoRP 2026-09-05: moderacion completa de verdad (decision de Oscar) --
// no existe una native de mute GLOBAL independiente de canal en la API de
// voz nueva (a diferencia de MumbleSetPlayerMuted, que se queda solo para
// quien siga en Mumble), asi que se simula silenciando al jugador en TODOS
// sus canales nativos actuales y futuros (setPlayerAdminMuted, ver
// native_channels.lua) ademas de la llamada a Mumble que ya habia -- cubre
// a un jugador este en el transporte que este, sin tener que saber cual usa.
function setAdminMuted(mutePly, isMuted) {
	MumbleSetPlayerMuted(mutePly, isMuted);
	exports[GetCurrentResourceName()].setPlayerAdminMuted(mutePly, isMuted);
	Player(mutePly).state.muted = isMuted;
}

RegisterCommand('muteply', (source, args) => {
	const mutePly = parseInt(args[0])
	const duration = parseInt(args[1]) || 900
	if (mutePly && exports[GetCurrentResourceName()].isValidPlayer(mutePly)) {
		const isMuted = !MumbleIsPlayerMuted(mutePly);
		setAdminMuted(mutePly, isMuted);
		emit('pma-voice:playerMuted', mutePly, source, isMuted, duration);
		// since this is a toggle, if theres a mutedPlayers entry it can be assumed
		// that they're currently muted, so we'll clear the timeout and unmute
		if (mutedPlayers[mutePly]) {
			clearTimeout(mutedPlayers[mutePly]);
			delete mutedPlayers[mutePly];
			setAdminMuted(mutePly, isMuted)
			return;
		}
		mutedPlayers[mutePly] = setTimeout(() => {
			setAdminMuted(mutePly, !isMuted)
			delete mutedPlayers[mutePly]
		}, duration * 1000)
	}
}, true)
