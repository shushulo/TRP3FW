# Ghost Mode Architecture

**Last Updated**: 2026-01-11
**Version**: 2.9.2-hotfix (v2.0-beta)

---

## Table of Contents

1. [Overview](#overview)
2. [Ghost Mode Concept](#ghost-mode-concept)
3. [Ghost Flag System](#ghost-flag-system)
4. [Profile Generation](#profile-generation)
5. [Triggering Logic](#triggering-logic)
6. [Alternate Profiles](#alternate-profiles)
7. [TRP3 Ghost Mode](#trp3-ghost-mode)
8. [MSP Ghost Mode](#msp-ghost-mode)
9. [Start Phase Ghost Mode](#start-phase-ghost-mode)
10. [Cleanup and Expiration](#cleanup-and-expiration)
11. [Security Considerations](#security-considerations)
12. [Troubleshooting](#troubleshooting)

---

## Overview

**Ghost mode** allows TRP3FW to send **blank or alternate profiles** instead of blocking profile requests entirely. This provides stealth protection against remote tracking while maintaining RP addon compatibility.

### Use Cases

1. **Start Phase Protection** (Phase 169 on Epsilon)
   - Prevent profile leakage in starting areas
   - Send blank profile instead of blocking (prevents errors in requesting addon)

2. **Alert-Only Mode**
   - Notify about failed location checks WITHOUT blocking
   - Send blank profile to requester (they think you have no RP profile)

3. **Alternate Profile Mode**
   - Send a specific "public" profile to non-nearby players
   - Keep your real profile private for actual nearby RPers

### Ghost vs Block

| Mode | Profile Sent? | Requester Sees | Your Addon Errors? |
|------|--------------|----------------|-------------------|
| **Allow** | ✅ Real profile | Your real RP data | No |
| **Block** | ❌ Nothing | Request timeout/error | Possible (LibMSP errors) |
| **Ghost** | ✅ Blank/alternate | Empty profile or alternate | No |

**Key Advantage**: Ghost mode prevents addon errors in the requesting player's RP addon while protecting your data.

---

## Ghost Mode Concept

### How It Works

```
1. Location check fails (player not nearby)
2. Ghost mode enabled in settings
3. TRP3FW sets ghost flag for target player
4. Profile send hook intercepts outgoing data
5. Hook replaces real profile with blank/alternate
6. Blank/alternate profile sent to requester
7. Ghost flag cleared (single-use)
```

### Data Flow

```
Requester sends profile request
    ↓
TRP3FW receives request via hooks
    ↓
Location check fails (phase/WHO/map)
    ↓
[Ghost mode enabled?]
    ↓
TRP3FW:EnableGhostForNextSend(playerName, profileID)
    ↓
TRP3FW.ghostNextSend = {target, profileID, expires}
    ↓
Profile send hooks check ghost flag
    ↓
Generate blank/alternate profile data
    ↓
Replace real profile with ghost profile
    ↓
Send ghost profile to requester
    ↓
Clear ghost flag
```

---

## Ghost Flag System

**File**: `features/ghostmode.lua`

### Data Structure

```lua
TRP3FW.ghostNextSend = {
    target = "PlayerName",            -- Who to ghost
    profileID = "alternate_profile",  -- Optional alternate profile ID
    timestamp = 1234567890.123,       -- When flag was set
    expires = 1234567920.123,         -- Expiration time (timestamp + 30s)
    reason = "location_fail"          -- Why ghost was triggered
}
```

### Setting Ghost Flag

```lua
function TRP3FW:EnableGhostForNextSend(playerName, profileID)
    -- Validate player name
    local cleanName = self:CleanPlayerName(playerName)
    if not cleanName then
        return false
    end

    -- Set ghost flag
    self.ghostNextSend = {
        target = cleanName,
        profileID = profileID,  -- nil = blank profile
        timestamp = GetTime(),
        expires = GetTime() + 30,  -- 30 second TTL
        reason = "user_request"
    }

    self:Debug("[Ghost Flag] Set for "..cleanName.." (profile: "..tostring(profileID or "blank")..")", "ghost")
    return true
end
```

### Checking Ghost Flag

```lua
function TRP3FW:GetCurrentGhostTarget()
    if not self.ghostNextSend then
        return nil  -- No active ghost flag
    end

    -- Validate structure
    if not self.ghostNextSend.target or not self.ghostNextSend.expires then
        self:Error("[Ghost Flag] Corrupted ghost flag, clearing")
        self.ghostNextSend = nil
        return nil
    end

    -- Check expiration
    local now = GetTime()
    if now > self.ghostNextSend.expires then
        self:Debug("[Ghost Flag] Expired "..string.format("%.1f", now - self.ghostNextSend.expires).."s ago", "ghost")
        self.ghostNextSend = nil
        return nil
    end

    -- Return active ghost target
    return self.ghostNextSend.target
end
```

### Consuming Ghost Flag

```lua
function TRP3FW:ShouldGhostSendTo(playerName)
    local ghostTarget = self:GetCurrentGhostTarget()
    if not ghostTarget then
        return false
    end

    local cleanName = self:CleanPlayerName(playerName)
    if cleanName == ghostTarget then
        self:Debug("[Ghost Flag] Match for "..cleanName, "ghost")
        return true
    end

    return false
end
```

**Important**: Ghost flag is NOT cleared when checked. It's cleared by the hook that actually sends the ghost profile (single-use guarantee).

### Clearing Ghost Flag

```lua
function TRP3FW:ClearGhostFlag(playerName)
    if not self.ghostNextSend then
        return
    end

    local cleanName = self:CleanPlayerName(playerName)
    if self.ghostNextSend.target == cleanName then
        self:Debug("[Ghost Flag] Cleared for "..cleanName, "ghost")
        self.ghostNextSend = nil
    end
end
```

---

## Profile Generation

Ghost mode supports two modes:
1. **Blank Profile** - Minimal valid profile (no RP data)
2. **Alternate Profile** - Send a different TRP3/MRP/XRP profile

### Blank Profile Generation

#### TRP3 Blank Profiles

**Characteristics** (`features/profiles/trp3_blank.lua`):
```lua
function TRP3FW:GetBlankCharacteristicsData()
    return {
        FN = UnitName("player"),  -- Game name
        LN = "",                  -- No last name
        FT = "",                  -- No title
        IC = "TEMP",              -- Default icon
        CH = "ffffff",            -- White color
        RA = "",                  -- No custom race
        CL = "",                  -- No custom class
        AG = "",                  -- No age
        EC = "",                  -- No eye color
        HE = "",                  -- No height
        WE = "",                  -- No weight
        MI = {},                  -- No misc traits
        PS = {},                  -- No psyche info
    }
end
```

**About** (`features/profiles/trp3_blank.lua`):
```lua
function TRP3FW:GetBlankAboutData()
    return {
        v = 1,          -- Version
        TE = 1,         -- Template 1 (simple text)
        T1 = {
            TX = ""     -- Empty text
        },
        BK = 1,         -- Background 1
        MU = nil        -- No music
    }
end
```

**Misc/Character**: Similar empty structures with minimal valid fields.

#### MSP Blank Profiles

**Blank MSP Fields** (`hooks/msp_exchange.lua`):
```lua
function TRP3FW:GetBlankMSPFields()
    return {
        VP = "3",                                  -- Protocol version
        VA = "TRP3FW/"..self.VERSION,             -- Addon version (REQUIRED)
        NA = UnitName("player") or "",             -- Character name
        GU = UnitGUID("player") or "",             -- GUID
        GC = select(2, UnitClass("player")) or "", -- Game class
        GR = select(2, UnitRace("player")) or "",  -- Game race
        GS = tostring(UnitSex("player")) or "",    -- Game sex
        GF = UnitFactionGroup("player") or "",     -- Game faction
        FC = "0",                                  -- RP Status: Neutral
        CO = "",                                   -- Not OOC
        -- All other RP fields omitted (NH, NI, NT, RA, RC, CU, IC, DE, HI, AG, AE, AH, AW, HB, HH, etc.)
    }
end
```

**Why VA is Required**: LibMSP spec requires `VA` (addon version) field. Without it, LibMSP throws errors.

### Alternate Profile Generation

#### Retrieving Alternate Profiles

```lua
function TRP3FW:GetGhostProfileID(playerName)
    if not self.ghostNextSend or self.ghostNextSend.target ~= playerName then
        return nil
    end

    return self.ghostNextSend.profileID  -- May be nil (blank mode)
end
```

#### TRP3 Profile Fetching

```lua
function TRP3FW:GetProfileCharacteristics(profileID)
    if not TRP3_API or not TRP3_API.profile then
        return nil
    end

    local profile = TRP3_API.profile.getProfileByID(profileID)
    if not profile or not profile.player then
        return nil
    end

    return profile.player.characteristics
end
```

**Similar functions** for `GetProfileAbout()`, `GetProfileMisc()`, `GetProfileCharacter()`.

#### MSP Profile Fetching

**Direct MSP** (MRP/XRP - profiles already in MSP format):
```lua
function TRP3FW:GetProfileDirectMSP(profileID)
    -- MRP profiles
    if mrp and mrpSaved and mrpSaved.Profiles and mrpSaved.Profiles[profileID] then
        return mrpSaved.Profiles[profileID]  -- Already MSP fields
    end

    -- XRP profiles
    if xrp and xrp.profiles and xrp.profiles[profileID] then
        return xrp.profiles[profileID]  -- Already MSP fields
    end

    return nil
end
```

**TRP3 → MSP Conversion**:
```lua
function TRP3FW:GetProfileTRP3ToMSP(profileID)
    -- Check conversion cache first
    if self.mspConversionCache[profileID] then
        return self.mspConversionCache[profileID].mspFields
    end

    -- Fetch TRP3 profile sections
    local characteristics = self:GetProfileCharacteristics(profileID)
    local about = self:GetProfileAbout(profileID)
    local character = self:GetProfileCharacter(profileID)

    -- Convert to MSP format
    local mspFields = {}
    mspFields.VP = "3"
    mspFields.VA = "TRP3FW/"..self.VERSION
    mspFields.NA = self:GetCompleteName(characteristics)
    mspFields.IC = characteristics.IC
    mspFields.RA = characteristics.RA
    mspFields.RC = characteristics.CL
    mspFields.AG = characteristics.AG
    mspFields.AE = characteristics.EC  -- Eye color
    mspFields.AH = characteristics.HE  -- Height
    mspFields.AW = characteristics.WE  -- Weight
    mspFields.DE = about and about.T1 and about.T1.TX  -- Description
    mspFields.CU = character and character.CU  -- Currently
    -- ... (full conversion ~60 fields)

    -- Cache result (expensive operation)
    self.mspConversionCache[profileID] = {
        mspFields = mspFields,
        timestamp = GetTime()
    }

    return mspFields
end
```

**Cache Rationale**: TRP3→MSP conversion is expensive (155 lines of logic). Profiles rarely change during play, so aggressive caching improves performance.

---

## Triggering Logic

Ghost mode can be triggered in three ways:

### 1. Location Check Failure (Decision Engine)

**File**: `features/decision.lua`

```lua
function TRP3FW:CheckLocationAndNotify(playerName, addon, isWhisper, sendId, originalFunc, originalArgs)
    -- ... location check cascade ...

    if locationFailed then
        if TRP3FW.Prefs.ghostOnLocationFail then
            -- Enable ghost flag
            local alternateProfileID = TRP3FW.Prefs.ghostProfileID
            self:EnableGhostForNextSend(playerName, alternateProfileID)

            -- Allow send (ghost flag active)
            if originalFunc then
                pcall(originalFunc, unpack(originalArgs))
            end

            return true
        else
            -- Block send
            return false
        end
    end
end
```

### 2. Start Phase Protection (Phase 169)

**File**: `features/ghostmode.lua`

```lua
function TRP3FW:ShouldBlockForStartPhase(playerName, isProfileSend)
    -- Skip if whitelisted
    if self:IsPlayerWhitelisted(playerName) then
        return false, nil
    end

    -- Skip if not profile send
    if not isProfileSend then
        return false, nil
    end

    -- Skip if profile switch override active
    if self:IsProfileSwitchOverrideActive() then
        return false, nil
    end

    -- Check if either blocking OR ghosting enabled
    if not TRP3FW.Prefs.blockStartPhase and not TRP3FW.Prefs.ghostOnStartPhase then
        return false, nil
    end

    -- Check Epsilon API
    if not self.hasEpsilonAPI then
        return false, nil
    end

    -- Get cached phase ID
    local phaseID = self:GetCachedPhaseID()
    if phaseID ~= 169 then
        return false, nil
    end

    -- Phase 169 detected - ghost mode takes priority over block
    if TRP3FW.Prefs.ghostOnStartPhase and (self.hasTRP3ExchangeHooks or self.hasMSPExchangeHooks) then
        return true, "ghost"
    elseif TRP3FW.Prefs.blockStartPhase then
        return true, "block"
    else
        return false, nil
    end
end
```

**Trigger Points**:
- **Chomp hook** (Stage 4: Start phase block/ghost)
- **MSP callback hook** (LibMSP request received)
- **SendObject hook** (Pre-serialization check)

### 3. Alert-Only Mode

**File**: `features/stages/AlertFastPathStage.lua`

```lua
if TRP3FW.Prefs.alertOnPhase and not TRP3FW.Prefs.blockOnPhase then
    -- Alert-only mode (ghost instead of block)
    TRP3FW:EnableGhostForNextSend(playerName, nil)  -- Blank profile

    -- Allow send (async location check for notification only)
    context.allowed = true
    if context.originalFunc then
        pcall(context.originalFunc, unpack(context.originalArgs))
    end

    return {handled = true, allowed = true}
end
```

---

## Alternate Profiles

### Configuring Alternate Profile

**UI Setting** (`ui/settings.lua`):
```lua
local ghostProfileInput = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
ghostProfileInput:SetText(TRP3FW.Prefs.ghostProfileID or "")
ghostProfileInput:SetScript("OnTextChanged", function(self)
    TRP3FW.Prefs.ghostProfileID = self:GetText()
end)
```

**Command**:
```bash
/trp3fw ghostprofile MyPublicProfile
```

### How Alternate Profiles Work

1. **User creates alternate profile** in TRP3/MRP/XRP (e.g., "Public Profile")
2. **User sets profile ID** in TRP3FW settings (`ghostProfileID = "Public Profile"`)
3. **Ghost mode triggered** → `EnableGhostForNextSend(playerName, "Public Profile")`
4. **Hooks fetch profile** → `GetProfileCharacteristics("Public Profile")`
5. **Hooks send profile** → Requester sees "Public Profile" instead of real profile

### Profile ID Format

| Addon | Profile ID Format | Example |
|-------|------------------|---------|
| TRP3 | Profile name string | `"My Public Profile"` |
| MRP | Saved profile key | `"profile_1"` |
| XRP | Profile name | `"Public"` |

---

## TRP3 Ghost Mode

**File**: `hooks/trp3.lua`

### SendObject Hook (Pre-Serialization)

```lua
AddOn_TotalRP3.Communications.sendObject = function(prefix, object, ...)
    -- Only intercept profile sends (prefix "SI")
    if prefix == "SI" and object and object[1] then
        local informationType = object[1]  -- characteristics/about/misc/character
        local target = extractTargetFromArgs(...)

        -- Check ghost flag
        if TRP3FW:ShouldGhostSendTo(target) then
            local profileID = TRP3FW:GetGhostProfileID(target)

            -- Generate ghost data for this informationType
            local ghostData = TRP3FW:GetGhostDataForInformationType(informationType, profileID)

            if ghostData then
                -- Validate payload
                local valid, sanitized = TRP3FW:ValidateGhostTRP3Payload(informationType, ghostData)

                if valid then
                    object = {informationType, sanitized}  -- Replace data
                    TRP3FW:Debug("[sendObject] Sending ghost data for "..informationType, "ghost")
                else
                    TRP3FW:Warn("[sendObject] Invalid ghost payload, blocking send")
                    return  -- Block (invalid ghost data)
                end
            else
                TRP3FW:Warn("[sendObject] Failed to generate ghost data, blocking send")
                return  -- Block
            end
        end
    end

    return originalSendObject(prefix, object, ...)
end
```

### Why Pre-Serialization?

Chomp serializes `object` into a string before transmission. By hooking `sendObject` (before serialization), we have access to:
- **informationType**: Which profile section is being sent
- **Structured data**: Easy to replace with ghost data

If we hooked Chomp directly, we'd only see serialized strings (harder to parse and replace).

### Ghost Data Validation

```lua
function TRP3FW:ValidateGhostTRP3Payload(informationType, payload)
    if type(payload) ~= "table" then
        return false, GetBlankForType(informationType)
    end

    local sanitized = ShallowCopy(payload)

    if informationType == registerInfoTypes.CHARACTERISTICS then
        -- Ensure required fields exist and have correct types
        sanitized.FN = SanitizeString(sanitized.FN, UnitName("player"))
        sanitized.CH = SanitizeString(sanitized.CH, "ffffff")
        sanitized.IC = SanitizeString(sanitized.IC, "TEMP")
        if type(sanitized.MI) ~= "table" then sanitized.MI = {} end
    elseif informationType == registerInfoTypes.ABOUT then
        sanitized.v = tonumber(sanitized.v) or 1
        sanitized.TE = tonumber(sanitized.TE) or 1
        if type(sanitized.T1) ~= "table" then sanitized.T1 = {} end
        sanitized.T1.TX = SanitizeString(sanitized.T1.TX, "")
    end
    -- ... (similar for MISC, CHARACTER)

    return true, sanitized
end
```

**Purpose**: Prevent malformed ghost profiles from breaking requester's addon.

---

## MSP Ghost Mode

**Files**: `hooks/msp_exchange.lua`, `hooks/msp.lua`

### MSP Callback Hook (Request Detection)

```lua
-- LibMSP callback fires when REQUEST received
table.insert(msp.callback.received, 1, function(senderName)
    -- Start phase check
    local shouldBlock, action = TRP3FW:ShouldBlockForStartPhase(senderName, true)

    if shouldBlock and action == "ghost" then
        -- Enable ghost flag BEFORE LibMSP prepares reply
        TRP3FW:EnableGhostForNextSend(cleanName, alternateProfileID)
    end
end)
```

**Timing Critical**: Ghost flag must be set BEFORE LibMSP prepares the reply payload.

### Chomp Hook (Payload Replacement)

```lua
-- Chomp hook (final stage before transmission)
if shouldGhost and addon == "MSP" then
    -- Generate MSP ghost payload
    local ghostPayload = TRP3FW:GenerateMSPGhostPayload(playerName)

    if ghostPayload then
        -- Replace text payload
        args[2] = ghostPayload  -- args = {prefix, text, chatType, target, ...}
        TRP3FW:Debug("[Chomp Hook] Replaced MSP payload with ghost", "ghost")
    end
end
```

### MSP Ghost Payload Generation

```lua
function TRP3FW:GenerateMSPGhostPayload(target)
    local profileID = self:GetGhostProfileID(target) or TRP3FW.Prefs.ghostProfileID
    local fields = self:GetProfileMSPFields(profileID)

    -- Fallback to blank if profile fetch fails
    if not fields then
        fields = self:GetBlankMSPFields()
    end

    -- MSP format: "FIELD1:VALUE1`FIELD2:VALUE2`..."
    local parts = {}
    local SEP = string.char(0x60)  -- Backtick separator

    for k, v in pairs(fields) do
        table.insert(parts, k .. ":" .. tostring(v))
    end

    return table.concat(parts, SEP)
end
```

**Format**: MSP uses backtick-separated field:value pairs.

### MSP Metatable Proxy (Deprecated)

**Old Method** (v1.x): Used metatable on `msp.my` to intercept field reads.

**Problem**: Synchronization issues, metatable dropped by other addons, complex to maintain.

**New Method** (v2.x): Generate ghost payload in Chomp hook (payload replacement strategy).

**Advantage**: Simpler, no metatable synchronization, more reliable.

---

## Start Phase Ghost Mode

**Purpose**: Prevent profile leakage in Phase 169 (Epsilon start phase)

### Why Phase 169?

On Epsilon WoW:
- **Phase 169** = Default starting phase
- **Anyone** can be in Phase 169 (new characters, logged out in start zone)
- **Risk**: Remote players can request your profile from Phase 169

### Start Phase Settings

```lua
TRP3FW.Prefs.blockStartPhase = false  -- Block sends in Phase 169
TRP3FW.Prefs.ghostOnStartPhase = true  -- Ghost sends in Phase 169 (takes priority)
```

**Priority**: Ghost mode > Block mode

### Start Phase Protection Flow

```
Player in Phase 169
    ↓
Receives profile request
    ↓
ShouldBlockForStartPhase(playerName, true)
    ↓
Returns: true, "ghost"
    ↓
EnableGhostForNextSend(playerName, nil)
    ↓
Send blank profile (no RP data leaked)
```

### Profile Switch Override

**File**: `features/profileswitch.lua`

**Purpose**: Automatically switch to "safety profile" in Phase 169/Map 1605

**When Active**: Phase 169 protection is **disabled**
```lua
if TRP3FW:IsProfileSwitchOverrideActive() then
    -- Skip ghost/block logic
    return false, nil
end
```

**Rationale**: User already switched to safety profile manually, no need to ghost/block.

---

## Cleanup and Expiration

### Ghost Flag Expiration

**TTL**: 30 seconds

**Expiration Check**:
```lua
function TRP3FW:GetCurrentGhostTarget()
    if not self.ghostNextSend then
        return nil
    end

    local now = GetTime()
    if now > self.ghostNextSend.expires then
        self:Debug("[Ghost Flag] Expired", "ghost")
        self.ghostNextSend = nil
        return nil
    end

    return self.ghostNextSend.target
end
```

**Why 30s?**
- Profile exchanges complete in 1-2 seconds
- 30s provides generous buffer for slow network/addon processing
- Prevents stale ghost flags from affecting future sends

### Manual Cleanup

```lua
-- Called by hooks after sending ghost profile
TRP3FW:ClearGhostFlag(playerName)
```

### Corruption Recovery

```lua
-- Validate structure before use
if not self.ghostNextSend.target or not self.ghostNextSend.expires then
    self:Error("[Ghost Flag] Corrupted ghost flag detected, clearing")
    self.ghostNextSend = nil
    return nil
end
```

**Corruption Causes**:
- Addon reload mid-send
- Memory corruption (rare)
- Manual table modification by other addons

---

## Security Considerations

### 1. Ghost Profile Sanitization

**Risk**: Alternate profile contains malicious data that breaks requester's addon.

**Mitigation**: Validate all ghost payloads before sending
```lua
local valid, sanitized = TRP3FW:ValidateGhostTRP3Payload(informationType, ghostData)
if not valid then
    -- Fall back to blank profile
    ghostData = GetBlankForType(informationType)
end
```

### 2. Profile ID Validation

**Risk**: User enters invalid profile ID → addon errors.

**Mitigation**: Check if profile exists before fetching
```lua
function TRP3FW:GetProfileCharacteristics(profileID)
    local profile = TRP3_API.profile.getProfileByID(profileID)
    if not profile or not profile.player then
        return nil  -- Fall back to blank
    end
    return profile.player.characteristics
end
```

### 3. Ghost Flag Hijacking

**Risk**: Another addon sets `TRP3FW.ghostNextSend` maliciously.

**Mitigation**: Structure validation, expiration enforcement
```lua
if not self.ghostNextSend.target or not self.ghostNextSend.expires then
    self:Error("[Ghost Flag] Corrupted ghost flag, clearing")
    self.ghostNextSend = nil
end
```

### 4. MSP Conversion Cache Poisoning

**Risk**: Cached MSP conversion contains stale/incorrect data.

**Current**: No cache expiration (profiles assumed static during play session)

**Future**: Consider cache TTL or invalidation on profile edit events.

### 5. Recursion Prevention

**Risk**: Ghost mode hooks trigger profile sends → infinite loop.

**Mitigation**: Recursion guards (see [HOOK_SYSTEM.md](HOOK_SYSTEM.md#safety-mechanisms))

---

## Troubleshooting

### Ghost Mode Not Activating

**Symptoms**:
- Profiles blocked instead of ghosted
- Real profile sent instead of ghost

**Debug**:
```bash
/trp3fw debug
/trp3fw debugfilter ghost
# Trigger ghost send
# Look for "[Ghost Flag]" messages
```

**Common Causes**:
1. **Ghost mode disabled**
   - Check: `/trp3fw status` → "Ghost on location fail: No"
   - Fix: `/trp3fw ghost` (toggle)

2. **Exchange hooks not installed**
   - Check: `/dump TRP3FW.hasMSPExchangeHooks` → Should be `true`
   - Fix: `/trp3fw reloadhooks`

3. **Ghost flag expired**
   - Check: `/dump TRP3FW.ghostNextSend` → Should be table, not nil
   - Cause: 30s elapsed between flag set and send
   - Fix: Increase TTL or trigger send faster

4. **Profile ID invalid**
   - Check: `/dump TRP3_API.profile.getProfileByID("MyProfile")`
   - Fix: Use correct profile name

### Blank Profile Sent Instead of Alternate

**Symptoms**:
- Ghost mode works but sends blank instead of alternate profile

**Debug**:
```lua
/dump TRP3FW.Prefs.ghostProfileID  -- Should be profile name, not nil
/dump TRP3FW.ghostNextSend.profileID  -- Should match setting
```

**Common Causes**:
1. **Profile ID not set**
   - Fix: `/trp3fw ghostprofile MyPublicProfile`

2. **Profile doesn't exist**
   - Check: `/trp3fw profiles` (list available profiles)
   - Fix: Create profile in TRP3/MRP/XRP first

3. **Profile fetch failed**
   - Check debug: "Profile not found, using blank"
   - Cause: Typo in profile name
   - Fix: Use exact profile name (case-sensitive)

### MSP Ghost Not Working

**Symptoms**:
- TRP3 ghost works, MSP sends real profile

**Debug**:
```bash
/trp3fw debug
/trp3fw debugfilter ghost
# Trigger MSP send
# Look for "[Chomp Hook] Replaced MSP payload"
```

**Common Causes**:
1. **Chomp ghost disabled**
   - Check: `/dump TRP3FW.Prefs.enableChompGhost`
   - Fix: `/trp3fw chompghost` (toggle)

2. **MSP exchange hooks not installed**
   - Check: `/dump TRP3FW.hasMSPExchangeHooks`
   - Fix: `/trp3fw reloadhooks`

3. **Payload replacement failed**
   - Check debug: "Failed to generate payload"
   - Cause: MSP conversion error
   - Fix: Report bug with debug log

### Start Phase Ghost Not Triggered

**Symptoms**:
- In Phase 169 but ghost not applied

**Debug**:
```lua
/dump C_Epsilon.GetPhaseId()  -- Should be 169
/dump TRP3FW:GetCachedPhaseID()  -- Should be 169
/dump TRP3FW.Prefs.ghostOnStartPhase  -- Should be true
```

**Common Causes**:
1. **Ghost on start phase disabled**
   - Fix: Enable in settings UI or `/trp3fw ghoststart`

2. **Profile switch override active**
   - Check: `/dump TRP3FW:IsProfileSwitchOverrideActive()`
   - Cause: You manually switched to safety profile
   - Fix: Disable profile switch or use ghost mode

3. **Phase cache stale**
   - Cause: Changed phase but cache not updated
   - Fix: `/reload` (cache refreshes on PLAYER_ENTERING_WORLD)

### Ghost Flag Corruption

**Symptoms**:
- Error: "Corrupted ghost flag detected"

**Debug**:
```lua
/dump TRP3FW.ghostNextSend
-- Should have: target, profileID, timestamp, expires
```

**Causes**:
- Addon reload during send
- Another addon modified table
- Memory corruption (very rare)

**Fix**:
- Ghost flag auto-clears on corruption
- Next send will set new flag

### Performance Issues

**Symptoms**:
- Lag when sending ghost profiles
- Frame drops during MSP conversion

**Debug**:
```bash
/trp3fw profile on
# Trigger ghost send
/trp3fw profile report
# Look for "GetProfileTRP3ToMSP" latency
```

**Optimization**:
- MSP conversion uses aggressive caching
- First conversion: ~5-10ms (expensive)
- Cached conversions: ~0.1ms (fast)

**If Still Slow**:
- Check: `/dump TRP3FW.mspConversionCache` size
- Clear cache: `/reload` (cache cleared on addon load)

---

## Performance

### Overhead

| Operation | Avg Latency | Notes |
|-----------|-------------|-------|
| Set ghost flag | 0.05ms | O(1) table assignment |
| Check ghost flag | 0.08ms | Structure validation + expiration check |
| Generate blank TRP3 | 0.2ms | Table creation |
| Generate blank MSP | 0.3ms | Table creation + string concat |
| Fetch alternate TRP3 | 1.5ms | API call + table copy |
| Convert TRP3 → MSP (first) | 8ms | 155 lines of conversion logic |
| Convert TRP3 → MSP (cached) | 0.1ms | Cache lookup |

**Total Ghost Send Overhead**: 1-10ms (depends on blank vs alternate, cached vs uncached)

### Optimization Techniques

1. **MSP Conversion Cache**
   - Aggressive caching (unlimited TTL during session)
   - Profiles rarely change during play
   - Dramatic speedup for repeated sends

2. **Lazy Evaluation**
   - Only generate ghost data when needed
   - Skip validation if profile fetch fails (fallback to blank)

3. **Reuse Tables**
   - Blank profiles use same table structure each time
   - Reduce GC pressure

4. **Early Validation**
   - Check ghost flag validity before expensive operations
   - Abort early on corruption/expiration

---

**Related Documentation**:
- [HOOK_SYSTEM.md](HOOK_SYSTEM.md) - Hook implementation details
- [DECISION_LOGIC.md](DECISION_LOGIC.md) - When ghost mode is triggered
- [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - `ghostNextSend` structure
- [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md) - Ghost mode settings

**Last Updated**: 2026-01-11
**Maintainer**: Review when modifying ghost mode logic or adding alternate profile sources
