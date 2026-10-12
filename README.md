[🇨🇳 中文文档 / Chinese](README.zh-CN.md) · [Development](DEVELOPMENT.md)

# AdGuardHome LuCI Dashboard

**Standard AdGuard Home management panel for LuCI 2.0** | **LuCI 2.0 AdGuard Home Dashboard**
**v2.7.1**

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

> Before overwriting, install.sh automatically backs up the existing panel files (including `manifest.json`) to `/root/agh_backup_dashboard_<ts>/` and generates `restore.sh` inside the backup dir. If the install fails or you want to roll back to the old panel, run `sh /root/agh_backup_dashboard_<ts>/restore.sh` (restores panel files only, does not touch the AGH core binary). A backup is only created when panel files already exist — i.e. a **fresh install produces no backup**, and what install.sh backs up is always an **upgrade**.

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
- **Backup management**: lists all `/root/agh_backup_*` backup dirs (dashboard/core), showing type/timestamp/file count/size/contains-core/contains-restore.sh; supports one-click restore (only dashboard backups have restore.sh), shows restore command, and delete to free space
- **install self-backup**: install.sh auto-backs-up existing panel files (including `manifest.json`) + generates restore.sh, identical to the panel-upgrade backup mechanism
- **i18n support**: auto switch between Chinese and English based on LuCI system language (144 translations; every dictionary entry is referenced and every `T()` call has an entry)
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

## Supply-chain integrity (mirror authenticity) / 供应链完整性（镜像真实性）

When you upgrade (or install) through a mirror (`mirror|…`), the files **and** `checksums.sha256` both come from that same mirror. The per-file sha256 check therefore proves **integrity** (no corruption, no truncated download) and blocks a **stale cached build** from a CDN — but it does **not** prove **authenticity**: a malicious mirror (or a man-in-the-middle) can serve a self-consistent `(files, checksums.sha256)` pair, and the hash comparison passes because the checksum list is itself fetched from the attacker.

**As of v2.6.13 the RSA release-signature check is removed.** It was added in v2.6.9 to close the self-referential-checksum gap, but on stock OpenWrt the `openssl` CLI misreports a perfectly valid signature as invalid (confirmed: the released files verify `Verified OK` off-router, yet a hard gate there bricked upgrades even after `openssl-util` was installed — directly violating the project rule "signature verification must never be a hard gate for upgrades"). Upgrade / install now use **per-file sha256 integrity only, exactly like 2.6.2** — which catches corruption and stale proxy caches, but cannot prove authenticity against a malicious mirror.

Mirrors are still a convenience, not a trust boundary: use a mirror you trust, or connect directly to `raw.githubusercontent.com`.

---

## Backup & Restore

### Two backup types

| Type | Created when | Path | Has restore.sh | Restores |
|------|------|------|:---:|------|
| dashboard | panel upgrade — via the panel's "Upgrade panel" button **or** install.sh (one-liner / offline package) run over an existing install | `/root/agh_backup_dashboard_<ts>` | ✓ | panel files (incl. manifest.json, core untouched) |
| core | AGH core upgrade | `/root/agh_backup_core_<ts>` | ✗ | old binary only (manual `cp`) |

> Dirs named `agh_backup_install_<ts>` are the legacy name for the same thing: install.sh only ever wrote a backup when panel files already existed (a fresh install has nothing to back up), so those are panel upgrades too and are listed as such. New backups always use the `dashboard` prefix. Hover a row's type in the panel to see its raw directory name.

### How to restore

**In-panel**: LuCI → Services → AdGuard Home → Backup management → find the backup → click "Restore" or "Command"

**Command line**:
```sh
# panel upgrade backups
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
- Backup dirs: `/root/agh_backup_{dashboard,core}_<ts>` (kept by timestamp, cleanable in panel Backup management)

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

- **v2.7.1**
  - **Documentation correction, no functional change**: v2.7.0's release notes said a browser stuck on a stale view needs "one manual hard refresh" — that is wrong for this router and it matters, because following it does not fix the browser. A hard refresh (Ctrl+F5 / Cmd+Shift+R) still sends conditional revalidation headers, and uhttpd — which sends no `Cache-Control` and, on routers without a battery-backed RTC, can serve files whose mtime is *older* than the cached copy after a clock reset — answers `304`, so the browser keeps the stale body. The only reliable fix is to **enable "Disable cache" in the browser's devtools and reload with it enabled**, which skips the cache lookup entirely and sends no conditional headers (Safari: Develop → Disable Caches). The affected wording has been corrected in the v2.7.0, v2.6.7 and v2.6.5 entries below; the corresponding in-app guide (shown on version mismatch) was already correct
  - One code comment aligned with the same wording; `DASHBOARD_VIEW_VERSION` and manifest bumped to 2.7.1; `checksums.sha256` regenerated

- **v2.7.0**
  - **Removed the destructive-action mutex — and removed the race that had made it necessary.** Since v2.6.4 both upgrade runners were written to a fixed path (`/tmp/agh_core_upgrade_runner.sh`, `/tmp/agh_dashboard_upgrade_runner.sh`), so a click on a *different* button (Upgrade core / Force reinstall / Install core, each with its own confirm modal and its own button-level guard) truncated the script another click was still executing and started a second process. The mutex existed only to paper over that. Both runners now write to a unique path (`_PID_TIME_SEQ.sh`, with an existence probe so a script that is still running can never be overwritten) and clean up after themselves — the race is gone at its root, so the lock, its 120 s watchdog, its 90 s fallback timer and the silent "button does nothing" failure mode they introduced go with it. Every button keeps its own `disabled` guard, which is what actually stops one button from being submitted twice
  - **Removed the in-page view hot-swap** (fetching and re-evaluating `dashboard.js` in place). It failed in three real-world rounds (v2.6.5 / v2.6.7 / v2.6.11), and a page cannot turn off the browser's HTTP disk cache by itself. The button now opens the manual cache-disable guide directly, and the guide is triggered by a plain version mismatch at render time (`dashboard_version` vs `DASHBOARD_VIEW_VERSION`) instead of depending on the hot-swap failing. One consequence to know: a browser still stuck on an old view must **enable "Disable cache" in the browser's devtools and reload with it enabled** — a "hard refresh" is **not** enough (see the note below on why Ctrl+F5 / Cmd+Shift+R does not work here)
  - **Fixed a crash found during pre-release verification (never released)**: the generated self-cleanup line `rm -f '<runner>'` referenced `scrpath` *before* its `local` declaration, so Lua would have concatenated a nil value and aborted the core upgrade. The line is now emitted after the path exists
  - Manifest bumped to 2.7.0; `checksums.sha256` regenerated

- **v2.6.13**
  - **Removed the RSA release-signature check entirely — back to the 2.6.2 way.** The signature feature (added in v2.6.9) was meant to prove release authenticity against a malicious mirror, but `openssl` on stock OpenWrt misreports a valid signature as invalid, and gating on it bricked upgrades even after `openssl-util` was installed (the released files actually verify `Verified OK` off-router — confirmed byte-identical through the proxy and on desktop OpenSSL). We reverted to the pre-signature behaviour: upgrade and install now verify **per-file sha256 integrity only**, exactly like 2.6.2. This still catches corruption and stale proxy caches, but no longer blocks a working upgrade. The pinned public key, `verify_sig` / `verify_release_sig`, the openssl-util auto-install, and `checksums.sha256.sig` generation are all gone
  - Manifest bumped to 2.6.13; `checksums.sha256` regenerated (no signature)

- **v2.6.12**
  - **Upgrade auto-installs `openssl-util` for full signature verification (B+graceful)**: the release-signature check is now best-effort with a self-healing step. If `openssl` (the CLI from `openssl-util`) is missing, the runner first tries `opkg install openssl-util`; if that succeeds it verifies the signature at full strength, and only if the install fails (no `opkg` / offline) does it fall back to sha256-only with a warning. `checksums.sha256.sig` unavailable also degrades to sha256-only. Only a present-but-invalid signature (genuine tampering) still refuses to deploy. This fixes the v2.6.9 regression where a missing `openssl` refused every upgrade on stock OpenWrt images without `openssl-util`
  - Manifest bumped to 2.6.12; `checksums.sha256` regenerated and re-signed

- **v2.6.11**
  - **"Clear Cache & Reload" now tells you what to do instead of silently failing**: a web page cannot turn off the browser's HTTP disk cache by itself. There is no JS API for it (DevTools' "Disable cache" only works while DevTools is open), Service Workers require a secure context and `http://192.168.x.x/` is not one, and LuCI loads view modules with `Request.get(url, { cache: true })` (luci.js:2541 — `cache: true` means "do not append a timestamp", luci.js:740) on the page-navigation path we cannot intercept. So when the automatic hot-swap cannot confirm a fresh view, the button now opens a guide with the exact steps for Chrome/Edge, Firefox and Safari, plus a one-click reload that fires while your cache-disable is still active
  - **The guide only appears when the running version really differs from the installed one**: if the version executing in your browser already matches the server manifest, a failed refresh is just a transient network problem, and telling you to disable your browser cache would be noise. The check compares `DASHBOARD_VIEW_VERSION` (this JS file, i.e. what the browser loaded) with `statusData.dashboard_version` (server manifest, i.e. what is installed). Separately, if the bytes served back are identical to the ones already running, that is direct evidence the browser handed over its cached copy, and the guide is shown even when the two versions agree
  - **The hot-swap no longer reports success when it did not**: it now verifies the fetched text really carries the server's version (`DASHBOARD_VIEW_VERSION` vs `dashboard_version`) before swapping it in. Previously a 200 response carrying the stale body was swapped in and reported as "switched to the latest view", which is exactly the "the button does nothing" symptom this change is meant to eliminate
  - Six new UI strings added to both locales. Manifest bumped to 2.6.11; `checksums.sha256` regenerated and re-signed

- **v2.6.10**
  - **Documentation correction**: the v2.6.9 changelog explained the 403 root cause as "the RPC client sends the CSRF token via the `X-CSRF-Token` **header**". That was wrong, and has been verified against the LuCI sources (21.02 / 22.03 / 24.10 / master). This view's `'require request'` resolves to the `Request` class (`classes.request = Request`, luci.js:2218), whose `post()` sends a **JSON body containing no token at all** — not in the form body, not in any header (there is no `csrf` / `X-CSRF` string anywhere in luci.js). Combined with `test_post_security()` reading only `http.formvalue("token")` (dispatcher.lua:516-530), that is why a `post()` route could only ever return 403. The 403 fix in v2.6.9 is unaffected — only its explanation was wrong
  - **Security note stated accurately**: `call()` routes do **not** perform CSRF token validation; request legitimacy rests on the LuCI session cookie and ACL checks (dispatcher.lua:941-963). This is the normal LuCI view-layer pattern, not token-based protection
  - Internal comments in `adguardhome.lua` corrected to match the verified mechanism; no functional change. Manifest bumped to 2.6.10; `checksums.sha256` regenerated and re-signed

- **v2.6.9**
  - **Fixed every write action returning HTTP 403 and doing nothing**: dashboard upgrade, core upgrade/reinstall, backup restore/delete, proxy set, and clear-log all silently no-op'd. v2.6.4 had switched those action routes from `call()` to `post()`; LuCI's `post()` triggers `test_post_security()`, which requires the CSRF token in the **form body**, but this view's `request.post` (the `Request` class from `'require request'`) sends a **JSON body with no token at all** — not in the form body and not in any header — so every write was rejected with 403 and never reached the handler. Reverted all action routes to `call()` (the v2.6.2/2.6.3 form that was confirmed working)
  - **Added RSA-signed release verification (supply-chain authenticity)**: `checksums.sha256` is now signed at release time, and the upgrade runner / installer verify `checksums.sha256.sig` against a **public key pinned in the plugin and the installer** before deploying. A malicious mirror or man-in-the-middle that serves both the files and the checksum list still cannot forge the signature (it never sees the private key), so tampering is detected and the upgrade is refused — closing the self-referential-checksum gap documented in the Security section
  - **Fail-closed on the router**: if `openssl` is missing, deployment is refused and the log tells you `opkg install openssl-util` — without a verifier there is no authenticity guarantee, so we refuse rather than silently skip
  - **Reverted in v2.6.13**: the signature feature was removed because stock OpenWrt's `openssl` misreported valid signatures as invalid and bricked upgrades; the project now uses per-file sha256 integrity only (the 2.6.2 way)
  - The earlier "upgrade did nothing" reports were two distinct bugs: the v2.6.8 guard fix addressed the *button-click* path; this release fixes the *route/CSRF* path that actually blocked the backend. Manifest bumped to 2.6.9; `checksums.sha256` regenerated and now signed

- **v2.6.8**
  - **Fixed the backup "Restore" and "Delete" buttons doing nothing**: the destructive-action guard latched on and then swallowed the click with a bare `return` — no request, no error, no notification. Reproduced with a jsdom harness running the real module: after a successful "Restore", `_actionBusy` stayed set because its *only* reset path was a completion marker appearing in the exec log, and a concurrent "check for update" truncates that log via `log_start`. The next "Delete" click was therefore discarded in silence
  - **The guard can no longer fail silently**: a blocked click now raises an explicit notification ("an operation is in progress — please wait") instead of nothing at all, and a watchdog releases the lock automatically after 120 s (with a notice) if the reset path ever breaks again. Arming and releasing now go through `_armBusy()` / `_releaseBusy()` (time-stamped) so every arm has a paired release
  - **"Upgrade dashboard" failed the same way** — it is guarded by the same code, so a click could be swallowed with the confirm modal simply staying open and no request being sent; that is also why the log area stayed empty (the runner never started). It is fixed by the same change: you now get feedback instead of dead silence, and the lock expires on its own
  - **"Restore" confirmation moved from the native `window.confirm` to LuCI's `ui.showModal`**, matching every other dialog in this panel — browsers suppress repeated native dialogs, which made the click look dead. A 90 s fallback timer also stops the guard reset from depending solely on a log marker
  - **Log polling is no longer completely silent on failure**: 5 consecutive `fetchLog` failures now stop the poll, release the guard, and surface an error
  - 4 new i18n strings; both `.po` files updated and both `.lmo` recompiled. Version bumped to 2.6.8; `checksums.sha256` regenerated. No backend (Lua) changes

- **v2.6.7**
  - **Fixed "Clear Cache & Reload" still not switching to the new view on Safari / router uhttpd**: v2.6.5/2.6.6 relied on `fetch(..., {cache:'reload'})` writing the fresh file back into the HTTP disk cache, then `location.reload()` expecting the navigation to pick up that entry. But `cache:'reload'` writes back asynchronously, and on Safari / router uhttpd that write is unreliable — the navigation reads the stale entry first, so the old view came back. Only DevTools "Disable cache" worked, because it skips the cache lookup entirely and therefore sends no conditional headers
  - **The button now hot-swaps the view in place, with no dependence on the HTTP cache write-back**: it stops the old instance's polls, fetches the latest dashboard.js as TEXT with `cache: 'no-store'` (which forces the browser to fetch the real file from the server, past any cached URL variant) plus a deliberately non-matching `If-None-Match` / 1970 `If-Modified-Since`, re-evaluates that text inside this module's own closure scope to obtain the new view class, instantiates it, renders it with the data we already hold, and replaces the root node (`parentNode.replaceChild`). The old view is gone and the new one is live without a full page reload
  - **A browser already stuck on a stale view must disable its HTTP cache and reload with it disabled** — the old button inside the stale copy cannot repair itself. Note that a "hard refresh" does **not** do this: Ctrl+F5 / Shift+Reload still revalidates and uhttpd answers `304` (see the v2.6.9 entry below for the mechanism)
  - Version bumped to 2.6.7; `checksums.sha256` regenerated. No new i18n strings

- **v2.6.6**
  - **Fixed a v2.6.4 regression where "Upgrade dashboard" did nothing after "Check for update"**: the destructive-action guard (`_actionLocked`) returned true whenever a log-poll interval was active, and the version check starts exactly such a poll — so in the ~2–4 s window before the poll sees `=== check done ===`, clicking "Upgrade" was silently swallowed (the modal closed, no request was sent, no error shown). v2.6.2 / v2.6.3 had no such guard and upgraded normally
  - **The guard now keys only on a genuine destructive action in progress** (`_actionBusy`), not on passive log polling. Every destructive action (dashboard upgrade, core install/upgrade, restore, delete backup) now sets `_actionBusy` on start and resets it when the completion marker appears in the log (or on failure / poll timeout), so concurrent re-submission is still blocked while the spurious "check → upgrade" block is gone
  - **Restore from backup had the same silent-silence regression and is fixed by the same change**: `confirmRestore` in v2.6.4/2.6.5 also started with `if (this._actionLocked()) return;` (v2.6.4 changelog item "Destructive buttons can no longer be double-submitted"), so a "Restore" click during the post-check poll window was swallowed exactly like "Upgrade". The backend `restore_backup` was never at fault (unchanged from v2.6.2; both dashboard and core backups ship a `restore.sh`). v2.6.6's decoupling makes "Restore" work again — no separate patch needed
  - Version bumped to 2.6.6; `checksums.sha256` regenerated. No new i18n strings

- **v2.6.5**
  - **Fixed "Clear Cache & Reload" having no effect — the cached view JS is now actually refreshed** (two independent causes had to be fixed together): the button re-fetched this view as `dashboard.js?_cb=<timestamp>`, but the HTTP cache keys on the full URL *including the query string*, so that only refreshed an entry nobody ever requests. LuCI loads view modules as `base_url + module path + '.js'` plus `?v=` + `resource_version` whenever the page's `luci.js` src carries `?v=` (`luci.js:2474`, present since 21.02) — and that `?v=` tracks LuCI itself, not this panel, so it never changes when the panel is upgraded. That is why a stale `dashboard.js` was served indefinitely and why disabling browser caching was the only workaround. Both the bare URL and the `?v=` URL are now re-fetched with `cache: 'reload'` (which bypasses the cache read and then writes the fresh response back), so the exact key LuCI requests is the one that gets refreshed, and the reload genuinely picks up the new view
  - **Conditional requests were being answered with `304`, which is why even Ctrl+F5 / Cmd+Shift+R did nothing**: a revalidation carries `If-None-Match` / `If-Modified-Since`, and as soon as the server's validator still reports "not modified" the browser keeps reusing the stale cached body. On routers without a battery-backed RTC the clock falls back to the firmware build date after a reboot, so a freshly deployed file can carry an mtime *older* than the cached one and uhttpd answers `304` — the new view is on disk, yet every reload re-serves the old one. DevTools "Disable cache" appears to help only because it skips the cache lookup entirely and therefore sends no conditional headers. The refresh now sends a deliberately non-matching `If-None-Match` plus an epoch `If-Modified-Since`, so the server answers `200` with the full body, and `cache: 'reload'` (which bypasses the cache read and writes the fresh response back) stores it
  - **The button now proves it is working**: it disables itself and switches to "Working..." on click, instead of looking completely inert while the stale view was still being served
  - **A stalled request can no longer postpone the reload forever**: the cache refresh is wrapped in a promise that also settles after a 3 s timeout, so a hanging fetch still falls through to the reload
  - **Note**: a browser already stuck on a stale view must have "Disable cache" enabled in its devtools and then reload — a hard refresh (Ctrl+F5 / Cmd+Shift+R) does **not** work, because it still revalidates and this router answers `304`; the entry above documents the mechanism. The stale copy of the button cannot repair itself
  - Version bumped to 2.6.5; `checksums.sha256` regenerated. No new i18n strings (the "Working..." label already existed)

- **v2.6.4**
  - **Security: remote version strings are no longer interpolated into shell commands (root RCE)**: `check_update` and `check_dashboard_update` used to write the version fetched from the network straight into `util.exec("echo '  result: latest = " .. v .. "' >> " .. EXEC_LOG)`. The capture patterns (`(.-)` and `([^"]+)`) both accept `'`, `$(`, backticks and `;`, so a single quote closed the literal and executed arbitrary commands as root (uhttpd runs as root). Both endpoints are called automatically ~1 s after the page loads, and a user-supplied `mirror|https://<host>/` — or any tampering with a mirror/MITM — was enough to control the value. All 14 log writes now go through a Lua `io.open(..., "a")` helper (`log_line` / `log_start`), so log content is only ever bytes; version strings additionally pass a `safe_version()` whitelist (`^v?%d+%.%d+%.%d+[%w%.%+%-]*$`) before use
  - **Security: the persisted proxy spec is validated on read too**: `/etc/adguardhome-dashboard.proxy` (mode 644) was read by `get_persisted_proxy()` and fed straight into `PRIMARY_PROXY`, which is interpolated into the generated shell script header (`PRIMARY_PROXY='...'`) and into `curl -x`. Request parameters were always validated with `is_safe_spec`, but this read path was not. It now re-validates and falls back to direct with a log line
  - **Write RPCs now use `post()` instead of `call()`, so CSRF tokens are actually checked**: all 14 entries were declared with `call()`, which produces a target without the `post` field — LuCI's `require_post_security()` is then always false and `test_post_security()` (comparing `http.formvalue("token")` with the session authtoken) never runs. Destructive calls (delete backup, upgrade, set proxy, restore, action, clear log) could be fired with a GET. Reads stay on `call()`; the front end's `request.post` ships the token automatically
  - **`install.sh` no longer destroys the existing core before unpacking**: overwriting `/opt/AdGuardHome` used to `rm -rf` the whole directory first, so a corrupt tarball or an architecture mismatch destroyed the old binary *and* `AdGuardHome.yaml` (filter rules, DNS rewrites, DHCP, credentials) while the log still printed "rolled back". The binary and the yaml are now backed up to `/root/agh_backup_core_<ts>/` (same layout as the panel's core backup) before deletion, and every failure path performs a real rollback that restores them and re-registers the service. `data/` query logs are deliberately not copied, so a small router's flash is not exhausted
  - **Refusing to deploy without a sha256 fingerprint**: when `checksums.sha256` could not be downloaded, both `install.sh` and the dashboard upgrade runner degraded to three `grep` feature checks (`fetchBackups` / `list_backups`), which forged content satisfies with one extra line. Both now treat a missing manifest as a failure — `install.sh` retries with another connection, the runner aborts and rolls back
  - **`install.sh` core install no longer pipes curl into `sh`**: the script has `set -e` but no `pipefail`, so `gh_curl "$AGH_INSTALL_URL" -fsSL | sh` took its exit status from `sh`; a curl failure (mirror 404, TLS error, cached empty file) fed empty input, `sh` succeeded, and the script printed "installation complete" although nothing was installed. The installer is now downloaded to a temp file, checked for non-empty content, and only then executed
  - **`install.sh` refuses to delete an unsafe project directory**: the "delete local project then re-download" branch only checked `-n` and `-d`. Since `PROJECT_ROOT` is derived as `dirname(dirname $0)`, a `files/` + `scripts/` layout under `/opt`, `/root` or `/mnt/...` made it equal that directory — wiping the AGH core and backups along with it. The directory must now also not be a high-risk parent path and must actually contain `manifest.json` plus `files/luci/controller/adguardhome.lua`; otherwise it re-downloads without deleting anything
  - **Fixed `delete_backup` always reporting success**: `fs.access(dir) and false or true` is always `true` (`(x and false) or true`), and `ok and nil or X` always yields `X`, so a failed `rm -rf` was reported as a success that also carried an error string. Now `ok = not fs.access(dir)`
  - **Fixed core upgrades being reported as done when they failed**: the rollback branch only tested `VERIFY_OK`. When the upgrade command failed but the old binary still ran, verification passed, the rollback was skipped, and `=== core upgrade done ===` was printed — which is exactly what the UI waits for. The test now includes `UPGRADE_RC`
  - **Fixed the "includes core" column always being false**: `list_backups` probed `<dir>/core/AdGuardHome`, but core backups store the binary at `<dir>/AdGuardHome`. Both layouts are now accepted. Core backups also get a generated `restore.sh` (the panel's `restore_backup` requires it), so they are restorable instead of "listed but unusable"
  - **Fixed the upgrade button claiming success when nothing started**: the front end's `doUpgrade` never read the response (`.then(function(){...})` with no parameter) while the backend discarded `launch_core_upgrade()`'s result and returned `success = true` unconditionally. A failed runner write now surfaces as an error instead of a 300 s log poll. `do_upgrade` / `install_core` return the real status
  - **Destructive buttons can no longer be double-submitted**: upgrade / force-reinstall / install-core / panel-upgrade / restore / delete now disable immediately on click and are guarded by `_actionLocked()` (in-flight request or an active upgrade poll). The backend runners live at fixed paths, so a second click used to overwrite the script currently executing and spawn a second process
  - **Fixed silent proxy-persistence failures**: two `sendSetProxy` call sites never checked the business `success` flag, and `_syncRegionPolicy` additionally mutated `statusData.proxy` optimistically first — so a failed write left the UI showing one proxy while check/upgrade kept using another, with no notification. All three now go through `_persistProxy()`, which updates local state only on success and notifies on failure
  - **Fixed a log-polling leak**: `autoRefreshLogInterval` was missing from the view-detach cleanup, so with "auto refresh log" enabled a 3 s `fetchLog()` kept running after switching to another LuCI page. Restore/delete errors now use `ui.addNotification` instead of `alert()`, which blocked the main thread and stalled the 2 s poll
  - **`uninstall.sh` now removes `/usr/share/adguardhome-dashboard/`**: `install.sh` treats `manifest.json` in that directory as the primary "is this project installed" marker, so leaving it behind made the next install wrongly report "detected installed vX.Y.Z" with a stale version. The log file is now deleted last (it used to be deleted and immediately recreated by the following `log()` calls), and `log()` writes via redirection instead of `| tee -a` so a read-only `/etc` can no longer abort the whole uninstall on the first line
  - `checksums.sha256` regenerated; i18n updated (two new strings, `.lmo` recompiled)

- **v2.6.3**
  - **Tightened the rpcd ACL to least privilege (removed dead wildcard grants)**: `files/luci/acl.json` declared `read.ubus.*:*`, `write.ubus.*:*` and `write.uci.*`, yet the panel never exercises any of those grants. The front end calls the controller strictly through LuCI's dispatcher (`L.url('admin/services/adguardhome/…')` + `request.get/post`), and the Lua controller does its root-level work with `os.execute` / `luci.util.exec` / `nixio.fs` directly inside the LuCI process — it never calls `uci`, `ubus`, or any rpcd object. The wildcards were a template carry-over, not a functional requirement. `read`/`write` are now empty `{}`; only the group name referenced by `menu.d` remains, so install / start-stop / upgrade / uninstall and the panel itself all keep working unchanged
    - **Emergency rollback**: revert `files/luci/acl.json` to the previous value — `"read": { "ubus": { "*": [ "*" ] } }, "write": { "ubus": { "*": [ "*" ] }, "uci": [ "*" ] }` — the exact prior content is preserved in this commit's diff
  - **`install.sh` now inherits the selected proxy for force / fresh core installs**: with `proxy|<addr>` selected, the core-upgrade runner used to invoke the official AdGuard Home `install.sh` (`-r`, or a fresh install) over a direct connection — the configured proxy only fetched `install.sh` itself, so the script's internal download of the AGH binary still went direct and could stall on mainland-China networks before the `fallback_upgrade_via_proxy` path kicked in. The runner now sets `HTTPS_PROXY` / `HTTP_PROXY` before running `install.sh` (the mirror type still cannot proxy this step — a mirror is a URL prefix, not a `curl -x` address — so it keeps the existing fallback)
  - **Dashboard upgrade runner path unified with core upgrade (fixed, not timestamped)**: both runners now use a fixed path (`/tmp/agh_dashboard_upgrade_runner.sh` and `/tmp/agh_core_upgrade_runner.sh`) instead of a timestamped unique path. Single-user home-router scenarios have no concurrent upgrade risk, and there is no need to retain historical runner scripts. The cleanup function removes the fixed runner path on exit
  - **Bilingual (EN/ZH) comments added for fixed runner paths**: both `launch_core_upgrade` and `do_upgrade_dashboard` now carry a bilingual comment explaining why a fixed path is used (single-user, no concurrency, no historical retention). The `ts` timestamp variable remains in scope and is still used inside the generated shell script for `BACKUP_DIR` and `TMPDIR` — it is **not** the version number and must not be removed
  - `checksums.sha256` regenerated (the release gate verifies this file against `files/luci/acl.json` and `files/luci/controller/adguardhome.lua`)

- **v2.6.2**
  - **Fixed backups being labelled "install" even when they were panel upgrades**: install.sh hard-coded `/root/agh_backup_install_<ts>`, but it only ever writes a backup when panel files already exist — a fresh install logs "Fresh install detected" and leaves no directory behind. So *every* `agh_backup_install_*` was in fact a panel upgrade (via the one-liner or the offline package) and still showed up as an "install" in the panel's backup manager. The script now decides the type from what is actually being overwritten: existing panel files found → `agh_backup_dashboard_<ts>` (panel upgrade), otherwise it keeps the `install` name (and creates nothing anyway). The log line now says "Panel upgrade detected"
  - **Legacy `agh_backup_install_*` dirs are listed as panel upgrades too** (BACKUP_DIR type mapping): since a backup can only be produced by overwriting an existing panel, those directories are panel upgrades by construction. Their names are left untouched — restore, delete and `restore.sh` are unaffected. Hovering a row's type in the panel shows the raw directory name, so the two producers remain distinguishable
  - Docs: the backup type table is now two rows (dashboard / core) with a legacy-naming note, and the install.sh / rollback paths use `/root/agh_backup_dashboard_<ts>`

- **v2.6.1**
  - **The "Dashboard Version" block now shows which view the browser is actually running**: a third line, `Loaded in browser: vX.Y.Z`, is driven by `DASHBOARD_VIEW_VERSION` baked into the view JS — the only reliable answer to "which code is the browser executing right now". The server-reported version (`Current:` / the manifest) updates on deploy but cannot tell whether the browser is still serving a cached older view from localStorage or the HTTP cache. When the two differ, the line turns red with a tooltip explaining the cache situation, and a **`Clear Cache & Reload`** button is always present (not only on mismatch — a stale JS never runs new code, so it could never show the warning to the person who needs it). The button does a genuine hard reload that clears LuCI's cached view module in localStorage, re-fetches the view JS with `cache:'reload'`, drops Cache Storage, and replaces to a cache-busted URL. This makes browser-cache cases (the "upgraded but the UI is still old / egress IP never shows" reports) self-diagnosing instead of silent
  - **Hardened the server-side egress-IP probe diagnostics**: `geo_probe` now checks `command -v curl` first and returns `curl: missing` when the package is absent; each endpoint appends `; printf '\n__RC__=%s' "$?"` so the real exit code and stderr come back in `errors[]`; a non-zero exit (DNS failure rc=6, SSL rc=60, HTTP 403 rc=22) is no longer misread as success — a 403 body used to be parsed as a valid response and could set `is_cn` wrong, breaking the region policy. The failure banner now surfaces the first error (e.g. `ip-api.com: rc=60 SSL certificate problem`) instead of a generic "could not detect". The old `location.reload(true)` self-heal (force arg long-ignored by browsers) was replaced by the same cache-bypassing reload as the button above

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
