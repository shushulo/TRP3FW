# Epsilon Compatibility Diagnostics Manual

This guide helps you identify *exactly* how the Epsilon API has changed and which mitigation strategies to deploy.

## Phase 1: The "Existence" Check (Catastrophic Failure)
**Goal:** Determine if the API still exists or has been renamed/hidden.

1.  **Check Global Table:**
    ```lua
    /dump C_Epsilon
    ```
    *   **Success:** Prints a table. (Proceed to Phase 2)
    *   **Failure:** Prints `nil`. -> **Mitigation:** Whitelisting (Proxy Strategy) required.

2.  **Check RunPrivileged:**
    ```lua
    /dump C_Epsilon.RunPrivileged
    ```
    *   **Success:** Prints `function: 0x...`
    *   **Failure:** Prints `nil`. -> **Mitigation:** Fallback to Native API (if they replaced it with `CastSpell`) or Proxy.

---

## Phase 2: The "Functionality" Check (Sanitization & Whitelisting)
**Goal:** Determine if we can run code, or if specific functions are blocked.

1.  **Test Basic Execution:**
    ```lua
    /run C_Epsilon.RunPrivileged('print("Hello from TRP3FW Test")')
    ```
    *   **Success:** You see "Hello from TRP3FW Test" in chat.
    *   **Failure:** Silent or Error. -> **Diagnosis:** Rate Limit or Sanitization.

2.  **Test "Dangerous" Function (SendWho):**
    ```lua
    /run C_Epsilon.RunPrivileged('C_FriendList.SendWho("Self")')
    ```
    *   **Success:** WHO window opens or updates.
    *   **Failure:** Nothing happens. -> **Diagnosis:** Function Whitelisting (Circuit Breaker needed).

3.  **Test "Obfuscation" Bypass:**
    If Test 2 failed, try this:
    ```lua
    /run C_Epsilon.RunPrivileged('local f=C_FriendList; local s="Send".."Who"; f[s]("Self")')
    ```
    *   **Success:** They are using lazy string matching. -> **Mitigation:** Enable Obfuscation.
    *   **Failure:** They are using AST analysis or Sandboxing. -> **Mitigation:** Persistent Proxy Spell.

---

## Phase 3: The "Stress" Check (Rate Limiting)
**Goal:** Determine the new Rate Limit.

1.  **Burst Test (Manual):**
    Create a macro:
    ```lua
    /run for i=1,10 do C_Epsilon.RunPrivileged('print("Ping "..i)') end
    ```
    *   **Result A (No Limit):** You see Ping 1 through 10 instantly.
    *   **Result B (Hard Cap):** You see Ping 1 through 5, then silence. -> **Limit:** 5 calls/sec (or burst size).
    *   **Result C (Throttle):** You see Ping 1... (pause) ... Ping 2. -> **Limit:** 1 call/sec. -> **Mitigation:** School Bus Batching.

---

## Phase 4: The "Proxy" Check (SpellForge Bypass)
**Goal:** Verify if we can piggyback off SpellCreator.

1.  **Check ARC API:**
    ```lua
    /dump ARC
    /dump ARC.RegisterAction
    ```
    *   **Success:** Tables exist.

2.  **Test Injection:**
    ```lua
    /run ARC.RegisterAction("TEST", "test_key", "script", "Test", { command = function() print("Proxy Works") end })
    /run ARC:CAST("test_key")
    ```
    *   **Success:** "Proxy Works" prints. -> **Mitigation:** Valid backup plan.

3.  **Test Persistent Spell (The Vault):**
    *   Open SpellCreator Vault.
    *   Create a Personal Spell "TRP3FW_Test".
    *   Action: Script -> `print("Vault Works")`.
    *   Save & Cast.
    *   **Success:** "Vault Works" prints. -> **Mitigation:** Persistent Proxy Spell is viable.

---

## Phase 5: Map Check Bypasses (If SendWho is Dead)
**Goal:** Find a way to verify location without `SendWho`.

1.  **Test 1: The Friend Hack**
    *   Pick a player in the same phase but far away (not targetable via client).
    *   Run:
    ```lua
    /run C_FriendList.AddFriend("TargetName"); C_Timer.After(1, function() local info = C_FriendList.GetFriendInfo("TargetName"); print("Zone:", info and info.area); C_FriendList.RemoveFriend("TargetName") end)
    ```
    *   **Success:** Prints the zone name. -> **Mitigation:** Implement "Friend List Scanner".
    *   **Failure:** Prints `nil` or "Zone: nil".

2.  **Test 2: Server-Side Target Info**
    *   We need to see if the server environment can access target data that the client can't.
    *   Run:
    ```lua
    /run C_Epsilon.RunPrivileged('FocusUnit("TargetName"); print("Focus Zone:", GetZoneText())')
    ```
    *   **Note:** `GetZoneText` usually returns *Player's* zone. If this prints *your* zone, it failed.
    *   **Try:** `UnitPosition`:
    ```lua
    /run C_Epsilon.RunPrivileged('FocusUnit("TargetName"); local y,x,z,map = UnitPosition("focus"); print("Focus Map:", map)')
    ```
    *   **Success:** Prints a map ID different from yours (if they are elsewhere). -> **Mitigation:** Server-Side Position Check.

3.  **Note on Minimap Tracking:**
    *   Minimap "blips" (Track Humanoids) are **NOT** accessible via Lua API.

4.  **Test 3: Map Scan (Passive/Broadcast)**
    *   If `SendWho` is dead, this is the primary fallback.
    *   Open your World Map.
    *   Run:
    ```lua
    /run TRP3_API.MapScannersManager.launch("playerScan")
    ```
    *   **Success:** You see "Scan" messages in chat or TRP3 map dots appear. -> **Mitigation:** Force Map Scan fallback.

---

## Phase 6: The Profile Query Fallback (Silent Ping)
**Goal:** Verify if a player exists/is in-phase by pinging their addon directly (bypassing Server API).

1.  **Test:**
    *   Target a player.
    *   Run:
    ```lua
    /run TRP3_API.r.sendMSPQuery(UnitName("target"))
    ```
    *   **Success:** You see "TRP3: Received profile data" (or similar debug message).
    *   **Mitigation:** Use `sendMSPQuery` as a "soft" location check. If they reply, they are here.

