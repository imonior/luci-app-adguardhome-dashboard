#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# Build an offline-installable release tarball.
# 生成可离线安装的发布压缩包（作为 GitHub Release 资产发布）。
#
# The tarball keeps the repo layout:
#   <pkg>/scripts/install.sh  →  SCRIPT_DIR=<pkg>/scripts
#   <pkg>/files/...           →  PROJECT_ROOT=<pkg>, LOCAL_FILES=<pkg>/files
#   <pkg>/manifest.json
#   <pkg>/checksums.sha256
#   <pkg>/OFFLINE_PACKAGE     →  marker that makes install.sh skip ALL networking
#
# so the existing "install using local files" branch inside install.sh is reused
# as-is — no separate offline installer to maintain.
# ─────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_PATH="$0"
ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." 2>/dev/null && pwd)"
if [ -z "$ROOT" ]; then echo "error: cannot resolve project root" >&2; exit 1; fi
cd "$ROOT"

# ── version (single source of truth: manifest.json) ──
VER=$(grep '"version"' manifest.json 2>/dev/null \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1) || VER=""
if [ -z "$VER" ]; then
    echo "error: cannot read \"version\" from manifest.json" >&2
    exit 1
fi

PKG_NAME="luci-app-adguardhome-dashboard-v${VER}"
DIST_DIR="$ROOT/dist"
STAGE_PARENT="$DIST_DIR/.staging"
STAGE="$STAGE_PARENT/$PKG_NAME"
TARBALL="$DIST_DIR/${PKG_NAME}.tar.gz"

echo "==> version: $VER"
echo "==> staging: $STAGE"

rm -rf "$STAGE_PARENT"
mkdir -p "$STAGE/scripts" "$STAGE/files/luci/controller" \
         "$STAGE/files/luci/menu.d" "$STAGE/files/luci/i18n" "$STAGE/files/view"

# ── deployable files (same set the online installer downloads) ──
cp "files/luci/controller/adguardhome.lua"                  "$STAGE/files/luci/controller/"
cp "files/luci/menu.d/luci-app-adguardhome-dashboard.json"  "$STAGE/files/luci/menu.d/"
cp "files/luci/acl.json"                                    "$STAGE/files/luci/"
cp "files/view/dashboard.js"                                "$STAGE/files/view/"
cp "files/luci/i18n/adguardhome.lmo"                        "$STAGE/files/luci/i18n/"
cp "files/luci/i18n/adguardhome.zh-cn.lmo"                  "$STAGE/files/luci/i18n/"
cp "files/luci/i18n/adguardhome.po"                         "$STAGE/files/luci/i18n/"
cp "files/luci/i18n/adguardhome.zh-cn.po"                   "$STAGE/files/luci/i18n/"
cp "manifest.json"                                          "$STAGE/manifest.json"
cp "checksums.sha256"                                       "$STAGE/checksums.sha256"

# ── this tarball is an OFFLINE INSTALLER, not a source archive ──
# ⚠ 本包只承载「离线安装」所需内容，**不要**把 README / LICENSE / DEVELOPMENT.md
#   等文档塞进来：完整项目源码由 GitHub Release 页面自动附带的 Source code
#   (tarball / zipball) 提供，安装包必须保持精简。
# ⚠ Keep this tarball a lean offline INSTALLER — never bundle README/LICENSE/docs.
#   The complete project source is the auto-generated "Source code" archive that
#   GitHub attaches to every release.

# ── installer ──
cp "scripts/install.sh"   "$STAGE/scripts/install.sh"
cp "scripts/uninstall.sh" "$STAGE/scripts/uninstall.sh"
chmod 755 "$STAGE/scripts/install.sh" "$STAGE/scripts/uninstall.sh"

# ── junk that must never ship ──
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true

# ── offline marker (read by install.sh) ──
cat > "$STAGE/OFFLINE_PACKAGE" <<EOF
This directory is a self-contained offline release package of
luci-app-adguardhome-dashboard v${VER}.

Because this marker file exists, scripts/install.sh installs purely from ./files
and performs NO network access at all (no geo probe, no connection test, no
online version lookup, no re-download).

Install:
    sh scripts/install.sh

The package bundles the LuCI panel ONLY — it never contains the AdGuard Home core
(the core is released on its own schedule, so it cannot be pinned into this package).

To install the core offline, copy the official tarball for THIS machine's
architecture into this folder (the one holding this marker):

    AdGuardHome_linux_<arch>.tar.gz

scripts/install.sh then unpacks it into /opt and registers the service — still with
zero network access. It also accepts the tarball one level up (next to this folder).
Without a matching tarball only the panel is installed, and the installer prints
which architecture to fetch.

Built: $(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)
EOF

# ── human-readable install note (EN + ZH) ──
cat > "$STAGE/INSTALL.md" <<EOF
# luci-app-adguardhome-dashboard v${VER} — offline package

## Install

\`\`\`sh
tar xzf ${PKG_NAME}.tar.gz
cd ${PKG_NAME}
sh scripts/install.sh
\`\`\`

No network access is required and none is used: the installer deploys straight
from \`./files\` and verifies every file against the bundled \`checksums.sha256\`.

## AdGuard Home core (optional)

The package contains the **LuCI panel only**. The AdGuard Home core is never
bundled — it is released on its own schedule, so it cannot be pinned here.

To install the core offline, download the official tarball on a machine with
network access and copy it into this folder:

    AdGuardHome_linux_<arch>.tar.gz

It is also accepted one level up (next to this folder). The installer then
unpacks it into /opt/AdGuardHome and registers the service — no network needed.

Direct download (both URLs serve the same file):
    curl -fLO https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_<arch>.tar.gz
    curl -fLO https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_<arch>.tar.gz

Without a matching tarball the installer installs the panel only, and prints
which architecture to fetch.

Download page:
    https://github.com/AdguardTeam/AdGuardHome/releases/latest

## Uninstall

\`\`\`sh
sh scripts/uninstall.sh
\`\`\`

---

# luci-app-adguardhome-dashboard v${VER} — 离线安装包

## 安装

\`\`\`sh
tar xzf ${PKG_NAME}.tar.gz
cd ${PKG_NAME}
sh scripts/install.sh
\`\`\`

**全程不需要联网、也不会联网**：安装脚本直接从 \`./files\` 部署，并用包内自带的
\`checksums.sha256\` 对每个文件做 sha256 指纹校验。

## AdGuard Home 核心（可选）

本包**只包含 LuCI 面板**，不随包提供 AdGuard Home 核心
（核心独立发布，版本无法固定在本包内）。

如需离线安装核心，请在有网的机器上下载与本机架构匹配的官方压缩包，放入本目录：

    AdGuardHome_linux_<arch>.tar.gz

放在本项目目录的上一级也可以（安装脚本会两级扫描）。安装脚本会将它解压到
/opt/AdGuardHome 并注册服务，全程无需联网。

直链下载（两条链接是同一份文件）：
    curl -fLO https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_<arch>.tar.gz
    curl -fLO https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_<arch>.tar.gz

若目录内没有匹配的核心包，脚本只安装面板，并明确提示需要获取哪个架构的文件。

下载地址：
    https://github.com/AdguardTeam/AdGuardHome/releases/latest

## 卸载

\`\`\`sh
sh scripts/uninstall.sh
\`\`\`
EOF

# ── self-check: the bundled manifest must match the bundled files ──
# 自校验：包内的 files 必须与包内的 checksums.sha256 完全一致
echo "==> verifying staged files against checksums.sha256"
( cd "$STAGE" && sha256sum -c checksums.sha256 ) || {
    echo "error: staged content does not match checksums.sha256 — regenerate it before packaging" >&2
    exit 1
}

# ── pack ──
rm -f "$TARBALL"
( cd "$STAGE_PARENT" && tar czf "$TARBALL" "$PKG_NAME" )
rm -rf "$STAGE_PARENT"

echo "==> built: $TARBALL"
echo "==> size:  $(wc -c < "$TARBALL" | tr -d ' ') bytes"
if command -v sha256sum >/dev/null 2>&1; then
    echo "==> sha256: $(sha256sum "$TARBALL" | awk '{print $1}')"
fi
echo "==> done"
