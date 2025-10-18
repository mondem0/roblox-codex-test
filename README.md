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
2. Inside that folder create two `ModuleScript` objects:
   * **`TowerService`** → [`ServerScriptService/Modules/TowerService.lua`](ServerScriptService/Modules/TowerService.lua)
   * **`WaveService`** → [`ServerScriptService/Modules/WaveService.lua`](ServerScriptService/Modules/WaveService.lua)
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
   * Optional extra fields (like custom slow resistance) can be added; scripts ignore unknown keys.
3. If the enemy uses a custom model, add it to `ReplicatedStorage/Assets/Enemies` and match the `ModelName` value.

```lua
EnemyConfigs.Shielder = {
    Name = "Shielder",
    ModelName = "Shielder",
    Health = 220,
    Speed = 10,
    Reward = 45,
}
```

### Creating or editing waves

1. Open **`WaveConfigs`**. The module returns an array where each element represents a wave.
2. A wave is a list of spawn groups. Each group can be one of the following:
   * **Single-type group** – use `Type`, `Count`, and `Delay`. Add `BatchSize` *(optional)* to emit several of that same enemy each batch.
   * **Multi-type group** – use `Types` (an array) to list the enemies that should appear at the same time. Each entry needs a `Type` and can include a `Count` (defaults to `1`). Use `Repeat` (or `Count`) on the group to decide how many cycles to run, and `Delay` to wait between each cycle.
3. Append a new wave (or edit existing ones) to change pacing. Combine single-type, batch, and multi-type groups for the cadence you want.

```lua
table.insert(WaveConfigs, {
    { Type = "Runner", Count = 20, Delay = 0.45, BatchSize = 4 },
    {
        Types = {
            { Type = "Runner" },
            { Type = "Shielder" },
        },
        Repeat = 3,
        Delay = 0.9,
    },
})
```

> Tip: keep the last wave challenging—clearing the final wave ends the game with a victory. You can add an unlimited number of waves.

## Gameplay Overview

* **Towers**: Archer (rapid single-target), Cannon (area splash), Frost Mage (slow + damage). Each tower includes two upgrade tiers with distinct stat boosts.
* **Loadouts**: Players pick three towers from the selection screen at the start (and after restarts). The shop only enables those three slots, so add new entries to `TowerConfigs` to expand the picker. Each tower can only occupy one slot—picking a tower that’s already assigned will move it to the active slot and free the previous one. The Start button remains hidden until you confirm the full three-tower loadout.
* **Enemies**: Grunts (balanced), Runners (fast, low HP), Tanks (slow, high HP). These samples live in [`EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua); add more entries there to introduce new archetypes. Defeating enemies awards cash for all players.
* **Waves**: Five sample waves live in [`WaveConfigs.lua`](ReplicatedStorage/Modules/Config/WaveConfigs.lua). Add or edit entries there to change pacing—the system automatically starts the next wave when the current one clears, and players can press `Start` before wave 1. Use `BatchSize` for multi-spawns of a single enemy and `Types`/`Repeat` groups to launch mixed enemy squads at once.
* **Economy & Lives**: Players begin with $350 and 30 lives. Lives decrease when enemies reach the exit. Losing all lives ends the game for everyone; clearing every wave triggers victory.
* **Tower management**: Press **`X`** while placing to cancel without spending money. Select one of your towers and press **`E`** to buy the next upgrade or **`X`** to sell it for **50%** of the total amount invested (base cost + upgrades).
* **Enemy info**: Hovering over an enemy shows a floating card beside the cursor with that enemy’s name and HP. No extra billboard setup is required while testing.

## Testing Checklist

1. Publish the game or run **Play** in Studio.
2. When Play starts, the auto-generated HUD should appear with tower slots, money, lives, and a wave counter. The Start button should be hidden for now.
3. Use the tower selection screen that pops up to assign three different towers to the slots and confirm the loadout. The shop buttons should update to the towers you chose, and the Start button should appear near the status panel.
4. Click a tower button, position the preview over the ground, and click to place it. Towers should appear under the `workspace.Towers` folder.
5. Start the waves. Enemies spawn at `EnemySpawn`, follow your waypoint path, and take damage from towers. Groups that set `BatchSize` above 1 will spawn several of the same enemy at once, while groups that define `Types` will spawn those enemies together each cycle.
6. Press **`X`** while aiming the preview to cancel placement without spending money.
7. Verify money updates when enemies are defeated, towers deal damage as expected, and that lives decrease when an enemy reaches the exit.
8. With one of your towers selected, press **`E`** to purchase an upgrade (if available) and press **`X`** to sell it. Confirm upgrade costs apply and 50% refunds are awarded on sale.

Enjoy customizing the visuals, adding sound effects, or expanding with new towers and waves!
