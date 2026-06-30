# 🧩 luci-app-adguardhome-dashboard
A lightweight, production-grade LuCI dashboard installer for AdGuard Home.
Designed for OpenWrt / ImmortalWrt / iStoreOS.
---
# 🚀 Overview
This project provides a **stateless, transactional LuCI dashboard installer** for AdGuard Home with:
- Safe installation (rollback supported)
- Automatic upgrade system
- Integrity verification (SHA256)
- Delta-based updates
- GitHub Actions CI/CD release system
- Optional plugin feed support (v2.2)
---
# ✨ Features
## v1.0 - Basic Installer
- One-line install
- Online / Offline support
- LuCI menu injection
- Backup before install
- OpenWrt compatible structure
---
## v2.0 - Transactional Engine
- Lock-based concurrency protection
- Full rollback support
- SHA256 checksum verification
- Delta upgrade system
- Install journal logging (`/etc/adguardhome-dashboard.log`)
- Safe system recovery on failure
---
## v2.1 - Release System
- GitHub Actions auto release
- Git tag based versioning
- Auto changelog generation
- Manifest support (iStoreOS / OpenWrt)
- Release chain versioning
---
## v2.2 - Ecosystem Layer
- Plugin index system (`index.json`)
- Self-update engine (`self-update.sh`)
- Feed-compatible architecture
- Optional external metadata loading
- Extensible upgrade pipeline
---
# 📦 Installation
## 🌐 Online Install
```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/scripts/install.sh)"

⸻

📦 Offline Install

unzip luci-app-adguardhome-dashboard.zip
cd luci-app-adguardhome-dashboard
sh scripts/install.sh

⸻

🔄 Upgrade

Simply re-run:

sh scripts/install.sh

The installer automatically detects existing installation and performs upgrade.

⸻

🧹 Uninstall

sh scripts/uninstall.sh

⸻

🔁 Self Update (v2.2)

sh scripts/self-update.sh

⸻

🧠 Architecture

luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh        # transactional installer engine
│   ├── uninstall.sh
│   └── self-update.sh    # v2.2 auto upgrade engine
│
├── files/
│   ├── version           # Git tag synced version
│   ├── checksums.sha256  # integrity verification
│   ├── delta.map         # incremental update map
│   ├── index.json        # plugin feed (v2.2)
│   │
│   ├── luci/
│   │   ├── menu.json
│   │   └── acl.json
│   │
│   └── view/
│       └── dashboard.js
│
├── manifest.json         # iStoreOS / OpenWrt metadata
├── README.md
└── .github/workflows/
    └── release.yml

⸻

⚙️ System Requirements

* OpenWrt 21+
* ImmortalWrt
* iStoreOS

⸻

🧩 Design Philosophy

This project follows these principles:

1. Idempotent Installation

Running install multiple times always results in the same system state.

2. Transaction Safety

Any failure triggers automatic rollback to previous stable state.

3. Minimal Core Dependency

Only relies on:

* shell
* curl / wget
* core OpenWrt LuCI runtime

4. Optional Ecosystem Expansion

Features like index.json and self-update.sh are optional extensions, not core dependencies.

⸻

📡 AdGuard Home Note

AdGuard Home is installed via official upstream script:

https://github.com/AdguardTeam/AdGuardHome

This project only manages the LuCI dashboard layer.

⸻

📊 Logging

Install logs:

/etc/adguardhome-dashboard.log

Version file:

/etc/adguardhome-dashboard.version

⸻

🔐 Safety Features

* Lock file prevents concurrent installation
* Backup before any modification
* Automatic rollback on failure
* SHA256 integrity check (optional but recommended)

⸻

📦 CI/CD (GitHub Actions)

On every tag:

git tag v2.2.0
git push origin v2.2.0

CI will automatically:

* Generate version file
* Build checksum
* Generate delta map
* Build release zip
* Attach GitHub release asset

⸻

🧭 Compatibility

System	     Status
OpenWrt	     ✅
ImmortalWrt	 ✅
iStoreOS	 ✅

⸻

📌 Notes

* Dashboard is independent of AdGuard Home core
* Re-running install.sh performs upgrade automatically
* No manual file copying required
* Fully stateless design

⸻

🚀 Roadmap

v2.3 (Planned)

* Plugin store UI (LuCI frontend)
* Multi-index feed system
* Dependency resolution (like opkg)
* Conflict detection
* Auto-update daemon
* Central plugin registry support

⸻

📄 License

MIT License