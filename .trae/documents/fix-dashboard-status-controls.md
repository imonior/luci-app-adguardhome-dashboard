# AdGuard Home Dashboard 修复与完备体升级计划

> **交付状态 (v2.1, 2026-07-08)**：所有规划功能已实现。
> - 菜单注册改用 `files/luci/menu.d/luci-app-adguardhome-dashboard.json`（LuCI 2.0 标准，非旧 `files/luci/menu.json`）
> - `dashboard.htm` 模板已删除（不再需要，LuCI 2.0 由 menu.json + JS View 管理生命周期）
> - `install.sh` 改为文件复制模式（非 curl-pipe heredoc），从项目目录直接部署
> - Lua Controller 移至 `/usr/lib/lua/luci/controller/`（非 `/usr/share/luci/controller/`）
> - 5 个 API 端点全部实现（含 `get_log()`）
> - 日志查看器已实现（含升级时 2s 快速轮询）
> - 翻译文件已同步，.lmo 使用标准 LMO 格式编译

## Context

Dashboard 的核心版本、运行状态无法正确显示，控制按钮不起作用。根因有三：

1. **ACL 权限缺失**：`acl.json` 仅授予 `cgi-io: list` 读权限，`fs.exec()` 被 LuCI 沙箱拦截
2. **版本解析错误**：用 `-s status` 获取版本（该命令不输出版本号），且正则 `version\s*=\s*"..."` 不匹配 AdGuardHome 实际输出格式 `AdGuard Home, version v0.107.77`
3. **状态检测不可靠**：依赖匹配 `service: running` 字符串，不同版本输出格式不同

采用 LuCI 2.0 标准实践修复：添加后端 Lua Controller 提供 RPC 接口，前端改用 `request` 库调用。同时加入日志查看器、5 秒状态轮询、版本检查与一键升级功能。

## 修改文件清单

### 1. 新增 `files/luci/controller/adguardhome.lua` — 后端 RPC Controller

后端控制器，仅注册 RPC leaf 节点（不注册菜单，菜单由 `menu.json` 处理）。

**路由注册**（`index()` 函数）：
- `admin/services/adguardhome/status` → `get_status()`
- `admin/services/adguardhome/action` → `do_action()`
- `admin/services/adguardhome/check_update` → `check_update()`
- `admin/services/adguardhome/upgrade` → `do_upgrade()`
- `admin/services/adguardhome/log` → `get_log()`

所有 `entry()` 使用 `.leaf = true`，不设 title（不出现在菜单中）。

**`get_status()` 修复要点**：
- 版本：执行 `/opt/AdGuardHome/AdGuardHome --version 2>&1`，用 `ver:match("version v?([%d%.]+)")` 捕获
- 运行状态：用 `pgrep -f AdGuardHome` 获取 PID（比字符串匹配可靠）
- 端口：遍历 `/opt/AdGuardHome/AdGuardHome.yaml`、`/etc/AdGuardHome.yaml`、`/etc/adguardhome/adguardhome.yaml`，匹配 `port:%s*(%d+)`

**`do_action(action)` 修复要点**：
- 白名单校验 action（仅允许 `start`/`stop`/`restart`/`install_service`），防止命令注入
- 用 `util.exec()` 执行 `/etc/init.d/AdGuardHome <action>` 或二进制 `-s <action>`

**`check_update()` 修复要点**：
- 修正 Gemini 代码中的反引号 bug：URL 用单引号包裹，不是反引号（反引号在 shell 中是命令替换）
- `curl -m 8 -fsSL 'https://api.github.com/...'`，正则提取 `tag_name`

**`do_upgrade()` 修复要点**：
- 同样修正反引号 bug
- `os.execute("echo '...' > /tmp/agh_upgrade.log")` 清空旧日志
- `os.execute("curl -fsSL '...' | sh >> /tmp/agh_upgrade.log 2>&1 &")` 后台执行，避免 504

**`get_log()` 逻辑**：
- 优先读 `/tmp/agh_upgrade.log`（升级日志，size > 100 才算有内容）
- 否则 `logread -e AdGuardHome | tail -n 30`
- 都没有则返回提示文本

### 2. 重写 `files/view/dashboard.js` — 前端视图

**模块依赖变更**：
- 移除：`'require fs'`、`'require rpc'`
- 新增：`'require request'`

**API 调用层**（全部通过 `request` 库 + `L.url()` 路径）：
```javascript
fetchStatus:  request.get(L.url('admin/services/adguardhome/status'))
sendAction:   request.post(L.url('admin/services/adguardhome/action'), { action: action })
fetchUpdate:  request.get(L.url('admin/services/adguardhome/check_update'))
sendUpgrade:  request.post(L.url('admin/services/adguardhome/upgrade'))
fetchLog:     request.get(L.url('admin/services/adguardhome/log'))
```

**`load()`**：并行获取 status + log

**`render()` 布局**（4 个区块）：
1. **实时仪表盘** — 表格显示：核心部署、核心版本、服务状态、运行状态(含PID)、Web端口、管理入口链接
2. **服务控制台** — 启动/重启/停止/注册服务 按钮，显示当前控制模式
3. **版本更新** — 显示当前版本 vs 最新版本，一键升级按钮
4. **日志查看器** — `<pre>` 滚动区域 + 手动刷新按钮

**5 秒自动轮询**：
- `render()` 中用 `setInterval` 每 5 秒调用 `fetchStatus()`
- 回调中更新 DOM 元素（不重新 render 整个视图）
- 用 `document.body.contains(rootNode)` 检测视图是否仍可见，不可见时 `clearInterval`

**控制按钮执行流程**：
- `execAction(action)` → `ui.showModal('执行中...')` → `sendAction(action)` → `ui.hideModal()` → 成功则刷新状态 + `ui.addNotification`，失败则显示错误

**升级执行流程**：
- 点击升级 → 确认对话框 → `sendUpgrade()` → 启动日志快速轮询（每 2 秒 `fetchLog()`）→ 更新 `<pre>` 内容（自动滚到底部）→ 5 分钟后或检测到日志含 "done"/"installed" 时停止快速轮询

**修复 Gemini 代码的问题**：
- `localLog` 全局变量 → 改为 `this.logData` 视图属性
- 补全 Gemini 截断的 `execAction` 函数

**保留现有 UI 风格**：表格 + cbi-section + cbi-button 样式不变，仅切换数据来源。

### 3. 更新 `scripts/install.sh`

**`fetch()` 函数增加下载**：
```sh
download "$BASE/files/luci/controller/adguardhome.lua" "$TMP/adguardhome.lua"
```

**`apply()` 函数增加部署**：
```sh
mkdir -p /usr/share/luci/controller
cp "$TMP/adguardhome.lua" /usr/share/luci/controller/adguardhome.lua
chmod 644 /usr/share/luci/controller/adguardhome.lua
```

**`verify()` 函数增加检查**：
```sh
[ -f /usr/share/luci/controller/adguardhome.lua ]
```

### 4. 更新 `scripts/uninstall.sh`

增加一行：
```sh
rm -f /usr/share/luci/controller/adguardhome.lua
```

### 5. 新增 `files/luci/menu.d/luci-app-adguardhome-dashboard.json`

LuCI 2.0 标准菜单注册，`"action": {"type": "view", "path": "adguardhome/dashboard"}`。取代旧的 Lua `entry()` 菜单注册和 `dashboard.htm` 模板渲染方式。

### 6. 不变：`files/luci/acl.json`

Controller 端点由 LuCI session 认证保护（admin 路径下自动 require admin 登录），不需要额外 rpcd ACL。

## 架构对比

```
当前（不工作）:
  浏览器 → fs.exec() → 直接执行二进制 → ACL 拦截 ✗

修复后:
  浏览器 → request.get/post(L.url(...)) → LuCI Controller RPC → util.exec() → 系统命令 ✓
  升级:  Controller → os.execute("... &") → 后台执行 → 日志写入 /tmp/agh_upgrade.log ✓
```

## 验证

1. 在 OpenWrt 上执行 `install.sh` 安装
2. 进入 LuCI → 服务 → AdGuard Home
3. 验证仪表盘：核心版本应显示 `v0.107.x`，运行状态应显示 `● 正在运行 (PID xxx)` 或 `■ 已停止`
4. 验证控制按钮：点击启动/停止/重启，应弹出"执行中"模态框，完成后显示成功通知并自动刷新状态
5. 验证 5 秒轮询：手动 `kill` AdGuardHome 进程，5 秒内仪表盘应自动更新为"已停止"
6. 验证日志查看器：点击刷新按钮，应显示最近 30 行系统日志或升级日志
7. 验证版本检查：点击"检查更新"，应显示 GitHub 最新 release 版本号
8. 验证一键升级：点击升级后，日志查看器应实时滚动显示下载和安装进度
9. 卸载验证：执行 `uninstall.sh`，确认 controller 文件被移除
