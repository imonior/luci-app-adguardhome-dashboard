#!/bin/sh
set -e

# 完全卸载 AdGuardHome LuCI Dashboard：移除全部 LuCI 资产、配置标记与缓存。
# Fully remove the AdGuardHome LuCI Dashboard: all LuCI assets, config markers and caches.
LOG="/etc/adguardhome-dashboard.log"
log() {
    # 用重定向而非 `| tee -a`：管道的退出码取 tee，/etc 只读或写满时 tee 失败会让
    # set -e 在第一行 log 就终止整个卸载。/ Redirection instead of `| tee -a`: a pipeline
    # takes tee's exit status, so a read-only or full /etc aborts the whole uninstall on the
    # very first log line under set -e.
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] [uninstall] $1" >> "$LOG" 2>/dev/null || true
    echo "[$ts] [uninstall] $1"
}

log "start uninstall"

# 1. 彻底移除所有 LuCI 资产 / Remove every LuCI asset
# Controller
rm -f /usr/lib/lua/luci/controller/adguardhome.lua
rm -f /usr/share/luci/controller/adguardhome.lua
# 旧版 HTML 模板（v1 遗留）/ Legacy v1 HTML templates
rm -rf /usr/lib/lua/luci/view/adguardhome
# JS View
rm -f /www/luci-static/resources/view/adguardhome/dashboard.js
rm -rf /www/luci-static/resources/view/adguardhome 2>/dev/null || true
# Menu & ACL
rm -f /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json
rm -f /usr/share/luci/menu.d/luci-app-adguardhome.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome.json
# i18n
rm -f /usr/lib/lua/luci/i18n/adguardhome.lmo
rm -f /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo
rm -f /usr/share/luci/i18n/adguardhome.po
rm -f /usr/share/luci/i18n/adguardhome.zh-cn.po
# 部署清单目录：install.sh 把 /usr/share/adguardhome-dashboard/manifest.json 当作
# 「本项目是否已安装」的首要判据。漏删会让下次安装误报「检测到已安装 vX.Y.Z」，
# 且残留的版本号可能还是旧的。/ Deployed manifest dir: install.sh treats
# /usr/share/adguardhome-dashboard/manifest.json as the primary "is this project installed"
# marker. Leaving it behind makes the next install wrongly report "detected installed vX.Y.Z"
# with a stale version number.
rm -rf /usr/share/adguardhome-dashboard

# 2. 清理配置标记 / Clean up config markers
rm -f /etc/adguardhome-dashboard.version
rm -f /etc/adguardhome-dashboard.proxy

# 3. 强力清除 LuCI 索引缓存 (关键步骤) / Force-clear the LuCI index cache (critical step)
# 卸载不彻底的核心原因往往是索引缓存没删，导致后台还在试图寻找旧视图文件。
# A stale index cache is the usual cause of an "incomplete" uninstall: the backend keeps
# looking for the view file that was just removed.
log "clearing LuCI caches..."
rm -f /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-htmlcache 2>/dev/null || true
rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null || true

# 4. 重启服务 / Restart services
log "restart LuCI services"
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

log "uninstall completed"
echo "AdGuardHome LuCI Dashboard has been completely uninstalled / AdGuardHome LuCI Dashboard 已完全卸载"

# 5. 日志文件最后删除：上面每一步 log() 都还在往里追加，提前删会被立刻重建，
# 于是「清理日志」名存实亡。/ Delete the log file LAST: every log() above still appends
# to it, so deleting it earlier just has it recreated immediately — the cleanup was a no-op.
rm -f /etc/adguardhome-dashboard.log
