# CLAUDE.md

Project context for Claude Code when working in this Roblox game.

## Project: Burn Rush

A round-based Roblox free-for-all shooter. Every player is armed with a hitscan pistol and a breakable shield; one shot eliminates, a shield blocks one shot, last player standing wins (or everyone still alive wins if the timer runs out). Built with Rojo + Luau.

- **Rojo project**: `default.project.json` (services map to `src/<Service>/`)
- **Toolchain**: `aftman.toml`
- **Scripts**: Luau (`.luau` ModuleScript, `.server.luau` Script, `.client.luau` LocalScript)
- **Style**: Functional modules (no OOP). Each system is a table with `init()` and public functions.

The earlier tag/flamethrower build (burner conversion, stages, fire hazards) lives under `archive/` at the repo root, outside the Rojo tree, for reference only.

## Architecture

### Server (`src/ServerScriptService/`)

- `Main.server.luau`: bootstrap. Requires and `init()`s every system in this order:
  `PlayerState → MapManager → AbilitySystem → CombatSystem → RoundManager`
- `Systems/PlayerState.luau`: per-player state (`Lobby` / `Safe`; eliminated players go back to `Lobby`). Replicates via `PlayerStateChanged` RemoteEvent. Exposes `StateChanged` BindableEvent.
- `Systems/RoundManager.luau`: game loop and round lifecycle. Owns the phase state machine, character setup (`BreakJointsOnDeath = false` on every spawn), attaching/detaching the third-person weapon model, elimination handling, and the kill-feed broadcast. Starts/stops `CombatSystem` and `AbilitySystem` together at the Reveal → Round boundary and at round end.
- `Systems/CombatSystem.luau`: the pistol and shield engine. Per-player shield state (up/cooldown/breaks-in-chain), hitscan shoot handling, shield raise/lower/break logic, and the passive Heartbeat step that expires shields and clears cooldowns. Auto-creates `ShootRequest`, `ShieldRequest`, `ShieldChanged`, `ShotBlocked`, `DamageDealt`, `DamageTaken` on `init()` via the `ensureRemote` pattern. Exposes `PlayerEliminated` BindableEvent `(victim, killer?)`.
- `Systems/MapManager.luau`: clones map from `ServerStorage.Maps` into `Workspace.LoadedMap`, manages spawn points and lobby teleport. Warns at `init()` if `ServerStorage.Maps` is missing or empty.
- `Systems/AbilitySystem.luau`: dash mechanic for safe players (Q key). Phase-gated via `start()` / `stop()`: dash is rejected outside the active `Round` phase, so safe players cannot dash during reveal or lobby. `start()` also clears `lastDash` so cooldowns don't carry across rounds.

### Client (`src/StarterPlayerScripts/`)

- `Main.client.luau`: bootstrap. Inits `AbilityHUDController`, `DashController`, `UIController`, `KillFeedController`, `KillConfirmController`, `CombatController`, `CombatFeedbackController`, `ChangeIndicatorController`, `ShopButtonController`, `CameraController` (in that order).
- Outside combat, players use the **stock Roblox classic camera and free cursor**. While combat mode is active (local state `Safe`, phase in `{Reveal, Round}`), `CameraController` switches to a Shift Lock style shoulder camera: `MouseBehavior = LockCenter` re-asserted every `RenderStepped`, `RotationType = CameraRelative` so the character faces the camera, `Humanoid.CameraOffset = CAMERA_SHOULDER_OFFSET`, FOV eased to `CAMERA_COMBAT_FOV`, zoom clamped to `[CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM]`; everything restores to stock when it deactivates. Aiming is a raycast from the camera through the mouse position, which is the screen center while locked.
- `Controllers/CameraController.luau`: the shoulder camera above. Exposes `getBaseOffset()`, which `CombatFeedbackController` adds its damage shake on top of, so the two never fight over `Humanoid.CameraOffset`.
- `Controllers/UIController.luau`: reads phase/player-state remotes, renders RichText into `Game.StatusFrame.Status` (main announcements) and the `Game.SecondaryStatus` pill (`Secondary` + `Alive` chips). During `Round`, Status reads "LAST ONE STANDING" and the pill shows `1:30` on the left and `ALIVE 2/3` on the right (`safe/total`, alive count excludes the local player). In other phases the pill shows a single full-width line (`PLAYERS 1/2`, `STARTING IN 5`, `POSITION YOURSELF 8`). At `End`, Status renders the winner banner (1 / 2 / `N PLAYERS SURVIVED!` formats, empty winners falls back to "ROUND ENDED").
- `Controllers/KillFeedController.luau`: listens to `KillFeed` remote, clones `Game.ID_Objects.KillData` into `Game.Killfeed` per kill, animates entrance/exit (TweenService), maintains a queue. Text is `"<Killer> shot <Victim>"` when there's a killer, `"<Victim> eliminated"` otherwise.
- `Controllers/KillConfirmController.luau`: pop-up notification ("ELIMINATED <Name>") shown to the killer only when `KillFeed` fires with `killerName == localPlayer.Name`. Clones `Game.ID_Objects.KillConfirm` into `Game` per kill. Each banner has its own independent lifecycle (expand → fade-in → 3s hold → fade-out → collapse): banners do **not** cancel each other. Concurrent kills stack: the newest sits at the template's authored position; older ones reflow by `STACK_DIRECTION` (-1 = upward) × `(height + STACK_GAP)` per slot. Soft cap `MAX_STACK = 5` evicts the oldest banner when exceeded; the evicted banner's coroutine bails on its next `clone.Parent` check after destroy. All stacking tunables are at the top of the file.
- `Controllers/DashController.luau`: sends `DashRequest` on Q, phase-gated to `Round` and state-gated to `Safe`. Resets `lastDash` to 0 the moment the client sees phase transition into `Round`, so stale cooldowns don't carry across rounds.
- `Controllers/CombatController.luau`: shooting and shield input, and the source of truth for the shield and gun meters. On LMB, raycasts `Camera:ViewportPointToRay` at the mouse cursor (`UserInputService:GetMouseLocation()`) out to `PISTOL_RANGE` (excluding the local character) to find the aim point, then fires `ShootRequest(Head.Position, direction)`: client-side gated on state `Safe`, phase `Round`, shield not up, and the local `PISTOL_COOLDOWN` timer. On E, fires `ShieldRequest(true)` to raise (only when status is Ready) or `ShieldRequest(false)` to lower (only while Up). Listens to `ShieldChanged(status, duration, breaksInChain)` to drive `Game.Actions.Meters.ShieldMeter.BarBG.Fill`: full and draining to empty over `duration` while Up, empty and filling back up over `duration` while on Cooldown, full and static when Ready. `BarBG.EmptyOverlay` is visible only during Cooldown. `Game.Actions.Meters.GunMeter` has the same children: on every shot sent its `Fill` snaps empty and refills over `PISTOL_COOLDOWN` with `EmptyOverlay` visible until full; it resets to full on every phase change. The meters' parent (`Game.Actions`) is shown only while combat is active - local state `Safe` and phase in `{Reveal, Round}` - so it's visible (but inert) during the Reveal countdown too. Exposes `ShotFired: BindableEvent.Event`, fired whenever a shot is actually sent, consumed by `CombatFeedbackController` for the crosshair punch.
- `Controllers/CombatFeedbackController.luau`: purely cosmetic. Listens to `DamageDealt` (shooter side: throttled hit-confirm sound, batches damage into floating numbers above the victim's head via the `ReplicatedStorage.Assets.UI.DamageNumber` BillboardGui template), `DamageTaken` (victim side: vignette pulse, camera shake via `Humanoid.CameraOffset`, HP-threshold grunts at 75/50/25%, looping sizzle while taking damage), `KillFeed` (kill-confirm whoosh for a kill landed / convert-impact effect when eliminated), and `ShotBlocked` (a sound for either party when a shield absorbs a shot). Uses `Game.Vignette` and `Game.Crosshair` GuiObjects. Local-only sound IDs are stubbed (`""`): see the `SOUND_IDS` table at the top of the file when assets are ready. The gunshot and shield-block sounds are played **server side** by `CombatSystem` (a `Sound` parented to the relevant head, so everyone hears them spatially); their IDs are `PISTOL_SHOT_SOUND` and `SHIELD_BLOCK_SOUND` in Constants.
  - **Combat mode**: listens to both `PlayerStateChanged` and `RoundStateChanged` for the local player. Active iff `state == Safe AND phase ∈ {Reveal, Round}`. When active, shows `Game.Crosshair` and moves it to the mouse cursor every `RenderStepped`. When inactive, hides the crosshair and snaps it back to idle. Damage shake writes `Humanoid.CameraOffset` as `CameraController.getBaseOffset() + jitter` and settles back to the base offset.
  - **Crosshair**: idle by default, punched (size + color tween, reverses automatically) on `CombatController.ShotFired`. It is a per-shot pulse, not a continuous fire-state visual: there's no sustained flame stream anymore.

### Character (`src/StarterCharacterScripts/`)

- `Health.client.luau`: empty override of Roblox's default Health script. Disables passive HP regen so damage persists between encounters.

### Shared (`src/ReplicatedStorage/`)

- `Shared/Constants.luau`: all tunables (round timing, pistol/shield numbers, movement/dash, state and phase strings, UI colors, shield status strings, end reasons).
- `Shared/Types.luau`: Luau type aliases: `PlayerStateName` (`"Lobby" | "Safe"`), `RoundPhase`, `EndReason`, `RoundEndExtra`.
- `Shared/Abilities.luau`: ability metadata table (currently just `Dash`), keyed by id, grouped into categories. `Abilities.categoryForState(state)` maps `STATE_SAFE` to the `Survivor` category; used by `AbilityHUDController` to pick which ability icon to show.

### Remotes (`ReplicatedStorage.Remotes`)

The `Remotes` folder lives in Studio (not Rojo source); it is preserved across syncs because `ReplicatedStorage` has `ignoreUnknownInstances: true`. Several remotes are **auto-created** by their owning system if missing (the `ensureRemote` pattern), so you don't have to author them in Studio.

- `RoundStateChanged` (RemoteEvent): server broadcasts `(phase, duration?, extra?)`. During `Reveal` and `Round`, `extra` is `nil`. At `End`, `extra` is `{ winners = { name, ... }, reason }`: `winners` is empty when `reason == "Aborted"`.
- `PlayerStateChanged` (RemoteEvent): server broadcasts `(player, state)`.
- `DashRequest` (RemoteEvent): client → server.
- `ShootRequest` (RemoteEvent): client → server `(origin: Vector3, direction: Vector3)`. `origin` is the client's Head position. Server rejects if `origin` is more than `PISTOL_ORIGIN_TOLERANCE` studs from the server-side head, if `direction` isn't a finite non-zero vector, if the round isn't active, if the shooter isn't `Safe`, if their shield is up, or if they're still on `PISTOL_COOLDOWN`. Auto-created by `CombatSystem.init()`.
- `ShieldRequest` (RemoteEvent): client → server `(raise: boolean)`. `true` raises (rejected if already up, on cooldown, round inactive, or not `Safe`); `false` lowers manually and starts the cooldown. Auto-created by `CombatSystem.init()`.
- `ShieldChanged` (RemoteEvent): server → owning client only `(status, duration, breaksInChain)`. `status` is one of `Constants.SHIELD_UP` / `SHIELD_COOLDOWN_STATUS` / `SHIELD_READY`; `duration` is how long that status lasts (0 for Ready). Sent on every transition (raise, natural expiry, manual lower, break, cooldown ending) and once each on `CombatSystem.start()` / `stop()` as Ready. Auto-created by `CombatSystem.init()`.
- `ShotBlocked` (RemoteEvent): server → both parties `(otherPlayer: Player)`, sent when a shield absorbs a shot: to the shooter with the victim, to the victim with the shooter. Auto-created by `CombatSystem.init()`.
- `DamageDealt` (RemoteEvent): server → shooter `(victim, dmg, victimHP)` on a landed, unblocked shot. `victimHP` is the HP after the shot (0 on elimination). Auto-created by `CombatSystem.init()`.
- `DamageTaken` (RemoteEvent): server → victim `(attacker?, dmg, currentHP)`, same moment as `DamageDealt`. Auto-created by `CombatSystem.init()`.
- `KillFeed` (RemoteEvent): server broadcasts `(killerName?, victimName)` per elimination. Auto-created by `RoundManager.init()`.
- `FireRequest`, `FuelChanged`, `InfectionProgress`: no longer used by any active system; don't create or reference them (kept only to avoid Studio-side cleanup on old saves).

### GUI structure (`PlayerGui.Game`, a ScreenGui authored in Studio)

- `StatusFrame.Status` (TextLabel): main HUD line. "GET READY!" during intermission/reveal, "LAST ONE STANDING" during the round, winner banner at end. RichText, all uppercase.
- `StatusFrame.Accent` (Frame): thin orange line under the headline, faded at both ends by a `UIGradient`. Static, no script touches it.
- `SecondaryStatus` (Frame): dark rounded pill under the headline. `UIController` hides it when there is nothing to show (End phase). Children: `Secondary` (TextLabel, left chip: timer during `Round`, the whole line in every other phase, stretched to full width), `Alive` (TextLabel, right chip: `ALIVE safe/total`, visible only during `Round`), `Divider` (Frame, visible only with `Alive`). If `Alive` is missing, `UIController` falls back to one string in `Secondary` joined by ` | `.
- `KillFeed` (Frame, vertical UIListLayout, right-aligned): pinned top-right; kill feed rows are parented here. The layout owns row `Position`, so rows can fade but not slide.
- `ID_Objects.KillData` (Frame): row template cloned per kill into `KillFeed`. Children: `Strip` (Frame, dark backing faded out leftward by a `UIGradient`) and `Label` (TextLabel, RichText, right-aligned, with a `UIStroke`). `KillFeedController` fades `Label` text, its stroke and `Strip` together. Hidden by default; `Visible = true` set on the clone.
- `ID_Objects.KillConfirm` (Frame): kill-confirm banner template, bottom-center, `ClipsDescendants = true` so its contents stay hidden while it is collapsed. `AnchorPoint` must stay `0, 0`: the expand/collapse tween grows it from its left edge. Children: `Title` (TextLabel with a `UIStroke`, both faded by `KillConfirmController`) and `Accent` (Frame, static).
- `Actions` (Frame, horizontal UIListLayout, right-aligned): the bottom-right HUD cluster. Anchored `1, 1` with a `UIAspectRatioConstraint` and a `UISizeConstraint` minimum, so the tile and meters scale as one unit; children are sized in scale against it. Shown only while combat is active for the local player. Children: `AbilityAction` (see below) and `Meters` (Frame, vertical UIListLayout) holding `ShieldMeter` and `GunMeter`, each with static `BarBG.Label` / `BarBG.KeyHint` text, `BarBG.Fill` (sized 0..1 by `CombatController`: shield charge / pistol cooldown) and `BarBG.EmptyOverlay` (visible while that meter is refilling from a cooldown).
- `Vignette` (Frame): full-screen damage overlay; `BackgroundTransparency` is tweened by `CombatFeedbackController` on every damage tick taken.
- `Crosshair` (Frame): small reticle that follows the mouse cursor during combat (needs `AnchorPoint = 0.5, 0.5`); punched (size + color tween) by `CombatFeedbackController` on every shot fired.
- `Actions.AbilityAction` (Frame): dash ability HUD tile, left of the meters. Children: `AbilityIcon` (ImageLabel), `AbilityTitle` (TextLabel), `KeyHint` (TextLabel, static), `Accent` (Frame, static), `Overlay` (GuiObject swept 1→0 height by `AbilityHUDController.triggerCooldown` across the ability's cooldown). Shown only while the local player is `Safe` during `Round`.
- `ChangeIndicator` (Frame): elimination banner. Children: `Title` (TextLabel, set to "ELIMINATED") and `UpdatedInfo` (TextLabel, set to "SPECTATING"). Played by `ChangeIndicatorController` when the local player transitions off `Safe` mid-round while other players are still `Safe`.

### Lobby GUI (`PlayerGui.Lobby`, a ScreenGui authored in Studio)

`ResetOnSpawn = false`, so controllers bind to it once.

- `ShopButton` (TextButton): native dark panel with a `UIScale` child and an orange `Accent` bar. `Controllers/ShopButtonController.luau` tweens the `UIScale` and `BackgroundTransparency` for hover/press feedback (tunables at the top of the file). Purely cosmetic: no shop exists yet, so clicking does nothing.

### Asset templates (`ReplicatedStorage.Assets.UI`)

- `DamageNumber` (BillboardGui): must contain a `Label` (TextLabel) with a `UIStroke` and `UIScale`. Cloned and parented to the victim's `Head` per damage burst by `CombatFeedbackController`. Authored in Studio (not in Rojo source).

## Round Flow

`Lobby → Intermission (10s) → Reveal (10s) → Round (90s) → End (3s arena freeze + 5s lobby = 8s) → Lobby`

`gameLoop` loads the map **before** broadcasting `Intermission`. If the map fails to load (no `ServerStorage.Maps`, or it's empty), it warns and stays in the `Lobby` phase instead of getting stuck cycling through intermission.

**Reveal phase** is a no-damage, no-shield, no-dash positioning window (`REVEAL_TIME = 10s`). Every player is set `Safe` and teleported into the arena, but `CombatSystem` and `AbilitySystem` aren't started until Reveal ends, so `ShootRequest`/`ShieldRequest`/`DashRequest` are all rejected server-side, and the client's own phase gates (`currentPhase ~= PHASE_ROUND`) stop it from even sending them.

**Round phase** (`ROUND_TIME = 90s`) is when `CombatSystem.start()` and `AbilitySystem.start()` run. It ends early only when `PlayerState.countInState(STATE_SAFE) <= 1` (one player left: `REASON_LAST_STANDING`, they're the sole winner) or the player count drops below `MIN_PLAYERS` (`REASON_ABORTED`, winners empty). Otherwise it runs the full 90s and every remaining `Safe` player wins (`REASON_SURVIVED`).

**End phase** is a single 8-second window split server-side into two halves:
1. **Arena freeze (`END_DELAY_TIME = 3s`)**: `CombatSystem.stop()` and `AbilitySystem.stop()` run first (this strips every `PlayerShield` ForceField), then every character's third-person weapon is detached, then every character gets an invisible `ForceField` named `RoundEndForceField` (belt-and-suspenders invincibility against any in-flight shot), and `RoundStateChanged(PHASE_END, END_DELAY_TIME + END_TIME, { winners, reason })` is broadcast **immediately**. Players are still standing in the arena, but combat mode deactivates client-side (phase ∉ {Reveal, Round}) so the crosshair hides and the meter disappears. The single phase broadcast covers both halves so the End-phase timer reads correctly on the client.
2. **Lobby announcement (`END_TIME = 5s`)**: players are healed to MaxHealth, `RoundEndForceField`s are stripped, everyone is teleported to lobby + set to `STATE_LOBBY`, and the map is unloaded. The winner banner remains visible in the lobby for the remaining 5s before the next `gameLoop` iteration broadcasts `PHASE_LOBBY`.

`endRound` is the function that orchestrates this: it stops systems → detaches weapons → adds ForceFields → broadcasts `PHASE_END` (with the full 8s duration) → `task.wait(END_DELAY_TIME)` → heals + strips ForceFields + teleports + `setLobby` → unloads map → `task.wait(END_TIME)`.

## Pistol

Hitscan, third-person aiming at the mouse cursor, one press per shot (no hold-to-fire).

- **Client**: on LMB, `CombatController` raycasts `Camera:ViewportPointToRay` at the mouse cursor out to `PISTOL_RANGE`, excluding the local character; the aim point is the hit position or the ray's far end. `direction = (aimPoint - Head.Position).Unit`, sent as `ShootRequest(Head.Position, direction)`. Client-side gates: state `Safe`, phase `Round`, shield not up, local `PISTOL_COOLDOWN` timer elapsed.
- **Server** (`CombatSystem.shoot`): re-validates everything the client already checked, plus `PISTOL_ORIGIN_TOLERANCE` (rejects if the claimed origin is too far from the server-side head) and re-normalizes/validates `direction` as a finite, non-zero vector. Raycasts `origin → direction * PISTOL_RANGE`, excluding the shooter's character.
- **Damage**: `PISTOL_DAMAGE` (100, one shot eliminates) applied only on a direct hit against another `Safe` player. A hit against a raised shield calls `breakShield` instead of dealing damage (see Shield below).
- **Tracer**: on every accepted shot (hit or miss), the server spawns a thin anchored Neon `Part` named `PistolTracer` (`CanCollide`/`CanQuery`/`CanTouch` all false) from `origin` to the hit point (or `origin + direction * PISTOL_RANGE` on a miss), parented to `Workspace`, and destroys it after `PISTOL_TRACER_LIFETIME` via `Debris:AddItem`. Server-created parts replicate on their own: no remote needed.
- **Cooldown**: `PISTOL_COOLDOWN` (1.0s) between shots, checked server-side with `PISTOL_COOLDOWN_TOLERANCE` (0.05s) slack for network jitter.

## Shield

Raise it with E; it blocks exactly one shot, then breaks.

- **Raising**: puts a native `ForceField` named `PlayerShield` (`Visible = true`) on the character and sets `Humanoid.WalkSpeed` to `SHIELD_WALKSPEED` (12, down from `SAFE_WALKSPEED` 16). Rejected if already up, on cooldown, the round isn't active, or the player isn't `Safe`. While the shield is up the player cannot shoot: the server rejects `ShootRequest` and the client doesn't even send it.
- **Duration: shrinking re-raise**: a freshly raised shield lasts `SHIELD_DURATIONS[1]` (1.0s). Each time it's *broken* by an incoming shot (not lowered manually, not expired naturally), `breaksInChain` increments and the next raise uses `SHIELD_DURATIONS[1 + breaksInChain]` (clamped to the array, 0.5s after one break, 0.25s after two or more). The chain resets to 0 breaks once `os.clock() - lastBreakAt > SHIELD_CHAIN_RESET` (5.0s), so pressure only stays cheap if the defender keeps re-raising fast; a gap resets them to the full 1s shield.
- **Natural expiry or manual lower**: either one removes the ForceField, restores `SAFE_WALKSPEED`, and starts `SHIELD_COOLDOWN` (3.0s) before the player can raise again: `ShieldChanged` fires `SHIELD_COOLDOWN_STATUS` immediately, then `SHIELD_READY` once the cooldown elapses.
- **Break** (a landed shot hits a raised shield): the ForceField is removed immediately, `breaksInChain += 1`, `lastBreakAt = now`, and, critically, there is **no cooldown**. `ShieldChanged` fires `SHIELD_READY` right away, so the player can re-raise on the very next input, just with the shorter duration from the chain. `ShotBlocked` fires to both the shooter and the (former) shield holder.
- The Heartbeat `step` in `CombatSystem` is what actually expires an up shield past `expiresAt` and clears a cooldown past `cooldownUntil`: both paths funnel through `lowerShield`/status broadcasts so the client meter always matches server state.

## Elimination

Players are **never killed** in the Roblox sense. When a `Safe` player's HP reaches 0 from a landed shot:
- HP is restored to `MaxHealth`.
- `CombatSystem.PlayerEliminated` fires `(victim, killer?)`.
- `RoundManager.onPlayerEliminated`, gated to `currentPhase == PHASE_ROUND`, sets the victim to `STATE_LOBBY`, teleports them to the lobby (they spectate from there), and broadcasts `KillFeed(killerName?, victimName)`.
- `Humanoid.BreakJointsOnDeath` is set `false` on every spawn so a 0-HP frame never triggers ragdoll or a death animation.

`killerName` is always present for a pistol elimination (cone/hazard kills don't exist in this mode); it's only `nil` in the remote's shape for forward-compatibility with `KillFeedController`'s no-killer text path.

## Visual identity

- **Third-person weapon**: `RoundManager.setSafe` welds a clone of `ReplicatedStorage.Weapons.<VIEWMODEL_DEFAULT_WEAPON>` (named `EquippedWeapon`) onto the character's right arm via a `Motor6D`, using the grip `CFrame` and motor name read from the matching rig under `ReplicatedStorage.ThirdPersonRigs` (falls back to identity + `"Weapon"` if the rig/motor isn't found). `setLobby` and round end both detach it.
- **Shield**: the `PlayerShield` ForceField itself is the only visual: see Shield above. No outline/highlight system exists in this mode (there's no "who's the burner" to call out; everyone looks the same).

## Map Authoring

Maps live in `ServerStorage.Maps` (each is a `Model`). At runtime they are cloned into `Workspace.LoadedMap` (a Folder created on demand). `MapManager.unloadMap()` destroys the whole folder, so even if the `currentMap` reference is lost no orphan parts can survive.

Required structure inside each map Model:
- `SpawnPoints/` folder containing `BasePart`s named `SpawnPoint`.

A `Fireproof` `BoolValue` child no longer means anything: there's no touch-ignition system in this mode, so it's safe to leave on old map geometry or remove.

## Rojo & Project Config

`default.project.json`:
- No `Baseplate` is defined: sync does not re-create one.
- `$ignoreUnknownInstances: true` is set on the DataModel root, `Workspace`, `StarterPlayer`, `Lighting`, `SoundService`. All folder-mapped services have the same flag in their `init.meta.json`. **Anything you build in Studio that isn't in source is preserved across syncs** (Remotes folder, Maps, Lobby, GUI assets, etc.).
- Files that *are* in source remain authoritative: Studio edits to those will be overwritten on next sync.

## Conventions

- New tunables go in `Constants.luau`. Don't hardcode magic numbers in systems.
- New cross-system signals: prefer `BindableEvent` over polling. Existing examples: `PlayerState.StateChanged`, `CombatSystem.PlayerEliminated`.
- Server creates Workspace instances; they replicate to clients automatically. No remote needed for visual effects (see the pistol tracer).
- Per-frame work goes through `RunService.Heartbeat` (server) or `RenderStepped` (client).
- Phase changes broadcast via the existing `RoundStateRemote` `extra` payload: add fields rather than creating new remotes for round metadata.
- Need a new RemoteEvent? Use the `ensureRemote(parent, name)` pattern at the top of `CombatSystem.luau`: it returns the existing remote if present, else creates one. Don't rely on Studio-authored remotes for new functionality.
- UI text colors: use `colorize(color, text)` helper in `UIController` to wrap text in RichText `<font>` tags. Both labels have `RichText = true` set automatically on first resolve.
- Cosmetic-only client feedback (sounds, screen shake, vignette, damage numbers) belongs in `CombatFeedbackController`: driven by `DamageDealt` / `DamageTaken` / `KillFeed` / `ShotBlocked` remotes. Don't add gameplay logic here; if a feature needs server authority, route it through the existing remotes instead.

## Testing

In Studio, use **Test → Local Server → 2 Players** for end-to-end testing. To shorten iteration, temporarily lower `ROUND_TIME` in `Constants.luau`.

Quick smoke checklist after changes:
1. After intermission, the 10s Reveal countdown begins: Status shows "GET READY!", secondary shows a positioning countdown. LMB does not fire a shot (no tracer, no `DamageDealt`/`DamageTaken`), E does not raise a shield, and Q does not dash: the `Actions` meters are visible but stay full and idle.
2. Round starts: Status switches to "LAST ONE STANDING", the pill shows `1:30` and `ALIVE N/N` split by a divider (timer flips red below 30s; alive count excludes self).
3. During Reveal and Round the crosshair follows the free mouse cursor; the camera is the stock classic camera. LMB fires a hitscan shot toward the cursor: a gunshot is audible to everyone nearby, a short tracer part appears from the shooter to the hit point (or out to `PISTOL_RANGE` on a miss), the crosshair punches once, the `GunMeter` empties and refills over the cooldown, and a second LMB press within `PISTOL_COOLDOWN` (1s) does nothing until it elapses.
4. E raises a shield: a visible `ForceField` appears on the character, WalkSpeed drops, and the meter starts draining from full over 1s. Shooting is refused while it's up (server rejects, no `DamageDealt`).
5. A shot lands on a raised shield: the shield breaks immediately (ForceField gone), `ShotBlocked` fires for both players (feedback sound), and the meter goes instantly to Ready (full, no cooldown wait): raising again right away gives a visibly shorter shield (0.5s, then 0.25s on a second break within `SHIELD_CHAIN_RESET`).
6. Manually lowering a shield (E while up) or letting one expire naturally both start a 3s cooldown: the meter empties and refills over that window with `EmptyOverlay` visible, and raising is refused until it completes.
7. A landed unblocked shot eliminates in one hit: HP resets to max (no death animation), the victim is moved to `STATE_LOBBY` and teleported to the lobby, `KillFeed` shows `"<Killer> shot <Victim>"`, and the `ChangeIndicator` banner ("ELIMINATED" / "SPECTATING") plays for the victim if other players are still `Safe`.
8. As a victim taking damage, a vignette pulse + light camera shake fire; the screen does NOT shake while not being hit. Damage numbers stream above the victim's head.
9. Reduce to the last two players and eliminate one: the round ends immediately with `REASON_LAST_STANDING` - no need to wait for the timer - and the survivor is the sole winner.
10. Let the round timer run out with multiple players still `Safe`: the round ends with `REASON_SURVIVED` and every remaining `Safe` player is listed as a winner (1 / 2 / `N PLAYERS SURVIVED!` formats on the banner).
11. Round end (last-standing, timer, or aborted): immediately, the crosshair and `Actions` meters disappear, shooting/shield/dash are dead, and players hold their final positions in the arena for **3 seconds** (`END_DELAY_TIME`), invincible (`RoundEndForceField` parented to each character). Then everyone snaps to the lobby at full HP, the map disappears (`Workspace.LoadedMap` gone, all `PlayerShield`/`RoundEndForceField`/`EquippedWeapon` instances removed), and the winner banner remains for `END_TIME = 5s` more.
12. **Get multiple kills in quick succession (≤ 3s apart)**: the `KillConfirm` banner does NOT cancel the previous one. New banners stack above the most recent (configurable via `STACK_DIRECTION`); each banner runs its own independent expand/hold/collapse. Beyond `MAX_STACK = 5` the oldest is evicted cleanly.
13. Start a second round: dash works immediately once `Round` begins (no stale cooldown carrying from the previous round), and the shield chain/cooldown state is reset for everyone (`CombatSystem.start()` clears it).

If you start the server and immediately hear the intermission countdown loop forever, check Output for `MapManager: ServerStorage.Maps ...` warnings: that's the cause.
