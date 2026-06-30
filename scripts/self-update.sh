#!/bin/sh
set -e

GITHUB_USER="xxx"
GITHUB_REPO="xxx"
BRANCH="${GITHUB_BRANCH:-main}"

REMOTE_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$BRANCH"

VERSION_FILE="/etc/adguardhome-dashboard.version"

TMP="/tmp/agh_self_update"

log() {
    echo "[self-update] $1"
}

download() {
    command -v curl >/dev/null && curl -fsSL "$1" -o "$2" || wget -qO "$2" "$1"
}

get_remote_version() {
    download "$REMOTE_BASE/files/version" "$TMP/version"
    cat "$TMP/version"
}

get_local_version() {
    [ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo "0.0.0"
}

compare_versions() {
    [ "$1" != "$2" ]
}

install_latest() {
    log "downloading latest installer..."
    download "$REMOTE_BASE/scripts/install.sh" "$TMP/install.sh"
    sh "$TMP/install.sh"
}

main() {
    mkdir -p "$TMP"

    LOCAL=$(get_local_version)
    REMOTE=$(get_remote_version)

    log "local=$LOCAL remote=$REMOTE"

    if compare_versions "$LOCAL" "$REMOTE"; then
        log "update available"
        install_latest
    else
        log "already latest"
    fi
}

main
