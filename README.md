# Roblox Tower Defense Kit

This repository contains Luau scripts and configuration modules for a complete tower defense prototype. Each section below explains **exactly** where to place the files inside Roblox Studio, how to assemble the map, and how to wire up the gameplay systems.

## File Placement Guide

Create the folders in **Explorer** exactly as listed. If a folder already exists, reuse it. All scripts are plain `Script` or `LocalScript` objects unless noted otherwise.

### ReplicatedStorage
1. Create a `Folder` named `Modules`.
2. Inside `Modules`, add a `Folder` named `Config`.
3. Insert a `ModuleScript` named **`TowerConfigs`** and paste the contents of [`ReplicatedStorage/Modules/Config/TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua).
4. Insert a `ModuleScript` named **`EnemyConfigs`** and paste the contents of [`ReplicatedStorage/Modules/Config/EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua).
5. Insert a `ModuleScript` named **`WaveConfigs`** and paste [`ReplicatedStorage/Modules/Config/WaveConfigs.lua`](ReplicatedStorage/Modules/Config/WaveConfigs.lua).
6. In `Modules`, add a `ModuleScript` named **`PathService`** and paste [`ReplicatedStorage/Modules/PathService.lua`](ReplicatedStorage/Modules/PathService.lua).
7. Create a `Folder` named `Remotes`. You do **not** need to add RemoteEvents manually; [`ServerScriptService/GameManager.server.lua`](ServerScriptService/GameManager.server.lua) will generate them if missing.

### ServerScriptService
1. Add a `Folder` called `Modules`.
2. Inside that folder create three `ModuleScript` objects:
   * **`TowerService`** → [`ServerScriptService/Modules/TowerService.lua`](ServerScriptService/Modules/TowerService.lua)
   * **`WaveService`** → [`ServerScriptService/Modules/WaveService.lua`](ServerScriptService/Modules/WaveService.lua)
   * **`SoundEffects`** → [`ServerScriptService/Modules/SoundEffects.lua`](ServerScriptService/Modules/SoundEffects.lua)
3. Add a `Script` named **`GameManager`** in `ServerScriptService` and paste [`ServerScriptService/GameManager.server.lua`](ServerScriptService/GameManager.server.lua).

### StarterPlayerScripts
1. Inside `StarterPlayer > StarterPlayerScripts`, insert a `LocalScript` named **`TowerClient`**.
2. Paste [`StarterPlayer/StarterPlayerScripts/TowerClient.client.lua`](StarterPlayer/StarterPlayerScripts/TowerClient.client.lua).

If you plan to replace the sample tower or enemy meshes, create a `Folder` named **`Assets`** inside `ReplicatedStorage` and add optional subfolders called **`Towers`** and **`Enemies`**. The client script now builds the entire interface at runtime, so no UI templates are required.

## Map Construction Instructions

Follow these steps to build the play area quickly:

1. **Workspace Root**: Create a `Model` named **`Map`**. All map parts go inside this model.
2. **Ground**: Insert a `Part` named `PathGround`. Resize it to roughly `200 × 1 × 200`, anchor it, color it a muted green or brown. This part is used for placement validation; you may also split it into multiple parts if you keep them grouped inside a `Model` named `PathGround`.
3. **Enemy Path**: Inside `Map`, add a `Folder` named **`Path`**. Create numbered `Part` objects (`1`, `2`, `3`, …, `10`). Place them above the ground to trace the path. Make each part a small anchored neon block (`Size = 2 × 2 × 2`) that floats just above the ground. Enemies will lerp between these points in numeric order.
   * Suggested layout: form a gentle zig-zag. Start near one corner of the map, cross the field in 8–10 segments, and end near the opposite corner.
4. **Spawn & Exit**:
   * Add a `Part` named **`EnemySpawn`**. Place it just before waypoint `1`. Make sure its orientation points toward waypoint `1` (`LookVector` alignment).
   * Add a `Part` named **`Exit`** at the end of the path (after the last waypoint). Players lose lives when enemies reach this position.
5. **Player Spawn**: Add a `Part` named **`PlayerSpawn`** somewhere safe off the track. The server teleports players here when they spawn.
6. **Cosmetics**: Add any decorative terrain, cliffs, props, or obstacles. Keep towers’ buildable surface open and flat.
7. **Collision**: Anchor every static part. Ensure the path waypoints themselves are set to `Transparency = 1` and `CanCollide = false` so players and towers do not bump into them.

## Custom Tower & Enemy Models

You can replace the minimalist placeholder geometry with your own creations without touching any scripts.

1. **Create an Assets folder (optional)**: Inside `ReplicatedStorage`, add a `Folder` named **`Assets`**. Within it, create subfolders named **`Towers`** and **`Enemies`** for any custom models you want to swap in. Leave them empty to use the auto-generated geometry.
2. **Tower models**:
   * Parent each custom tower `Model` to `ReplicatedStorage/Assets/Towers` and name it after the `ModelName` field in [`TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua) (defaults: `Archer`, `Cannon`, `FrostMage`).
   * Include a `Base` part (set as `PrimaryPart`, anchored, centered on the ground), plus a `Head` assembly that pivots toward enemies. The `Head` can be a single `Part` **or** a `Model` that contains multiple pieces; just make sure the model’s `PrimaryPart` is the piece that should rotate. Keep every child anchored (or welded to the pivot) so the script can reposition them together.
   * Add a thin `Barrel` `Part` that sticks out of the front of the head. You can leave it as a sibling of the head or parent it under the head model—the server will locate it automatically. Aim the barrel down the head’s negative Z-axis so it points forward when the tower spawns.
   * Anchor every part and disable collisions so placement remains smooth.
   * Update the matching entry in [`TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua) with a `BaseSize` vector that reflects your `Base` part’s dimensions (X and Z are used for the preview square and spacing checks). Towers with splash damage can also set `SplashColor` to tint their explosion effect.
3. **Enemy models**:
   * Parent each enemy `Model` to `ReplicatedStorage/Assets/Enemies` using the names in [`EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua) (`Grunt`, `Runner`, `Tank`).
   * Provide a `HumanoidRootPart` (or assign a `PrimaryPart`) centered on the character plus a `Head` part. Anchor all geometry and disable collisions so enemies glide along the path.
   * Add as many extra anchored `BasePart` limbs, accessories, or sub-models as you like—the server records each part’s offset from the root so the entire rig follows the path and rotates correctly.
4. **Adjusting names**: If you use different model names, update the corresponding `ModelName` value in the config table.
5. **Optional flair**: Accessories, meshes, particles, or lights parented to the model will automatically replicate when towers or enemies spawn.

## Built-in UI

The `TowerClient` LocalScript now fabricates every interface element at runtime, so you can drop the scripts into a clean experience and press Play without wiring any Gui objects by hand. Out of the box you get:

* A pre-game **tower selection screen** that lists every entry from `TowerConfigs`, lets creators pick three unique towers for their loadout, and prevents placement until all slots are filled.
* A bottom **shop bar** that shows the chosen towers, previews their cost, and blocks interaction until the loadout is confirmed.
* A top-left **status panel** with money, lives, and the current wave, plus a separate Start/Restart button that appears near the panel once the loadout is confirmed.
* A top-right **tower details** window that displays range, damage, slow/splash stats, upgrade descriptions, and live sell values. Upgrade (`E`) and sell (`X`) hotkeys stay in sync with the buttons and dim when you cannot afford an action.
* A cursor-following **enemy hover card** that always shows the hovered enemy’s name and health for quick debugging.

If you want a bespoke layout, you can still duplicate the generated Gui objects in play mode, tweak them in Studio, and then update the script to match your custom hierarchy. The default skins are intentionally minimalist so you can ship immediately or treat them as a starting point for further styling.

## Extending Enemy Types & Waves

You can expand the roster and pacing without editing any gameplay scripts—just update the config modules inside `ReplicatedStorage/Modules/Config`.

### Adding a new enemy type

1. Open **`EnemyConfigs`**. Each key in the returned table (e.g. `Grunt`, `Runner`, `Tank`) defines an enemy archetype.
2. Duplicate an existing entry and change its fields:
   * `Name`: Label shown in the hover UI.
   * `ModelName`: The model to clone from `ReplicatedStorage/Assets/Enemies` (defaults to the key if omitted).
   * `Health`: Starting hit points.
   * `Speed`: How fast the enemy moves along the path (studs per second).
   * `Reward`: How much cash each player earns when this enemy dies.
   * `DebuffImmunities`: Optional table or array of status names that the enemy should ignore (e.g. `{ Slow = true }` or `{ "Explosion" }`).
   * Additional custom fields can be added; scripts ignore unknown keys you store for your own systems.
3. If the enemy uses a custom model, add it to `ReplicatedStorage/Assets/Enemies` and match the `ModelName` value.

#### Debuff immunities

Set `DebuffImmunities` on an enemy entry to make it shrug off specific status effects applied by towers. The value can be either an array of status names or a dictionary-style table with boolean flags. The wave service automatically normalizes everything to lowercase before checking the immunity list.

Two status strings ship in the default scripts:

* `Slow` &mdash; prevents the Frost Mage slow from applying.
* `Explosion` &mdash; blocks splash damage unless the enemy is the cannon's primary target, enabling shield formations that soak direct hits without sharing the blast.

Below are standalone examples that demonstrate the two built-in immunities. You can copy and adapt these snippets when creating your own archetypes:

```lua
EnemyConfigs.LightningBoss = {
    Name = "Storm Tyrant",
    ModelName = "LightningBoss",
    Health = 850,
    Speed = 12,
    Reward = 225,
    DebuffImmunities = { Slow = true },
}

EnemyConfigs.Shielder = {
    Name = "Bulwark Captain",
    ModelName = "Shielder",
    Health = 320,
    Speed = 9,
    Reward = 60,
    DebuffImmunities = { Explosion = true },
}
```

##### Combining multiple immunities

To make a single enemy resistant to several debuffs, include each status name in the `DebuffImmunities` table. Both dictionary-style and array-style declarations work, so use whichever fits your workflow. The example below shows an elite enemy that ignores both slow effects and untargeted explosions:

```lua
EnemyConfigs.ParagonChampion = {
    Name = "Paragon Champion",
    ModelName = "BossElite",
    Health = 1100,
    Speed = 11,
    Reward = 275,
    DebuffImmunities = {
        Slow = true,
        Explosion = true,
    },
    -- alternatively:
    -- DebuffImmunities = { "Slow", "Explosion" },
}
```

> In the sample content, both **Boss1** and **LightningBoss** ignore slow effects so Frost Mage towers cannot stall them, while the new **Shielder** archetype shrugs off splash damage unless directly targeted. Use the combined example above if you want a single enemy to benefit from both defenses.

##### Splitting enemies on death

Set `SplitChildren` (or the alias `SplitOnDeath`) on an enemy entry to automatically emit additional enemies the instant the original unit is destroyed. Each child entry can include:

* `Type` &mdash; the enemy key to spawn (required).
* `Count` &mdash; how many copies to emit (defaults to `1`).
* `ProgressOffset` &mdash; shifts the child forward/backward along the path relative to where the parent died.
* `ProgressSpacing` &mdash; extra spacing to apply between each child in the same entry so they do not stack.
* `OffsetRadius` or `PositionOffset` &mdash; optional world offsets to spread the new spawns around the parent.
* `PlaySpawnSound` &mdash; set to `true` if you want the child to reuse its configured `SpawnSound` when it appears (children are silent by default to avoid audio spam).

Children inherit the parent's current waypoint progress and immediately continue moving down the path. The helper accepts either an array of child definitions or a dictionary keyed by enemy type, which makes quick tweaks (like "spawn two Runners") painless.

```lua
EnemyConfigs.Broodmother = {
    Name = "Broodmother",
    ModelName = "Tank",
    Health = 320,
    Speed = 9,
    Reward = 95,
    SplitChildren = {
        -- Array style declaration
        {
            Type = "Runner",
            Count = 2,
            ProgressSpacing = 0.05,
            OffsetRadius = 3,
        },
        {
            Type = "Broodling",
            Count = 3,
            ProgressOffset = -0.04,
            ProgressSpacing = 0.05,
            PlaySpawnSound = true,
        },
        -- Dictionary style works too:
        -- Runner = 2,
        -- Broodling = { Count = 3, ProgressSpacing = 0.05 },
    },
}
```

The sample waves now include a late-game Broodmother pack so you can see the split behavior in action.

##### Stunning towers on death

Add `TowerStunOnDeath` (alias `StunTowersOnDeath`) to give an enemy a disabling shockwave when it dies. Towers caught inside the configured radius immediately stop firing, keep their current rotation, and gain a `Stunned` attribute until the timer expires. The wave service also plays a looping sound from each stunned tower so players know the defense is disabled.

Supported fields inside the stun table:

* `Radius` &mdash; distance (in studs) around the dying enemy that should be affected (required).
* `Duration` &mdash; how long the stun lasts in seconds (required).
* `Sound` or `StunSound` &mdash; optional sound descriptor to loop from every stunned tower. Use the same format as other sound fields (`rbxassetid://...`, a table of `Sound` properties, or a `Sound` instance).
* `SoundName` &mdash; optional custom name applied to the looping sound instance.
* `Loop` &mdash; set to `false` if you prefer a one-shot cue; the default automatically loops while the tower is stunned.
* `Freeze` &mdash; set to `false` to let towers keep rotating while stunned. By default towers are frozen in place and cannot turn until the effect ends.

```lua
EnemyConfigs.FrostWarden = {
    Name = "Frost Warden",
    ModelName = "FrostWarden",
    Health = 380,
    Speed = 10,
    Reward = 140,
    TowerStunOnDeath = {
        Radius = 14,
        Duration = 4.5,
        Sound = {
            SoundId = "rbxassetid://1234567896",
            Volume = 0.95,
        },
        SoundName = "FrostWardenStun",
    },
}
```

> Towers resume firing once the stun timer expires, and any looping sounds are automatically stopped and destroyed when the effect ends or the tower is sold.

### Creating or editing waves

1. Open **`WaveConfigs`**. The module now exposes a small helper named `AddWave` that registers each wave, assigns it both a numeric index, and stores optional metadata such as rewards or descriptions.
2. A wave is still a list of spawn groups. Each group can spawn one enemy type sequentially or mix several types at the same time:
   * For a **single-type group**, set `Type`, `Count`, and `Delay` (seconds to wait between each enemy; use `0` for no delay).
   * For a **multi-type group**, provide a `Streams` array. Each entry represents a continuous spawn stream for a single enemy type and supports its own timing. Specify `Type`, optional `Count`, and either an `Interval` (seconds between spawns) or `Rate` (spawns per second). Add `StartDelay` (or `InitialDelay`) to stagger when a stream begins, and set `Delay` on the group to pause before the next group starts.
3. Duplicate one of the `AddWave({ ... })` blocks (or insert a new one) to introduce additional waves. Change the `Name`, `Reward`, `Description`, or any custom metadata you want to track, then edit the `Groups` array to control the actual spawns.

```lua
WaveConfigs.AddWave({
    Name = "wave6",
    Reward = 180,
    Description = "Air support arrives alongside heavy shields.",
    Groups = {
        { Type = "Runner", Count = 20, Delay = 0.45 },
        {
            Streams = {
                { Type = "Runner", Count = 12, Interval = 0.6 },
                { Type = "Shielder", Count = 6, Interval = 0.9, StartDelay = 0.45 },
            },
            Delay = 1.4,
        },
    },
})
```

> Tip: keep the last wave challenging—clearing the final wave ends the game with a victory. You can add an unlimited number of waves, and any metadata you include remains accessible through `WaveConfigs.Definitions` for custom progression logic.

## Configuring Sound Effects

The shared [`SoundEffects` module](ServerScriptService/Modules/SoundEffects.lua) centralizes every audio cue so creators can attach custom sounds without editing gameplay logic. Each sound field accepts either:

* A plain string containing a `rbxassetid://` identifier.
* A table with `SoundId` plus any extra `Sound` properties (for example `Volume`, `PlaybackSpeed`, or `RollOffMaxDistance`).
* A pre-built `Sound` instance, which will be cloned before playback.

### Enemy spawn & death hooks

Add `SpawnSound` and/or `DeathSound` to an entry in [`EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua). The wave service plays the spawn clip from the enemy’s root part and moves death audio to an invisible anchor so it can finish even after the model is destroyed.

```lua
EnemyConfigs.Shielder = {
    Name = "Bulwark Captain",
    ModelName = "Shielder",
    Health = 320,
    Speed = 9,
    Reward = 60,
    DebuffImmunities = { Explosion = true },
    SpawnSound = {
        SoundId = "rbxassetid://1234567890",
        Volume = 0.8,
    },
    DeathSound = {
        SoundId = "rbxassetid://1234567891",
        Volume = 1.1,
    },
}
```

### Tower stun loops

Assign `Sound` (or `StunSound`) inside an enemy’s `TowerStunOnDeath` table to play a looping cue from every stunned tower while the effect is active. Sounds use the same descriptor format shown above and default to looping; include `Loop = false` inside the stun table if you only want a single playback.

### Tower fire sounds

Set `FireSound` on a tower inside [`TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua) to trigger audio each time the tower attacks. Upgrades can override the base sound by defining their own `FireSound` entry—otherwise the tower keeps using the previous value.

```lua
TowerConfigs.Cannon = {
    Name = "Cannon",
    ModelName = "Cannon",
    Cost = 250,
    Range = 22,
    Damage = 20,
    FireRate = 1.5,
    SplashRadius = 6,
    FireSound = {
        SoundId = "rbxassetid://2234567891",
        Volume = 1.2,
        PlaybackSpeed = 0.9,
    },
    Upgrades = {
        {
            Cost = 300,
            Damage = 28,
            FireSound = "rbxassetid://5566778899",
        },
    },
}
```

Leave any of these fields `nil` to disable the corresponding cue. The helper automatically destroys temporary parts/sounds once playback finishes, so repeated spawns and shots will not clutter the workspace.

## Gameplay Overview

* **Towers**: Archer (rapid single-target), Cannon (area splash), Frost Mage (slow + damage). Each tower includes two upgrade tiers with distinct stat boosts.
* **Loadouts**: Players pick three towers from the selection screen at the start (and after restarts). The shop only enables those three slots, so add new entries to `TowerConfigs` to expand the picker. Each tower can only occupy one slot—picking a tower that’s already assigned will move it to the active slot and free the previous one. The Start button remains hidden until you confirm the full three-tower loadout.
* **Enemies**: Grunts (balanced), Runners (fast, low HP), Tanks (slow, high HP), Shielders (soak direct hits and ignore untargeted splash damage), Broodmothers (split into Broodlings and Runners when slain), Broodlings (nimble hatchlings spawned by Broodmothers), Frost Wardens (collapse into tower-stunning pulses), plus two boss variants (Boss1 and LightningBoss) that ignore slow debuffs. These samples live in [`EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua); add more entries there to introduce new archetypes. Defeating enemies awards cash for all players.
* **Waves**: Eight sample waves live in [`WaveConfigs.lua`](ReplicatedStorage/Modules/Config/WaveConfigs.lua). Add or edit entries there to change pacing—the system automatically starts the next wave when the current one clears, and players can press `Start` before wave 1. Groups that define `Streams` will emit multiple enemy types simultaneously with independent spawn cadences, and the final sample wave highlights Frost Wardens stunning nearby towers when they fall.
* **Economy & Lives**: Players begin with $350 and 30 lives. Lives decrease when enemies reach the exit. Losing all lives ends the game for everyone; clearing every wave triggers victory.
* **Tower management**: Press **`X`** while placing to cancel without spending money. Select one of your towers and press **`E`** to buy the next upgrade or **`X`** to sell it for **50%** of the total amount invested (base cost + upgrades).
* **Enemy info**: Hovering over an enemy shows a floating card beside the cursor with that enemy’s name and HP. No extra billboard setup is required while testing.

## Testing Checklist

1. Publish the game or run **Play** in Studio.
2. When Play starts, the auto-generated HUD should appear with tower slots, money, lives, and a wave counter. The Start button should be hidden for now.
3. Use the tower selection screen that pops up to assign three different towers to the slots and confirm the loadout. The shop buttons should update to the towers you chose, and the Start button should appear near the status panel.
4. Click a tower button, position the preview over the ground, and click to place it. Towers should appear under the `workspace.Towers` folder.
5. Start the waves. Enemies spawn at `EnemySpawn`, follow your waypoint path, and take damage from towers. Groups that define a `Streams` array release several enemy types at once, each honoring its own spawn interval.
6. Press **`X`** while aiming the preview to cancel placement without spending money.
7. Verify money updates when enemies are defeated, towers deal damage as expected, and that lives decrease when an enemy reaches the exit.
8. With one of your towers selected, press **`E`** to purchase an upgrade (if available) and press **`X`** to sell it. Confirm upgrade costs apply and 50% refunds are awarded on sale.

Enjoy customizing the visuals, adding sound effects, or expanding with new towers and waves!
