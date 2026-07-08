# 🧩 AdGuardHome LuCI Dashboard

**轻量级 LuCI 仪表盘安装器** | **Lightweight LuCI Dashboard Installer**  
**v2.0 Full Edition**

为 OpenWrt / ImmortalWrt / iStoreOS 提供完整的 AdGuard Home 管理面板。

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

- **极简设计**：仅安装必要 LuCI 文件
- **自动安装核心**：检测并安装 AdGuard Home（官方脚本）
- **安全下载**：重试 + 文件大小校验
- **自动刷新菜单**：安装后自动刷新 LuCI 缓存
- **跨平台支持**：OpenWrt / ImmortalWrt / iStoreOS
- **后端 RPC 架构**：标准 LuCI 2.0 Controller + request API，无 ACL 越权问题
- **实时状态监控**：5 秒自动轮询，实时更新版本/运行状态/PID/端口
- **服务控制台**：启动/停止/重启/注册系统服务，一键操作
- **日志查看器**：实时查看运行日志和升级进度日志
- **版本管理**：检查更新 + 一键升级，升级进度实时滚动显示
- **国际化支持**：中英文自动切换，基于 LuCI 系统语言设置

---

## 📁 项目结构 / Structure

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh        # 安装/更新脚本
│   └── uninstall.sh      # 卸载脚本
├── files/
│   ├── luci/
│   │   ├── menu.json     # 菜单注册 (LuCI 2.0)
│   │   ├── acl.json      # 访问控制权限
│   │   ├── controller/
│   │   │   └── adguardhome.lua  # 后端 RPC Controller
│   │   └── i18n/
│   │       ├── adguardhome.po       # 英文翻译
│   │       └── adguardhome.zh-cn.po # 中文翻译
│   └── view/
│       └── dashboard.js  # 前端视图
├── manifest.json         # 包清单
└── README.md             # 项目说明
```

---

## 🔌 API 接口 / API Endpoints

| 路径 | 方法 | 功能 |
|------|------|------|
| `/admin/services/adguardhome/status` | GET | 获取状态（版本/运行/PID/端口） |
| `/admin/services/adguardhome/action` | POST | 执行操作（start/stop/restart/install_service） |
| `/admin/services/adguardhome/check_update` | GET | 检查最新版本 |
| `/admin/services/adguardhome/upgrade` | POST | 启动一键升级 |
| `/admin/services/adguardhome/log` | GET | 获取日志（运行日志/升级日志） |

---

## 📋 系统要求 / Requirements

- OpenWrt / ImmortalWrt / iStoreOS
- curl（大多数固件已内置）
- 至少 8MB 剩余空间
- LuCI 2.0（OpenWrt 21.02+）

---

## 📡 注意事项 / Notes

- 本项目提供完整的 LuCI 仪表盘管理面板，包含状态监控、服务控制、日志查看和版本升级功能
- 安装完成后，在 LuCI → **服务** → **AdGuard Home** 进入仪表盘
- 升级日志文件：`/tmp/agh_upgrade.log`
- 安装日志：`/etc/adguardhome-dashboard.log`

---

## ⚙️ 哲学 / Philosophy

- Stateless & Minimal
- Fail-fast download validation
- Standard LuCI 2.0 patterns
- Keep it simple and stable

---

**MIT License** | 轻量 · 稳定 · 可维护  
**Lightweight · Stable · Maintainable**
