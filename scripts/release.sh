#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# Release orchestrator: run the full pre-push preflight check, then build the
# downloadable project tarball (via scripts/make_package.sh).
#
# 发布编排器：先跑「推送前完整检查」，再构建可下载的整项目压缩包
# （构建本身委托给 scripts/make_package.sh）。
#
# Usage / 用法:
#   sh scripts/release.sh              # 1) preflight check  2) build package
#   sh scripts/release.sh --check      # preflight check only (CI 在构建前调用)
#   sh scripts/release.sh --no-package # 仅检查（同上）
#   sh scripts/release.sh --strict     # 把原本只是告警的项（脏工作树/未打 tag）也视为失败
#
# Exit code: number of mandatory check failures (0 = all pass).
# 退出码 = 强制检查失败数（0 表示全部通过）。
# ─────────────────────────────────────────────────────────────────────────────

CHECK_ONLY=0
STRICT=0
for a in "$@"; do
    case "$a" in
        --check|--no-package) CHECK_ONLY=1 ;;
        --strict) STRICT=1 ;;
        -h|--help) sed -n '3,22p' "$0"; exit 0 ;;
        *) echo "unknown arg: $a" >&2; exit 2 ;;
    esac
done

SCRIPT_PATH="$0"
ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." 2>/dev/null && pwd)"
if [ -z "$ROOT" ]; then echo "error: cannot resolve project root" >&2; exit 2; fi
cd "$ROOT" || { echo "error: cannot cd to $ROOT" >&2; exit 2; }

FAIL=0
WARN_COUNT=0

ok()   { printf '[OK]    %s\n' "$1"; }
warn() { printf '[WARN]  %s\n' "$1"; WARN_COUNT=$((WARN_COUNT+1)); }
fail() { printf '[FAIL]  %s\n' "$1"; FAIL=$((FAIL+1)); }
hdr()  { printf '\n=== %s ===\n' "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── 1. version (single source of truth: manifest.json) ──
hdr "Version consistency / 版本一致性"
MANIFEST_VER=$(grep '"version"' manifest.json 2>/dev/null \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
if [ -z "$MANIFEST_VER" ]; then
    fail "manifest.json: cannot read \"version\""
else
    ok "manifest.json version = $MANIFEST_VER"
fi

JS_VER=$(grep 'DASHBOARD_VIEW_VERSION = ' files/view/dashboard.js 2>/dev/null \
    | head -n1 | sed -n 's/.*"\([^"]*\)".*/\1/p')
if [ -n "$MANIFEST_VER" ] && [ "$JS_VER" != "$MANIFEST_VER" ]; then
    fail "dashboard.js DASHBOARD_VIEW_VERSION ($JS_VER) != manifest.json ($MANIFEST_VER)"
else
    ok "dashboard.js DASHBOARD_VIEW_VERSION = ${JS_VER:-<none>}"
fi

# README 顶部版本标记 `**vX.Y.Z**`（heading）。中英文两份都要有。
for rf in README.md README.zh-CN.md; do
    if [ ! -f "$rf" ]; then
        fail "$rf: missing"
        continue
    fi
    if [ -n "$MANIFEST_VER" ] && ! grep -qF "**v${MANIFEST_VER}**" "$rf"; then
        fail "$rf: top version marker **v${MANIFEST_VER}** not found"
    else
        ok "$rf: version marker present"
    fi
done

# ── 2. Changelog bilingual entries / 变更记录双语条目 ──
hdr "Changelog entries / 变更记录条目"
for rf in README.md README.zh-CN.md; do
    [ -f "$rf" ] || continue
    if [ -n "$MANIFEST_VER" ] && ! grep -qE "^[[:space:]]*-[[:space:]]*\*\*v${MANIFEST_VER}\*\*" "$rf"; then
        fail "$rf: no changelog bullet '- **v${MANIFEST_VER}**' found"
    else
        ok "$rf: changelog bullet present"
    fi
done

# ── 3. Code syntax / 代码语法 ──
hdr "Code syntax / 代码语法"
if [ -f scripts/install.sh ]; then
    if sh -n scripts/install.sh 2>/dev/null; then ok "install.sh: POSIX syntax OK"; else fail "install.sh: POSIX syntax error (sh -n)"; fi
else
    warn "scripts/install.sh missing — skipped"
fi
if [ -f scripts/make_package.sh ]; then
    if sh -n scripts/make_package.sh 2>/dev/null; then ok "make_package.sh: POSIX syntax OK"; else fail "make_package.sh: POSIX syntax error (sh -n)"; fi
fi
if [ -f scripts/uninstall.sh ]; then
    if sh -n scripts/uninstall.sh 2>/dev/null; then ok "uninstall.sh: POSIX syntax OK"; else fail "uninstall.sh: POSIX syntax error (sh -n)"; fi
fi

if [ -f files/view/dashboard.js ]; then
    if have node; then
        if node --check files/view/dashboard.js 2>/dev/null; then ok "dashboard.js: JS syntax OK (node --check)"; else fail "dashboard.js: JS syntax error (node --check)"; fi
    else
        # 缺工具 = 静默漏检。--strict 下视为失败，确保门禁不被降级绕过。
        # Missing tool means a silently skipped gate: fail under --strict.
        if [ "$STRICT" = 1 ]; then fail "node not found — cannot verify dashboard.js syntax (required under --strict)"; else warn "node not found — skipping dashboard.js syntax check"; fi
    fi
else
    warn "files/view/dashboard.js missing — skipped"
fi

if [ -f files/luci/controller/adguardhome.lua ]; then
    # 校验器探测：优先 `luac -p`，其次 `lua` 的 loadfile。
    # 兼容 brew 的 lua/luac 与 Ubuntu 的 lua5.4 / luac5.4（runner 上无版本无关名字）。
    # Checker discovery: prefer `luac -p`, fall back to `lua` loadfile; probes the
    # version-suffixed names too, since CI runners expose only lua5.4/luac5.4.
    LUAC_BIN=""
    for c in luac luac5.4 luac5.3 luac5.1; do
        have "$c" && { LUAC_BIN="$c"; break; }
    done
    LUA_BIN=""
    for c in lua lua5.4 lua5.3 lua5.1; do
        have "$c" && { LUA_BIN="$c"; break; }
    done
    if [ -n "$LUAC_BIN" ]; then
        if "$LUAC_BIN" -p files/luci/controller/adguardhome.lua 2>/dev/null; then ok "adguardhome.lua: Lua syntax OK ($LUAC_BIN -p)"; else fail "adguardhome.lua: Lua syntax error ($LUAC_BIN -p)"; fi
    elif [ -n "$LUA_BIN" ]; then
        if "$LUA_BIN" -e 'assert(loadfile("files/luci/controller/adguardhome.lua"))' 2>/dev/null; then ok "adguardhome.lua: Lua load OK ($LUA_BIN)"; else fail "adguardhome.lua: Lua load failed ($LUA_BIN)"; fi
    else
        # Lua 语法是本项目历史 P0 高发区，绝不能静默跳过。
        # Lua syntax is this project's historical P0 hotspot — never skip it silently.
        if [ "$STRICT" = 1 ]; then fail "no lua/luac found — cannot verify Lua syntax (install lua5.4; required under --strict)"; else warn "no lua/luac found — skipping Lua syntax check"; fi
    fi
else
    warn "files/luci/controller/adguardhome.lua missing — skipped"
fi

# ── 4. Content fingerprint / 内容指纹 ──
hdr "Content fingerprint / 内容指纹 (checksums.sha256)"
if [ -f checksums.sha256 ]; then
    if have sha256sum; then
        if sha256sum -c checksums.sha256 >/dev/null 2>&1; then ok "checksums.sha256 matches files/"; else fail "checksums.sha256 does NOT match files/ (run: sh scripts/make_package.sh after regenerating)"; fi
    else
        warn "sha256sum not found — cannot verify checksums"
    fi
else
    fail "checksums.sha256 missing"
fi

# ── 5. changes_package sync / 本地测试目录同步 ──
hdr "changes_package sync / 本地测试目录同步"
if [ -d changes_package ]; then
    for f in files/luci/controller/adguardhome.lua:changes_package/adguardhome.lua \
             files/view/dashboard.js:changes_package/dashboard.js \
             manifest.json:changes_package/manifest.json \
             checksums.sha256:changes_package/checksums.sha256; do
        src="${f%%:*}"; dst="${f##*:}"
        if [ ! -f "$dst" ]; then fail "changes_package: $dst missing"; continue; fi
        if cmp -s "$src" "$dst" 2>/dev/null; then ok "changes_package: $(basename "$dst") byte-identical"; else fail "changes_package: $(basename "$dst") differs from $src (re-sync: cp $src $dst)"; fi
    done
else
    warn "changes_package/ not present (gitignored, local-only) — skipped"
fi

# ── 6. Git state (advisory unless --strict) / 仓库状态 ──
hdr "Git state / 仓库状态"
if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dirty" -gt 0 ]; then
        if [ "$STRICT" = 1 ]; then fail "working tree is dirty ($dirty changed file(s)) — commit before release"; else warn "working tree is dirty ($dirty changed file(s)) — commit before pushing"; fi
    else
        ok "working tree clean"
    fi
    tag=$(git describe --exact-match --tags 2>/dev/null || true)
    if [ -n "$tag" ]; then
        tver=$(printf '%s' "$tag" | sed -n 's/^v\(.*\)$/\1/p')
        if [ -n "$MANIFEST_VER" ] && [ "$tver" != "$MANIFEST_VER" ]; then
            fail "current tag $tag (v$tver) != manifest version $MANIFEST_VER"
        else
            ok "on tag $tag matching manifest version"
        fi
    else
        if [ "$STRICT" = 1 ]; then fail "not on a git tag — tag the release first"; else warn "not on a git tag (advisory; CI builds on tag push)"; fi
    fi
else
    warn "git not available / not a repo — skipped"
fi

# ── summary / 汇总 ──
hdr "Result / 结论"
if [ "$FAIL" -eq 0 ]; then
    printf 'PREFLIGHT PASSED (%s warning(s))\n' "$WARN_COUNT"
else
    printf 'PREFLIGHT FAILED: %s mandatory check(s) failed\n' "$FAIL"
fi

[ "$CHECK_ONLY" = 1 ] && { [ "$FAIL" -eq 0 ] && exit 0 || exit "$FAIL"; }

# ── build package / 构建压缩包 ──
if [ "$FAIL" -ne 0 ]; then
    printf '\nRefusing to build package with failing preflight checks.\n' >&2
    exit "$FAIL"
fi
hdr "Build package / 构建整项目压缩包"
if [ -f scripts/make_package.sh ]; then
    sh scripts/make_package.sh || exit $?
else
    fail "scripts/make_package.sh missing — cannot build"
    exit "$FAIL"
fi

printf '\nRelease artifacts ready in dist/. Push the tag to publish.\n' >&2
exit 0
