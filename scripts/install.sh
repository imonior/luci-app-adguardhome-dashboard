#!/bin/sh
set -e

VERSION_FILE="/etc/adguardhome-dashboard.version"
LOG_FILE="/etc/adguardhome-dashboard.log"
LOCK_FILE="/var/run/agh.lock"
TMP="/tmp/agh_install"
BACKUP="/tmp/agh_backup"

GITHUB_USER="imonior"
GITHUB_REPO="luci-app-adguardhome-dashboard"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH"

MENU_DIR="/usr/share/luci/menu.d"
ACL_DIR="/usr/share/rpcd/acl.d"
VIEW_DIR="/www/luci-static/resources/view/adguardhome"

log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

lock() {
    [ -f "$LOCK_FILE" ] && exit 1
    echo $$ > "$LOCK_FILE"
}

unlock() {
    rm -f "$LOCK_FILE"
}

download() {
    url="$1"
    out="$2"

    curl -fSL --retry 3 --connect-timeout 10 "$url" -o "$out" || return 1
    [ -s "$out" ] || return 1
}

backup() {
    mkdir -p "$BACKUP"
    cp -r "$MENU_DIR" "$BACKUP/" 2>/dev/null || true
    cp -r "$ACL_DIR" "$BACKUP/" 2>/dev/null || true
    cp -r "$VIEW_DIR" "$BACKUP/" 2>/dev/null || true
}

rollback() {
    log "rollback triggered"
    cp -r "$BACKUP"/* / 2>/dev/null || true
}

fetch() {
    mkdir -p "$TMP"

    # offline mode
    if [ -d "./files" ]; then
        cp -r ./files/* "$TMP/"
        return 0
    fi

    # online mode
    download "$BASE/files/luci/menu.json" "$TMP/menu.json" || return 1
    download "$BASE/files/luci/acl.json" "$TMP/acl.json" || return 1
    download "$BASE/files/view/dashboard.js" "$TMP/dashboard.js" || return 1

    download "$BASE/files/checksums.sha256" "$TMP/checksums.sha256" || true
    download "$BASE/files/version" "$TMP/version" || true
}

verify() {
    [ -f "$TMP/checksums.sha256" ] || return 0

    cd "$TMP" || return 1

    while read sum file; do
        [ -f "$file" ] || {
            log "missing file: $file"
            return 1
        }

        echo "$sum  $file" | sha256sum -c - || return 1
    done < checksums.sha256
}

install() {
    mkdir -p "$MENU_DIR" "$ACL_DIR" "$VIEW_DIR"

    cp "$TMP/luci/menu.json" "$MENU_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/luci/acl.json" "$ACL_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/view/dashboard.js" "$VIEW_DIR/dashboard.js"
}

write_version() {
    [ -f "$TMP/version" ] && cp "$TMP/version" "$VERSION_FILE"
}

main() {
    lock
    backup

    fetch || { rollback; unlock; exit 1; }
    verify || { rollback; unlock; exit 1; }

    install
    write_version

    unlock
    log "install success"
}

main
