[🇨🇳 中文文档 / Chinese](README.zh-CN.md) · [Development](DEVELOPMENT.md)

# AdGuardHome LuCI Dashboard

**Standard AdGuard Home management panel for LuCI 2.0** | **LuCI 2.0 AdGuard Home Dashboard**
**v2.6.0**

A complete AdGuard Home management panel for OpenWrt / ImmortalWrt / iStoreOS.

---

## Install

### One-click install (recommended)

```sh
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh | sh
```

> Piping the script into `sh` (rather than `sh -c "$(curl …)"`) avoids the OS **per-argument length limit**: the old form passed the whole installer as a single command-line argument, and aborts *before running* as soon as the script grows past that limit. The prompts are read from the terminal, so the interactive steps are unaffected.

The install script runs in two steps:

1. **AdGuard Home core** — detects whether `/opt/AdGuardHome/AdGuardHome` is installed; if not, it calls the official script to auto-install. If already installed, you can choose to overwrite (auto-stops the running service) or skip.
2. **LuCI Dashboard** — downloads menu registration, Lua Controller, JS View, translations and `checksums.sha256` from GitHub into a temp dir, performs **sha256 content-fingerprint verification** (aborts immediately and prompts to switch proxy if a stale cached version is hit), then deploys to the corresponding system locations.

> Before overwriting, install.sh automatically backs up the existing panel files (including `manifest.json`) to `/root/agh_backup_install_<ts>/` and generates `restore.sh` inside the backup dir. If the install fails or you want to roll back to the old panel, run `sh /root/agh_backup_install_<ts>/restore.sh` (restores panel files only, does not touch the AGH core binary).

### Domestic acceleration / Proxy

Two **semantically different** connection types are supported. They are **not interchangeable** — a mirror is a URL *prefix*, a full proxy is a `curl -x` target; using a proxy address as a prefix builds an invalid URL that always fails.

- **Mirror** (URL *prefix*) — wire form `mirror|<prefix>`, e.g. `mirror|https://ghfast.top/`.
  curl appends the original GitHub URL to the prefix. **Mainland China only.**
- **Full proxy** (like a system proxy) — wire form `proxy|<addr>`, e.g. `proxy|http://127.0.0.1:7890` or `proxy|socks5://127.0.0.1:1080`.
  curl uses `-x <addr>` and leaves the URL unchanged. Works in any region.
- **Direct** — empty value; plain curl.

On startup the script auto-detects GitHub connectivity and tests each candidate, showing latency so you can pick a working one:

```
  #   connection              status
  ─────────────────────────────────────────
  1)  direct                  ✗ unavailable
  2)  ghfast.top              ✓ 320ms   [mainland China only]
  3)  gh-proxy.com            ✓ 450ms   [mainland China only]
  4)  Custom mirror URL       (prefix type)
  5)  Custom proxy server     (http://host:port | socks5://host:port)
```

`GITHUB_PROXY` accepts the same wire form and skips detection. Prefix the value with `proxy|` for a full proxy server; a bare value ending in `/` is treated as a mirror (legacy compatibility):

```sh
# mirror (URL prefix)
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh | GITHUB_PROXY=https://ghfast.top/ sh
# full proxy server (system-proxy style)
GITHUB_PROXY=proxy|http://127.0.0.1:7890 sh install.sh
```

> Note: the `curl` URL that downloads the script itself must also go through the mirror — as shown above, the `curl` URL already has the `ghfast.top/` prefix. (A full proxy server, being a network-level proxy, needs no prefix.)

> **Region-aware**: the built-in mirrors only serve mainland China. When the router's egress IP is detected **outside mainland China**, `install.sh` skips them and offers only `Direct` + the two custom inputs; the dashboard hides the mirror rows as well. Both keep the **manual inputs available at all times**, and in the dashboard a previously selected **mirror** is automatically switched back to `Direct` (and stated in the banner) — so a hidden mirror can never keep breaking requests invisibly.

The selection is stored in `/etc/adguardhome-dashboard.proxy` in the wire form above (`proxy=mirror|https://ghfast.top/`), and the same format is used by `install.sh`, the dashboard and the generated upgrade scripts.

### Install from a local clone

If you have cloned the project onto the router, running it from the project directory uses local files automatically (no network download needed):

```sh
cd /path/to/luci-app-adguardhome-dashboard
sh scripts/install.sh
```

> `install.sh` is idempotent for both install and update, and auto-cleans old version files.

### Offline install (release package)

Every release also publishes a self-contained tarball — `luci-app-adguardhome-dashboard-vX.Y.Z.tar.gz` — as an asset on the [Releases page](https://github.com/imonior/luci-app-adguardhome-dashboard/releases). Download it, extract it, and install **without any network access at all**:

```sh
# Get the tarball onto the router however suits you (scp, USB stick, ...), then:
tar xzf luci-app-adguardhome-dashboard-vX.Y.Z.tar.gz
cd luci-app-adguardhome-dashboard-vX.Y.Z
sh scripts/install.sh
```

The package carries an `OFFLINE_PACKAGE` marker, so `install.sh` detects it and skips the egress-IP probe, the connection test and every online version lookup. It deploys straight from `./files` and verifies each file against the bundled `checksums.sha256` — the same fingerprint check the online install performs.

Three things to know:

- The package bundles the **LuCI panel only**. The AdGuard Home core is never bundled — it is released on its own schedule, so it cannot be pinned into a package. To install the core offline, put the official tarball for your machine's architecture next to the package directory (the installer scans that folder and its parent):
  ```sh
  AdGuardHome_linux_arm64.tar.gz     # use the arch printed by `uname -m`
  ```
  The installer detects it, unpacks it into `/opt/AdGuardHome` and registers the service — still with zero network access. If the tarball is missing or its architecture does not match, only the panel is installed and the installer prints exactly which file to fetch. Get the tarball from the [AdGuard Home releases page](https://github.com/AdguardTeam/AdGuardHome/releases/latest).
- **Existing installations are never silently overwritten.** Both the AdGuard Home core and this panel are detected first, and in both online and offline runs you are asked whether to reinstall or keep the current version.
- The same offline behaviour can be forced on any checkout with `sh scripts/install.sh -l` (alias: `--local` / `--offline`).

To build the package yourself: `sh scripts/make_package.sh` (writes to `dist/`).

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/uninstall.sh | sh
```

---

## Features

- **LuCI 2.0 standard architecture**: menu.json registration + JS View lifecycle management (not template rendering)
- **Backend RPC**: Lua Controller exposes 14 API endpoints, no ACL privilege escalation
- **Real-time status monitoring**: 5-second polling, live version/running state/PID/ports/proxy/panel version
- **Service console**: start/stop/restart/register system service, supports both init.d and binary modes
- **Layered log viewer**: stacked mode — top is the exec/upgrade log (EXEC_LOG), bottom appends AGH native log or system `logread` (latest 50/100 lines); supports manual refresh, 2-second auto-polling during upgrade, optional auto-refresh toggle (3s), and one-click clear of the middle-layer log
- **Core version management**: check update + one-click upgrade + force reinstall, with 2-second progress polling
- **Global proxy selection**: two **typed** connection kinds — **mirror** (`mirror|<prefix>`, a URL prefix, preset candidates labelled *mainland China only*) and **full proxy** (`proxy|<addr>`, `curl -x`, works anywhere, incl. `socks5://`) — each with its own custom input row, plus `Direct`; persisted immediately to `/etc/adguardhome-dashboard.proxy` on selection
- **Proxy latency test**: single-point / batch test of all candidates, each tested with its own type-aware invocation (mirror prefix vs `curl -x`), target matches the actual download domain (`raw.githubusercontent.com`)
- **Network egress / region detection**: on load the panel probes the router's public egress IP and region via public geo-IP services and shows the geolocation; when the region is **outside mainland China** the CN-only mirror rows are hidden, and a previously selected **mirror** is **automatically switched back to `Direct`** (persisted, and explicitly stated in the banner) so no hidden proxy keeps breaking requests. The two manual inputs (custom mirror / custom proxy server) and the `Direct` option always stay available; `install.sh` applies the same rule
- **Panel self-upgrade**: check panel version (reads `manifest.json`) → one-click upgrade (downloads 7 panel files including `manifest.json` and overwrites locally), no manual upload needed
- **Two-phase commit + auto rollback**: both core and panel upgrades use "download to temp dir + integrity check → backup + atomic mv overwrite"; any step failure auto-restores deployed files from backup
- **Integrity verification (two layers)**: ① type check — lmo magic `LMO\0` / lua contains `function` / js contains `view.extend` / po contains `msgid`, preventing empty files / 404 HTML / truncation; ② **sha256 content fingerprint**: both install and panel upgrade first download `checksums.sha256` and compare each panel file's sha256; any content inconsistent with the release manifest (especially stale proxy/CDN caches) is blocked and the upgrade aborts, avoiding a broken panel
- **Backup management**: lists all `/root/agh_backup_*` backup dirs (install/core/dashboard), showing type/timestamp/file count/size/contains-core/contains-restore.sh; supports one-click restore (only install/dashboard backups have restore.sh), shows restore command, and delete to free space
- **install self-backup**: install.sh auto-backs-up existing panel files (including `manifest.json`) + generates restore.sh, identical to the panel-upgrade backup mechanism
- **i18n support**: auto switch between Chinese and English based on LuCI system language (139 translations; every dictionary entry is referenced and every `T()` call has an entry)
- **Cross-platform**: OpenWrt / ImmortalWrt / iStoreOS

---

## Project Structure

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh        # install/update script (Part1: AGH core  Part2: Dashboard files + auto-backup + restore.sh)
│   └── uninstall.sh      # uninstall script
├── files/
│   ├── luci/
│   │   ├── menu.d/
│   │   │   └── luci-app-adguardhome-dashboard.json  # LuCI 2.0 menu registration
│   │   ├── acl.json      # rpcd access control
│   │   ├── controller/
│   │   │   └── adguardhome.lua  # backend Lua Controller (13 API endpoints)
│   │   └── i18n/
│   │       ├── adguardhome.po       # English translation source
│   │       ├── adguardhome.zh-cn.po # Chinese translation source
│   │       ├── adguardhome.lmo      # compiled English translation (LuCI binary format)
│   │       └── adguardhome.zh-cn.lmo# compiled Chinese translation
│   └── view/
│       └── dashboard.js  # LuCI 2.0 JS View (view.extend)
├── tools/
│   └── po2lmo.py         # .po → .lmo compiler (dev only, not deployed)
├── checksums.sha256      # release sha256 manifest (source of content fingerprint for install / panel upgrade)
├── manifest.json         # package manifest (panel self-upgrade version source)
├── README.md             # project docs (English, default)
└── README.zh-CN.md       # project docs (Chinese)
```

---

## API Endpoints

| Path | Method | Function |
|------|--------|----------|
| `/admin/services/adguardhome/status` | GET | get status (version/running/PID/ports/path/proxy/panel version) |
| `/admin/services/adguardhome/action` | POST | run action (start/stop/restart/install_service/install_core) |
| `/admin/services/adguardhome/set_proxy` | POST | persist the typed proxy spec immediately to `/etc/adguardhome-dashboard.proxy` (`mirror\|<prefix>` / `proxy\|<addr>` / empty = direct) |
| `/admin/services/adguardhome/proxy_test` | POST | test proxy latency with the type-aware invocation (mirror prefix vs `curl -x`; target: `raw.githubusercontent.com`) |
| `/admin/services/adguardhome/check_update` | POST | check latest AGH core version on GitHub (uses persisted proxy) |
| `/admin/services/adguardhome/upgrade` | POST | start AGH core upgrade (force=0 uses `--update` / force=1 uses install script `-r`) |
| `/admin/services/adguardhome/check_dashboard_update` | GET | check latest panel version (reads GitHub `manifest.json`) |
| `/admin/services/adguardhome/upgrade_dashboard` | POST | start panel self-upgrade (download 7 files incl. `manifest.json` and overwrite locally) |
| `/admin/services/adguardhome/log` | GET | get layered log (top EXEC_LOG + bottom AGH-native/logread + header summary) |
| `/admin/services/adguardhome/clear_log` | POST | clear middle-layer exec/upgrade log (EXEC_LOG) |
| `/admin/services/adguardhome/backups` | GET | list all `/root/agh_backup_*` backup dirs |
| `/admin/services/adguardhome/restore_backup` | POST | restore from a specified backup (runs `<dir>/restore.sh`) |
| `/admin/services/adguardhome/delete_backup` | POST | delete a specified backup dir |

---

## Upgrade Flow

> **Channel support**: This panel only upgrades AdGuard Home on the **stable (release)** channel. It cannot switch to or pull from the **beta / edge** channels — the core upgrade always targets the latest stable release. If you have manually installed a beta/edge build, upgrade via `AdGuardHome --update` directly or reinstall a stable build.

### AGH core upgrade (two-phase commit + auto rollback)

```
Phase 1: backup current binary → /root/agh_backup_core_<ts>/AdGuardHome
Phase 2: run upgrade
       ├─ force=1: multi-proxy download install.sh → stop service → sh install.sh -r
       ├─ force=0 + binary present: AdGuardHome --update
       └─ no binary: multi-proxy download install.sh → sh install.sh
Phase 3: integrity check (new binary exists + executable + can print version)
Phase 4: check failed → restore old binary from backup + restart service → write FAILED marker
Phase 5: restart service → write done marker
```

### Panel self-upgrade (two-phase commit + auto rollback)

```
Phase 1: download all 7 files to /tmp/agh_dash_new_<ts>/ + integrity check
       ├─ first download checksums.sha256 (content-fingerprint manifest, from GitHub main)
       ├─ compare each file's sha256 (pass only if consistent with release manifest; stale proxy cache is blocked)
       ├─ lmo: check trailing magic 4c4d6f00 (LMO\0)
       ├─ lua: check contains 'function' + 'list_backups'
       ├─ js:  check contains 'view.extend' + 'fetchBackups'
       └─ po:  check contains 'msgid'
       any failure → write FAILED marker + auto rollback → no target file touched
Phase 2: per-file backup + atomic mv overwrite
       any failure → restore deployed files from /root/agh_backup_dashboard_<ts>/ → write FAILED marker
Phase 2.5: generate restore.sh in backup dir (consistent with install.sh restore logic, restores 7 panel files incl. manifest.json)
Phase 3: clear LuCI cache + restart rpcd/uhttpd → write done marker
```

---

## Version Rollback

### In-panel downgrade is not supported

`check_dashboard_update` only prompts when the remote version on GitHub `main` is **newer** than the
installed one (`need_update = remote > local`). After the release source is rolled back, panels already
running the newer version simply show "up to date" — the upgrade flow never performs a downgrade.
Downgrading is a command-line operation only.

### Install any released version (works on the router directly)

Every tag has an auto-generated source archive on GitHub, which is itself a working installer package
(the archive mirrors the repo skeleton the installer expects):

```sh
cd /tmp
curl -fLO https://github.com/imonior/luci-app-adguardhome-dashboard/archive/refs/tags/v2.5.6.tar.gz
tar xzf v2.5.6.tar.gz
sh luci-app-adguardhome-dashboard-2.5.6/scripts/install.sh
# Detected local project files -> choose 1) Install using local files
```

- Replace `v2.5.6` with any released tag. Verify afterwards: `cat /usr/share/adguardhome-dashboard/manifest.json` should show the expected version.
- The archive download hits `codeload.github.com`; in mainland China prefix the URL with a mirror (e.g. `https://ghfast.top/https://github.com/...`) or fetch it on another machine and `scp` it over.
- The AdGuard Home **core** is versioned independently of the panel — a panel rollback does not touch it.
- After a downgrade the panel will offer the newer version as an update again; just ignore it — nothing upgrades automatically.

### Rolling back the release itself

The release source is whatever sits on GitHub `main` (single source of truth = `manifest.json` there).
To retract a bad release, `git revert` the offending commits on `main` (avoid force-pushing): install.sh,
panel self-upgrade and `check_dashboard_update` immediately serve the previous version again, and
`checksums.sha256` reverts together with the code, so fingerprint checks stay consistent. Assets already
published under an existing tag are never overwritten or removed.

---

## Proxy Cache & Content Fingerprint

GitHub mirrors/CDNs (such as `ghfast.top`, `gh-proxy.com`) cache `raw.githubusercontent.com` content and often ignore the `?_cb=` timestamp parameter. If the cache holds an **older version missing some features**, install/upgrade silently installs a broken panel (this once caused the "Backup management" and "Clear log" buttons to disappear).

To fully guard against this, both install and panel upgrade use **two-layer verification**:

1. **sha256 content fingerprint (primary)**: first download `checksums.sha256` from GitHub main (records panel file sha256), then compare each downloaded file's sha256. Any content inconsistent with the release manifest (stale proxy cache, truncation, tampering) is **immediately aborted with a prompt to switch proxy** — a broken panel is never installed.
2. **Semantic feature (fallback)**: when `checksums.sha256` is unavailable (network etc.), degrade to keyword checks — `dashboard.js` must contain `fetchBackups`, `adguardhome.lua` must contain `list_backups`.

### Verify locally whether the deployed panel is up to date

```sh
# On the router: does the panel JS contain backup management? ( >0 means OK)
grep -c fetchBackups /www/luci-static/resources/view/adguardhome/dashboard.js

# In the repo: verify local files against the release manifest (all OK = matches release)
sha256sum -c checksums.sha256
```

### Hit an old version during install/upgrade?

The install log shows `sha256 mismatch` / `content verification failed` and prompts to switch proxy:

```sh
# Re-run with another proxy
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh | GITHUB_PROXY=https://ghfast.top/ sh
# Or connect directly to raw.githubusercontent.com (bypass mirror cache)
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/files/view/dashboard.js -o /www/luci-static/resources/view/adguardhome/dashboard.js
```

---

## Backup & Restore

### Three backup types

| Type | Created when | Path | Has restore.sh | Restores |
|------|------|------|:---:|------|
| install | install/update panel | `/root/agh_backup_install_<ts>` | ✓ | panel files (incl. manifest.json, core untouched) |
| dashboard | panel self-upgrade | `/root/agh_backup_dashboard_<ts>` | ✓ | panel files (incl. manifest.json, core untouched) |
| core | AGH core upgrade | `/root/agh_backup_core_<ts>` | ✗ | old binary only (manual `cp`) |

### How to restore

**In-panel**: LuCI → Services → AdGuard Home → Backup management → find the backup → click "Restore" or "Command"

**Command line**:
```sh
# install / dashboard backups
sh /root/agh_backup_install_<ts>/restore.sh
sh /root/agh_backup_dashboard_<ts>/restore.sh

# core backup (manual)
/etc/init.d/AdGuardHome stop 2>/dev/null || /etc/init.d/adguardhome stop 2>/dev/null
cp /root/agh_backup_core_<ts>/AdGuardHome /opt/AdGuardHome/AdGuardHome
chmod 755 /opt/AdGuardHome/AdGuardHome
/etc/init.d/AdGuardHome start 2>/dev/null || /etc/init.d/adguardhome start 2>/dev/null
```

> Clean backups: click "Delete" in panel Backup management, or manually `rm -rf /root/agh_backup_*`

---

## Layered Log

```
┌─────────────────────────────────────────┐
│ === AdGuardHome status ===             │  ← header summary
│ AdGuard Home v0.107.52                 │
│ PID: 1234 (running)                    │
│ ========================...             │
│                                         │
│ === Exec/Upgrade log ===               │  ← middle layer EXEC_LOG
│ [output of upgrade/start/stop actions]  │
│                                         │
│ === System/Runtime log (latest) ===     │  ← runtime layer
│ [AGH native log tail -n 100]            │
│ or [logread -e AdGuardHome tail -n 50]  │
└─────────────────────────────────────────┘
```

**Operations**:
- "Refresh log" button: re-fetch latest content, auto-scroll to bottom
- "Clear log" button: clears EXEC_LOG (runtime log is managed by AGH/system and is unaffected)
- "Auto refresh" toggle: 3s interval auto-fetch (yields to upgrade polling while an upgrade is in progress)

---

## Requirements

- OpenWrt / ImmortalWrt / iStoreOS
- LuCI 2.0 (OpenWrt 21.02+)
- curl (built into most firmwares)
- At least 8MB free space

---

## Notes

- After install, open the dashboard at LuCI → **Services** → **AdGuard Home**
- Proxy persistence file: `/etc/adguardhome-dashboard.proxy` (holds the typed spec, e.g. `proxy=mirror|https://ghfast.top/` or `proxy=proxy|http://127.0.0.1:7890`)
- Exec/upgrade log: `/tmp/agh_exec.log` (EXEC_LOG, contains `done` / `FAILED` markers for frontend polling)
- Install log: `/etc/adguardhome-dashboard.log`
- Backup dirs: `/root/agh_backup_{install,core,dashboard}_<ts>` (kept by timestamp, cleanable in panel Backup management)

---

## Architecture

```
Browser JS View  ──HTTP──▸  Lua Controller  ──exec──▸  System commands
(view.extend)              (util.exec)               (pgrep/init.d/binary)
     │                          │
     │ 5s poll status           │ read persisted proxy
     │ 2s poll log (upgrading)  │ call GitHub raw / API
     │ 3s poll log (auto-refresh)│ write EXEC_LOG / backup dirs
     └──────────────────────────┘
```

---

## Changelog

> Language: **English (default)** · [中文](README.zh-CN.md#变更记录--changelog) — user-facing docs are English by default; the zh-CN file is the translation companion.

- **v2.6.0**
  - **Fixed the egress IP / region banner never showing a result**: `sendGeoProbe` consumed the RPC response directly, but LuCI's client-side `request.get()` resolves to a **Response wrapper** (`status` / `headers` / `json()`), not the payload. `renderGeo` therefore saw `ok === undefined` on every call and always rendered the "could not detect egress IP" branch — even though the server-side probe had succeeded (the probe is fine and wider than the installer's: 10 endpoints vs 4, which is why the installer's detection always looked correct while the panel never did). The call now unwraps `res.json()` first, like every other RPC in the file
  - The same bug also disabled the region policy: `geoData.is_cn === false` (collapse the mainland-China-only mirror presets outside CN, and fall back to Direct if a mirror was selected) never evaluated. Both now work
  - **Fixed the English UI rendering Chinese**: every string added by the backup manager (33 entries — "Backup Management", "Refresh Backups", "Restore", "Delete", the table headers, the confirmations …) had been copied into `adguardhome.po` with the Chinese source left as the English `msgstr`, so an English-language LuCI showed Chinese labels. Translations filled in and **both `.lmo` files recompiled** — LuCI loads the binary `.lmo`, not the `.po`, so shipping a corrected `.po` alone would have changed nothing on the router
  - **The release gate now covers i18n**: `scripts/release.sh` gained a dedicated section — en ↔ zh-cn `.po` msgid sets must match, no English `msgstr` may still contain CJK, no zh-cn `msgstr` may be empty, each `.lmo` must be byte-identical to a fresh `tools/po2lmo.py` compile of its `.po` (a stale `.lmo` is otherwise completely invisible), the view's fallback `_EN` dictionary must have no untranslated value and must cover every `T()` key, and both READMEs must expose the same section structure. A missing `python3` / `po2lmo.py` fails under `--strict` instead of silently skipping the gate

- **v2.5.10**
  - **Fixed panel self-upgrade always aborting at the LMO check**: the generated upgrade runner hex-dumped the `.lmo` tail with `od -An -tx1`, but OpenWrt's BusyBox ships **no `od`** (install.sh's own byte-order comment has said exactly that all along). `2>/dev/null` swallowed `od: not found`, the digest stayed empty, and **every valid `.lmo` failed verification** — the upgrade rolled back with `[verify] LMO magic bad`. The magic check now hashes the last 4 bytes with `sha256_of` (already a hard dependency of the runner) and compares against the known digest of `LMO\0`; no new dependency, fail-closed on an empty digest
  - ⚠️ **Routers on ≤ 2.5.9 cannot self-upgrade to this version from the panel** — the broken verifier lives in the *deployed* controller that generates the runner, so the in-panel path cannot repair itself. Run the install.sh one-liner once (it downloads and deploys 2.5.10 directly); from 2.5.10 on, panel self-upgrade works again

- **v2.5.9**
  - **Fixed the panel self-upgrade silently doing nothing** (the "new version detected, but the log stays empty and nothing upgrades" bug): the generated upgrade script's stderr used to land on the HTTP socket and vanish with the connection, so any parse/startup failure left no trace at all. Both generated runners (core + panel) now redirect stderr into the execution log, and the dashboard checks the RPC `success` field instead of trusting HTTP 200 — a failed launch now raises a real error notification instead of a false "upgrade started" banner
  - **Anti-stale-view self-heal**: the view JS now embeds its own `DASHBOARD_VIEW_VERSION` and compares it with the server-reported version on render. A mismatch means the browser is executing a cached older view (LuCI caches view modules keyed by URL in localStorage / the HTTP cache — which is why a stale UI could survive a reinstall + refresh), so the dashboard clears those cached view entries and hard-reloads once (sessionStorage-guarded against loops). Upgrading no longer requires clearing browser storage by hand
  - **More robust network egress / region detection**: the geo probe now tries 10 endpoints instead of 4 (adds ipapi.co, api.myip.com, extreme-ip-lookup.com, checkip.amazonaws.com, ifconfig.me, icanhazip.com plus plain-IP services), retries each endpoint once, uses `--connect-timeout 4 --max-time 6` per attempt with a 25s overall cap, and returns the list of endpoints tried so the UI can show them on failure
  - **Release tooling**: new `scripts/release.sh` orchestrator — one command runs the full pre-push check (version consistency across `manifest.json` / the view JS constant / both READMEs, bilingual changelog entries, shell + JS + Lua syntax, `checksums.sha256` fingerprint, `changes_package/` sync) and then builds the offline installer tarball. The release workflow calls it as `--check --strict` before building, installs Lua on the runner (the image ships none, which had silently disabled the Lua syntax gate) and checks out full history so the tag/version cross-check can resolve the tag
  - The release asset stays a **lean offline installer** (deployable files + installer + manifest/checksums only) — the complete project source is the auto-generated *Source code* archive on the release page, so README/LICENSE are deliberately **not** duplicated into the installer
  - **One-line install command switched to the pipe form** — `curl -fsSL <url> | sh` instead of `sh -c "$(curl …)"`. The command substitution expands the whole script into a single argv, so it dies with `argument list too long` once the script outgrows the per-argument limit; piping through stdin has no such ceiling (and no temp file to clean up). The installer is now safe to feed this way: interactive reads go through a `read_input` helper that falls back to `/dev/tty` when the script itself arrives on stdin (a bare `read` would swallow the *next line of the script*), and interactivity is decided by one `_is_interactive` predicate shared with that reader, so a piped run can still prompt. `sh install.sh` (and `printf '1\n' | sh install.sh`) behave exactly as before. When the script is fed from stdin the local-project paths are cleared too, so the "re-download after deleting the local copy" branch can never resolve to the pseudo-parent of the current directory
  - `DEVELOPMENT.md` release section rewritten to match the current pipeline (four-place version bump, checksum regeneration, `scripts/release.sh --check`, CI `--check --strict`)

- **v2.5.8**
  - **Offline install package**: every release now ships a self-contained tarball (built by `scripts/make_package.sh` + the release workflow on tag push). Download, extract, run `scripts/install.sh` — the `OFFLINE_PACKAGE` marker gates **every** network touchpoint (geo probe, connection selection, online version check, file downloads)
  - **AdGuard Home core is supplied locally, never bundled**: the installer scans `AdGuardHome_linux_<arch>.tar.gz` next to the project (two levels: project dir + parent) and installs the core fully offline, mirroring the official three steps (clean dir → `tar -C /opt -x -z` → `-s install`) with a `--version` self-check and full rollback on any failure. A matching package + existing core → asked whether to overwrite; arch mismatch → prints both sides (this machine vs. packages found); no package → prints the exact filename plus **direct download links** (AGH CDN `static.adtidy.org` and the GitHub release asset, the latter mirror-friendly for mainland China) and the release page
  - **Existing-install detection for both AGH core and this panel**, online and offline alike: existing installs are detected first and you are asked whether to reinstall (panel defaults to reinstall; core overwrite defaults to keep)
  - **Version Rollback documented** (see its own section): in-panel downgrade is not supported; any released version installs from its tag source archive with a one-liner; retracting a release = `git revert` on `main`
  - The overwrite cleanup criterion is now the install **directory** (`-d /opt/AdGuardHome`) instead of the binary, so leftover directories cannot mix stale files into a fresh install
  - Three bare `read` calls hardened against `set -e` + stdin EOF (previously could silently abort the whole install)
  - All of the v2.5.7 work below shipped in this release (v2.5.7 was never published as its own version)
  - Replaced the dashboard version comparator (`semver_compare`, which compared all numeric segment naively and could not order prerelease versions) with a SemVer-correct implementation (`compareSemVer`/`parseSemVer`); a release build now correctly reports as newer than its own beta, so panel self-upgrade prompts behave correctly after any prerelease line
  - Added a third fallback for AdGuard Home core update checks: `static.adtidy.org/adguardhome/release/version.json` (AdGuard Team's own CDN), reached when both GitHub API and raw CHANGELOG paths fail — improves reachability on networks where GitHub is blocked
  - Fixed a cosmetic log bug: the upgraded-binary line printed a double `v` (`vv0.107.79`) because the version already includes the `v` prefix
  - Documented that the panel supports **stable-channel upgrade only** (no beta/edge channel switching)
  - Removed the `kkgithub.com` proxy candidate (a short-lived domain that cannot provide long-term service); the built-in proxy list is now `ghfast.top` / `gh-proxy.com` only
  - Added **network egress / region detection**: both `install.sh` and the dashboard now probe the router's public IP and region (via public geo-IP services), display the IP geolocation, and recommend a proxy in mainland China vs. noting direct works abroad
  - Built-in mirrors (`ghfast.top` / `gh-proxy.com`) are now treated as **mainland-CN only**: outside mainland China `install.sh` skips them (offering Direct + Custom only) and the dashboard hides the mirror rows — the manual inputs stay available in both, and `GITHUB_PROXY` still overrides everything
  - **Two typed proxy kinds** (they are not interchangeable — a mirror is a URL *prefix*, a full proxy is a `curl -x` target):
    - `mirror|<prefix>` — GitHub URLs are appended to the prefix; **mainland China only**; preset candidates are now labelled *"mainland China only"* in the UI
    - `proxy|<addr>` — passed as `curl -x` with the URL unchanged (system-proxy style, `http(s)`/`socks5`); works in any region
    - A single wire format is shared by `install.sh`, the dashboard, `/etc/adguardhome-dashboard.proxy` and both generated upgrade scripts; bare legacy values are still read as mirrors (backward compatible)
  - Dashboard proxy area now has **two separate manual input rows** — *Custom mirror* and *Custom proxy server* — instead of one ambiguous box (typing a proxy address into a prefix field used to build a URL that always failed)
  - Region fallback is now **explicit instead of silent**: outside mainland China a previously selected *mirror* is automatically switched back to `Direct` and persisted, and the banner says so — a hidden mirror can no longer keep breaking requests with no clue why
  - **Fixed a crash in the proxy resolver**: `resolve_proxy()` called `is_safe_proxy()` before it was declared, which in Lua's lexical scoping resolves to a global (`nil`) — any request carrying a `proxy` form value (all five proxy-related RPCs do) raised `attempt to call a nil value`, surfacing as "network broken with no reason". The validator now precedes its callers
  - Proxy validation widened for full proxies (`socks5://`, bare `host:port`) while the injection guard stays whitelist-based
  - The generated **core-upgrade** script now routes every download through one type-aware helper instead of a mirror-only loop, and applies a selected **full proxy** to the otherwise-direct `AdGuardHome --update` step via `HTTPS_PROXY`/`HTTP_PROXY`
  - i18n dictionary audited: every `T()` call now has an entry and every entry is referenced (6 dead entries removed)

- **v2.5.6**
  - Extended the proxy-aware GitHub Releases fallback (previously added for `AdGuardHome --update`) to the force-reinstall (`install.sh -r`) and fresh-install paths. These previously fetched the binary package directly from `static.adtidy.org` (bypassing the selected proxy) with no fallback on failure; now they fall back to a proxy-aware package download + overwrite when `install.sh` fails
  - `fallback_upgrade_via_proxy` now takes an explicit destination argument (defaults to `BIN_PATH`, or the first `BIN_PATHS` entry when unset), so the fresh-install path can place the binary correctly

- **v2.5.5**
  - Proxy selection simplified to: test connectivity → pick by result (install: enter number; dashboard: click) → fixed for the session; only if the chosen connection actually fails mid-download does it re-prompt with a fresh connectivity test (install.sh)
  - Custom proxy latency test now works reliably (`proxify()` normalizes the missing trailing slash)
  - Dashboard proxy test UX: page-load auto-test + manual per-proxy single test + "Test All" button; removed the 60s background polling and the auto re-test on upgrade FAILED (user can click test manually)

- **v2.5.1**
  - Fixed install.sh verification root cause: `verify_one()` returned the boolean inverted, so valid files were flagged as failed (aborting install) and stale/cached files were silently accepted. Present since the 2.3.1 fingerprint check; now corrected (pass → 0, fail → 1)
  - Panel self-upgrade now strictly honors the UI proxy choice (direct = direct only; selected proxy = that proxy + direct fallback) instead of always appending built-in proxies
  - Panel self-upgrade download hardened: target dir is created before each `curl -o`, eliminating the `curl: (23)` write failure
  - install.sh GitHub direct connectivity probe now retries (3×, 12s each) so a merely-slow `raw.githubusercontent.com` is no longer misreported as "direct unavailable"
  - install.sh interaction is now English by default with a language picker (English / 中文); reinstall backup messaging clarified

- **v2.5.0**
  - Bumped version to **2.5.0** (single version source = `manifest.json`; the router reads the locally deployed `/usr/share/adguardhome-dashboard/manifest.json` at runtime)
  - Fixed panel self-upgrade "all downloads fail after clicking upgrade, leaving only an empty backup dir":
    - The upgrade script previously passed `$TMPDIR` as a literal into a single-quoted shell argument, so `curl -o` wrote to a fake path causing `curl: (23)` write failure; now uses the real absolute path computed by Lua
    - The backup dir is now created lazily per file, so no empty backup dir is left behind when download/verify fails
  - Clarified "Clear log" semantics: only clears the middle-layer exec/upgrade log (EXEC_LOG); the system/AGH runtime log layer is view-only cleared and re-shows after refresh (system/AGH's own logs are never deleted)
- **v2.4.0**
  - Added backup management, panel self-upgrade, sha256 content-fingerprint two-layer verification, proxy-cache protection, etc. (see "Proxy Cache & Content Fingerprint")

---

**MIT License** | Lightweight · Stable · Standard LuCI 2.0
