#!/bin/sh
set -e

REPO="imonior/luci-app-adguardhome-dashboard"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

AGH_DIR="/opt/AdGuardHome"
AGH_BIN="/opt/AdGuardHome/AdGuardHome"
AGH_INSTALL_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1"
}

echo ""
echo "========================================================="
echo " AdGuardHome LuCI Dashboard 安装程序"
echo "========================================================="
echo ""

# ═══════════════════════════════════════════════════════════
# 第一部分：安装 AdGuard Home 核心
# ═══════════════════════════════════════════════════════════

log "── 第一部分：AdGuard Home 核心 ──"

if [ -f "$AGH_BIN" ]; then
    log "检测到已安装 AdGuard Home ($AGH_BIN)"
    # 显示当前版本
    CURRENT_VER=$("$AGH_BIN" --version 2>&1 | grep -o 'v[0-9.]*' | head -1)
    [ -n "$CURRENT_VER" ] && log "当前版本: $CURRENT_VER"

    echo ""
    echo "  1) 从官方重新下载安装（覆盖当前版本）"
    echo "  2) 跳过，保留当前版本"
    echo ""
    printf "请选择 [1/2，默认 2]: "
    read -r CHOICE
    CHOICE=${CHOICE:-2}

    if [ "$CHOICE" = "1" ]; then
        # 检查是否在运行，运行中需要先停止
        if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
            log "检测到 AdGuard Home 正在运行，先停止服务..."
            if [ -f /etc/init.d/AdGuardHome ]; then
                /etc/init.d/AdGuardHome stop 2>/dev/null || true
            elif [ -f /etc/init.d/adguardhome ]; then
                /etc/init.d/adguardhome stop 2>/dev/null || true
            else
                "$AGH_BIN" -s stop 2>/dev/null || true
            fi
            sleep 2
            # 再次检查
            if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
                log "警告: 服务未能正常停止，尝试强制终止..."
                killall AdGuardHome 2>/dev/null || true
                sleep 1
            fi
            log "AdGuard Home 已停止"
        fi

        log "从官方脚本重新安装 AdGuard Home..."
        curl -fsSL "$AGH_INSTALL_URL" | sh
        log "AdGuard Home 安装完成"
    else
        log "跳过 AdGuard Home 核心安装，保留当前版本"
    fi
else
    log "未检测到 AdGuard Home，开始从官方脚本安装..."
    curl -fsSL "$AGH_INSTALL_URL" | sh
    log "AdGuard Home 安装完成"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# 第二部分：安装 LuCI Dashboard 管理面板
# ═══════════════════════════════════════════════════════════

log "── 第二部分：LuCI Dashboard 管理面板 ──"

# 检测是否有本地项目文件（开发模式优化）
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR" 2>/dev/null)"
LOCAL_FILES="$PROJECT_ROOT/files"

TMPDIR=$(mktemp -d)
DOWNLOAD_DIR="$TMPDIR/download"
mkdir -p "$DOWNLOAD_DIR/luci/controller" "$DOWNLOAD_DIR/luci/menu.d" "$DOWNLOAD_DIR/luci/i18n" "$DOWNLOAD_DIR/view"

# 从 GitHub 下载所有 Dashboard 文件
download_from_github() {
    log "从 GitHub 下载 Dashboard 文件..."
    dl() {
        local url="$1" dest="$2"
        if curl -fsSL -o "$dest" "$url"; then
            log "  ✓ $(basename "$dest")"
        else
            log "  ✗ 下载失败: $(basename "$dest") ($url)"
            rm -rf "$TMPDIR"
            exit 1
        fi
    }
    dl "${RAW_BASE}/files/luci/controller/adguardhome.lua"                "$DOWNLOAD_DIR/luci/controller/adguardhome.lua"
    dl "${RAW_BASE}/files/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json"
    dl "${RAW_BASE}/files/luci/acl.json"                                  "$DOWNLOAD_DIR/luci/acl.json"
    dl "${RAW_BASE}/files/view/dashboard.js"                              "$DOWNLOAD_DIR/view/dashboard.js"
    dl "${RAW_BASE}/files/luci/i18n/adguardhome.lmo"                      "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo"
    dl "${RAW_BASE}/files/luci/i18n/adguardhome.zh-cn.lmo"                "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo"
    log "所有文件下载完成"
}

if [ -f "$LOCAL_FILES/luci/controller/adguardhome.lua" ]; then
    log "检测到本地项目文件 ($PROJECT_ROOT)"
    echo ""
    echo "  1) 使用本地文件安装"
    echo "  2) 删除本地项目后从 GitHub 重新下载"
    echo ""
    printf "请选择 [1/2，默认 1]: "
    read -r SRC_CHOICE
    SRC_CHOICE=${SRC_CHOICE:-1}

    if [ "$SRC_CHOICE" = "2" ]; then
        log "删除本地项目目录: $PROJECT_ROOT"
        rm -rf "$PROJECT_ROOT"
        download_from_github
    else
        log "使用本地文件复制..."
        cp "$LOCAL_FILES/luci/controller/adguardhome.lua" "$DOWNLOAD_DIR/luci/controller/"
        cp "$LOCAL_FILES/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/"
        cp "$LOCAL_FILES/luci/acl.json" "$DOWNLOAD_DIR/luci/"
        cp "$LOCAL_FILES/view/dashboard.js" "$DOWNLOAD_DIR/view/"
        cp "$LOCAL_FILES/luci/i18n/adguardhome.lmo" "$DOWNLOAD_DIR/luci/i18n/"
        cp "$LOCAL_FILES/luci/i18n/adguardhome.zh-cn.lmo" "$DOWNLOAD_DIR/luci/i18n/"
    fi
else
    download_from_github
fi

# ── 清理旧版本文件 ──────────────────────────────────
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

# ── 创建目标目录 ────────────────────────────────────
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /usr/lib/lua/luci/i18n
mkdir -p /www/luci-static/resources/view/adguardhome

# ── 部署文件 ────────────────────────────────────────
log "部署文件到系统目录..."
cp "$DOWNLOAD_DIR/luci/controller/adguardhome.lua"                     /usr/lib/lua/luci/controller/adguardhome.lua
cp "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json"     /usr/share/luci/menu.d/
cp "$DOWNLOAD_DIR/luci/acl.json"                                       /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
cp "$DOWNLOAD_DIR/view/dashboard.js"                                   /www/luci-static/resources/view/adguardhome/dashboard.js
cp "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo"                           /usr/lib/lua/luci/i18n/
cp "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo"                     /usr/lib/lua/luci/i18n/

# ── 设置权限 ────────────────────────────────────────
chmod 644 /usr/lib/lua/luci/controller/adguardhome.lua \
          /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json \
          /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json \
          /usr/lib/lua/luci/i18n/adguardhome.lmo \
          /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo \
          /www/luci-static/resources/view/adguardhome/dashboard.js

# ── 清除缓存 & 重启服务 ────────────────────────────
log "清除 LuCI 缓存并重启服务..."
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-htmlcache /tmp/luci-cbi-*
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

# ── 清理临时目录 ────────────────────────────────────
rm -rf "$TMPDIR"

echo ""
echo "========================================================="
echo " 安装完成！"
echo ""
echo " AdGuard Home 核心:"
[ -f "$AGH_BIN" ] && echo "   ✓ $AGH_BIN" || echo "   ✗ 未安装"
echo ""
echo " LuCI Dashboard:"
echo "   Controller:  /usr/lib/lua/luci/controller/adguardhome.lua"
echo "   Menu:        /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json"
echo "   ACL:         /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json"
echo "   JS View:     /www/luci-static/resources/view/adguardhome/dashboard.js"
echo "   i18n (en):   /usr/lib/lua/luci/i18n/adguardhome.lmo"
echo "   i18n (zh):   /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo"
echo ""
echo " 请刷新浏览器 → LuCI → 服务 → AdGuard Home"
echo "========================================================="
