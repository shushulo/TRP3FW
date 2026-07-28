# Optimization Plan: Location Cascading Logic

**Status:** Proposed  
**Target:** `location/cascading.lua`  
**Goal:** Reduce latency, CPU usage, and memory churn during location checks.

## 1. Early Fast-Path (High Impact)

**Problem:**
The Interaction Cache check currently runs *after* substantial setup work (creating the `results` table, defining closures, checking settings). This overhead is wasted for ~50% of requests (e.g., repeated mouseovers).

**Proposed Change:**
Move the `Interaction Cache` check to the very top of `CheckLocationCascading`, immediately after timestamp retrieval.

**Pseudocode:**
```lua
function TRP3FW:CheckLocationCascading(...)
    local now = self:GetCurrentTime()
    
    -- 1. FAST PATH: Interaction Cache
    local CI = self.CacheInterface
    local interaction = CI and CI:Get("interaction", playerName)
    if interaction and (now - interaction.timestamp) < TTL then
        -- Return IMMEDIATE SUCCESS
        return callback(true, nil, "interaction_cache", ...) 
    end

    -- 2. Heavy Setup (Results table, closures, etc.)
    -- ...
```

**Benefit:**
- Reduces CPU time for frequently interacted players.
- Reduces garbage collection (GC) pressure by avoiding table allocation.

## 2. Closure Refactoring (Memory Impact)

**Problem:**
`CheckLocationCascading` creates multiple large closures (`evaluateResults`, `startStandardChecks`, `runMapCheck`) and a `results` table for every call. In Lua, this generates garbage that must be collected.

**Proposed Change:**
Refactor logic into static local functions that accept a `context` object.

**Refactoring Pattern:**
```lua
-- Static local function
local function EvaluateResults(context)
    -- Logic using context.results, context.options, etc.
end

function TRP3FW:CheckLocationCascading(...)
    local context = {
        results = { ... },
        options = options,
        callback = callback
    }
    -- Pass context instead of closing over upvalues
    EvaluateResults(context)
end
```

**Benefit:**
- Reduces memory allocation per check.
- Cleaner code separation.

## 3. SPVP Early Success (Latency Impact)

**Problem:**
In `optional` (parallel) mode, the system waits for *all* checks to complete (`checksComplete == checksExpected`) before returning a result. If the Standard check passes quickly (e.g., target found), the user still waits for the SPVP timeout or handshake.

**Proposed Change:**
Allow "Early Success" in `evaluateResults`.

**Logic:**
- If `results.phaseCheck == true` (via strong method like `target`) AND `results.mapCheck == true` (or skipped):
  - **Return SUCCESS immediately.**
  - Do not wait for pending SPVP check.
  - The SPVP check can complete silently in the background (updating cache) or be cancelled.

**Benefit:**
- Significant latency reduction for valid, nearby players when SPVP is enabled but slow.

## 4. Start Phase Early Exit (Safety/Performance)

**Problem:**
Epsilon Start Phase (169) checks are currently handled later in the pipeline or via settings flags inside the logic.

**Proposed Change:**
Add an explicit check at the start of `CheckLocationCascading`.

**Logic:**
```lua
if currentPhaseID == 169 and TRP3FW.Prefs.blockStartPhase then
    return callback(false, "start_phase_block", ...)
end
```

**Benefit:**
- Fails fast for blocked start phase traffic.
- Prevents wasted API calls and check logic.

## Implementation Priority

1. **Early Fast-Path:** Immediate win, low risk.
2. **SPVP Early Success:** High value for user experience (responsiveness).
3. **Closure Refactoring:** Good for long-term maintenance and memory stability.
