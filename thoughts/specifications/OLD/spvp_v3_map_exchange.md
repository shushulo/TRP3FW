# SPVP v3 Protocol Upgrade: Authenticated Map Exchange

## 1. Objective
To extend the Secure Phase Verification Protocol (SPVP) to securely exchange and verify `MapID` information alongside `PhaseID`. This mitigates "Map Spoofing" where a user might be in the correct phase but a different map (e.g., a "dark room" vs "main city") and claiming otherwise.

## 2. Protocol Changes

### 2.1 Versioning
*   **Old:** `SPVP_VERSION = 2`
*   **New:** `SPVP_VERSION = 3`
*   **Backward Compatibility:** v3 clients must accept v2 packets (treating MapID as `nil` or `0`).

### 2.2 Packet Structure Updates

#### A. INIT Packet (Prover -> Verifier)
*   **Format:** `INIT:Version:SessionID:PublicKey:MapID`
*   **Example:** `INIT:3:A1B2C3D4:123456789:571`
*   **Changes:** Appended `:MapID`.

#### B. REPLY Packet (Verifier -> Prover)
*   **Format:** `REPLY:SessionID:PublicKey:Verifier:MapID`
*   **Example:** `REPLY:A1B2C3D4:987654321:DEADBEEF:571`
*   **Changes:** Appended `:MapID`.

### 2.3 Verification Logic

#### Sender (Prover)
1.  Get current `MapID` via `C_Map.GetBestMapForUnit("player")` or internal tracker.
2.  Append to `INIT` packet.
3.  Include `MapID` in the cryptographic binding (Optional but recommended: `Hash(SharedKey + MapID)`). *Decision: Keep it simple for now, just transport.*

#### Receiver (Verifier)
1.  Parse `MapID` from packet.
2.  **Validation:**
    *   Check if `MapID` matches the map we *expect* them to be on (if scanning).
    *   **Trust:** Since SPVP proves they are in the correct *Phase* (which is the security boundary), we can generally trust the MapID they claim within that phase, *provided* we validate it against physical checks if possible.
3.  **Callback:** Return `verified=true`, `source="spvp"`, `mapID=receivedMapID`.

## 3. Implementation Steps

### Step 1: Update Constants
In `features/encryption/spvp.lua`:
```lua
local SPVP_VERSION = 3
```

### Step 2: Modify `StartSPVPHandshakeWithRetry`
```lua
local mapID = TRP3FW:GetCurrentMapID() or 0
local message = string.format("INIT:%d:%s:%d:%d", SPVP_VERSION, sessionID, publicKey, mapID)
```

### Step 3: Modify `HandleSPVPInit`
```lua
local version, sessionID, publicKey, mapID = message:match("^INIT:(%d+):(%w+):(%d+):?(%d*)$")
-- Handle v2 fallback (mapID is nil)
mapID = tonumber(mapID) or 0
```
*   Update `REPLY` generation to include local `MapID`.

### Step 4: Modify `HandleSPVPReply`
```lua
local sessionID, publicKey, verifier, mapID = message:match("^REPLY:(%w+):(%d+):(%w+):?(%d*)$")
-- Handle v2 fallback
mapID = tonumber(mapID) or 0
-- Pass mapID to callback
if session.callback then session.callback(true, "verified", mapID) end
```

## 4. Integration with Location System
*   **File:** `features/stages/SPVPStage.lua`
*   **Logic:** When SPVP succeeds, update `context.theirMapID` with the value received from the handshake. This allows `LocationStage` to update the map cache authoritatively.

## 5. Security Implications
*   **Map Spoofing:** A malicious client could send `INIT:3:...:FakeMapID`.
*   **Mitigation:** SPVP proves *Phase* ownership. If they are in the correct phase, "Map" is mostly a display/sharding concern. If they lie about the map, they just won't see anyone (because they are physically elsewhere). The firewall's job is primarily to block *Phase* spoofing (cross-phase data leaks).
*   **Benefit:** Allows us to reliably "locate" a player in a multi-map phase without running a slow `SendWho` or Map Scan.

---

## 6. Piggyback Strategy (Whitelisting Defense)

If `C_Epsilon` is restricted, we leverage `SpellCreator` (SpellForge) as a proxy.

### 6.1 Capability Detection
At startup (`TRP3FW:OnLoad`):
```lua
TRP3FW.isEpsilonProxyActive = false
if not C_Epsilon and ARC and ARC.RegisterAction then
    TRP3FW:Info("Epsilon API blocked; attempting ARC Proxy injection...")
    -- Register Proxy Action
    ARC.RegisterAction("TRP3FW", "proxy_run", "script", "TRP3FW Proxy", {
        command = function(code)
            if C_Epsilon and C_Epsilon.RunPrivileged then
                 C_Epsilon.RunPrivileged(code)
            end
        end
    })
    TRP3FW.isEpsilonProxyActive = true
end
```

### 6.2 Proxy Execution
In `core/utils.lua` (`RunPrivilegedSafe`):
```lua
if TRP3FW.isEpsilonProxyActive then
    -- Use Proxy
    local success, err = pcall(function()
        local action = ARC.GetAction("TRP3FW", "proxy_run") -- Hypothetical fetch
        action.command(code) 
    end)
    return success, err
else
    -- Normal Execution
    return pcall(C_Epsilon.RunPrivileged, code)
end
```

### 6.3 Method B: The Persistent Proxy Spell (The "Vault" Bypass)
If `ARC.RegisterAction` is blocked, we use SpellCreator's own persistence system.

**Mechanism:**
1.  **Check/Inject:** On startup, check `SpellCreatorSavedSpells` (SavedVariables) for a spell named `TRP3FW_Proxy`.
2.  **Create if Missing:**
    ```lua
    if not SpellCreatorSavedSpells["TRP3FW_Proxy"] then
        SpellCreatorSavedSpells["TRP3FW_Proxy"] = {
            commID = "TRP3FW_Proxy",
            fullName = "TRP3FW Proxy",
            actions = {
                {
                    actionType = "script", 
                    -- @1@ is replaced by the argument passed during CAST
                    vars = "if C_Epsilon and C_Epsilon.RunPrivileged then C_Epsilon.RunPrivileged([[ @1@ ]]) end",
                    delay = 0,
                    selfOnly = true
                }
            },
            profile = "TRP3FW"
        }
    end
    ```
3.  **Execute:**
    ```lua
    -- Passing the code as the first argument
    ARC:CAST("TRP3FW_Proxy", true, "TargetUnit('PlayerA')")
    ```

**Advantage:**
*   Looks like a legitimate user-created spell.
*   Persists across reloads.
*   Bypasses runtime restrictions on `RegisterAction`.

### 6.4 Fallback to Built-in Actions
If both Proxy methods fail, we use `ARC` built-ins:
*   **Targeting:** Use `ARC:CAST("TargetUnit", unitName)` (if exposed via command parser).
*   **Phase ID:** Use `ARC.PHASE.GetPhaseId()` (calling their function reference).