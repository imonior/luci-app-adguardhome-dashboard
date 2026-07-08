#!/bin/sh
set -e

LOG="/etc/adguardhome-dashboard.log"
log() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] [uninstall] $1" | tee -a "$LOG"
}

log "start uninstall"

# 1. 彻底移除所有 LuCI 资产
rm -f /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
rm -f /usr/share/luci/controller/adguardhome.lua
rm -f /www/luci-static/resources/view/adguardhome/dashboard.js
# 移除对应的视图目录（如果为空的话）
rm -rf /www/luci-static/resources/view/adguardhome 2>/dev/null || true

# 2. 清理配置标记与日志
rm -f /etc/adguardhome-dashboard.log
rm -f /etc/adguardhome-dashboard.version

# 3. 强力清除 LuCI 索引缓存 (关键步骤)
# 卸载不彻底的核心原因往往是索引缓存没删，导致后台还在试图寻找旧视图文件
log "clearing LuCI caches..."
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-htmlcache /tmp/luci-cbi-* 2>/dev/null || true

# 4. 重启服务
log "restart LuCI services"
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

log "uninstall completed"
echo "✅ AdGuardHome LuCI Dashboard 已完全卸载"