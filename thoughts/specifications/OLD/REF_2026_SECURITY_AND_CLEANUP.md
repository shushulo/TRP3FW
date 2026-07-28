# Specification: 2026 Security Hardening & Architectural Cleanup

**Status:** Complete
**Date:** 2026-02-22
**Target Version:** 3.0.0-alpha

## 1. Overview
Following a comprehensive audit of the TRP3FW codebase and its associated design documents (`thoughts/`), this specification defines a set of targeted improvements to further harden the addon's security posture and prune architectural debt accumulated during the V2 lifecycle.

## 2. Security Findings & Hardening

### 2.1 Single-Quote Escaping in `SanitizePlayerName`
**Issue:** `SecurityService:SanitizePlayerName` currently escapes double quotes (`"`) and backslashes (`\`), but omits single quotes (`'`). While existing `RunPrivilegedSafe` calls primarily use double-quoted strings, any future transition to single quotes or use in contexts where single quotes act as delimiters could lead to Lua injection.

**Done:** Updated `SecurityService:SanitizePlayerName` to include single-quote escaping.

### 2.2 SPVP Entropy & PRNG Quality
**Issue:** The SPVP implementation relies on `math.random` and a 26-bit DH prime. While sufficient for preventing casual spoofing in a WoW environment, it is theoretically vulnerable to PRNG state prediction if an attacker can observe multiple handshakes.

**Done:** 
*   Increased the frequency of `math.randomseed` calls during salt generation using high-resolution entropy (`GetTimePreciseSec()`).
*   Improved re-seeding frequency during salt and session ID generation.

## 3. Architectural Cleanup

### 3.1 Caches
**Done:** Migrated all caches to the unified `CacheInterface`. Registered in `core/init.lua`.

### 3.2 Deprecated Code
**Done:** Removed `PhaseInStage` and `pendingPhaseInRequests`.

### 3.3 Decompose `CheckLocationCascading`
**Done:** Refactored `location/cascading.lua` into static local functions with context passing.

### 3.4 Event Centralization
**Done:** Implemented `core/EventService.lua`. Migrated major modules.

## 5. Implementation Plan

| Phase | Task | Status | Risk Level |
| :--- | :--- | :--- | :--- |
| **1. Security** | Escaping & PRNG Hardening | **Done** | Low |
| **2. Pruning** | Deprecated Tables, Fallbacks & Ghost Code | **Done** | Medium |
| **3. Refactor** | Decompose `CheckLocationCascading` | **Done** | Medium |
| **4. Cleanup** | Consolidate Decision Helpers | **Done** | Low |
| **5. Modularize**| Event Centralization | **Done** | High |
| **6. Decouple** | WHO Engine Extraction (Base) | **Done** | High |
