# 🧩 AdGuardHome LuCI Dashboard

## 📦 v1.0 Stable Minimal Edition

Lightweight LuCI dashboard installer for AdGuard Home.

---

# 🚀 Features

- Install + Update unified (idempotent)

- Auto install AdGuard Home (official script)

- Safe download with retry + size check

- No CI/CD / no version system / no checksum system

- Works on OpenWrt / ImmortalWrt / iStoreOS

---

# 📦 Install / Update

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
```
👉 install.sh = install + update (same command)

---

## 🧹 Uninstall
```sh
sh scripts/uninstall.sh
```

---

# 🧠 Architecture

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
├── files/
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
git tag v1.0
git push origin v1.0
```
Pipeline will:
- Build release package
- Generate checksum
- Attach GitHub release

---

⚙️ Philosophy

* Stateless
* No build system
* No package manager abstraction
* No CI/CD complexity
* Fail-fast download validation

---

# 🚀 Roadmap

v1.1:
- Plugin store UI
- Multi-feed system
- Dependency resolution
- Conflict detection
- Auto update daemon

---

# 📄 License

MIT License