# 🧩 luci-app-adguardhome-dashboard

A lightweight, production-grade LuCI dashboard installer for AdGuard Home.  
Designed for OpenWrt / ImmortalWrt / iStoreOS.

---

# 🚀 Overview

This project provides a stateless LuCI dashboard installer for AdGuard Home:

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

## v2.0 - Transactional Engine
- Lock-based concurrency protection
- Full rollback support
- SHA256 checksum verification
- Delta upgrade system
- Install journal logging

## v2.1 - Release System
- GitHub Actions auto release
- Git tag based versioning
- Auto changelog generation
- Manifest support

## v2.2 - Ecosystem Layer
- Plugin index system (index.json)
- Self-update engine
- Feed-compatible architecture

---

# 📦 Installation

## 📦 Online Install
```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
```
---

## 📦 Offline Install
```sh
unzip luci-app-adguardhome-dashboard.zip
cd luci-app-adguardhome-dashboard
sh scripts/install.sh
```
---

## 📦 Upgrade
```sh
sh scripts/install.sh
```
---

## 📦 Uninstall
```sh
sh scripts/uninstall.sh
```
---

## 📦 Self Update
```sh
sh scripts/self-update.sh
```
---

# 🧠 Architecture

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── self-update.sh
├── files/
│   ├── version
│   ├── checksums.sha256
│   ├── delta.map
│   ├── index.json
│   ├── luci/
│   │   ├── menu.json
│   │   └── acl.json
│   └── view/
│       └── dashboard.js
├── manifest.json
└── README.md
```
---

# ⚙️ System Requirements

| System | Status |
|--------|--------|
| OpenWrt | ✅ |
| ImmortalWrt | ✅ |
| iStoreOS | ✅ |

---

# 📡 Notes

[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) is installed via official upstream script.

This project only manages LuCI dashboard layer.

else, you can manually install ADH via curl before install this LuCI dashboard:
```sh
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
```

---

# 📊 Logging

Install log:
- /etc/adguardhome-dashboard.log

Version file:
- /etc/adguardhome-dashboard.version

---

# 🔐 Safety

- Lock file prevents concurrent installation
- Backup before modification
- Automatic rollback on failure
- SHA256 verification supported

---

# 📦 CI/CD
```sh
git tag v2.2.0
git push origin v2.2.0
```
Pipeline will:
- Build release package
- Generate checksum
- Attach GitHub release

---

# 🚀 Roadmap

v2.3:
- Plugin store UI
- Multi-feed system
- Dependency resolution
- Conflict detection
- Auto update daemon

---

# 📄 License

MIT License