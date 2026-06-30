#!/bin/sh
set -e

###############################################################################
# AdGuardHome Dashboard Installer v2.3 FINAL (apk/opkg compatible)
###############################################################################

VERSION_FILE="/etc/adguardhome-dashboard.version"
LOG_FILE="/etc/adguardhome-dashboard.log"
LOCK_FILE="/var/run/agh_dashboard.lock"
BACKUP_DIR="/tmp/agh_dashboard_backup"
TMP="/tmp/agh_install"

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

###############################################################################
# PACKAGE MANAGER DETECTION (NEW CORE)
###############################################################################
detect_pm() {
    if command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v opkg >/dev/null 2>&1; then
        echo "opkg"
    else
        echo "unknown"
    fi
}

install_pkg() {
    PM=$(detect_pm)

    case "$PM" in
        apk)
            log "using apk package manager"
            apk add "$@" >/dev/null 2>&1 || true
            ;;
        opkg)
            log "using opkg package manager"
            opkg update >/dev/null 2>&1 || true
            opkg install "$@" >/dev/null 2>&1 || true
            ;;
        *)
            log "WARNING: no package manager found"
            ;;
    esac
}

###############################################################################
# LOCK
###############################################################################
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        PID=$(cat "$LOCK_FILE" 2>/dev/null)
        kill -0 "$PID" 2>/dev/null && {
            log "ERROR: install already running ($PID)"
            exit 1
        }
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

###############################################################################
# DOWNLOAD
###############################################################################
download() {
    command -v curl >/dev/null && \
        curl -fsSL "$1" -o "$2" || \
        wget -qO "$2" "$1"
}

###############################################################################
# MODE DETECTION
###############################################################################
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -d "$SCRIPT_DIR/files" ]; then
    MODE="offline"
else
    MODE="online"
fi

###############################################################################
# BACKUP
###############################################################################
backup() {
    log "backup system state"
    mkdir -p "$BACKUP_DIR"

    cp -r "$MENU_DIR" "$BACKUP_DIR/" 2>/dev/null || true
    cp -r "$ACL_DIR" "$BACKUP_DIR/" 2>/dev/null || true
    cp -r "$VIEW_DIR" "$BACKUP_DIR/" 2>/dev/null || true
    cp "$VERSION_FILE" "$BACKUP_DIR/" 2>/dev/null || true
}

rollback() {
    log "ROLLBACK triggered"
    [ -d "$BACKUP_DIR" ] && cp -r "$BACKUP_DIR"/* / 2>/dev/null || true
}

###############################################################################
# FETCH FILES
###############################################################################
fetch() {
    mkdir -p "$TMP"

    if [ "$MODE" = "offline" ]; then
        log "offline mode detected"
        cp -r "$SCRIPT_DIR/files/"* "$TMP/"
    else
        log "online mode detected"

        download "$REMOTE_BASE/files/luci/menu.json" "$TMP/menu.json"
        download "$REMOTE_BASE/files/luci/acl.json" "$TMP/acl.json"
        download "$REMOTE_BASE/files/view/dashboard.js" "$TMP/dashboard.js"

        download "$REMOTE_BASE/files/version" "$TMP/version" || true
        download "$REMOTE_BASE/files/checksums.sha256" "$TMP/checksums.sha256" || true
        download "$REMOTE_BASE/files/delta.map" "$TMP/delta.map" || true
        download "$REMOTE_BASE/files/index.json" "$TMP/index.json" || true
    fi
}

###############################################################################
# CHECKSUM VERIFY
###############################################################################
verify_checksum() {
    [ -f "$TMP/checksums.sha256" ] || return 0
    log "checksum verify"
    (cd "$TMP" && sha256sum -c "$TMP/checksums.sha256") || exit 1
}

###############################################################################
# DELTA APPLY
###############################################################################
apply_delta() {
    [ -f "$TMP/delta.map" ] || return 1

    log "delta apply"

    while IFS='=' read -r file action; do
        [ "$action" = "UPDATE" ] || continue

        case "$file" in
            menu.json)
                cp "$TMP/menu.json" "$MENU_DIR/luci-app-adguardhome-dashboard.json"
                ;;
            acl.json)
                cp "$TMP/acl.json" "$ACL_DIR/luci-app-adguardhome-dashboard.json"
                ;;
            dashboard.js)
                cp "$TMP/dashboard.js" "$VIEW_DIR/dashboard.js"
                ;;
        esac
    done < "$TMP/delta.map"

    return 0
}

###############################################################################
# FULL INSTALL
###############################################################################
full_install() {
    log "full install"

    mkdir -p "$MENU_DIR" "$ACL_DIR" "$VIEW_DIR"

    cp "$TMP/menu.json" "$MENU_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/acl.json" "$ACL_DIR/luci-app-adguardhome-dashboard.json"
    cp "$TMP/dashboard.js" "$VIEW_DIR/dashboard.js"
}

###############################################################################
# AGH CORE INSTALL (SAFE + COMPATIBLE)
###############################################################################
install_agh() {
    if [ -x /opt/AdGuardHome/AdGuardHome ]; then
        log "AdGuardHome already exists, skip"
        return
    fi

    log "installing AdGuardHome (official)"

    install_pkg curl ca-certificates

    sh -c "$(curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh)"
}

###############################################################################
# VERSION WRITE
###############################################################################
write_version() {
    [ -f "$TMP/version" ] && cp "$TMP/version" "$VERSION_FILE"
}

###############################################################################
# REFRESH LUCI
###############################################################################
refresh_luci() {
    log "refresh LuCI"

    rm -rf /tmp/luci-*
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true
}

###############################################################################
# ERROR HANDLER (FIXED: no trap loop)
###############################################################################
on_error() {
    log "ERROR occurred → rollback"
    rollback
    release_lock
    exit 1
}

trap on_error INT TERM

###############################################################################
# MAIN
###############################################################################
main() {
    acquire_lock
    backup

    install_agh
    fetch

    verify_checksum

    apply_delta || full_install

    write_version
    refresh_luci

    release_lock
    log "install completed successfully"
}

main