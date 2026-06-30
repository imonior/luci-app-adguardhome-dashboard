# 🧩 AdGuardHome LuCI Dashboard

**轻量级 LuCI 静态仪表盘安装器** | **Lightweight LuCI Dashboard Installer**  
**v1.0 Stable Minimal Edition**

为 OpenWrt / ImmortalWrt / iStoreOS 提供干净的 AdGuard Home 管理入口。

---

## 🚀 一键安装 / Install & Update

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
```

> `install.sh` 同时支持安装和更新（幂等）

---

## 🧹 卸载 / Uninstall

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/uninstall.sh)"
```

---

## 📦 特性 / Features

- 极简设计，仅安装必要 LuCI 文件
- 自动检测并安装 AdGuard Home（官方脚本）
- 安全下载（重试 + 文件大小校验）
- 自动刷新 LuCI 菜单
- 支持 OpenWrt 各类衍生系统
- No version system / no checksum / no CI/CD（极简哲学）
- **内核级状态追踪**：利用 UBus 总线内存穿透，实时监控进程运行状态与 PID。
- **动态端口探测**：支持多路径 YAML 解析 + 网络层实时侦测，完美兼容自定义配置。
- **0 权限报错**：摒弃高危 exec 调用，符合现代安全沙箱规范，告别 ACL 越权拦截。

---

## 📁 项目结构 / Structure

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh
│   └── uninstall.sh
├── files/
│   ├── luci/
│   │   ├── menu.json
│   │   └── acl.json
│   └── view/
│       └── dashboard.js
├── manifest.json
└── README.md
```

---

## 📋 系统要求 / Requirements

- OpenWrt / ImmortalWrt / iStoreOS
- curl（大多数固件已内置）
- 至少 8MB 剩余空间

---

## 📡 注意事项 / Notes

- 本项目**仅提供 LuCI 仪表盘入口**，不负责 AdGuard Home 核心运行。
- AdGuard Home 核心可通过官方脚本安装：
  ```sh
  curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
  ```
- 安装完成后，在 LuCI → **服务** → **AdGuard Home** 进入仪表盘。
- 提示：如遇端口识别延迟，请确保 AdGuard Home 核心进程已由 procd 系统服务托管，或手动重启一次服务以激活总线映射。

---

## 📊 日志 / Logging

- 安装日志：`/etc/adguardhome-dashboard.log`

---

## ⚙️ 哲学 / Philosophy

- Stateless & Minimal
- Fail-fast download validation
- Keep it simple and stable

---

**MIT License** | 轻量 · 稳定 · 可维护  
**Lightweight · Stable · Maintainable**
