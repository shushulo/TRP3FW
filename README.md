# TRP3 Firewall (TRP3FW)

**Intelligent Profile Privacy & Security for Roleplayers**

[![Version](https://img.shields.io/badge/version-2.0--beta-blue.svg)]()
[![WoW](https://img.shields.io/badge/WoW-9.2.7%2B-orange.svg)]()
[![License](https://img.shields.io/badge/license-Personal%20Use-green.svg)]()

> **Beta v2.9.2+**: Now with **Intelligent Dynamic Batching** and **Soft Phase Verification** for high-traffic performance.

TRP3 Firewall monitors and controls who can see your RP profile. It automatically blocks or "ghosts" requests from players who are not nearby (different phase, map, or zone), improving privacy and performance in crowded areas.

---

## 🚀 Quick Start

### 1. Installation
*   Download the **TRP3FW** folder.
*   Place it in your `_retail_/Interface/AddOns/` directory.
*   **Required**: Ensure you have **TotalRP3**, **MyRolePlay**, or **XRP** installed.

### 2. First Launch & Presets
On first launch, you will be prompted to choose a preset. These can be changed later in `/trp3fwui`.

| Preset | Behavior |
|--------|----------|
| **Relaxed** | Notifications only. Never blocks anyone. |
| **Balanced** | Alert mode for both Phase and Map requests. |
| **Recommended** | **(Default)** Blocks requests from players in different phases/maps. |
| **Strict** | Maximum security. Blocks all non-nearby requests and scan replies. |
| **Ghosty** | Stealth mode. Sends **blank profiles** instead of blocking. |

### 3. Usage
*   **Open Settings:** `/trp3fwui`
*   **Check Status:** `/trp3fw status`
*   **Note:** You can always **request** other players' profiles. TRP3FW only blocks *your* outgoing data.

---

## 🛡️ Key Features

*   **Smart Location Detection**: Cascades through **Phase Checks** (Epsilon), **WHO Queries**, and **Map Scanning**.
*   **Ghost Mode**: Send a **blank** or **alternate profile** (e.g., "Unknown Hooded Figure") to blocked players.
*   **High Performance**: Intelligent dynamic batching handles 50+ concurrent requests instantly.
*   **Security Hardened**: Input sanitization, rate limiting, and protection against scan spoofing.
*   **Cross-Protocol**: Fully compatible with **TotalRP3**, **MyRolePlay**, and **XRP**.

**Project Info**
*   **Version:** 2.0-beta (v2.9.2+ Hotfix)
*   **Updated:** January 2026
*   **License:** Personal Use Only
