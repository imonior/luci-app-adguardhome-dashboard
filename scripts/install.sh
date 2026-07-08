#!/bin/sh
#=============================================================================
# 🧩 AdGuardHome LuCI Dashboard - 统一全自动安装/更新器 (2026 工业级生产版)
#=============================================================================
set -e

BASE="https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main"

MENU_DIR="/usr/share/luci/menu.d"
ACL_DIR="/usr/share/rpcd/acl.d"
VIEW_DIR="/www/luci-static/resources/view/adguardhome"

TMP="/tmp/agh_dashboard_install"
LOG="/etc/adguardhome-dashboard.log"

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1" | tee -a "$LOG"
}

download() {
    local url="$1"
    local out="$2"
    local i=0
    while [ $i -lt 3 ]; do
        if curl -fsSL --connect-timeout 6 "$url" -o "$out"; then
            local size
            size=$(wc -c < "$out" 2>/dev/null || echo 0)
            [ "$size" -gt 30 ] && return 0
        fi
        i=$((i+1))
        log "⚠️ 下载失败或文件异常，1秒后进行第 $i 次重试: $url"
        sleep 1
    done
    log "❌ 致命错误：尝试 3 次后仍无法下载 $url"
    exit 1
}

detect_conflict() {
    local conflicts=()
    
    if [ -f "$MENU_DIR/luci-app-adguardhome.json" ]; then
        conflicts+=("$MENU_DIR/luci-app-adguardhome.json")
    fi
    if [ -f "$ACL_DIR/luci-app-adguardhome.json" ]; then
        conflicts+=("$ACL_DIR/luci-app-adguardhome.json")
    fi
    if [ -f "/usr/share/luci/controller/adguardhome.lua" ]; then
        conflicts+=("/usr/share/luci/controller/adguardhome.lua")
    fi
    if [ -f "$VIEW_DIR/dashboard.js" ]; then
        conflicts+=("$VIEW_DIR/dashboard.js")
    fi

    if [ ${#conflicts[@]} -gt 0 ]; then
        echo ""
        echo "⚠️ 检测到已存在旧版 AdGuard Home 仪表盘文件："
        for f in "${conflicts[@]}"; do
            echo "   - $f"
        done
        echo ""
        echo "这些文件可能与新版本冲突，是否删除并继续安装？"
        echo ""
        read -p "请输入 [Y] 删除并安装 / [N] 退出安装: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "用户选择退出安装"
            exit 0
        fi
        log "用户选择删除旧文件并继续安装"
        for f in "${conflicts[@]}"; do
            rm -f "$f" 2>/dev/null || true
            log "已删除: $f"
        done
    else
        log "未检测到冲突文件，继续安装"
    fi
}

install_agh() {
    if [ -x /opt/AdGuardHome/AdGuardHome ] || [ -x /usr/bin/AdGuardHome ] || [ -x /usr/sbin/AdGuardHome ]; then
        log "AdGuardHome 核心二进制文件已存在 → 跳过核心安装"
        return
    fi
    
    log "🚀 未检测到 AdGuardHome 核心，正在调用官方脚本进行无人值守安装..."
    curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh || {
        log "❌ 核心服务安装失败，请检查网络连接。"
        exit 1
    }
}

fetch() {
    rm -rf "$TMP"
    mkdir -p "$TMP"
    log "📦 开始从 GitHub 仓库拉取最新的轻量级仪表盘资产..."
    
    download "$BASE/files/luci/menu.json" "$TMP/menu.json"
    download "$BASE/files/luci/acl.json" "$TMP/acl.json"
    download "$BASE/files/luci/controller/adguardhome.lua" "$TMP/adguardhome.lua"
    download "$BASE/files/luci/i18n/adguardhome.po" "$TMP/adguardhome.po"
    download "$BASE/files/luci/i18n/adguardhome.zh-cn.po" "$TMP/adguardhome.zh-cn.po"
    download "$BASE/files/luci/i18n/adguardhome.lmo" "$TMP/adguardhome.lmo"
    download "$BASE/files/luci/i18n/adguardhome.zh-cn.lmo" "$TMP/adguardhome.zh-cn.lmo"
    download "$BASE/files/view/dashboard.js" "$TMP/dashboard.js"
}

apply() {
    log "清理并确立目标系统目录拓扑结构..."
    mkdir -p "$MENU_DIR" "$ACL_DIR" "$VIEW_DIR"

    rm -f "$ACL_DIR/luci-app-adguardhome-dashboard.json" 2>/dev/null || true

    log "分发各组件至系统对应的路由、权限和视图沙箱..."
    mkdir -p /usr/share/luci/controller /usr/share/luci/i18n /usr/lib/lua/luci/i18n
    cp "$TMP/menu.json" "$MENU_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/acl.json" "$ACL_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/adguardhome.lua" /usr/share/luci/controller/adguardhome.lua
    cp "$TMP/adguardhome.po" /usr/share/luci/i18n/adguardhome.po
    cp "$TMP/adguardhome.zh-cn.po" /usr/share/luci/i18n/adguardhome.zh-cn.po
    cp "$TMP/adguardhome.lmo" /usr/lib/lua/luci/i18n/adguardhome.lmo
    cp "$TMP/adguardhome.zh-cn.lmo" /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo
    cp "$TMP/dashboard.js" "$VIEW_DIR/dashboard.js"

    log "i18n 翻译文件部署成功"

    log "写入本地版本锚定标记..."
    echo "v2.0-Full" > /etc/adguardhome-dashboard.version

    log "规范化文件系统权限 (遵循 Linux 只读静态分发规范)..."
    chmod 644 "$MENU_DIR/luci-app-adguardhome-dashboard.json" \
              "$ACL_DIR/luci-app-adguardhome-dashboard.json" \
              /usr/share/luci/controller/adguardhome.lua \
              /usr/share/luci/i18n/adguardhome.po \
              /usr/share/luci/i18n/adguardhome.zh-cn.po \
              /usr/lib/lua/luci/i18n/adguardhome.lmo 2>/dev/null \
              /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo 2>/dev/null \
              "$VIEW_DIR/dashboard.js" 2>/dev/null || true
}

restart_luci() {
    log "⚡ 正在强制粉碎 LuCI 菜单缓存与模块路由索引..."
    rm -rf /tmp/luci-indexcache \
           /tmp/luci-modulecache \
           /tmp/luci-htmlcache \
           /tmp/luci-cbi-* 2>/dev/null || true
    
    log "🔄 正在重启系统权限总线精灵进程 (rpcd)..."
    /etc/init.d/rpcd restart 2>/dev/null || true
    
    log "🔄 正在重启 Web 核心服务 (uhttpd)..."
    /etc/init.d/uhttpd restart 2>/dev/null || true
}

verify() {
    if [ -f "$VIEW_DIR/dashboard.js" ] && [ -f "$ACL_DIR/luci-app-adguardhome-dashboard.json" ] && \
       [ -f /usr/share/luci/controller/adguardhome.lua ]; then
        return 0
    else
        log "❌ 部署验证失败：核心组件未能成功写入目标路径"
        exit 1
    fi
}

main() {
    log "=== AdGuardHome 极简仪表盘部署开始 ==="
    install_agh
    detect_conflict
    fetch
    apply
    restart_luci
    verify
    
    rm -rf "$TMP"
    
    log "=== 部署流程完美结束 ==="
    echo "========================================================="
    echo " ✅ AdGuardHome LuCI Dashboard 安装/更新成功！"
    echo " ℹ️  请刷新你的浏览器缓存，进入 LuCI -> [服务] -> [AdGuard Home]"
    echo "========================================================="
}

main
