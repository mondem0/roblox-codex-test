# Roblox Tower Defense Kit

This repository contains Luau scripts and configuration modules for a complete tower defense prototype. Each section below explains **exactly** where to place the files inside Roblox Studio, how to assemble the map, and how to wire up the gameplay systems.

## File Placement Guide

Create the folders in **Explorer** exactly as listed. If a folder already exists, reuse it. All scripts are plain `Script` or `LocalScript` objects unless noted otherwise.

### ReplicatedStorage
1. Create a `Folder` named `Modules`.
2. Inside `Modules`, add a `Folder` named `Config`.
3. Insert a `ModuleScript` named **`TowerConfigs`** and paste the contents of [`ReplicatedStorage/Modules/Config/TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua).
4. Insert a `ModuleScript` named **`EnemyConfigs`** and paste the contents of [`ReplicatedStorage/Modules/Config/EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua).
5. In `Modules`, add a `ModuleScript` named **`PathService`** and paste [`ReplicatedStorage/Modules/PathService.lua`](ReplicatedStorage/Modules/PathService.lua).
6. Create a `Folder` named `Remotes`. You do **not** need to add RemoteEvents manually; [`ServerScriptService/GameManager.server.lua`](ServerScriptService/GameManager.server.lua) will generate them if missing.

### ServerScriptService
1. Add a `Folder` called `Modules`.
2. Inside that folder create two `ModuleScript` objects:
   * **`TowerService`** → [`ServerScriptService/Modules/TowerService.lua`](ServerScriptService/Modules/TowerService.lua)
   * **`WaveService`** → [`ServerScriptService/Modules/WaveService.lua`](ServerScriptService/Modules/WaveService.lua)
3. Add a `Script` named **`GameManager`** in `ServerScriptService` and paste [`ServerScriptService/GameManager.server.lua`](ServerScriptService/GameManager.server.lua).

### StarterPlayerScripts
1. Inside `StarterPlayer > StarterPlayerScripts`, insert a `LocalScript` named **`TowerClient`**.
2. Paste [`StarterPlayer/StarterPlayerScripts/TowerClient.client.lua`](StarterPlayer/StarterPlayerScripts/TowerClient.client.lua).

The UI shown in the client script is intentionally minimalist. You are free to restyle or replace it with your own ScreenGui, provided you keep the same object names (`Shop`, `Status`, etc.) or adapt the script accordingly.

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

1. **Create an Assets folder**: Inside `ReplicatedStorage`, add a `Folder` named **`Assets`**. Within it, create two folders: **`Towers`** and **`Enemies`**.
2. **Tower models**:
   * Parent each custom tower `Model` to `ReplicatedStorage/Assets/Towers` and name it after the `ModelName` field in [`TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua) (defaults: `Archer`, `Cannon`, `FrostMage`).
   * Include a `Base` part (set as `PrimaryPart`, anchored, centered on the ground), plus a `Head` assembly that pivots toward enemies. The `Head` can be a single `Part` **or** a `Model` that contains multiple pieces; just make sure the model’s `PrimaryPart` is the piece that should rotate. Keep every child anchored (or welded to the pivot) so the script can reposition them together.
   * Add a thin `Barrel` `Part` that sticks out of the front of the head. You can leave it as a sibling of the head or parent it under the head model—the server will locate it automatically. Aim the barrel down the head’s negative Z-axis so it points forward when the tower spawns.
   * Anchor every part and disable collisions so placement remains smooth.
   * Update the matching entry in [`TowerConfigs.lua`](ReplicatedStorage/Modules/Config/TowerConfigs.lua) with a `BaseSize` vector that reflects your `Base` part’s dimensions (X and Z are used for the preview square and spacing checks). Towers with splash damage can also set `SplashColor` to tint their explosion effect.
3. **Enemy models**:
   * Parent each enemy `Model` to `ReplicatedStorage/Assets/Enemies` using the names in [`EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua) (`Grunt`, `Runner`, `Tank`).
   * Provide a `HumanoidRootPart` (or assign a `PrimaryPart`) centered on the character plus a `Head` part. Anchor all geometry and disable collisions so enemies glide along the path.
4. **Adjusting names**: If you use different model names, update the corresponding `ModelName` value in the config table.
5. **Optional flair**: Accessories, meshes, particles, or lights parented to the model will automatically replicate when towers or enemies spawn.

## Gameplay Overview

* **Towers**: Archer (rapid single-target), Cannon (area splash), Frost Mage (slow + damage). Each tower includes two upgrade tiers with distinct stat boosts.
* **Enemies**: Grunts (balanced), Runners (fast, low HP), Tanks (slow, high HP). Defeating enemies awards cash for all players.
* **Waves**: Five handcrafted waves. The system automatically starts the next wave when the current one clears. Players can also press the `Start` button before wave 1.
* **Economy & Lives**: Players begin with $350 and 30 lives. Lives decrease when enemies reach the exit. Losing all lives ends the game for everyone; clearing every wave triggers victory.
* **Tower management**: Press **`X`** while placing to cancel without spending money. Select one of your towers and press **`E`** to buy the next upgrade or **`X`** to sell it for **50%** of the total amount invested (base cost + upgrades).

## Testing Checklist

1. Publish the game or run **Play** in Studio.
2. Confirm the UI appears with tower buttons, money, lives, wave counter, and a `Start` button.
3. Click a tower button, position the preview over the ground, and click to place it. Towers should appear under the `workspace.Towers` folder.
4. Start the waves. Enemies spawn at `EnemySpawn`, follow your waypoint path, and take damage from towers.
5. Press **`X`** while aiming the preview to cancel placement without spending money.
6. Verify money updates when enemies are defeated, towers deal damage as expected, and that lives decrease when an enemy reaches the exit.
7. With one of your towers selected, press **`E`** to purchase an upgrade (if available) and press **`X`** to sell it. Confirm upgrade costs apply and 50% refunds are awarded on sale.

Enjoy customizing the visuals, adding sound effects, or expanding with new towers and waves!
