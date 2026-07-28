# Specification: 2026 Architectural Phase 2 - Modularization & Decoupling

**Status:** Completed
**Date:** 2026-02-22
**Target Version:** 3.0.0-beta
**Pre-requisites:** Phase 1 (Complete)

## 1. Overview
Following the successful completion of the Phase 1 cleanup (core hardening and event centralization), Phase 2 addresses the two largest remaining areas of architectural debt: the tightly-coupled WHO engine and the 6,000-line settings monolith.

## 2. Component 1: WHO Engine Decoupling

### 2.1 WHO Service
**Done:** Extracted core logic into `WhoService.lua`. `location/who.lua` is now a thin wrapper.

### 2.2 Suppression Logic
**Done:** Migrated chat filters and WhoList hooks to `WhoService`.

## 3. Component 2: UI Modularization

### 3.1 Tab Manager
**Done:** Implemented `ui/TabManager.lua` for lazy loading and module registration.

### 3.2 Modular Tabs
*   **Status.lua**: **Done** (Migrated metrics and cache performance).
*   **Notifications.lua**: **Done** (Migrated notification settings).
*   **Alerts.lua**: **Done** (Migrated location, SPVP, and override settings).
*   **Filters.lua**: **Done** (Migrated filters and hook safety).
*   **Debug.lua**: **Done** (Migrated cache and debug settings).
*   **Profiles.lua**: **Done** (Migrated profile management).

### 3.3 Settings Coordinator
**Done:** Refactored `ui/settings.lua` to act as a coordinator. It handles `RefreshUI` with defensive guards, manages the `TabManager`, and initializes the main frame. Redundant legacy code blocks were removed.

## 4. Implementation Plan

| Step | Task | Status | Risk |
| :--- | :--- | :--- | :--- |
| **1** | **WHO Service Extraction** | **Done** | Medium |
| **2** | **WHO Suppression Migration** | **Done** | Low |
| **3** | **Settings Infrastructure** | **Done** | High |
| **4** | **Tab Extraction (Status)** | **Done** | Medium |
| **5** | **Tab Extraction (Notifications)** | **Done** | Medium |
| **6** | **Tab Extraction (Alerts/Security)** | **Done** | Medium |
| **7** | **Tab Extraction (Filters)** | **Done** | Medium |
| **8** | **Tab Extraction (Debug)** | **Done** | Medium |
| **9** | **Tab Extraction (Profiles)** | **Done** | Medium |
| **10** | **Clean up Settings.lua** | **Done** | High |
| **11** | **Fix Status Tab Metrics** | **Done** | Low |
