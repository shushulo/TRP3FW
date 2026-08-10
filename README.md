# TRP3 Firewall (TRP3FW)

**Intelligent Profile Privacy & Security for Roleplayers**

[![Version](https://img.shields.io/badge/version-1.6.1-blue.svg)]()
[![WoW](https://img.shields.io/badge/WoW-9.2.7%2B-orange.svg)]()
[![License](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)

TRP3 Firewall controls who receives *your* RP profile. When another player's addon requests your
profile, TRP3FW works out whether they are actually near you — same phase, same map, same zone —
and then allows, blocks, or "ghosts" the request (sends a blank profile instead of refusing
outright). The result is more privacy in crowded areas and less profile traffic overall.

It only ever gates **outgoing** data. You can always request other players' profiles, and nothing
you do here stops other people from seeing you in-game.

---

## Installation

1. Download the latest `TRP3FW.zip` from the [Releases](../../releases) page.
2. Extract the `TRP3FW` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
3. If the extracted folder has a version number in its name (e.g. `TRP3FW-1.6.0`), rename it to
   just `TRP3FW`. WoW will not load it otherwise.
4. Restart the game, or `/reload` if you are already logged in.

TRP3FW gates profile traffic belonging to another addon, so it needs one of
[Total RP 3](https://totalrp3.info), [MyRolePlay](https://www.curseforge.com/wow/addons/my-roleplay),
or [XRP](https://www.curseforge.com/wow/addons/xrp) to do anything useful. It loads without one
and simply has nothing to gate. Run `/trp3fw status` to see what was detected.

---

## Getting Started

Open the settings window with **`/trp3fwui`** (or `/trp3fw ui`, or click the minimap button).

On first launch you are asked to pick a **settings complexity level** — Basic, Intermediate,
Advanced, or Everything. This only controls how many options the UI shows you; it does not change
how the firewall behaves. Intermediate is the default, and you can change it any time from the
sidebar. "Skip" leaves it at the default.

### Presets

The **Alerts** tab has five one-click presets. Out of the box TRP3FW behaves like **Balanced** —
it notifies you but blocks nothing, so you can watch what it would do before letting it act.

| Preset | Behavior |
|--------|----------|
| **Relaxed** | Map alerts only. Phase checking off. Never blocks. |
| **Balanced** | **(Default)** Alerts on both phase and map mismatches. Never blocks. |
| **Recommended** | Alerts *and* blocks requests from players in a different phase or map. |
| **Strict** | As Recommended, plus blocks map-scan replies. |
| **Ghosty** | Sends **blank profiles** instead of blocking, so requesters see nothing unusual. |

Presets are a starting point — every underlying option stays editable afterwards.

---

## Key Features

* **Cascading location detection** — tries a **phase check**, then a **WHO query**, then a
  **map scan**, using the first that succeeds. Phase and WHO checks require the Epsilon server's
  API; map scanning works everywhere.
* **Ghost mode** — instead of blocking, send a blank profile, or a decoy profile of your own
  making (create a TRP3 profile, name it in the settings, and TRP3FW sends that instead).
  Per-phase and per-map overrides are supported.
* **Cross-protocol** — works with **Total RP 3**, **MyRolePlay**, and **XRP**, including the
  Mary Sue Protocol paths those addons share.
* **Content filters** — optionally strip colour gradients and inline icons from *incoming*
  profiles, collapse names padded with newlines and runs of spaces to inflate a tooltip, or
  enforce a minimum font size so nobody can send you unreadable text.
* **Built for crowds** — request batching, LRU caches on every hot path, and throttled WHO
  queries keep the cost flat when 50 people load in at once.
* **Security-minded** — all player names are sanitized before use, every cache is size-capped,
  and network-fed state is bounded and expired rather than allowed to grow.

---

## Common Commands

`/trp3fw` on its own prints the full command list. The ones worth knowing:

| Command | What it does |
|---------|--------------|
| `/trp3fwui` | Open the settings window (also `/trp3fw ui`) |
| `/trp3fw status` | Current settings, detected addons, hook and cache health |
| `/trp3fw stats` | Session counts — allows, blocks, ghosts, alerts |
| `/trp3fw location` | Your current map ID and zone name |
| `/trp3fw test` | Play sample notifications so you know what alerts look like |
| `/trp3fw reloadhooks` | Reinstall hooks after another addon updates |
| `/trp3fw debug` | Toggle debug output (see below) |
| `/reload` | Reload the UI |

### Troubleshooting

Start with `/trp3fw status` — it reports which addons were detected, whether the Epsilon API is
available, and whether the hooks installed cleanly.

* **Nothing seems to happen** — check an RP addon was detected, then try `/trp3fw reloadhooks`.
* **Phase or WHO checks unavailable** — both need Epsilon's API. On other servers TRP3FW falls
  back to map scanning automatically.
* **No notifications** — `/trp3fw notify toggle` and `/trp3fw display chat`.
* **Digging deeper** — `/trp3fw debug` then `/trp3fw debugfilter decision` (also `location`,
  `cache`, `ghost`, `hooks`, and others) narrows the output to one area.

---

## Project Info

* **Version:** 1.6.1
* **Interface:** 9.2.7+ (90207)
* **License:** [GPL-3.0](LICENSE)

Settings are stored per-account in `WTF/Account/<account>/SavedVariables/TRP3FW.lua`.
