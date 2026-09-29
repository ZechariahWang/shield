export type PlayerStateName = "Lobby" | "Safe"
export type RoundPhase = "Lobby" | "Round" | "End"
export type EndReason = "KillTarget" | "TimeUp" | "Aborted"

export type RoundEndExtra = {
	winners: { string },
	reason: EndReason,
}

return {}
