#!/bin/sh
set -e

###############################################################################
# AdGuardHome Dashboard Installer v3
###############################################################################

VERSION_FILE="/etc/adguardhome-dashboard.version"
LOG_FILE="/etc/adguardhome-dashboard.log"
LOCK_FILE="/var/run/agh_dashboard.lock"
TMP="/tmp/agh_install"
BACKUP="/tmp/agh_backup"

GITHUB_USER="imonior"
GITHUB_REPO="luci-app-adguardhome-dashboard"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

REMOTE_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH"

MENU_DIR="/usr/share/luci/menu.d"
ACL_DIR="/usr/share/rpcd/acl.d"
VIEW_DIR="/www/luci-static/resources/view/adguardhome"

###############################################################################
# LOG
###############################################################################
log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

###############################################################################
# LOCK
###############################################################################
acquire_lock() {
    [ -f "$LOCK_FILE" ] && {
        PID=$(cat "$LOCK_FILE" 2>/dev/null)
        kill -0 "$PID" 2>/dev/null && {
            log "install running ($PID)"
            exit 1
        }
    }
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

###############################################################################
# DOWNLOAD (safe)
###############################################################################
download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 10 "$1" -o "$2" || return 1
    else
        wget -qO "$2" "$1" || return 1
    fi

    [ -s "$2" ] || return 1
}

###############################################################################
# MODE
###############################################################################
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -d "$SCRIPT_DIR/files/luci" ]; then
    MODE="offline"
else
    MODE="online"
fi

###############################################################################
# BACKUP
###############################################################################
backup() {
    log "backup..."
    mkdir -p "$BACKUP"
    cp -r "$MENU_DIR" "$BACKUP/" 2>/dev/null || true
    cp -r "$ACL_DIR" "$BACKUP/" 2>/dev/null || true
    cp -r "$VIEW_DIR" "$BACKUP/" 2>/dev/null || true
}

###############################################################################
# ROLLBACK
###############################################################################
rollback() {
    log "rollback..."
    [ -d "$BACKUP" ] && cp -r "$BACKUP"/* / 2>/dev/null || true
}

###############################################################################
# FETCH
###############################################################################
fetch() {
    mkdir -p "$TMP"

    if [ "$MODE" = "offline" ]; then
        log "offline mode"
        cp -r "$SCRIPT_DIR/files/"* "$TMP/"
    else
        log "online mode"

        download "$REMOTE_BASE/files/luci/menu.json" "$TMP/menu.json" || return 1
        download "$REMOTE_BASE/files/luci/acl.json" "$TMP/acl.json" || return 1
        download "$REMOTE_BASE/files/view/dashboard.js" "$TMP/dashboard.js" || return 1

        download "$REMOTE_BASE/version" "$TMP/version" || true
        download "$REMOTE_BASE/files/checksums.sha256" "$TMP/checksums.sha256" || true
        download "$REMOTE_BASE/files/delta.map" "$TMP/delta.map" || true
    fi
}

###############################################################################
# CHECKSUM
###############################################################################
verify() {
    [ -f "$TMP/checksums.sha256" ] || {
        log "no checksum, skip"
        return 0
    }

    cd "$TMP" || return 1

    while read sum file; do
        [ -f "$file" ] || {
            log "missing file $file"
            return 1
        }

        echo "$sum  $file" | sha256sum -c - || return 1
    done < checksums.sha256
}

###############################################################################
# INSTALL
###############################################################################
install_files() {
    mkdir -p "$MENU_DIR" "$ACL_DIR" "$VIEW_DIR"

    cp "$TMP/menu.json" "$MENU_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/acl.json" "$ACL_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/dashboard.js" "$VIEW_DIR/dashboard.js"
}

###############################################################################
# VERSION
###############################################################################
write_version() {
    [ -f "$TMP/version" ] && cp "$TMP/version" "$VERSION_FILE"
}

###############################################################################
# LUCI REFRESH
###############################################################################
refresh() {
    rm -rf /tmp/luci-*
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true
}

###############################################################################
# MAIN
###############################################################################
main() {
    acquire_lock
    backup

    fetch || {
        log "fetch failed"
        rollback
        release_lock
        exit 1
    }

    verify || {
        log "checksum failed"
        rollback
        release_lock
        exit 1
    }

    install_files
    write_version
    refresh

    release_lock
    log "install success"
}

main
