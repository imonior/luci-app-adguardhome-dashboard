#!/bin/sh
set -e

log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1"
}

# ── 定位项目根目录 ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FILES_DIR="$PROJECT_ROOT/files"

if [ ! -f "$FILES_DIR/luci/controller/adguardhome.lua" ]; then
    echo "❌ 无法定位项目文件，请从项目目录内运行此脚本："
    echo "   cd /path/to/luci-app-adguardhome-dashboard && sh scripts/install.sh"
    exit 1
fi

log "=== AdGuardHome LuCI Dashboard 安装开始 ==="
log "项目路径: $PROJECT_ROOT"

# ── 清理旧版本冲突文件 ──────────────────────────
log "清理旧版本文件..."
rm -f /usr/lib/lua/luci/controller/adguardhome.lua
rm -f /usr/share/luci/controller/adguardhome.lua
rm -rf /usr/lib/lua/luci/view/adguardhome
rm -rf /www/luci-static/resources/view/adguardhome
rm -f /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json
rm -f /usr/share/luci/menu.d/luci-app-adguardhome.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome.json
rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
rm -f /usr/lib/lua/luci/i18n/adguardhome.lmo
rm -f /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo

# ── 创建目标目录 ────────────────────────────────
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /usr/lib/lua/luci/i18n
mkdir -p /www/luci-static/resources/view/adguardhome

# ── 部署 Lua Controller（仅 API 子路由） ────────
log "部署 Lua Controller..."
cp "$FILES_DIR/luci/controller/adguardhome.lua" /usr/lib/lua/luci/controller/adguardhome.lua

# ── 部署 LuCI 2.0 菜单注册 ─────────────────────
log "部署菜单配置..."
cp "$FILES_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json" /usr/share/luci/menu.d/

# ── 部署 rpcd ACL ──────────────────────────────
log "部署 ACL 权限..."
cp "$FILES_DIR/luci/acl.json" /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json

# ── 部署 i18n 翻译文件 ─────────────────────────
log "部署翻译文件..."
cp "$FILES_DIR/luci/i18n/adguardhome.lmo" /usr/lib/lua/luci/i18n/
cp "$FILES_DIR/luci/i18n/adguardhome.zh-cn.lmo" /usr/lib/lua/luci/i18n/

# ── 部署 JS View ───────────────────────────────
log "部署前端视图..."
cp "$FILES_DIR/view/dashboard.js" /www/luci-static/resources/view/adguardhome/dashboard.js

# ── 设置权限 ────────────────────────────────────
chmod 644 /usr/lib/lua/luci/controller/adguardhome.lua \
          /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json \
          /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json \
          /usr/lib/lua/luci/i18n/adguardhome.lmo \
          /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo \
          /www/luci-static/resources/view/adguardhome/dashboard.js

# ── 清除缓存 & 重启服务 ────────────────────────
log "清除 LuCI 缓存..."
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-htmlcache /tmp/luci-cbi-*

log "重启服务..."
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

log "=== 安装完成 ==="
echo ""
echo "========================================================="
echo " AdGuardHome LuCI Dashboard 安装成功"
echo " 请刷新浏览器 → LuCI → 服务 → AdGuard Home"
echo "========================================================="
echo ""
echo "部署文件清单:"
echo "  Controller:  /usr/lib/lua/luci/controller/adguardhome.lua"
echo "  Menu:        /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json"
echo "  ACL:         /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json"
echo "  JS View:     /www/luci-static/resources/view/adguardhome/dashboard.js"
echo "  i18n (en):   /usr/lib/lua/luci/i18n/adguardhome.lmo"
echo "  i18n (zh):   /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo"
