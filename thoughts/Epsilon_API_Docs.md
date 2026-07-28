# Epsilon Custom API & Events Documentation

This document outlines the custom APIs and event systems discovered within the Epsilon project codebase. It covers the native client API (`C_Epsilon`), the Lua wrapper library (`EpsilonLib`), and custom events.

## 1. Native Client API (`C_Epsilon`)

These functions are provided directly by the modified game client. They are often accessed via the global `C_Epsilon` table.

### Phase & Permissions
*   **`C_Epsilon.GetPhaseId()`**
    *   **Returns:** `number` (Phase ID)
    *   **Description:** Returns the ID of the current phase the player is in. Often wrapped in `tonumber()` in existing code.
*   **`C_Epsilon.IsOwner()`**
    *   **Returns:** `boolean`
    *   **Description:** Returns `true` if the player owns the current phase.
*   **`C_Epsilon.IsOfficer()`**
    *   **Returns:** `boolean`
    *   **Description:** Returns `true` if the player is an officer in the current phase.
*   **`C_Epsilon.IsMember()`**
    *   **Returns:** `boolean`
    *   **Description:** Returns `true` if the player is a member of the current phase.
*   **`C_Epsilon.IsDM`**
    *   **Type:** `boolean`
    *   **Description:** A flag (or check) indicating if the player has DM privileges.

### Data Storage
*   **`C_Epsilon.SetPhaseAddonData(key, value)`**
    *   **Arguments:** `key` (string), `value` (string)
    *   **Description:** Saves a string value associated with a specific key for the current phase. This data is synced to the server.
*   **`C_Epsilon.GetPhaseAddonData(key)`**
    *   **Arguments:** `key` (string)
    *   **Returns:** `string`
    *   **Description:** Retrieves a saved string value for the current phase.

### World & Objects
*   **`C_Epsilon.GetPosition()`**
    *   **Returns:** `x, y, z, mapID`
    *   **Description:** Returns the current position and map ID of the player.
*   **`C_Epsilon.RotateObject(guidLow, guidHigh, rotX, rotY, rotZ, scale)`**
    *   **Arguments:** `guidLow`, `guidHigh`, `rotX`, `rotY`, `rotZ`, `scale`
    *   **Description:** Rotates and scales a game object client-side.
*   **`C_Epsilon.VirtualEquip(itemEntry)`**
    *   **Arguments:** `itemEntry` (number)
    *   **Description:** Visually equips an item on the player (client-side only).

### Database Queries
*   **`C_Epsilon.GODI_Search(filter)`**
    *   **Arguments:** `filter` (string)
    *   **Description:** Searches for game objects matching the filter. Returns count for iteration.
*   **`C_Epsilon.GODI_RetrieveSearch(index)`**
    *   **Description:** Retrieves a specific result from the previous GODI search.
*   **`C_Epsilon.SoundKit_Search(filter)`**
    *   **Description:** Searches for sounds matching the filter.

### System
*   **`C_Epsilon.RunPrivileged(script)`**
    *   **Arguments:** `script` (string)
    *   **Description:** Executes a Lua script string with elevated privileges (bypassing standard Blizzard protection).
*   **`C_Epsilon.ShowMenu()`**
    *   **Description:** Opens the main Epsilon server menu.

---

## 2. Library API (`EpsilonLib`)

The `EpsilonLib` addon (often aliased as `EpsiLib`) wraps the native API and provides event handling utilities.

### Core
*   **`EpsilonLib` (or `EpsiLib`)**
    *   The main global table for the library.
*   **`EpsiLib.C_API`**
    *   Contains a copy of the `C_Epsilon` table.

### Server Communication
*   **`EpsiLib.Server.server.send(suffix, message)`**
    *   **Arguments:** `suffix` (string), `message` (string)
    *   **Description:** Sends a message to the server via `CHAT_MSG_ADDON` with the prefix `EPSILON_` + `suffix`.
*   **`EpsiLib.Server.server.receive(suffix, callback)`**
    *   **Arguments:** `suffix` (string), `callback` (function)
    *   **Description:** Registers a function to handle messages from the server with the specific `suffix`.
    *   **Callback Signature:** `function(message, channel, sender)`

### Event Manager
*   **`EpsiLib.EventManager:Register(event, callback, runOnce)`**
    *   **Arguments:** `event` (string), `callback` (function), `runOnce` (boolean, optional)
    *   **Description:** Registers a listener for standard WoW events or custom Epsilon events.
*   **`EpsiLib.EventManager:RegisterSimpleCommandWatcher(pattern, callback)`**
    *   **Arguments:** `pattern` (string), `callback` (function)
    *   **Description:** Triggers the callback when a system chat message matches the given pattern.

---

## 3. Custom Events

### `EPSILON_PHASE_CHANGE`
*   **Trigger:** Fired when the player changes phases.
*   **Usage:**
    ```lua
    EpsilonLib.EventManager:Register("EPSILON_PHASE_CHANGE", function(self, event, phaseID)
        print("Joined phase:", phaseID)
    end)
    ```

### Server Messages (`EPSILON_*`)
*   **Transport:** `CHAT_MSG_ADDON`
*   **Prefix:** `EPSILON_`
*   **Handling:** Use `EpsiLib.Server.server.receive` to handle specific message suffixes.
*   **Example Suffixes Found:**
    *   `DSPLY`: Display related messages.

---

## 4. Usage Examples

### checking Permissions
```lua
if C_Epsilon.IsOwner() or C_Epsilon.IsOfficer() then
    -- Allow editing
end
```

### Saving Phase Data
```lua
local myKey = "MY_ADDON_DATA"
local data = "Some serialized string"
C_Epsilon.SetPhaseAddonData(myKey, data)
```

### Rotating an Object
```lua
-- Rotates object with GUID parts low/high to x, y, z rotation with scale
C_Epsilon.RotateObject(guidLow, guidHigh, rotX, rotY, rotZ, scale)
```
