# UI Usability Improvements Specification

**Status:** Draft — Pending Review  
**Date:** 2026-04-27  
**Covers:** All files under `ui/`  
**Version Target:** Post-2.9.2-hotfix

---

## Overview

This document specifies targeted usability fixes identified during a deep-dive review of the TRP3FW settings UI. Each issue is documented with its root cause, exact location in the code, the proposed fix, and expected result. No new features are introduced — these are all corrections or polish to existing behavior.

---

## Issue 1 — Settings Window Width Overflows Tab Bar

**Priority:** High — breaks core navigation  
**File:** `ui/settings.lua`  
**Line:** ~863–874

### Problem

The main settings frame is created at 600×550. Tab buttons are created starting at x=10 with 88px width and 92px spacing:

```lua
settingsFrame:SetSize(600, 550)
b:SetSize(88, 30)
b:SetPoint("TOPLEFT", (i-1)*92+10, -30)
```

There are 7 registered tabs (Alerts, Notifications, Filters, Debug, Profiles, Status + any future ones). At 7 tabs:

- Last button starts at: `(7-1)*92 + 10 = 562`
- Last button ends at: `562 + 88 = 650`

This overflows the 600px frame by **50px**. The rightmost tab button(s) are clipped by the frame edge.

### Fix

Widen the frame to 700px. This comfortably accommodates 7 tabs with the current spacing, and leaves room for one more tab without overflow:

```lua
-- Before
settingsFrame:SetSize(600, 550)

-- After
settingsFrame:SetSize(700, 550)
```

Also update `TabManager:CreateScrollFrame` which hardcodes the scroll child width to 540:

```lua
-- Before (ui/TabManager.lua ~line 328)
scrollChild:SetSize(540, contentHeight or 1000)

-- After
scrollChild:SetSize(640, contentHeight or 1000)
```

And update the scroll frame itself which anchors to `BOTTOMRIGHT, -30, 40` — this is fine and will scale with the parent, but any hardcoded label widths inside tabs that assume a 540px content area should be reviewed when implementing.

### Expected Result

All tab buttons are visible and clickable. No overflow clipping.

---

## Issue 2 — Active Tab Has No Persistent Highlight

**Priority:** High — UX regression on every reopen  
**File:** `ui/settings.lua`  
**Line:** ~866–874

### Problem

Tab buttons switch their background color on click, but this state is not persisted. When the settings frame is hidden and reopened, all tab buttons revert to the unhighlighted color (`0.2, 0.2, 0.2, 0.8`) even though one tab's content is showing. The user has no visual indication of which tab is active.

The click handler updates sibling buttons but doesn't store which button corresponds to the active tab:

```lua
b:SetScript("OnClick", function()
    TRP3FW.TabManager:SwitchToTab(tabInfo.id)
    for j, t in ipairs(tabs) do
        if j == i then
            t.bg:SetColorTexture(0.3, 0.3, 0.3, 1)
            t.text:SetTextColor(1, 1, 1)
        else
            t.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            t.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end)
```

### Fix

Store the `tabs` list and the active tab index so `OnShow` can restore the highlight. The cleanest approach is to trigger the first tab's `OnClick` script on `OnShow`, which already contains all the highlight logic:

```lua
-- After building all tabs, add:
settingsFrame:SetScript("OnShow", function()
    -- Re-apply highlight to whichever tab is currently active
    local activeId = TRP3FW.TabManager.activeTab and TRP3FW.TabManager.activeTab.id
    for i, tabInfo in ipairs(TRP3FW.TabManager.orderedTabs) do
        local t = tabs[i]
        if t then
            local isActive = (tabInfo.id == activeId)
            t.bg:SetColorTexture(isActive and 0.3 or 0.2, isActive and 0.3 or 0.2, isActive and 0.3 or 0.2, isActive and 1.0 or 0.8)
            t.text:SetTextColor(isActive and 1 or 0.7, isActive and 1 or 0.7, isActive and 1 or 0.7)
        end
    end
    TRP3FW:RefreshUI()
end)
```

This also naturally fixes Issue 3 (see below) since `RefreshUI` is called on show.

### Expected Result

The active tab button is always visually highlighted when the window is open, including after hide/show cycles.

---

## Issue 3 — RefreshUI Is a No-op While Frame Is Hidden (Stale State on Reopen)

**Priority:** High — stale UI state after preset changes or external updates  
**File:** `ui/settings.lua`  
**Line:** 521–522

### Problem

`RefreshUI` returns early if `settingsFrame` is not visible:

```lua
function TRP3FW:RefreshUI()
    if refreshing or not settingsFrame or not settingsFrame:IsVisible() then
        refreshScheduled = false
        return
    end
    ...
end
```

This means:
- Applying a preset via `ApplyPreset()` calls `RefreshUI()` — if the panel is closed, nothing updates.
- When the user reopens the panel, checkboxes and dropdowns show stale values until they switch tabs (which triggers a tab refresh).
- `RequestRefreshUI` also uses a deferred `C_Timer.After(0, ...)` which fires while the frame is still hidden, so it also silently fails.

### Fix

Add an `OnShow` hook that calls `RefreshUI`. This is already partially covered by the fix in Issue 2, but should be explicit and guaranteed even if Issue 2's implementation changes:

```lua
-- Add inside InitializeUI, after settingsFrame is created
settingsFrame:HookScript("OnShow", function()
    TRP3FW:RefreshUI()
end)
```

Using `HookScript` rather than `SetScript` ensures this fires in addition to any other `OnShow` logic without clobbering it.

### Expected Result

The settings panel always shows current values when opened, regardless of whether changes were made while it was hidden (presets applied via slash commands, external setting changes, etc.).

---

## Issue 4 — Notifications Tab: Scan Group Frame Sizing Is Incorrect

**Priority:** Medium — visual glitch (border doesn't match content)  
**File:** `ui/tabs/Notifications.lua`  
**Line:** 61–71, 206

### Problem

The `scanGroup` backdrop frame is created with a hardcoded size:

```lua
scanGroup:SetSize(560, 480)
```

Then later, after all the scan controls are laid out, the code attempts to resize it dynamically:

```lua
scanGroup:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", 570, scanY + 10)
```

However, `SetSize` and a two-anchor `SetPoint` approach conflict — `SetSize` fixes the dimensions at creation, and since the `TOPLEFT` anchor is already set on line 62 (`SetPoint("TOPLEFT", 10, y)`), the later `BOTTOMRIGHT` anchor should redefine the size. In practice, WoW frames do resize when both `TOPLEFT` and `BOTTOMRIGHT` are anchored, but the initial `SetSize(560, 480)` call is misleading and can cause layout jitter during creation if the frame is shown before layout completes.

Additionally, the hardcoded `480` height is a magic number that may not match the actual content height as settings are added or removed.

### Fix

Remove the hardcoded `SetSize` call entirely and rely solely on the two-point anchoring, which correctly sizes the frame to its content:

```lua
-- Before
local scanGroup = CreateFrame("Frame", "TRP3FW_NotificationsScanGroup", content, "BackdropTemplate")
scanGroup:SetPoint("TOPLEFT", 10, y)
scanGroup:SetSize(560, 480)  -- REMOVE THIS LINE

-- ... (all scan controls laid out, scanY updated) ...

scanGroup:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", 570, scanY + 10)
```

```lua
-- After
local scanGroup = CreateFrame("Frame", "TRP3FW_NotificationsScanGroup", content, "BackdropTemplate")
scanGroup:SetPoint("TOPLEFT", 10, y)
-- SetSize removed — let BOTTOMRIGHT anchor define height

-- ... (all scan controls laid out, scanY updated) ...

scanGroup:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", 570, scanY + 10)
```

### Expected Result

The scan group border frame accurately wraps its content at all times, with no magic number to keep in sync.

---

## Issue 5 — Debug Tab: Slider/Checkbox Vertical Overlap

**Priority:** Medium — cosmetic but confusing layout  
**File:** `ui/tabs/Debug.lua`  
**Line:** 88–110

### Problem

The `phaseCheckBatchMode` checkbox is placed at `y` (after `y = y - 45`), then `y` is only advanced by `-50` before the batch sliders are placed — but those sliders use `OptionsSliderTemplate` which includes a label above and low/high text below, making them roughly 60–70px tall. The result is the sliders visually overlap with the checkbox label above them.

Additionally, the `setupSlider` local function definition runs right up against the first `CreateFrame` call with no blank line, making it very hard to see where the function ends and frame creation begins:

```lua
-- The function definition ends, then immediately:
    local batchSize = CreateFrame(...)  -- same visual block
```

### Fix

1. Increase the `y` advance before slider creation from `-50` to `-70`:

```lua
-- Before
y = y - 50
local batchSize = CreateFrame(...)

-- After
y = y - 70
local batchSize = CreateFrame(...)
```

2. Add a blank line between the end of `setupSlider` and the first slider `CreateFrame` call for readability (no functional change).

### Expected Result

Batch size and delay sliders sit cleanly below the "Enable Phase Batching" checkbox with no overlap.

---

## Issue 6 — Alerts Tab: 20 Override Rows Always Rendered

**Priority:** Low — performance and scroll UX  
**File:** `ui/tabs/Alerts.lua`  
**Line:** 314–334

### Problem

Twenty profile override rows are unconditionally created during tab initialization:

```lua
for i = 1, 20 do
    -- Creates label, EditBox, and Dropdown per row
end
```

Most users will never use overrides at all, and even power users rarely need more than 3–5 entries. This adds ~680px of mostly-empty scroll content to the tab and creates 60+ UI frames (20 labels + 20 editboxes + 20 dropdowns) at tab load time.

### Fix

Reduce the initial rendered rows to 5 and add an "Add Row" button that appends one more row (up to 20) when clicked. The existing `TRP3FW.Prefs.ghostProfileOverrides` table already supports 20 entries so no data model changes are needed:

```lua
-- Before
for i = 1, 20 do
    -- ...
end

-- After
local renderedRows = 0
local MAX_ROWS = 20
local INITIAL_ROWS = 5

local function RenderOverrideRow(i)
    -- existing row creation code, extracted to function
end

for i = 1, INITIAL_ROWS do
    RenderOverrideRow(i)
    renderedRows = i
end

local addRowBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
addRowBtn:SetSize(100, 22)
addRowBtn:SetPoint("TOPLEFT", 40, y)
addRowBtn:SetText("+ Add Row")
addRowBtn:SetScript("OnClick", function()
    if renderedRows < MAX_ROWS then
        renderedRows = renderedRows + 1
        RenderOverrideRow(renderedRows)
        if renderedRows >= MAX_ROWS then addRowBtn:Disable() end
    end
end)
```

Note: On tab load, if `ghostProfileOverrides` already has entries beyond row 5, those rows should be auto-rendered up to the last populated row.

### Expected Result

Tab creates 5 rows by default (much faster, shorter scroll). Power users can expand up to 20. Existing saved overrides beyond row 5 are still auto-shown on load.

---

## Issue 7 — Welcome Wizard: RefreshUI Called Before Frame Exists

**Priority:** Low — edge case on first install  
**File:** `ui/settings.lua`  
**Line:** 908

### Problem

`ShowWelcomeWizard` calls `TRP3FW:RefreshUI()` inside its button click handler:

```lua
b:SetScript("OnClick", function()
    TRP3FW.Prefs.uiComplexityLevel = l[1]
    TRP3FW.Prefs.complexitySetupDone = true
    TRP3FW:EnforceComplexityDefaults(l[1])
    TRP3FW:RefreshUI()  -- settingsFrame may not exist yet
    f:Hide()
end)
```

If the wizard is shown before `InitializeUI` runs (e.g. via a very early `PLAYER_LOGIN` hook), `settingsFrame` is nil and `RefreshUI` is a no-op — but this is silently ignored. The settings will still be correct in `TRP3FW.Prefs`, just the UI won't reflect them until `InitializeUI` completes and the panel is opened.

Additionally, there is no close button on the wizard frame — the user cannot dismiss it without selecting a complexity level.

### Fix

1. Guard the `RefreshUI` call with a nil check (it already guards internally, but being explicit is cleaner):

```lua
TRP3FW:EnforceComplexityDefaults(l[1])
if settingsFrame then TRP3FW:RefreshUI() end
f:Hide()
```

2. Add an "Skip / Use Defaults" close button to the wizard so the user can dismiss it without being forced to pick a level:

```lua
local skipBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
skipBtn:SetSize(200, 30)
skipBtn:SetPoint("BOTTOM", 0, 15)
skipBtn:SetText("Skip (Use Defaults)")
skipBtn:SetScript("OnClick", function()
    TRP3FW.Prefs.complexitySetupDone = true
    f:Hide()
end)
```

### Expected Result

No silent failure on first install. User can dismiss the wizard without being forced to select a complexity level.

---

## Summary Table

| # | Issue | Priority | File | Lines | Type |
|---|-------|----------|------|-------|------|
| 1 | Frame width clips tab buttons | High | `settings.lua` | 863–874 | Bug |
| 2 | Active tab loses highlight on reopen | High | `settings.lua` | 866–874 | UX |
| 3 | RefreshUI no-op while hidden → stale state | High | `settings.lua` | 521–522 | Bug |
| 4 | Scan group frame SetSize conflicts with anchors | Medium | `Notifications.lua` | 61–71, 206 | Bug |
| 5 | Slider/checkbox overlap in Debug tab | Medium | `Debug.lua` | 88–110 | Layout |
| 6 | 20 override rows always rendered | Low | `Alerts.lua` | 314–334 | Performance |
| 7 | Wizard RefreshUI called before frame exists | Low | `settings.lua` | 908 | Edge case |

---

## Implementation Notes

- Issues 1–3 are in `settings.lua` and should be done together since they interact (frame size, OnShow hook).
- Issues 4 and 5 are self-contained in their respective tab files.
- Issue 6 requires extracting the row-creation logic into a named function — test that existing saved overrides still load correctly after refactor.
- Issue 7 is a tiny guard + one new button — low risk.
- All changes are backwards-compatible with existing `TRP3FW_Settings` SavedVariables.
- No `.toc` changes required.

---

**Last Updated:** 2026-04-27  
**Author:** Review session  
**Status:** Awaiting approval before implementation
