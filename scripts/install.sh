#!/bin/sh
set -e

BASE="https://raw.githubusercontent.com/imonior/luci-app-adguardhome-dashboard/main"

MENU_DIR="/usr/share/luci/menu.d"
ACL_DIR="/usr/share/rpcd/acl.d"
VIEW_DIR="/www/luci-static/resources/view/adguardhome"

TMP="/tmp/agh_install"

log() {
    echo "[install] $1"
}

###############################################################################
# DOWNLOAD (稳定核心保留)
###############################################################################
download() {
    url="$1"
    out="$2"

    i=0
    while [ $i -lt 3 ]; do
        curl -fsSL --connect-timeout 5 "$url" -o "$out" && break
        i=$((i+1))
        sleep 1
    done

    [ -s "$out" ] || {
        log "FAILED: $url"
        exit 1
    }

    SIZE=$(wc -c < "$out" 2>/dev/null || echo 0)
    [ "$SIZE" -gt 50 ] || {
        log "INVALID FILE: $url"
        exit 1
    }
}

###############################################################################
# DEPENDENCY: AdGuardHome（必须保留）
###############################################################################
install_agh() {
    if [ -x /opt/AdGuardHome/AdGuardHome ] || [ -x /usr/bin/AdGuardHome ]; then
        log "AdGuardHome exists → skip"
        return
    fi

    log "install AdGuardHome (official)"

    curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh || {
        log "AdGuardHome install failed"
        exit 1
    }
}

###############################################################################
# FETCH FILES（install + update 共用逻辑）
###############################################################################
fetch() {
    rm -rf "$TMP"
    mkdir -p "$TMP"

    log "fetch dashboard files"

    download "$BASE/files/luci/menu.json" "$TMP/menu.json"
    download "$BASE/files/luci/acl.json" "$TMP/acl.json"
    download "$BASE/files/view/dashboard.js" "$TMP/dashboard.js"
}

###############################################################################
# APPLY FILES（覆盖式 = update本质）
###############################################################################
apply() {
    mkdir -p "$MENU_DIR" "$ACL_DIR" "$VIEW_DIR"

    cp "$TMP/menu.json" "$MENU_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/acl.json" "$ACL_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/dashboard.js" "$VIEW_DIR/dashboard.js"
}

###############################################################################
# MAIN（install = update）
###############################################################################
main() {
    log "start (install/update unified)"

    install_agh
    fetch
    apply

    rm -rf "$TMP"

    log "done"
}

main