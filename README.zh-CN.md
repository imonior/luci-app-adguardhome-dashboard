[🇺🇸 English](README.md) · [开发说明 Development](DEVELOPMENT.zh-CN.md)

# AdGuardHome LuCI Dashboard

**LuCI 2.0 标准 AdGuard Home 管理面板** | **LuCI 2.0 AdGuard Home Dashboard**
**v2.5.8**

为 OpenWrt / ImmortalWrt / iStoreOS 提供完整的 AdGuard Home 管理面板。

---

## 安装 / Install

### 一键安装（推荐）

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
```

安装脚本分两步执行：

1. **AdGuard Home 核心** — 检测 `/opt/AdGuardHome/AdGuardHome` 是否已安装，未安装则调用官方脚本自动安装；已安装则可选择覆盖安装（自动停止运行中的服务）或跳过
2. **LuCI Dashboard** — 从 GitHub 下载菜单注册、Lua Controller、JS View、翻译等文件及 `checksums.sha256` 到临时目录，先做 **sha256 内容指纹校验**（命中代理缓存旧版立即中止并提示换代理），再部署到系统对应位置

> install.sh 在覆盖前会自动把现有的面板文件（含 `manifest.json`）备份到 `/root/agh_backup_install_<ts>/`，并在备份目录内生成 `restore.sh`。万一安装失败或想回滚到旧版面板，执行 `sh /root/agh_backup_install_<ts>/restore.sh` 即可（仅恢复面板文件，不动 AGH 核心二进制）。

### 国内加速 / Proxy

支持两种**语义完全不同**的连接类型，二者**不可互换**——镜像是 URL *前缀*，全量代理是 `curl -x` 目标；把代理地址当前缀用会拼出必然失败的非法 URL。

- **镜像源**（URL *前缀*）—— 规格 `mirror|<前缀>`，如 `mirror|https://ghfast.top/`。
  curl 把原始 GitHub 地址拼到前缀之后。**仅中国大陆通常有效。**
- **全量代理服务器**（类似系统代理）—— 规格 `proxy|<地址>`，如 `proxy|http://127.0.0.1:7890` 或 `proxy|socks5://127.0.0.1:1080`。
  curl 使用 `-x <地址>`，URL 保持不变。任意地区可用。
- **直连** —— 空值，直接 curl。

脚本启动时自动检测 GitHub 连通性并逐个测试候选，显示延迟后选择一个可用连接：

```
  #   连接                    状态
  ─────────────────────────────────────────
  1)  直连                    ✗ 不可用
  2)  ghfast.top              ✓ 320ms   [适用于中国大陆]
  3)  gh-proxy.com            ✓ 450ms   [适用于中国大陆]
  4)  自定义镜像源 URL         （前缀型）
  5)  自定义代理服务器         （http://host:port | socks5://host:port）
```

`GITHUB_PROXY` 接受同样的规格并跳过检测。全量代理需加 `proxy|` 前缀；以 `/` 结尾的裸值仍按镜像源处理（向后兼容）：

```sh
# 镜像源（URL 前缀）
GITHUB_PROXY=https://ghfast.top/ sh -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
# 全量代理服务器（系统代理型）
GITHUB_PROXY=proxy|http://127.0.0.1:7890 sh install.sh
```

> 注意：`curl` 下载脚本本身的 URL 也需要经过镜像，如上面示例中 `curl` 的 URL 已加了 `ghfast.top/` 前缀。（全量代理属于网络层代理，无需加前缀。）

> **地区自适应**：内置镜像仅在中国大陆有效。检测到出口 IP 位于**境外**时，`install.sh` 会跳过这些镜像，只提供「直连」与两个自定义输入；面板同样隐藏镜像行。两处的**手动输入都始终保留**；面板还会把原先选中的**镜像**自动切回「直连」并在横幅中明确说明——不会出现「代理被隐藏却仍在后台生效、网络不通却查不出原因」的情况。

代理选择以 `proxy=mirror|https://ghfast.top/` 这类规格形式保存在 `/etc/adguardhome-dashboard.proxy`，`install.sh`、面板与两个升级生成脚本共用同一格式。

### 从本地项目安装

如果已将项目克隆到路由器，在项目目录内运行会自动使用本地文件（无需联网下载）：

```sh
cd /path/to/luci-app-adguardhome-dashboard
sh scripts/install.sh
```

> `install.sh` 支持安装和更新（幂等），自动清理旧版本文件。

### 离线安装（发布压缩包）

每个版本都会在 [Releases 页面](https://github.com/imonior/luci-app-adguardhome-dashboard/releases) 附带一个自包含压缩包资产 `luci-app-adguardhome-dashboard-vX.Y.Z.tar.gz`。下载后解压安装，**全程不需要联网、也不会联网**：

```sh
# 用任意方式把压缩包传到路由器（scp、U 盘等），然后：
tar xzf luci-app-adguardhome-dashboard-vX.Y.Z.tar.gz
cd luci-app-adguardhome-dashboard-vX.Y.Z
sh scripts/install.sh
```

包内自带 `OFFLINE_PACKAGE` 标记，`install.sh` 检测到后会跳过出口 IP 探测、连接选择与所有在线版本查询，直接从 `./files` 部署，并用包内自带的 `checksums.sha256` 对每个文件做 sha256 指纹校验（与在线安装同一套校验）。

三点说明：

- 包内**只包含 LuCI 面板**，**不随包提供** AdGuard Home 核心（核心独立发布，版本无法固定在本包内）。若要离线安装核心，请把与本机架构匹配的官方压缩包放到发布包目录内（安装脚本会扫描该目录及其上一级）：
  ```sh
  AdGuardHome_linux_arm64.tar.gz     # 架构以 `uname -m` 输出为准
  ```
  安装脚本会自动识别、解压到 `/opt/AdGuardHome` 并注册服务，**全程仍不需联网**。若没有匹配的核心包（或架构不符），脚本只安装面板，并明确提示需要获取哪个架构的文件。下载地址见 [AdGuard Home Releases](https://github.com/AdguardTeam/AdGuardHome/releases/latest)。
- **不会静默覆盖已有安装。** AdGuard Home 核心与本项目面板都会先检测，无论在线还是离线安装，都会询问「重新安装」还是「保留当前版本」。
- 任意检出目录也可用 `sh scripts/install.sh -l`（同义：`--local` / `--offline`）强制走同样的离线安装。

自行打包：`sh scripts/make_package.sh`（产物在 `dist/`）。

## 卸载 / Uninstall

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/uninstall.sh)"
```

---

## 特性 / Features

- **LuCI 2.0 标准架构**：menu.json 注册菜单 + JS View 生命周期管理，非模板渲染
- **后端 RPC**：Lua Controller 提供 14 个 API 端点，无 ACL 越权
- **实时状态监控**：5 秒自动轮询，实时更新版本/运行状态/PID/端口/代理设置/面板版本
- **服务控制台**：启动/停止/重启/注册系统服务，支持 init.d 和二进制双模式
- **混合日志查看器**：分层追加模式，顶部为执行/升级日志（EXEC_LOG），下方追加 AGH 原生日志或系统 logread 的最新 50/100 行；支持手动刷新、升级时 2 秒自动轮询、可选的自动刷新开关（3 秒间隔）、一键清空中间层日志
- **核心版本管理**：检查更新 + 一键升级 + 强制重装，升级进度 2 秒快速轮询实时滚动
- **全局代理选择**：两种**带类型**的连接——**镜像源**（`mirror|<前缀>`，URL 前缀，预置候选在界面上标注「适用于中国大陆」）与**全量代理服务器**（`proxy|<地址>`，走 `curl -x`，支持 `socks5://`，任意地区可用）——各自有独立的自定义输入行，另有「直连」；点选后立即持久化到 `/etc/adguardhome-dashboard.proxy`
- **代理延迟测试**：单点测试 / 批量测试所有候选，每个候选按自身类型构造请求（镜像前缀 vs `curl -x`），测试目标与实际下载域名一致（`raw.githubusercontent.com`）
- **出口 IP / 地区检测**：加载时面板探测路由器出口公网 IP 与归属地（公开 geo-IP 服务）并显示归属地；**地区判定为境外时**隐藏两个中国大陆专用镜像行，并把原先选中的**镜像**自动切回「直连」（同时持久化，并在横幅中明确说明），避免「隐藏的代理仍在后台生效」导致网络不通却查不出原因。两个手动输入（自定义镜像源 / 自定义代理服务器）与「直连」始终保留；install.sh 采用同一策略
- **面板自升级**：检查面板版本（读 `manifest.json`） → 一键升级（在线下载 7 个面板文件（含 manifest.json）覆盖本地），无需手动上传
- **两阶段提交 + 自动回滚**：核心升级和面板升级都采用「下载到临时目录 + 完整性校验 → 备份 + 原子 mv 覆盖」模式，任一步骤失败自动从备份还原已部署文件
- **完整性校验（双重防线）**：① 类型校验 lmo magic `LMO\0` / lua 含 `function` / js 含 `view.extend` / po 含 `msgid`，防止空文件 / 404 HTML / 截断；② **sha256 内容指纹**：install 与面板升级都先下载 `checksums.sha256`，对面板文件逐一比对 sha256，任何与发布清单不一致的内容（尤其是代理/CDN 缓存的旧版本）都会被拦截并中止升级，避免装上残缺面板
- **备份管理**：列出 `/root/agh_backup_*` 所有备份目录（install/core/dashboard 三类），显示类型/时间戳/文件数/大小/含核心/含 restore.sh；支持一键恢复（仅 install/dashboard 类备份有 restore.sh）、显示恢复命令、删除备份释放空间
- **install 自带备份**：install.sh 部署前自动备份现有面板文件（含 manifest.json）+ 生成 restore.sh，与面板升级的备份机制完全一致
- **国际化支持**：中英文自动切换，基于 LuCI 系统语言设置（139 条翻译；每条字典项都被引用，每个 `T()` 调用都有词条）
- **跨平台**：OpenWrt / ImmortalWrt / iStoreOS

---

## 项目结构 / Structure

```text
luci-app-adguardhome-dashboard/
├── scripts/
│   ├── install.sh        # 安装/更新脚本（Part1: AGH核心 Part2: Dashboard文件 + 自动备份 + 生成 restore.sh）
│   └── uninstall.sh      # 卸载脚本
├── files/
│   ├── luci/
│   │   ├── menu.d/
│   │   │   └── luci-app-adguardhome-dashboard.json  # LuCI 2.0 菜单注册
│   │   ├── acl.json      # rpcd 访问控制权限
│   │   ├── controller/
│   │   │   └── adguardhome.lua  # 后端 Lua Controller (13 个 API 端点)
│   │   └── i18n/
│   │       ├── adguardhome.po       # 英文翻译源文件
│   │       ├── adguardhome.zh-cn.po # 中文翻译源文件
│   │       ├── adguardhome.lmo      # 英文编译翻译（LuCI 二进制格式）
│   │       └── adguardhome.zh-cn.lmo# 中文编译翻译
│   └── view/
│       └── dashboard.js  # LuCI 2.0 JS View (view.extend)
├── tools/
│   └── po2lmo.py         # .po → .lmo 编译工具（开发用，不部署到路由器）
├── checksums.sha256      # 发布用 sha256 清单（install / 面板升级的内容指纹来源）
├── manifest.json         # 包清单（面板自升级版本号来源）
└── README.md             # 项目说明（英文默认）
└── README.zh-CN.md       # 项目说明（中文）
```

---

## API 接口 / API Endpoints

| 路径 | 方法 | 功能 |
|------|------|------|
| `/admin/services/adguardhome/status` | GET | 获取状态（版本/运行/PID/端口/路径/代理/面板版本） |
| `/admin/services/adguardhome/action` | POST | 执行操作（start/stop/restart/install_service/install_core） |
| `/admin/services/adguardhome/set_proxy` | POST | 立即持久化带类型的代理规格到 `/etc/adguardhome-dashboard.proxy`（`mirror\|<前缀>` / `proxy\|<地址>` / 空 = 直连） |
| `/admin/services/adguardhome/proxy_test` | POST | 按类型构造请求测试代理延迟（镜像前缀 vs `curl -x`；目标：`raw.githubusercontent.com`） |
| `/admin/services/adguardhome/check_update` | POST | 检查 AGH 核心 GitHub 最新版本（用持久化代理） |
| `/admin/services/adguardhome/upgrade` | POST | 启动 AGH 核心升级（force=0 用 `--update` / force=1 用安装脚本 `-r`） |
| `/admin/services/adguardhome/check_dashboard_update` | GET | 检查面板自身最新版本（读 GitHub `manifest.json`） |
| `/admin/services/adguardhome/upgrade_dashboard` | POST | 启动面板自升级（在线下载 7 个文件（含 manifest.json）覆盖本地） |
| `/admin/services/adguardhome/log` | GET | 获取混合日志（顶部 EXEC_LOG + 下部 AGH 原生/logread + 头部摘要） |
| `/admin/services/adguardhome/clear_log` | POST | 清空中间层执行/升级日志（EXEC_LOG） |
| `/admin/services/adguardhome/backups` | GET | 列出 `/root/agh_backup_*` 所有备份目录 |
| `/admin/services/adguardhome/restore_backup` | POST | 从指定备份恢复（执行 `<dir>/restore.sh`） |
| `/admin/services/adguardhome/delete_backup` | POST | 删除指定备份目录 |

---

## 升级流程 / Upgrade Flow

> **渠道支持说明**：本面板仅支持 AdGuard Home **稳定版（release）** 渠道的升级，无法切换到 beta/edge 渠道，也不会拉取 beta/edge 的预发布版本——核心升级始终以最新稳定版为目标。如果你手动安装了 beta/edge 构建，请直接用 `AdGuardHome --update` 升级，或重新安装稳定版。

### AGH 核心升级（两阶段提交 + 自动回滚）

```
阶段1: 备份当前二进制 → /root/agh_backup_core_<ts>/AdGuardHome
阶段2: 执行升级
       ├─ force=1: 多代理下载 install.sh → 停服 → sh install.sh -r
       ├─ force=0 + 有二进制: AdGuardHome --update
       └─ 无二进制: 多代理下载 install.sh → sh install.sh
阶段3: 完整性校验（新二进制存在 + 可执行 + 能输出版本）
阶段4: 校验失败 → 从备份恢复旧二进制 + 重启服务 → 写 FAILED 标记
阶段5: 重启服务 → 写 done 标记
```

### 面板自升级（两阶段提交 + 自动回滚）

```
阶段1: 7 个文件全部下载到 /tmp/agh_dash_new_<ts>/ + 完整性校验
       ├─ 先下载 checksums.sha256（内容指纹清单，来自 GitHub main）
       ├─ 每个文件 sha256 比对（与发布清单一致才放行；代理缓存旧版会被直接拦下）
       ├─ lmo: 校验尾字节 magic 4c4d6f00 (LMO\0)
       ├─ lua: 校验含 'function' + 'list_backups'
       ├─ js:  校验含 'view.extend' + 'fetchBackups'
       └─ po:  校验含 'msgid'
       任一失败 → 写 FAILED 标记 + 自动回滚 → 不动任何目标文件
阶段2: 逐文件备份 + mv 原子覆盖
       任一失败 → 从 /root/agh_backup_dashboard_<ts>/ 还原已部署的 → 写 FAILED 标记
阶段2.5: 在备份目录生成 restore.sh（与 install.sh restore 逻辑一致，恢复 7 个面板文件（含 manifest.json））
阶段3: 清 LuCI 缓存 + 重启 rpcd/uhttpd → 写 done 标记
```

---

## 版本回退 / Version Rollback

### 面板内不支持降级

`check_dashboard_update` 只在「GitHub main 上的远端版本**新于**本地」时提示更新（`need_update = remote > local`）。发布源回退后，已经装了新版本的面板只会显示「已是最新」——升级流程永远不会执行降级。**降级只能通过命令行。**

### 安装任意已发布版本（路由器上直接可用）

每个 tag 在 GitHub 上都有自动生成的源码归档，它本身就是一个可直接运行的安装包（归档结构与安装脚本期望的仓库骨架一致）：

```sh
cd /tmp
curl -fLO https://github.com/imonior/luci-app-adguardhome-dashboard/archive/refs/tags/v2.5.6.tar.gz
tar xzf v2.5.6.tar.gz
sh luci-app-adguardhome-dashboard-2.5.6/scripts/install.sh
# 检测到本地项目文件 → 选 1) 使用本地文件安装
```

- 把 `v2.5.6` 换成任意已发布 tag。装完核对：`cat /usr/share/adguardhome-dashboard/manifest.json` 应显示目标版本。
- 归档下载走 `codeload.github.com`，中国大陆可在 URL 前加镜像前缀（如 `https://ghfast.top/https://github.com/...`），或先在别的机器下载后 `scp` 上路由器。
- AdGuard Home **核心**版本独立于面板，面板回退不影响它。
- 降级后面板会再次提示有新版本更新，忽略即可——不会自动升级。

### 回退发布源本身

发布内容就是 GitHub `main` 上的当前状态（单一数据源 = main 上的 `manifest.json`）。要撤回有问题的版本，在 `main` 上 `git revert` 相应提交即可（**不要**强推）：install.sh、面板自升级、`check_dashboard_update` 立即恢复提供上一个版本，且 `checksums.sha256` 随代码一起回退，指纹校验保持自洽。已发布到既有 tag 名下的资产不会被覆盖或删除。

---

## 代理缓存与内容指纹校验 / Proxy Cache & Content Fingerprint

GitHub 镜像/CDN（如 `ghfast.top`、`gh-proxy.com`）会对 `raw.githubusercontent.com` 的内容做缓存，且往往忽略 `?_cb=` 时间戳参数。如果缓存里是**更早、缺少某些功能的旧版本**，安装/升级会静默装上残缺面板（本项目曾因此导致「备份管理」与「清空日志」按钮不显示）。

为彻底防住这类问题，install 与面板升级都采用 **双重校验**：

1. **sha256 内容指纹（主防线）**：先从 GitHub main 下载 `checksums.sha256`（记录面板文件的 sha256），再对下载到的每个文件逐一比对 sha256。任何与发布清单不一致的内容（含代理缓存旧版、截断、被替换）都会**立即中止并提示换代理**，不会装上残缺面板。
2. **语义特征（兜底防线）**：当 `checksums.sha256` 因网络等原因不可用时，降级为关键字校验 —— `dashboard.js` 必须含 `fetchBackups`、`adguardhome.lua` 必须含 `list_backups`。

### 本地验证已部署面板是否为最新版

```sh
# 路由器上：面板 JS 是否含备份管理（返回 >0 即正常）
grep -c fetchBackups /www/luci-static/resources/view/adguardhome/dashboard.js

# 仓库内：用发布清单校验本地文件（全部 OK 即与发布一致）
sha256sum -c checksums.sha256
```

### 安装/升级时命中旧版本怎么办

安装日志会出现 `sha256 不匹配` / `内容校验失败`，并提示更换代理：

```sh
# 换用其它代理后重跑
GITHUB_PROXY=https://ghfast.top/ sh -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh)"
# 或直接直连 raw.githubusercontent.com（绕过镜像缓存）
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/files/view/dashboard.js -o /www/luci-static/resources/view/adguardhome/dashboard.js
```

---

## 备份与恢复 / Backup & Restore

### 三类备份目录

| 类型 | 产生时机 | 路径 | 含 restore.sh | 恢复内容 |
|------|------|------|:---:|------|
| install | 安装/更新面板 | `/root/agh_backup_install_<ts>` | ✓ | 面板文件（含 manifest.json，不动 AGH 核心） |
| dashboard | 面板自升级 | `/root/agh_backup_dashboard_<ts>` | ✓ | 面板文件（含 manifest.json，不动 AGH 核心） |
| core | AGH 核心升级 | `/root/agh_backup_core_<ts>` | ✗ | 仅含旧二进制（手动 `cp` 恢复） |

### 恢复方式

**面板内**：进入 LuCI → 服务 → AdGuard Home → 备份管理 → 找到对应备份 → 点击「恢复」或「命令」

**命令行**：
```sh
# install / dashboard 类备份
sh /root/agh_backup_install_<ts>/restore.sh
sh /root/agh_backup_dashboard_<ts>/restore.sh

# core 类备份（手动）
/etc/init.d/AdGuardHome stop 2>/dev/null || /etc/init.d/adguardhome stop 2>/dev/null
cp /root/agh_backup_core_<ts>/AdGuardHome /opt/AdGuardHome/AdGuardHome
chmod 755 /opt/AdGuardHome/AdGuardHome
/etc/init.d/AdGuardHome start 2>/dev/null || /etc/init.d/adguardhome start 2>/dev/null
```

> 清理备份：在面板「备份管理」点击「删除」，或手动 `rm -rf /root/agh_backup_*`

---

## 混合日志 / Layered Log

```
┌─────────────────────────────────────────┐
│ === AdGuardHome 状态 ===                │  ← 头部摘要
│ AdGuard Home v0.107.52                  │
│ PID: 1234 (running)                     │
│ ========================...             │
│                                         │
│ === 执行/升级日志 ===                    │  ← 中间层 EXEC_LOG
│ [升级/启动/停止动作的输出]                │
│                                         │
│ === 系统/运行日志 (最新) ===             │  ← 运行日志层
│ [AGH 原生日志 tail -n 100]              │
│ 或 [logread -e AdGuardHome tail -n 50]  │
└─────────────────────────────────────────┘
```

**操作**：
- 「刷新日志」按钮：覆盖重刷最新内容，自动滚到底
- 「清空日志」按钮：清空 EXEC_LOG（运行日志由 AGH/系统管理，不受影响）
- 「自动刷新」开关：3 秒间隔自动拉取（升级进行中时让位给升级轮询，避免冲突）

---

## 系统要求 / Requirements

- OpenWrt / ImmortalWrt / iStoreOS
- LuCI 2.0（OpenWrt 21.02+）
- curl（大多数固件已内置）
- 至少 8MB 剩余空间

---

## 注意事项 / Notes

- 安装完成后，在 LuCI → **服务** → **AdGuard Home** 进入仪表盘
- 代理持久化文件：`/etc/adguardhome-dashboard.proxy`（存放带类型的规格，如 `proxy=mirror|https://ghfast.top/` 或 `proxy=proxy|http://127.0.0.1:7890`）
- 执行/升级日志：`/tmp/agh_exec.log`（EXEC_LOG，含 `done` / `FAILED` 标记供前端轮询判定结果）
- 安装日志：`/etc/adguardhome-dashboard.log`
- 备份目录：`/root/agh_backup_{install,core,dashboard}_<ts>`（按时间戳保留，可在面板「备份管理」清理）

---

## 架构 / Architecture

```
浏览器 JS View  ──HTTP──▸  Lua Controller  ──exec──▸  系统命令
(view.extend)              (util.exec)               (pgrep/init.d/binary)
     │                          │
     │ 5s 轮询 status           │ 读取持久化代理
     │ 2s 轮询 log (升级时)     │ 调用 GitHub raw / API
     │ 3s 轮询 log (自动刷新)   │ 写 EXEC_LOG / 备份目录
     └──────────────────────────┘
```

---

## 变更记录 / Changelog

> 语言切换 / Language: **中文（当前）** · [English](README.md#changelog) —— 对外文档默认英文，本节为中文对照版。

- **v2.5.8**
  - **离线安装包**：每个 Release 现在都附带自包含的 tar.gz（tag 推送时由 `scripts/make_package.sh` + 发布工作流自动构建）。下载、解压、运行 `scripts/install.sh` 即可；包内 `OFFLINE_PACKAGE` 标记会关闭**所有**联网动作（geo 探测、连接选择、在线版本检查、文件下载）
  - **AGH 核心不随包提供、由本地供给**：安装脚本扫描项目目录及其上一级的 `AdGuardHome_linux_<arch>.tar.gz`，完全离线安装核心，复刻官方三步（清目录 → `tar -C /opt -x -z` → `-s install`），带 `--version` 自检与任一步失败即整体回滚。有匹配包且已装核心 → 询问是否覆盖；架构不符 → 同时列出「本机架构 / 目录内可用架构」；无包 → 打印精确文件名与**直链下载方式**（AGH 官方 CDN `static.adtidy.org` 与 GitHub Release 资产——后者大陆可加镜像前缀）及发布页
  - **AGH 核心与本项目面板的已装检测**（在线离线都判）：先检测已装版本，交互确认是否重装（面板默认重装；核心覆盖默认保留）
  - **新增「版本回退」文档章节**：面板内不支持降级；任意已发布版本可用 tag 源码归档一键安装；撤回发布 = 在 `main` 上 `git revert`
  - 覆盖安装的清理判据改为安装**目录**（`-d /opt/AdGuardHome`）而非二进制，避免残留目录把旧文件混进新装
  - 三处裸 `read` 针对 `set -e` + stdin EOF 加固（此前可能静默中止整个安装）
  - 下列原 v2.5.7 工作区改动全部随本版本发布（v2.5.7 从未单独发版）：
  - 替换面板版本比较器（原 `semver_compare` 仅按数字段简单比较，无法正确排序预发布号）为符合 SemVer 的实现（`compareSemVer`/`parseSemVer`）；正式版现在能正确判定比其 beta 更新，控制台自升级提示在任意预发布线之后行为正确
  - 为核心更新检查增加第三条兜底：`static.adtidy.org/adguardhome/release/version.json`（AdGuard Team 自家 CDN），在 GitHub API 与 raw CHANGELOG 两条路都失败时启用，提升 GitHub 被封锁网络下的可达性
  - 修复一处日志显示 bug：升级后二进制版本行多打了一个 `v`（`vv0.107.79`），版本号本身已含 `v` 前缀
  - 文档说明面板**仅支持稳定版渠道升级**（不可切换 beta/edge 渠道）
  - 移除 `kkgithub.com` 代理候选（短期域名，无法长期稳定服务）；内置代理列表现仅 `ghfast.top` / `gh-proxy.com`
  - 新增**出口 IP / 地区检测**：install.sh 与面板均在启动时/加载时探测路由器出口公网 IP 与归属地（公开 geo-IP 服务），显示 IP 归属地，并在中国大陆时建议使用代理、境外时提示直连通常可用
  - 内置镜像（`ghfast.top` / `gh-proxy.com`）明确为**中国大陆专用**：境外时 install.sh 跳过预置镜像（只提供「直连」+ 自定义），面板隐藏镜像行；两处的手动输入始终保留，`GITHUB_PROXY` 环境变量仍可覆盖一切
  - **两种带类型的代理**（二者不可互换——镜像是 URL *前缀*，全量代理是 `curl -x` 目标）：
    - `mirror|<前缀>` —— 把 GitHub 地址拼到前缀后；**仅中国大陆通常有效**；界面上预置候选已标注「适用于中国大陆」
    - `proxy|<地址>` —— 以 `curl -x` 传入、URL 不变（系统代理型，支持 `http(s)`/`socks5`）；任意地区可用
    - `install.sh`、面板、`/etc/adguardhome-dashboard.proxy` 与两个升级生成脚本共用同一规格格式；不带竖线的旧裸值仍按镜像源解析（向后兼容）
  - 面板代理区改为**两个独立的手动输入行**——「自定义镜像源」与「自定义代理服务器」——取代原先含义模糊的单输入框（过去把代理地址填进前缀框会拼出必然失败的 URL）
  - 地区回退由「静默」改为**显式**：境外时原先选中的**镜像**会自动切回「直连」并持久化，且横幅中明确写出——不会再出现「代理被隐藏却仍在后台生效、网络不通却查不出原因」
  - **修复代理解析器的崩溃**：`resolve_proxy()` 调用了声明在其后的 `is_safe_proxy()`，按 Lua 词法作用域会解析为全局（nil）——任何携带 `proxy` 表单值的请求（5 个代理相关 RPC 全部携带）都会抛 `attempt to call a nil value`，表现为「网络不通却没有任何原因提示」。校验函数现已置于调用者之前
  - 放宽全量代理的合法性校验（支持 `socks5://`、裸 `host:port`），注入防护仍走白名单
  - 核心升级生成脚本的全部下载改为走同一个类型感知的辅助函数（取代原来只认镜像前缀的循环）；选择全量代理时，原本必须直连的 `AdGuardHome --update` 步骤也会通过 `HTTPS_PROXY`/`HTTP_PROXY` 走代理
  - 审计 i18n 字典：每个 `T()` 调用都有词条、每条词条都被引用（清理 6 条死词条）

- **v2.5.6**
  - 将代理感知的 GitHub Releases 兜底（此前仅为 `AdGuardHome --update` 增加）扩展到强制重装（`install.sh -r`）与全新安装路径。这两条路径此前直接从 `static.adtidy.org` 拉取二进制包（绕过所选代理）且失败无兜底；现在当 `install.sh` 失败时自动回退到代理感知的包下载 + 覆盖写入
  - `fallback_upgrade_via_proxy` 现接受显式目标路径参数（默认 `BIN_PATH`，为空时取首个 `BIN_PATHS` 条目），使全新安装路径也能正确落盘二进制

- **v2.5.5**
  - 代理选型简化为：先测试连通性 → 按结果选择（install 输入序号 / dashboard 点选）→ 当次下载固定使用 → 仅当所选连接在下载中确实失败时，才用新的连通测试结果交互提示用户改选（install.sh）
  - 自定义代理延迟测试现在稳定可用（`proxify()` 规范化缺失的结尾斜杠）
  - 面板代理测试交互：页面加载自动测 + 手动每个代理单点测试 + 「测试所有」按钮；移除了 60s 后台轮询与升级 FAILED 时的自动重测（用户可手动点测试）

- **v2.5.1**
  - 修复安装脚本校验根因：`verify_one()` 返回语义反转，导致合法文件被误判为失败（中止安装）、陈旧/缓存文件被静默放行。该问题自 2.3.1 引入指纹校验时存在，现已修正（通过→0、失败→1）
  - 面板自升级现在严格遵守 UI 代理选择（选 direct 仅直连；选某代理则仅该代理+直连兜底），不再无条件追加内置代理
  - 面板自升级下载加固：每次 `curl -o` 前先创建目标目录，消除 `curl: (23)` 写失败
  - 安装脚本 GitHub 直连连通性探针改为重试（3 次、每次 12s），避免 `raw.githubusercontent.com` 偶发慢连被误报为「直连不可用」
  - 安装脚本交互改为英文为默认并开头可选语言（English / 中文）；非首次安装备份文案已明确

- **v2.5.0**
  - 版本号提升至 **2.5.0**（版本单一数据源 = `manifest.json`，路由器运行时读取本地部署的 `/usr/share/adguardhome-dashboard/manifest.json`）
  - 修复面板自升级「点升级后下载全失败、只留下空备份目录」：
    - 升级脚本原将 `$TMPDIR` 当作字面量写入被单引号包裹的 shell 参数，`curl -o` 写到假路径导致 `curl: (23)` 写失败；改为使用 Lua 计算出的真实绝对路径
    - 备份目录改为按文件惰性创建，下载/校验失败时不再残留空备份目录
  - 「清空日志」明确语义：仅清空中间层执行/升级日志（EXEC_LOG）；系统/AGH 运行日志层只清视图、刷新后继续显示（不删系统/AGH 自身日志）
- **v2.4.0**
  - 新增备份管理、面板自升级、sha256 内容指纹双重校验、代理缓存防护等（详见「代理缓存与内容指纹校验」一节）

---

**MIT License** | 轻量 · 稳定 · 标准 LuCI 2.0
