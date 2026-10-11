[🇺🇸 English](README.md) · [开发说明 Development](DEVELOPMENT.zh-CN.md)

# AdGuardHome LuCI Dashboard

**LuCI 2.0 标准 AdGuard Home 管理面板** | **LuCI 2.0 AdGuard Home Dashboard**
**v2.6.8**

为 OpenWrt / ImmortalWrt / iStoreOS 提供完整的 AdGuard Home 管理面板。

---

## 安装 / Install

### 一键安装（推荐）

```sh
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh | sh
```

> 用管道把脚本喂给 `sh`（而不是 `sh -c "$(curl …)"`）：后者把整个安装脚本当作**单个命令行参数**传入，脚本体积一旦超过系统的单参数长度上限，就会在真正执行前中断。交互提问会自动从终端读取，选择步骤不受影响。

安装脚本分两步执行：

1. **AdGuard Home 核心** — 检测 `/opt/AdGuardHome/AdGuardHome` 是否已安装，未安装则调用官方脚本自动安装；已安装则可选择覆盖安装（自动停止运行中的服务）或跳过
2. **LuCI Dashboard** — 从 GitHub 下载菜单注册、Lua Controller、JS View、翻译等文件及 `checksums.sha256` 到临时目录，先做 **sha256 内容指纹校验**（命中代理缓存旧版立即中止并提示换代理），再部署到系统对应位置

> install.sh 在覆盖前会自动把现有的面板文件（含 `manifest.json`）备份到 `/root/agh_backup_dashboard_<ts>/`，并在备份目录内生成 `restore.sh`。万一安装失败或想回滚到旧版面板，执行 `sh /root/agh_backup_dashboard_<ts>/restore.sh` 即可（仅恢复面板文件，不动 AGH 核心二进制）。只有已存在面板文件时才会创建备份——即**全新安装不产生任何备份**，install.sh 备份下来的一定是**升级**前的状态。

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
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh | GITHUB_PROXY=https://ghfast.top/ sh
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
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/uninstall.sh | sh
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
- **备份管理**：列出 `/root/agh_backup_*` 所有备份目录（dashboard/core 两类），显示类型/时间戳/文件数/大小/含核心/含 restore.sh；支持一键恢复（仅 dashboard 类备份有 restore.sh）、显示恢复命令、删除备份释放空间
- **install 自带备份**：install.sh 部署前自动备份现有面板文件（含 manifest.json）+ 生成 restore.sh，与面板升级的备份机制完全一致
- **国际化支持**：中英文自动切换，基于 LuCI 系统语言设置（144 条翻译；每条字典项都被引用，每个 `T()` 调用都有词条）
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
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/scripts/install.sh | GITHUB_PROXY=https://ghfast.top/ sh
# 或直接直连 raw.githubusercontent.com（绕过镜像缓存）
curl -fsSL https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main/files/view/dashboard.js -o /www/luci-static/resources/view/adguardhome/dashboard.js
```

---

## 备份与恢复 / Backup & Restore

### 两类备份目录

| 类型 | 产生时机 | 路径 | 含 restore.sh | 恢复内容 |
|------|------|------|:---:|------|
| dashboard（面板升级） | 面板「升级面板」按钮 **或** 在已安装面板的机器上跑 install.sh（一键命令 / 离线包） | `/root/agh_backup_dashboard_<ts>` | ✓ | 面板文件（含 manifest.json，不动 AGH 核心） |
| core（核心升级） | AGH 核心升级 | `/root/agh_backup_core_<ts>` | ✗ | 仅含旧二进制（手动 `cp` 恢复） |

> 名为 `agh_backup_install_<ts>` 的目录是同一件事的历史命名：install.sh 只在已存在面板文件时才会写备份（全新安装无内容可备份），所以那些同样都是面板升级，列表里也按面板升级展示。新备份一律使用 `dashboard` 前缀。把鼠标悬停在面板的类型列上可看到该行的原始目录名。

### 恢复方式

**面板内**：进入 LuCI → 服务 → AdGuard Home → 备份管理 → 找到对应备份 → 点击「恢复」或「命令」

**命令行**：
```sh
# 面板升级类备份
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
- 备份目录：`/root/agh_backup_{dashboard,core}_<ts>`（按时间戳保留，可在面板「备份管理」清理）

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

- **v2.6.8**
  - **修复备份管理里「恢复」和「删除」按钮完全不起作用**：破坏性操作守卫一旦置位就无法复位，随后用一个裸 `return` 把点击吞掉——不发请求、不报错、没有任何提示。已用 jsdom 跑真实模块复现：一次「恢复」成功后 `_actionBusy` 一直保持置位，因为它的**唯一**复位途径是在执行日志里等到完成标记，而并发的「检查更新」会用 `log_start` 截断该日志；于是紧接着点「删除」被静默丢弃
  - **守卫不再可能静默失效**：点击被拦时现在会明确提示「操作进行中，请稍候」，而不是什么都不发生；并且加了看门狗——置位超过 120 秒自动解锁并提示，避免复位路径再次断掉时永久卡死。置位/复位统一走 `_armBusy()` / `_releaseBusy()`（带时间戳），保证每次置位都有配对复位
  - **「升级面板」是同一个失效模式**——它共用这道守卫，所以点击同样会被吞掉，表现为确认弹窗纹丝不动、请求根本没发出；这也解释了为什么日志区完全看不到升级动作（runner 从未启动）。同一次改动一并修好：现在有明确反馈，且锁会自动过期
  - **「恢复」确认框从原生 `window.confirm` 改为 LuCI 的 `ui.showModal`**，与面板其余对话框一致——浏览器会抑制重复的原生对话框，导致点击看起来毫无反应。同时加了 90 秒兜底定时器，不再把守卫复位单独押在日志标记上
  - **日志轮询失败不再完全静默**：`fetchLog` 连续失败 5 次会停止轮询、复位守卫并报错提示
  - 新增 4 条 i18n 词条；两份 `.po` 已更新、两个 `.lmo` 已重编。版本升至 2.6.8；重新生成 `checksums.sha256`。后端（Lua）无改动

- **v2.6.7**
  - **修复「清缓存并重载」在 Safari / 路由器 uhttpd 下仍切不到新视图**：v2.6.5 / 2.6.6 依赖 `fetch(..., {cache:'reload'})` 把新文件写回 HTTP 磁盘缓存，再靠 `location.reload()` 让导航命中那条。但 `cache:'reload'` 的写回是异步的，且在 Safari / 路由器 uhttpd 下不可靠——导航先读到旧条目，旧视图又复活了。只有开发者工具「禁用缓存」才有效，因为它完全跳过缓存查找、因而根本不发条件头
  - **该按钮现在改为原地「热替换」最新视图，不再依赖 HTTP 缓存写回**：先停掉旧实例的轮询，再以 `cache: 'no-store'`（强制浏览器绕过 HTTP 缓存、从服务端取真文件，任何 URL 变体的缓存副本都绕开）加上必然不匹配的 `If-None-Match` / 1970 的 `If-Modified-Since` 把最新 dashboard.js 作为文本拉取；在本模块自身闭包作用域内重新求值该文本得到新视图类，实例化后用已持有的数据 `render()`，再以 `parentNode.replaceChild` 替换根节点。旧视图消失、新视图即时生效，无需整页重载
  - **已经卡在旧视图上的浏览器仍需手动硬刷新一次来加载本版本**——旧副本里的按钮无法自我修复（与以往相同）。此后每次升级都由热替换自动处理
  - 版本升至 2.6.7；重新生成 `checksums.sha256`。无新增 i18n 词条

- **v2.6.6**
  - **修复 v2.6.4 引入的回归：「检查更新」后点「升级面板」毫无反应**：破坏性操作守卫 `_actionLocked` 此前只要日志轮询在进行就返回 true，而「检查更新」恰恰会启动这样一个轮询 —— 于是在轮询看到 `=== check done ===` 之前的约 2–4 秒窗口里，点「升级」会被静默吞掉（模态关了、请求没发出、也没有报错）。v2.6.2 / v2.6.3 没有这道守卫，升级一直正常
  - **守卫现在只认真正进行中的破坏性操作**（`_actionBusy`），不再认被动日志轮询。每个破坏性操作（面板升级、核心安装/升级、恢复、删除备份）都在开始时置位 `_actionBusy`，并在日志中出现完成标记（或失败 / 轮询超时）时复位，因此并发重复提交仍被拦截，而「检查→升级」的误拦截已消除
  - **「从备份恢复」是同一个静默吞掉回归、且已被同一处改动修好**：v2.6.4 / 2.6.5 的 `confirmRestore` 开头也是 `if (this._actionLocked()) return;`（即 v2.6.4 变更记录的「破坏性按钮防重复提交」一条），所以在「检查更新」后的轮询窗口里点「恢复」和「升级」一样会被吞掉。后端 `restore_backup` 本身从未出错（自 v2.6.2 起未变；面板备份与核心备份都自带 `restore.sh`）。2.6.6 的解耦让「恢复」恢复正常 —— 无需另出补丁
  - 版本升至 2.6.6；重新生成 `checksums.sha256`。无新增 i18n 词条

- **v2.6.5**
  - **修复「清缓存并重载」点击无效 —— 现在真正刷新了被缓存的视图 JS**（两个独立成因需一并修掉）：该按钮此前把本视图按 `dashboard.js?_cb=<时间戳>` 重新拉取，但 HTTP 缓存以**完整 URL（含 query）**为键，那只刷新了一个根本没人请求的条目。LuCI 加载视图模块的 URL 是 `base_url + 模块路径 + '.js'`，并在页面 `luci.js` 的 src 带 `?v=` 时再追加 `?v=` + `resource_version`（`luci.js:2474`，21.02 起即有）——而这个 `?v=` 只跟随 LuCI 自身、**不随本面板升级变化**，所以旧的 `dashboard.js` 被无限期命中，只能靠关闭浏览器缓存绕开。现在裸 URL 与带 `?v=` 的 URL 都会以 `cache: 'reload'` 重新拉取（该模式绕过缓存读取并把新响应写回），真正刷新的正是 LuCI 会请求的那个键，重载后即是新视图
  - **条件请求被回以 `304`，这正是连 Ctrl+F5 / Cmd+Shift+R 都无效的原因**：重验证请求会带上 `If-None-Match` / `If-Modified-Since`，只要服务端校验器仍判「未修改」，浏览器就继续复用缓存里的旧 body。没有电池 RTC 的路由器重启后时钟会回落到固件编译日期，于是新部署的文件 mtime 可能比缓存里的**更旧**，uhttpd 就回 `304` —— 新文件确实在磁盘上，但每次重载都在吐旧的那个。DevTools「Disable cache」之所以看起来有效，只是因为它完全跳过缓存查找、因而根本不发条件头。现在刷新时会显式带上必然不匹配的 `If-None-Match` 与 1970 的 `If-Modified-Since`，让服务端无论如何都回 `200` 全量内容，再由 `cache: 'reload'`（绕过缓存读取并把新响应写回）存下来
  - **按钮现在能证明自己在工作**：点击后立即置灰并变为「处理中...」，不再看起来毫无反应
  - **卡住的请求不会再无限期推迟重载**：刷新逻辑包在 Promise 里并附带 3 秒超时兜底，即使 fetch 挂住也会继续重载
  - **注意**：已经卡在旧视图上的浏览器需要**手动硬刷新一次**（Ctrl+F5 / Cmd+Shift+R）来加载本版本 —— 旧副本里的按钮无法自我修复。此后每次面板升级都会自动处理
  - 版本升至 2.6.5；重新生成 `checksums.sha256`。无新增 i18n 词条（「处理中...」已存在）

- **v2.6.4**
  - **安全：远端版本号不再拼进 shell 命令（root RCE）**：`check_update` 与 `check_dashboard_update` 过去把网络取回的版本号直接写进 `util.exec("echo '  result: latest = " .. v .. "' >> " .. EXEC_LOG)`。捕获模式 `(.-)` 与 `([^"]+)` 都放行 `'`、`$(`、反引号和 `;`，一个单引号就能闭合字面量并以 root 执行任意命令（uhttpd 以 root 运行）。这两个端点在页面加载约 1 秒后自动调用，用户填写的 `mirror|https://<host>/`、或镜像被投毒 / 链路被中间人篡改，都足以控制该值。现在 14 处日志写入全部改走 Lua `io.open(..., "a")`（`log_line` / `log_start`），日志内容只可能是字节；版本号另外还要过 `safe_version()` 白名单（`^v?%d+%.%d+%.%d+[%w%.%+%-]*$`）才会被使用
  - **安全：持久化代理规格读取时也校验**：`/etc/adguardhome-dashboard.proxy`（权限 644）由 `get_persisted_proxy()` 读出后直接进入 `PRIMARY_PROXY`，而后者会被拼进生成的 shell 脚本头部（`PRIMARY_PROXY='...'`）与 `curl -x`。请求参数一直都过 `is_safe_spec`，唯独这条读取路径没有。现在读取后重新校验，不合法则回落直连并记日志
  - **写类 RPC 改用 `post()`，CSRF token 校验才真正执行**：14 个 entry 原先全部用 `call()` 声明，生成的 target 不带 `post` 字段 → LuCI 的 `require_post_security()` 恒为 false → `test_post_security()`（比对 `http.formvalue("token")` 与会话 authtoken）一次都不跑，删备份 / 升级 / 写代理 / 恢复 / 执行动作 / 清日志都能被 GET 触发。读类保留 `call()`；前端 `request.post` 会自动带 token
  - **`install.sh` 不再先毁掉已有核心再解压**：覆盖 `/opt/AdGuardHome` 时过去先 `rm -rf` 整个目录，压缩包损坏或架构不匹配时旧二进制**和** `AdGuardHome.yaml`（过滤规则、DNS 重写、DHCP、账号密码）一起消失，日志却仍打印"已回滚"。现在删除前先把二进制与 yaml 备份到 `/root/agh_backup_core_<ts>/`（与面板核心升级同一布局），三条失败路径都会真正回滚：还原文件并重新注册服务。`data/` 查询日志刻意不复制，避免撑爆小路由器的 flash
  - **缺少 sha256 指纹清单时拒绝部署**：`checksums.sha256` 下载失败时，`install.sh` 与面板升级 runner 都会降级成三条 `grep` 语义特征（`fetchBackups` / `list_backups`），伪造内容多加一行就能通过。现在两者都把清单缺失判为失败——install.sh 换连接重试，runner 中止并回滚
  - **`install.sh` 安装核心不再 `curl | sh`**：脚本有 `set -e` 但没有 `pipefail`，`gh_curl "$AGH_INSTALL_URL" -fsSL | sh` 的退出码取自 `sh`；curl 失败（镜像 404、TLS 错误、缓存空文件）时喂进去的是空输入，`sh` 成功返回 0，于是照常打印"安装完成"而其实什么都没装。现在先落盘、检查非空、再执行
  - **`install.sh` 拒绝删除不安全的项目目录**：「删除本地项目后重新下载」分支过去只判断 `-n` 与 `-d`。`PROJECT_ROOT` 是 `dirname(dirname $0)` 推出来的，当 `files/` + `scripts/` 摆在 `/opt`、`/root` 或 `/mnt/...` 下时它就等于那个目录，连同 AGH 核心与备份一起被删。现在额外要求：目录名不得落在高危父目录名单内，且必须真的含有 `manifest.json` 与 `files/luci/controller/adguardhome.lua`；否则不删除任何文件，直接重新下载
  - **修复 `delete_backup` 永远报成功**：`fs.access(dir) and false or true` 恒为 `true`（`(x and false) or true`），`ok and nil or X` 恒得到 `X`，于是 `rm -rf` 失败也报成功，还附带一条 error。改为 `ok = not fs.access(dir)`
  - **修复核心升级失败仍报 done**：回滚分支只判断 `VERIFY_OK`。升级命令失败但旧二进制仍可执行时校验通过 → 跳过回滚 → 照样打印 `=== core upgrade done ===`，而这正是前端等待的完成标记。现在同时判断 `UPGRADE_RC`
  - **修复「含核心」列恒为否**：`list_backups` 查的是 `<dir>/core/AdGuardHome`，而核心备份把二进制放在 `<dir>/AdGuardHome`。现在两种布局都认。核心备份同时生成 `restore.sh`（面板 `restore_backup` 要求存在），由「只能看」变为可一键恢复
  - **修复升级按钮谎报已启动**：前端 `doUpgrade` 从不读响应（`.then(function(){...})` 连形参都没有），后端又丢弃 `launch_core_upgrade()` 的返回值、无条件返回 `success = true`。runner 写入失败现在会如实报错，而不是让日志轮询空转 300 秒。`do_upgrade` / `install_core` 返回真实状态
  - **破坏性按钮防重复提交**：升级 / 强制重装 / 安装核心 / 升级面板 / 恢复 / 删除现在点击后立即禁用，并受 `_actionLocked()` 保护（有请求在飞或升级轮询进行中）。后端 runner 走固定路径，连点过去会覆盖正在执行的脚本并拉起第二个进程
  - **修复代理持久化静默失败**：两处 `sendSetProxy` 调用不检查业务 `success`，`_syncRegionPolicy` 还先乐观地把 `statusData.proxy` 改掉——写入失败时界面显示一个代理，check / upgrade 却用另一个，且没有任何提示。三处现统一走 `_persistProxy()`：仅成功才更新本地状态，失败时弹出提示
  - **修复日志轮询泄漏**：`autoRefreshLogInterval` 未纳入视图卸载清理，开启「自动刷新日志」后切到别的 LuCI 页面，3 秒一次的 `fetchLog()` 会一直跑。恢复 / 删除的错误提示改用 `ui.addNotification` 而非 `alert()`——后者阻塞主线程、会卡住 2 秒轮询
  - **`uninstall.sh` 补删 `/usr/share/adguardhome-dashboard/`**：`install.sh` 把该目录下的 `manifest.json` 当作「本项目是否已安装」的首要判据，残留会让下次安装误报「检测到已安装 vX.Y.Z」且版本号是旧的。日志文件改到最后删除（过去删完立刻被后续 `log()` 重建，等于没清理），`log()` 改用重定向而非 `| tee -a`，`/etc` 只读时不会再让整个卸载在第一行就中止
  - `checksums.sha256` 已重新生成；i18n 同步更新（新增 2 条词条，`.lmo` 已重编）

- **v2.6.3**
  - **将 rpcd ACL 收紧到最小权限（删除从未使用过的通配授权）**：`files/luci/acl.json` 原先声明 `read.ubus.*:*`、`write.ubus.*:*` 与 `write.uci.*`，但面板从未真正用到这些授权。前端只通过 LuCI dispatcher（`L.url('admin/services/adguardhome/…')` + `request.get/post`）调用 controller；Lua controller 的 root 级操作是用 `os.execute` / `luci.util.exec` / `nixio.fs` 直接在 LuCI 进程内完成的，从不调用 `uci`、`ubus` 或任何 rpcd 对象。这些通配授权属于「模板带进来」的多余声明，并非功能需要。现在 `read`/`write` 改为空对象 `{}`，仅保留 `menu.d` 引用的组名，安装 / 启停 / 升级 / 卸载以及面板本身均不受影响
    - **回滚（紧急恢复）**：将 `files/luci/acl.json` 改回旧值——`"read": { "ubus": { "*": [ "*" ] } }, "write": { "ubus": { "*": [ "*" ] }, "uci": [ "*" ] }`——本次提交的 diff 中保留了改前原内容
  - **`install.sh` 现继承所选代理用于「强制重装 / 全新安装」核心**：选中 `proxy|<addr>` 时，核心升级 runner 过去是用直连执行官方 AdGuard Home `install.sh`（`-r` 或全新安装）——用户配置的代理只用于下载 `install.sh` 本身，脚本内部下载 AGH 二进制时仍是直连，在大陆网络下可能在 `fallback_upgrade_via_proxy` 兜底生效前就先卡住。现在 runner 在运行 `install.sh` 前设置 `HTTPS_PROXY` / `HTTP_PROXY`（镜像模式仍无法代理这一步——镜像只是 URL 前缀而非 `curl -x` 地址，因此继续保留既有兜底）
  - **面板升级 runner 路径与核心升级统一（固定路径，非时间戳）**：两个 runner 现在都使用固定路径（`/tmp/agh_dashboard_upgrade_runner.sh` 和 `/tmp/agh_core_upgrade_runner.sh`），不再用时间戳生成唯一路径。单用户家庭路由器场景不存在并发升级风险，也无需保留历史 runner 脚本。cleanup 函数在退出时删除固定路径
  - **固定路径添加英中双语注释**：`launch_core_upgrade` 与 `do_upgrade_dashboard` 两处均补充双语注释，说明为何使用固定路径（单用户、无并发、无历史保留）。`ts` 时间戳变量仍在作用域内，且在生成的 shell 脚本内部用于 `BACKUP_DIR` 与 `TMPDIR`——它**不是**版本号，不可删除
  - `checksums.sha256` 已重新生成（发布门禁会校验此文件与 `files/luci/acl.json` 及 `files/luci/controller/adguardhome.lua` 的一致性）

- **v2.6.2**
  - **修复「备份明明是升级、却被标成安装」**：install.sh 里备份目录名写死为 `/root/agh_backup_install_<ts>`，但它只在「已存在面板文件」时才会写备份——全新安装只打印 "Fresh install detected"，不会留下任何目录。也就是说**每一个** `agh_backup_install_*` 本质上都是一次面板升级（通过一键命令或离线包），却在面板「备份管理」里显示成「安装」。现在按「实际被覆盖的是什么」判定类型：检测到已有面板文件 → `agh_backup_dashboard_<ts>`（面板升级），否则保留 `install` 命名（此时也不会创建目录）。日志文案同步改为 "Panel upgrade detected / 检测到面板升级"
  - **历史 `agh_backup_install_*` 目录也按面板升级展示**（BACKUP_DIR 类型映射）：既然只有覆盖已有面板才会产生备份，这些目录按定义就是面板升级。目录名保持原样——恢复、删除、`restore.sh` 均不受影响。把鼠标悬停在面板类型列上可看到原始目录名，两条产生路径仍可区分
  - 文档：备份类型表改为两行（dashboard / core）并加历史命名说明；install.sh / 回滚路径统一为 `/root/agh_backup_dashboard_<ts>`

- **v2.6.1**
  - **「面板版本」区块现在会显示浏览器实际在跑哪一份视图**：新增第三行 `浏览器已加载：vX.Y.Z`，取自写死在视图 JS 里的 `DASHBOARD_VIEW_VERSION`——这才是「浏览器此刻执行的是哪一版代码」的唯一可信来源。服务端上报的版本（`当前面板版本：` / manifest）在部署后立刻更新，但它无法反映浏览器是否还在用 localStorage / HTTP 缓存里的旧视图。两者不一致时该行变红并提示缓存原因；旁边的 **`清缓存并重载`** 按钮**常驻**（而非仅在不一致时出现——浏览器跑的是旧 JS 时新代码根本没机会执行，真卡住的人恰恰看不到红字提示）。该按钮执行真正的硬重载：清掉 localStorage 里 LuCI 缓存的 view 模块、用 `cache:'reload'` 重新拉取视图 JS、清空 Cache Storage、再 replace 到带 cache-buster 的 URL。至此「升级了界面还是旧的 / 出口 IP 一直探测不出」这类纯浏览器缓存问题可以自诊断，不再无声无息
  - **加固服务端出口 IP 探测的诊断能力**：`geo_probe` 先 `command -v curl` 判断有无 curl，缺失直接返回 `curl: missing`；每次请求追加 `; printf '\n__RC__=%s' "$?"`，把真实退出码与 stderr 通过 `errors[]` 回传；非零退出（DNS 失败 rc=6、SSL 失败 rc=60、HTTP 403 rc=22）不再被误判为成功——此前 403 页面会被当成有效响应解析，还可能把 `is_cn` 算错、连带地区策略失效。失败横幅现在直出首个错误（如 `ip-api.com: rc=60 SSL certificate problem`），不再只是一句笼统的「未能检测」。原自修复用的 `location.reload(true)`（force 参数早已被浏览器忽略）也已替换为与按钮相同的绕缓存重载

- **v2.6.0**
  - **修复出口 IP / 归属地横幅永远探测不出结果**：`sendGeoProbe` 直接把 RPC 响应传给了 `renderGeo`，但 LuCI 前端的 `request.get()` resolve 出来的是 **Response 包装对象**（`status` / `headers` / `json()`）而非数据载荷。于是 `renderGeo` 拿到的 `ok` 恒为 `undefined`，**每次都渲染「未能检测网络出口 IP」**——可服务端其实探测成功了（服务端探测本身没问题，而且比安装脚本更宽：10 端点 vs 4 端点，这正是「安装脚本能探测、面板永远探测不出」的原因）。现按文件里其它所有 RPC 一致的方式先 `res.json()`
  - 同一 bug 还导致地区策略从未生效：`geoData.is_cn === false`（境外时收起仅大陆有效的预置镜像行、若已选镜像则回退直连）永远不成立。两者现已恢复
  - **修复英文界面显示中文**：备份管理功能新增的字符串（33 条——「Backup Management」「Refresh Backups」「Restore」「Delete」、表头、确认提示等）被写入 `adguardhome.po` 时英文 `msgstr` 直接沿用了中文源文本，导致英文语言环境下界面显示中文。现已补齐英文译文，并**重新编译两个 `.lmo`**——LuCI 运行时加载的是二进制 `.lmo` 而非 `.po`，只改 `.po` 而不重编的话路由器上毫无变化
  - **发布门禁新增多语言检查**：`scripts/release.sh` 增加独立一节——中英 `.po` 的 msgid 集合必须一致、英文 `msgstr` 不得再含中文、中文 `msgstr` 不得为空、每个 `.lmo` 必须与对应 `.po` 现场编译结果字节一致（`.lmo` 过期否则完全不可见）、视图兜底字典 `_EN` 不得有未翻译项且必须覆盖所有 `T()` 键、两份 README 的章节结构必须一致。缺少 `python3` / `po2lmo.py` 时在 `--strict` 下视为失败，而不是静默跳过门禁

- **v2.5.10**
  - **修复面板自升级必然在 LMO 校验处中止**：生成的升级脚本用 `od -An -tx1` 提取 `.lmo` 末尾字节的十六进制，但 OpenWrt 的 BusyBox **没有 `od`**（install.sh 的端序判定注释其实早就写明了这一点）。`2>/dev/null` 把 `od: not found` 吞掉、摘要恒为空，于是**任何合法 `.lmo` 都校验失败**——升级回滚并报 `[verify] LMO magic bad`。现改为用 `sha256_of`（本就强制依赖）对末 4 字节求摘要、与 `LMO\0` 的已知 sha256 比对；零新增依赖，摘要为空时按失败处理（fail-closed）
  - ⚠️ **≤ 2.5.9 的路由器无法通过面板自升级升到本版**——损坏的校验器位于**已部署**的 controller 里（由它生成升级脚本），面板路径无法自我修复。请先跑一次 install.sh 一键命令（直接下载部署 2.5.10）；从 2.5.10 起，面板自升级恢复正常

- **v2.5.9**
  - **修复面板自升级「点了没反应」**（即「检测到新版、但日志空白且未升级」）：生成的升级脚本 stderr 原先落在 HTTP 连接上、随连接一起丢弃，导致任何解析/启动失败都毫无痕迹。现在两个生成脚本（核心升级 + 面板升级）都把 stderr 并入执行日志，面板也改为检查 RPC 的 `success` 字段而非只看 HTTP 200——启动失败会弹出真实错误提示，不再假报「升级已启动」
  - **防旧视图自修复**：视图 JS 现在内嵌 `DASHBOARD_VIEW_VERSION`，渲染时与服务端下发版本比对；不一致即说明浏览器在跑缓存的旧视图（LuCI 的 view 模块按 URL 缓存在 localStorage / HTTP 缓存中——这正是升级 + 刷新后界面仍残留旧内容的原因），面板会自动清除这些缓存视图项并硬重载一次（sessionStorage 防重载死循环）。此后升级无需再手动清浏览器存储
  - **出口 IP / 地区探测更健壮**：geo 探测端点由 4 个增至 10 个（新增 ipapi.co、api.myip.com、extreme-ip-lookup.com、checkip.amazonaws.com、ifconfig.me、icanhazip.com 及纯 IP 服务），每个端点重试 1 次，单次 `--connect-timeout 4 --max-time 6`，总耗时上限 25s；返回值带上「已尝试的端点」列表，失败时界面直接显示，便于诊断
  - **发布工具链**：新增 `scripts/release.sh` 发布编排器——一条命令完成推送前完整检查（`manifest.json` / 视图 JS 常量 / 两份 README 的版本一致性、双语变更记录条目、shell + JS + Lua 代码语法、`checksums.sha256` 指纹、`changes_package/` 同步）并构建离线安装包。发布工作流在构建前以 `--check --strict` 调用它，并新增 runner 侧安装 Lua（runner 镜像不含 Lua，此前导致 Lua 语法门禁静默失效）与完整历史 checkout（保证 tag / 版本交叉核对能取到 tag）
  - Release 资产保持为**精简的离线安装包**（仅含可部署文件 + 安装脚本 + manifest / 校验清单）；完整项目源码由 Release 页面自动附带的 *Source code* 归档提供，**不再**把 README / LICENSE 等文档塞进安装包
  - **一键安装命令改为管道形态**——由 `sh -c "$(curl …)"` 改为 `curl -fsSL <url> | sh`。原写法会把整个脚本展开成**单个 argv**，脚本一旦超过单参数上限就会以 `argument list too long` 在执行前中断；改用 stdin 管道则完全没有长度上限（也不需要临时文件）。安装脚本已适配该调用方式：交互读取统一走 `read_input` helper（脚本自身来自 stdin 时改读 `/dev/tty`，否则裸 `read` 会**吞掉脚本的下一行**），交互判据统一收敛到与读取共用的 `_is_interactive` 谓词，因此管道运行仍可正常提问。`sh install.sh`（以及 `printf '1\n' | sh install.sh`）行为完全不变。脚本来自 stdin 时还会清空「本地项目路径」，避免「删除本地副本后重新下载」分支把路径解析成当前目录的上级
  - `DEVELOPMENT.md` 发布章节重写以匹配当前流程（四处同步版本号、重算校验清单、`sh scripts/release.sh --check`、CI `--check --strict`）

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
