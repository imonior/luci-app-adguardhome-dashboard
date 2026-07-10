#!/bin/sh
set -e

REPO="imonior/luci-app-adguardhome-dashboard"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

AGH_DIR="/opt/AdGuardHome"
AGH_BIN="/opt/AdGuardHome/AdGuardHome"
AGH_INSTALL_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

# GitHub 加速代理列表（国内用户可选）
PROXY_LIST="
https://ghfast.top/
https://gh-proxy.com/
https://kkgithub.com/
"

log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1"
}

# 简易计时器（兼容 BusyBox date 不支持 %N）
_now_ms() {
    local t=$(date +%s%N 2>/dev/null)
    case "$t" in
        *N) echo $(( $(date +%s) * 1000 )) ;;
        *)  echo $(( t / 1000000 )) ;;
    esac
}
_elapsed_ms() { echo $(( $(_now_ms) - $1 )); }

echo ""
echo "========================================================="
echo " AdGuardHome LuCI Dashboard 安装程序"
echo "========================================================="
echo ""

# ── GitHub 连通性检测 & 代理选择 ────────────────────
PROXY_PREFIX=""

# 支持环境变量强制指定代理: GITHUB_PROXY=https://ghfast.top/ sh install.sh
if [ -n "$GITHUB_PROXY" ]; then
    PROXY_PREFIX="$GITHUB_PROXY"
    log "使用环境变量指定代理: $PROXY_PREFIX"
else
    # 测试 GitHub 直连（5 秒超时）
    log "检测 GitHub 连通性..."
    _t0=$(_now_ms)
    if curl -fsSL -m 5 -o /dev/null 'https://raw.githubusercontent.com' 2>/dev/null; then
        log "GitHub 直连正常 ($(_elapsed_ms $_t0)ms)"
    else
        log "GitHub 直连失败，正在测试代理节点..."

        # 逐个测试代理连通性
        _proxy_results=""
        for proxy in $PROXY_LIST; do
            _test_url="${proxy}https://raw.githubusercontent.com"
            _t1=$(_now_ms)
            if curl -fsSL -m 5 -o /dev/null "$_test_url" 2>/dev/null; then
                _proxy_results="$_proxy_results ok:$(_elapsed_ms $_t1)"
            else
                _proxy_results="$_proxy_results fail:0"
            fi
        done

        echo ""
        echo "  #   代理节点          状态"
        echo "  ─────────────────────────────"
        echo "  1)  直连              ✗ 不可用"

        _idx=2
        _r_iter="$_proxy_results"
        for proxy in $PROXY_LIST; do
            _domain=$(echo "$proxy" | sed 's|https\{0,1\}://||;s|/$||')
            _result=$(echo "$_r_iter" | awk '{print $1}')
            _r_iter=$(echo "$_r_iter" | awk '{$1=""; print}' | sed 's/^ //')
            _status=$(echo "$_result" | cut -d: -f1)
            _ms=$(echo "$_result" | cut -d: -f2)
            if [ "$_status" = "ok" ]; then
                printf "  %d)  %-18s ✓ %sms\n" "$_idx" "$_domain" "$_ms"
            else
                printf "  %d)  %-18s ✗ 超时\n" "$_idx" "$_domain"
            fi
            _idx=$((_idx + 1))
        done

        echo ""
        printf "请选择 [1-%d，默认 2]: " $((_idx - 1))
        read -r PROXY_CHOICE
        PROXY_CHOICE=${PROXY_CHOICE:-2}

        if [ "$PROXY_CHOICE" != "1" ]; then
            _i=1
            for proxy in $PROXY_LIST; do
                if [ "$_i" = "$((PROXY_CHOICE - 1))" ]; then
                    PROXY_PREFIX="$proxy"
                    break
                fi
                _i=$((_i + 1))
            done
            if [ -n "$PROXY_PREFIX" ]; then
                log "使用代理: $PROXY_PREFIX"
            else
                log "无效选择，使用直连"
            fi
        fi
    fi
fi

# 应用代理到所有 GitHub URL
if [ -n "$PROXY_PREFIX" ]; then
    RAW_BASE="${PROXY_PREFIX}https://raw.githubusercontent.com/${REPO}/${BRANCH}"
    AGH_INSTALL_URL="${PROXY_PREFIX}${AGH_INSTALL_URL}"
    GH_API_BASE="${PROXY_PREFIX}https://api.github.com"
    # 保存代理配置供 Dashboard 后续使用（check_update/upgrade）
    echo "proxy=${PROXY_PREFIX}" > /etc/adguardhome-dashboard.proxy 2>/dev/null || true
else
    GH_API_BASE="https://api.github.com"
    # 清除旧代理配置
    rm -f /etc/adguardhome-dashboard.proxy 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════
# 第一部分：安装 AdGuard Home 核心
# ═══════════════════════════════════════════════════════════

log "── 第一部分：AdGuard Home 核心 ──"

if [ -f "$AGH_BIN" ]; then
    log "检测到已安装 AdGuard Home ($AGH_BIN)"

    # 获取当前本地版本（awk 取最后一个字段，兼容 BusyBox）
    CURRENT_VER=$("$AGH_BIN" --version 2>&1 | awk '{print $NF}')
    case "$CURRENT_VER" in v*) ;; *) CURRENT_VER="v$CURRENT_VER" ;; esac

    # 获取 GitHub 最新版本（直连 + 代理双路径）
    LATEST_VER=$(curl -fsSL -m 5 "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null \
        | awk -F'"' '/tag_name/{print $4; exit}')
    # 直连失败则尝试已配置的 GH_API_BASE（可能是代理）
    if [ -z "$LATEST_VER" ] && [ "$GH_API_BASE" != "https://api.github.com" ]; then
        LATEST_VER=$(curl -fsSL -m 8 "${GH_API_BASE}/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null \
            | awk -F'"' '/tag_name/{print $4; exit}')
    fi
    # 仍失败则逐个尝试内置代理
    if [ -z "$LATEST_VER" ]; then
        for _p in $PROXY_LIST; do
            LATEST_VER=$(curl -fsSL -m 8 "${_p}https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null \
                | awk -F'"' '/tag_name/{print $4; exit}')
            [ -n "$LATEST_VER" ] && break
        done
    fi

    if [ -n "$CURRENT_VER" ] && [ -n "$LATEST_VER" ]; then
        log "当前版本: $CURRENT_VER    最新版本: $LATEST_VER"
        if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
            log "已是最新版本"
        fi
    elif [ -n "$CURRENT_VER" ]; then
        log "当前版本: $CURRENT_VER (无法获取在线版本)"
    elif [ -n "$LATEST_VER" ]; then
        log "当前版本: 未知    最新版本: $LATEST_VER"
    fi

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
    _cb=$(date +%s 2>/dev/null || echo 0)
    dl() {
        local url="$1" dest="$2"
        # 添加时间戳参数破除 CDN/代理缓存
        if curl -fsSL -m 30 --connect-timeout 10 --retry 2 -o "$dest" "${url}?_cb=${_cb}"; then
            log "  ✓ $(basename "$dest")"
        else
            log "  ✗ 下载失败: $(basename "$dest")"
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
# 清除所有 LuCI 相关缓存（包括 ucode bridge 缓存）
rm -rf /tmp/luci-* 2>/dev/null || true
rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null || true
# 清除 Lua 字节码缓存
find /tmp -name '*.luac' -delete 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

# ── 部署验证 ────────────────────────────────────────
log "验证部署文件..."
if grep -q 'loadc' /usr/lib/lua/luci/controller/adguardhome.lua 2>/dev/null; then
    log "⚠ 警告: controller.lua 仍包含旧代码 (i18n.loadc)"
    log "  可能是 GitHub CDN 缓存未刷新，请尝试以下方法:"
    log "  1) 等待几分钟后重新运行安装"
    log "  2) 使用代理: GITHUB_PROXY=https://ghfast.top/ sh install.sh"
    log "  3) 手动验证: curl -fsSL '${RAW_BASE}/files/luci/controller/adguardhome.lua' | grep loadc"
else
    log "  ✓ controller.lua 验证通过"
fi

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
