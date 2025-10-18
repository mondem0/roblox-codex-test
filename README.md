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

Create a `Folder` named **`Assets`** inside `ReplicatedStorage` (if you haven't already for the models) and add a subfolder called **`UI`**. Place your UI templates there as described in [Custom UI Templates](#custom-ui-templates); the client script clones those layouts into each player's `PlayerGui`.

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

1. **Create an Assets folder**: Inside `ReplicatedStorage`, add a `Folder` named **`Assets`**. Within it, create three folders: **`Towers`**, **`Enemies`**, and **`UI`**.
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

## Custom UI Templates

Design your own interface once and let the client script clone it for every player:

1. Inside `ReplicatedStorage/Assets/UI`, create a **`ScreenGui`** named **`TowerHUD`**. This layout is copied into each player’s `PlayerGui` when they join.
2. Give the `TowerHUD` three top-level children (names are important):
   * **`Shop`** – any Frame/ScrollingFrame you like. Add one `TextButton` per tower and set the button’s `TowerType` attribute (string) to match the key in `TowerConfigs` (e.g. `Archer`). If you want to preserve your custom text, set the button’s `AutoText` attribute to `false`; otherwise the script will label it as “Name | $Cost”.
   * **`Status`** – holds the HUD labels. Add `TextLabel`s named `MoneyLabel`, `LivesLabel`, and `WaveLabel`, plus a `TextButton` named `StartButton`. The script updates the text automatically; set `AutoText = false` and/or `AutoStyle = false` on `StartButton` if you prefer to manage the label or colors yourself.
   * **`TowerDetails`** – the inspection panel. Include `TextLabel`s named `TowerNameLabel`, `TowerLevelLabel`, `TowerStatsLabel`, `OwnershipLabel`, and `UpgradeDescriptionLabel`, plus buttons named `UpgradeButton` and `SellButton`. Feel free to restyle fonts, colors, and layout—the script only fills in the text and toggles visibility.
3. To customize the hover tooltip, add a **GuiObject** (for example a `Frame` or `TextLabel`) or an entire **`ScreenGui`** named **`EnemyHoverTemplate`** under `ReplicatedStorage/Assets/UI`. Include `TextLabel`s named `NameLabel` and `HealthLabel` (or a single `TextLabel` named `InfoLabel`). The LocalScript clones this UI, keeps your colors, and positions it near the player’s cursor while hovering an enemy. Optional `OffsetX`/`OffsetY` number attributes on the root GuiObject let you tweak the cursor offset in pixels.
4. Add a GuiObject named **`PlayerTowerPriceLabels`** anywhere inside `TowerHUD` if you want hover pricing. Place (and style) `TextLabel`s named `UpgradePriceLabel` and `SellPriceLabel` inside it. The script hides this container by default, updates the text with your tower’s next upgrade cost and sell refund, and shows it whenever the player hovers their mouse over a tower they own. Position it wherever you like in Studio—the script only toggles visibility and text.
5. You can add additional GUI elements (wave timers, ability buttons, etc.) to `TowerHUD`; they will clone along with everything else. Just avoid naming conflicts with the reserved objects listed above.
The scripts leave your color choices intact—they only update text, toggle visibility, and enable/disable buttons based on game state. If something is missing, the client logs a warning instead of generating fallback UI, so keep the names above consistent.




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
2. A wave is a list of spawn groups. Each group defines:
   * `Type`: Key from `EnemyConfigs`.
   * `Count`: How many to spawn in that group.
   * `Delay`: Seconds between each enemy in the group.
3. Append a new wave (or edit existing ones) to change pacing. Use as many groups per wave as you like.

```lua
table.insert(WaveConfigs, {
    { Type = "Runner", Count = 20, Delay = 0.45 },
    { Type = "Shielder", Count = 4, Delay = 1.6 },
})
```

> Tip: keep the last wave challenging—clearing the final wave ends the game with a victory. You can add an unlimited number of waves.

## Gameplay Overview

* **Towers**: Archer (rapid single-target), Cannon (area splash), Frost Mage (slow + damage). Each tower includes two upgrade tiers with distinct stat boosts.
* **Enemies**: Grunts (balanced), Runners (fast, low HP), Tanks (slow, high HP). These samples live in [`EnemyConfigs.lua`](ReplicatedStorage/Modules/Config/EnemyConfigs.lua); add more entries there to introduce new archetypes. Defeating enemies awards cash for all players.
* **Waves**: Five sample waves live in [`WaveConfigs.lua`](ReplicatedStorage/Modules/Config/WaveConfigs.lua). Add or edit entries there to change pacing—the system automatically starts the next wave when the current one clears, and players can press `Start` before wave 1.
* **Economy & Lives**: Players begin with $350 and 30 lives. Lives decrease when enemies reach the exit. Losing all lives ends the game for everyone; clearing every wave triggers victory.
* **Tower management**: Press **`X`** while placing to cancel without spending money. Select one of your towers and press **`E`** to buy the next upgrade or **`X`** to sell it for **50%** of the total amount invested (base cost + upgrades).
* **Enemy info**: Hovering over an enemy shows your `EnemyHoverTemplate` UI beside the cursor with that enemy’s name and HP—no default billboard is spawned. Edit the template in `ReplicatedStorage/Assets/UI` to restyle the display.

## Testing Checklist

1. Publish the game or run **Play** in Studio.
2. Confirm the UI appears with tower buttons, money, lives, wave counter, and a `Start` button.
3. Click a tower button, position the preview over the ground, and click to place it. Towers should appear under the `workspace.Towers` folder.
4. Start the waves. Enemies spawn at `EnemySpawn`, follow your waypoint path, and take damage from towers.
5. Press **`X`** while aiming the preview to cancel placement without spending money.
6. Verify money updates when enemies are defeated, towers deal damage as expected, and that lives decrease when an enemy reaches the exit.
7. With one of your towers selected, press **`E`** to purchase an upgrade (if available) and press **`X`** to sell it. Confirm upgrade costs apply and 50% refunds are awarded on sale.

Enjoy customizing the visuals, adding sound effects, or expanding with new towers and waves!
