# Deathmatch with respawns: design

Date: 2026-09-29. Replaces the last-one-standing round.

## Goal

A Call of Duty style free-for-all deathmatch. Being killed is no longer the end of
your round: you go back to the lobby, press SPAWN, and drop back into the match.
The match is won on kills.

Decisions made with the user:

| Topic | Decision |
|---|---|
| Mode | Free-for-all. No teams yet; nothing here should block adding them. |
| Win rule | First to `KILL_TARGET` kills, or the top scorer when the timer runs out. |
| Match flow | Match, short results break, new map, next match. Anyone in the lobby can spawn at any time during a match, late joiners included. |
| Bots | Respawn on their own after a delay. They score and can win. |
| Spawn guard | About 2s of invulnerability after spawning, ended early by shooting. Spawn points are picked away from enemies. |
| Scoreboard | Top bar only: timer, your kills against the target, the leader. |
| SPAWN button | Cloned from `SpectateButton` in the place through the Studio plugin. |

## Match flow

`Lobby (waiting) -> Round (the match) -> End (3s arena freeze + 5s results) -> Lobby`

- **Lobby**: waits until players plus planned bots reach `MIN_PLAYERS`, then loads
  a random map. A failed map load warns and retries, as today.
- **Round**: combat, abilities, grapple and bots start. The scores are cleared.
  Bots spawn at once. **Players start in the lobby** and enter with SPAWN. The
  phase lasts `ROUND_TIME` (300s) and ends early when a combatant reaches
  `KILL_TARGET` (20), or is aborted when players plus planned bots fall under
  `MIN_PLAYERS`.
- **End**: unchanged mechanics (systems stop, weapons detach, `RoundEndForceField`,
  freeze, heal, teleport to lobby, bots despawn, ragdolls clear, map unloads).
  `extra` is `{ winners = { name }, reason }` with reasons `KillTarget`, `TimeUp`,
  `Aborted`. The winner is the single top scorer; a player winner gets
  `SHOP_COINS_PER_WIN`. No kills at all means no winner.

The `Intermission` and `Reveal` phases are removed, with `INTERMISSION_TIME`,
`REVEAL_TIME`, `TEST_MODE`, `TEST_END_WALL` and the `Survived` and `LastStanding`
reasons. Solo testing does not need test mode: one player plus the bots is a match.

A match with every real player sitting in the lobby still runs: the bots fight it
out and someone reaches the target.

## Dying and spawning

**Dying** keeps today's path: kill feed line, `SHOP_COINS_PER_KILL` to a player
killer, ragdoll at the spot, victim set to `Lobby` and teleported to the lobby,
kill cam on the victim's client. New: the killer's score goes up by one. A death
with no killer (a reset) scores for nobody.

**Spawning**: the client sends `SpawnRequest`. The server accepts it when the phase
is `Round`, the player is `Lobby`, their character is alive, and `RESPAWN_DELAY`
(3s, the kill cam's length) has passed since their last death. It then:

1. clears the character's combat state with the new `CombatSystem.revive(char)`.
   This matters: players are never really killed, so the same character comes
   back, and `CombatSystem` still has it marked eliminated, which would make it
   unable to shoot or be hit;
2. sets the player `Safe` (walk speed, third-person weapon);
3. teleports them to the spawn point chosen by `MapManager._pickSpawn`;
4. adds the spawn protection.

**Spawn point**: among the map's spawn points, the one whose nearest living enemy
is farthest away. With no enemies, a random one.

**Spawn protection**: a visible `ForceField` named `SpawnProtection` on the
character for `SPAWN_PROTECTION_TIME` (2s). `CombatSystem.shoot` ignores a hit on a
protected victim (the tracer still draws, the shield is untouched) and removes the
shooter's own protection when they fire.

**Bots**: an eliminated bot is destroyed as today and comes back `RESPAWN_DELAY`
later at a picked spawn point, with protection, under the same name and skill, so
its score carries on. Known simplification: its avatar is rolled again each life.

**Ragdolls** used to live until round end. With respawns they would pile up, so
each one is removed after `RAGDOLL_LIFETIME` (15s).

## Scores

New server module `Systems/MatchScore.luau`, keyed by combatant name (a player's
name, a bot's generated name):

- `reset()`, `addKill(name)`, `kills(name)`
- `leader()` returns the name and kills of the top scorer, or nil with no kills.
  Ties go to whoever reached that count first.
- `targetReached()` is true once the leader has `KILL_TARGET` kills.

The scores replicate as attributes on a Folder `ReplicatedStorage.MatchScores`
(attribute name is the combatant name, value is the kills), created by the module.
Attributes replicate on their own, so late joiners need no sync remote. The
ordering and tie-break logic are pure functions over a plain table
(`MatchScore._leader(kills, reachedAt)`), covered by `Systems/MatchScoreTest.luau`.

## Client

- **`Controllers/SpawnController.luau`** (new): binds `Lobby.Buttons.SpawnButton`
  through `ShopController.bindLobbyButton`. The button shows only while the local
  state is `Lobby` and the phase is `Round`. It reads `SPAWN`, or `SPAWN IN 2` while
  the respawn delay runs (clicks do nothing then). A click sends `SpawnRequest`,
  closes any open modal and stops spectating.
- **`UIController`**: during `Round` the headline is `FIRST TO 20` until someone
  scores, then `<NAME> LEADS 12`. The pill shows the timer on the left and
  `KILLS 3/20` (the local player's) on the right. At `End` the headline is
  `<NAME> WINS!`, or `MATCH ENDED` with no winner. `Lobby` keeps
  `WAITING FOR PLAYERS...`.
- **`ChangeIndicatorController`**: the second line reads `PRESS SPAWN` instead of
  `SPECTATING`.
- Every `Reveal or Round` check becomes `Round` (CombatController,
  CombatFeedbackController, AbilityHUDController, ShiftLockController,
  MinimapController, MobileControlsController).
- The shop, inventory, settings and spectate buttons keep working between lives,
  since they already show whenever the state is `Lobby`.

## Server changes by file

| File | Change |
|---|---|
| `RoundManager.luau` | New game loop and match loop, `SpawnRequest` handling, scoring on elimination, last-death times. Reveal, intermission and test mode go. |
| `MatchScore.luau` (new) | Scores and their replication. |
| `CombatSystem.luau` | `revive(char)`; spawn protection checks in `shoot`. |
| `BotSystem.luau` | Bots keep an identity (name, skill) across lives and respawn after the delay. `aliveNames` goes with last-standing. |
| `MapManager.luau` | `_pickSpawn(spawns, enemies)` and `spawnCFrameAwayFrom(enemies)`. |
| `RagdollSystem.luau` | Per-ragdoll lifetime. |
| `Constants.luau`, `Types.luau` | New tunables and reasons; removed ones deleted. |

## Studio change

One edit to the place, through the Studio plugin, in the Edit datamodel: clone
`StarterGui.Lobby.Buttons.SpectateButton` as `SpawnButton`, text `SPAWN`, first in
the layout order. The user saves the place.

## Testing

Written first, run in a play session's Server VM:

- `MatchScoreTest`: kills add up; the leader is the top scorer; a tie goes to who
  got there first; `targetReached` flips exactly at the target; `reset` clears.
- `SpawnPickTest` for `MapManager._pickSpawn`: picks the point farthest from the
  nearest enemy; no enemies gives any point; no spawn points gives nil.

Then end to end through the Studio plugin, driving remotes and keys:

1. Match starts with the player in the lobby, bots fighting, SPAWN visible.
2. `SpawnRequest` puts the player in the arena with the weapon and protection; a
   second request while `Safe` does nothing.
3. A shot at the protected player does no damage; after 2s it kills.
4. Killed: back in the lobby, score of the killer up by one, SPAWN counts down and
   then works again, and the respawned character can shoot and be hit.
5. A killed bot is back within a few seconds under the same name.
6. The match ends when a combatant reaches the target, with that name on the
   banner, and the next match starts with scores at zero.

Success criterion: all six hold with no errors in the Output log.

## Risks and the case against

- **Respawns change the feel of one-shot kills.** Last one standing made every
  life matter; here a death costs three seconds. The shield and grapple matter
  less when dying is cheap. This is the intended trade, named so it is a choice.
- **Bots may dominate the scoreboard.** Five bots that never rest against players
  who visit the shop between lives. Bot skill and `BOT_COUNT` are the knobs.
- **Spawn kills** are still possible on small maps once protection ends; the
  farthest-spawn rule only helps when the map has spread-out spawn points.

## Out of scope

Teams, a full scoreboard panel, deaths and K/D, assists, killstreaks, a match
start countdown, map voting, and keeping a bot's avatar across lives.
