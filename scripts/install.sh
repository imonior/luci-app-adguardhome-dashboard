#!/bin/sh
set -e

# ── i18n: default English, optional language selection ──
# 默认英文交互；开始时可选择中文 / Default interaction is English; a language can be chosen at start.
_lang="en"
_t() {
    # _t "english text" "中文文本" — pick string by _lang
    if [ "$_lang" = "zh" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

REPO="imonior/luci-app-adguardhome-dashboard"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
_gh_raw="$RAW_BASE"   # pure direct URL; never gets a proxy prefix / 纯直连地址，永不被代理前缀修改

AGH_DIR="/opt/AdGuardHome"
AGH_BIN="/opt/AdGuardHome/AdGuardHome"
AGH_INSTALL_URL_BASE="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"
AGH_INSTALL_URL="$AGH_INSTALL_URL_BASE"

# ── 路径推导（必须在任何网络步骤之前：离线判断依赖它）──
# Path resolution: must happen before any networking, because offline detection depends on it.
# 发布包结构是仓库骨架： <root>/scripts/install.sh + <root>/files/ + <root>/manifest.json
# 因此 SCRIPT_DIR=<root>/scripts → PROJECT_ROOT=<root> → LOCAL_FILES=<root>/files，
# 正好命中下方已有的「检测到本地项目文件」分支，无需新增部署逻辑。
# A release tarball keeps the repo layout, so the existing "local files" branch is reused as-is.
SCRIPT_DIR="$(cd "$(dirname "$0" 2>/dev/null)" 2>/dev/null && pwd)"
if [ -z "$SCRIPT_DIR" ]; then SCRIPT_DIR="$(pwd)"; fi
PROJECT_ROOT="$(dirname "$SCRIPT_DIR" 2>/dev/null)"
LOCAL_FILES="$PROJECT_ROOT/files"

# ── 运行方式检测：管道喂入时 fd 0 就是脚本正文本身 ──
# `curl ... | sh` 时 $0 是解释器名（sh/bash），磁盘上并不存在脚本文件，因此 PROJECT_ROOT
# 毫无意义 —— 它会被推成 cwd 的上级目录，最坏情况下让「删除本地项目」分支误删真实目录。
# 判别到这一情形就清空路径上下文，禁用一切本地文件分支。
# When the script is piped into the shell (`curl ... | sh`), $0 is the interpreter name and no
# script file exists on disk, so PROJECT_ROOT is meaningless — worse, it degenerates into the
# parent of cwd and would let the "delete local project" branch remove a real directory. Drop
# the on-disk path context whenever we detect that invocation.
_script_from_stdin=0
case "$0" in
    sh|bash|ash|dash|-sh|-bash|/bin/sh|/bin/bash|/bin/ash|/bin/dash) _script_from_stdin=1 ;;
esac
if [ "$_script_from_stdin" = "1" ]; then
    PROJECT_ROOT=""
    LOCAL_FILES=""
fi

# ── 交互输入统一入口 ──
# 管道运行时 `read` 会把**下一行脚本**当成输入吞掉（实测：整行脚本被吃掉、if 分支错乱），
# 因此仅在「脚本来自 stdin」时改从 /dev/tty 读取；无控制终端时返回非 0，调用方走默认值。
# 其它运行方式（sh install.sh、把答案重定向到 stdin）行为完全不变。
# Interactive input entry point. Under a piped run a plain `read` swallows the *next script
# line*, so only when the script itself comes from stdin do we read from /dev/tty. Without a
# controlling terminal it returns non-zero and the caller falls back to its default. Every other
# invocation (sh install.sh, answers redirected onto stdin) behaves exactly as before.
_has_tty=0
if { : < /dev/tty; } 2>/dev/null; then _has_tty=1; fi
read_input() {
    if [ "$_script_from_stdin" != "1" ]; then
        read -r "$1"
    elif [ "$_has_tty" = "1" ]; then
        read -r "$1" < /dev/tty
    else
        return 1
    fi
}

# 是否处于「可交互」状态。`sh install.sh` 时看 stdin 是否为终端；脚本经管道喂入时可交互性
# 取决于「能否打开控制终端 /dev/tty」——此时 fd 0 是脚本正文，`[ -t 0 ]` 永远为假。
# 所有「交互 → 重新提示 / 非交互 → 直接中止」的分支都必须走这里，不能再用 `[ -t 0 ]`，
# 否则管道模式下明明读得到终端，却被判成非交互而中止安装。
# Interactive-or-not. Under `sh install.sh` this is "is stdin a terminal"; when the script itself
# is piped, fd 0 carries the script text so that test can never pass — interactive then means "the
# controlling terminal /dev/tty is still openable". Every interactive-vs-noninteractive branch
# must use this predicate instead of `[ -t 0 ]`, or a piped run that CAN read the terminal is
# misjudged as non-interactive and aborts.
_is_interactive() {
    if [ -t 0 ]; then return 0; fi
    if [ "$_script_from_stdin" = "1" ] && [ "$_has_tty" = "1" ]; then return 0; fi
    return 1
}

# ── 离线模式：自包含发布包 / 手动指定 ──
# Offline mode. A release tarball carries an OFFLINE_PACKAGE marker beside install.sh, so that
# `sh install.sh` inside an extracted package installs purely from ./files and never touches the
# network (no geo probe, no connection test, no online version lookup, no re-download on failure).
# 发布包内自带 OFFLINE_PACKAGE 标记 → 解压后直接 `sh install.sh` 即完全离线安装，无需任何参数。
OFFLINE=0
OFFLINE_REASON=""
if [ -f "$PROJECT_ROOT/OFFLINE_PACKAGE" ]; then
    OFFLINE=1
    OFFLINE_REASON="package"
fi
for _arg in "$@"; do
    case "$_arg" in
        -l|--local|--offline)
            OFFLINE=1
            OFFLINE_REASON="flag"
            ;;
        -h|--help)
            echo "Usage: sh install.sh [-l|--local|--offline] [-h|--help]"
            echo ""
            echo "  -l, --local, --offline"
            echo "        Install from ./files with no network access at all."
            echo "        Implied automatically when an OFFLINE_PACKAGE marker sits next to install.sh"
            echo "        (i.e. inside an extracted release tarball)."
            echo "  -h, --help"
            echo "        Show this help and exit."
            echo ""
            echo "  GITHUB_PROXY=mirror|https://ghfast.top/   force a mirror (mainland CN only)"
            echo "  GITHUB_PROXY=proxy|http://127.0.0.1:7890  force a full proxy server (any region)"
            echo ""
            echo "  AdGuard Home core (optional):"
            echo "        Put the official AdGuardHome_linux_<arch>.tar.gz next to this project"
            echo "        (or one level up) and the installer unpacks it into /opt/AdGuardHome"
            echo "        and registers the service. Works offline too — this project never"
            echo "        ships the core, since its version is released independently."
            echo "        Get it: https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_<arch>.tar.gz"
            echo ""
            echo "  Existing installs (core and panel) are detected first and you are asked"
            echo "  whether to reinstall or keep the current version, online or offline."
            exit 0
            ;;
    esac
done

# GitHub 加速镜像列表 —— **预置镜像仅适用于中国大陆**（同为镜像源类型：URL 前缀拼接）。
# 境外一律不展示/不测试预置镜像，只提供「直连」与「自定义代理」。
# 仅保留长期稳定服务的公开镜像；kkgithub.com 这类短期域名已移除，避免发布后失效。
# Built-in acceleration MIRRORS — mainland China only (type: mirror source = URL prefix).
# Outside CN they are neither listed nor probed; only Direct and Custom proxy are offered.
# Only long-lived public mirrors are kept; short-lived domains like kkgithub.com are removed.
PROXY_LIST="
mirror|https://ghfast.top/
mirror|https://gh-proxy.com/
"

log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1"
}

_now_ms() {
    # BusyBox date lacks %N nanoseconds; use seconds × 1000 (1s granularity suffices for proxy latency display and is cross-platform)
    # BusyBox date 不支持 %N 纳秒，用秒×1000（粒度 1s 足够代理延迟显示，且跨平台兼容）
    echo $(( $(date +%s 2>/dev/null || echo 0) * 1000 ))
}
_elapsed_ms() { echo $(( $(_now_ms) - $1 )); }

echo ""
echo "========================================================="
echo " AdGuardHome LuCI Dashboard"
echo "========================================================="
echo ""
echo "$(_t "Language / 语言:" "语言 / Language:")"
echo "  1) English (default)"
echo "  2) 中文"
printf "$(_t "Select [1/2, default 1]: " "请选择 [1/2，默认 1]: ")"
read_input _lang_choice || true
case "$_lang_choice" in
    2) _lang="zh" ;;
    *) _lang="en" ;;
esac
echo ""

# ── GitHub connectivity test & connection selection ──
# Always test every candidate (direct + proxies) and show a table, letting the user pick ONE connection.
# Downloads FIXEDLY use the selected connection (no silent proxy hop); only if the chosen connection
# is unreachable do we re-run the test and let the user pick again.
# 始终测试所有候选（直连 + 各代理）并展示表格，让用户选定「一个」连接。
# 下载「固定」使用该连接（不再静默跳代理）；仅当选定连接不可达时，才重新测试并让用户改选。
TEST_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/manifest.json"

# ── 代理规格：唯一 wire 格式（install.sh 与面板共用，写入 /etc/adguardhome-dashboard.proxy） ──
#   mirror|<prefix>  镜像源：把原 URL 拼到前缀后面（**仅中国大陆有效**）
#   proxy|<addr>     全量代理服务器：curl -x，URL 不变（类似系统代理，任意地区可用）
#   （空串）          直连
# 向后兼容：不带竖线的裸值按 mirror 处理（历史文件格式）。
# Proxy spec — single wire format shared by install.sh and the dashboard. A bare value
# without "|" is treated as a mirror (legacy /etc/adguardhome-dashboard.proxy format).
PROXY_MODE="mirror"     # mirror | proxy（仅在 PROXY_ADDR 非空时有意义）
PROXY_ADDR=""           # 具体地址；空 = 直连
CONNECTION_LABEL="$(_t "Direct" "直连")"

# 以 0/1 回答「是否含不安全字符」（白名单：字母数字 . _ : / @ % -）
# Answers whether the string contains characters outside a safe whitelist.
gh_unsafe() {
    printf '%s' "$1" | grep -q '[^A-Za-z0-9._:/@%-]'
}

gh_valid_mirror() {
    if [ -z "$1" ]; then return 1; fi
    if gh_unsafe "$1"; then return 1; fi
    case "$1" in
        http://*|https://*) return 0 ;;
        *) return 1 ;;
    esac
}

# 全量代理：要求带 scheme（http/https/socks5/socks5h/socks4/socks4a）或 host:port
gh_valid_proxy() {
    if [ -z "$1" ]; then return 1; fi
    if gh_unsafe "$1"; then return 1; fi
    case "$1" in
        *://*) return 0 ;;
        *:*)   return 0 ;;
        *)     return 1 ;;
    esac
}

gh_norm_mirror() {
    case "$1" in
        */) printf '%s' "$1" ;;
        *)  printf '%s/' "$1" ;;
    esac
}

# 依据 PROXY_MODE / PROXY_ADDR 生成人类可读标签
gh_make_label() {
    if [ -z "$PROXY_ADDR" ]; then
        CONNECTION_LABEL="$(_t "Direct" "直连")"
    elif [ "$PROXY_MODE" = "proxy" ]; then
        CONNECTION_LABEL="$(_t "Full proxy" "全量代理") $PROXY_ADDR"
    else
        CONNECTION_LABEL="$(_t "Mirror (mainland CN only)" "镜像源（仅中国大陆）") $PROXY_ADDR"
    fi
}

# 解析复合规格 → PROXY_MODE / PROXY_ADDR / CONNECTION_LABEL
gh_parse_spec() {
    case "$1" in
        mirror\|*) PROXY_MODE="mirror"; PROXY_ADDR="${1#mirror|}" ;;
        proxy\|*)  PROXY_MODE="proxy";  PROXY_ADDR="${1#proxy|}" ;;
        "")        PROXY_MODE="mirror"; PROXY_ADDR="" ;;
        *)         PROXY_MODE="mirror"; PROXY_ADDR="$1" ;;
    esac
    if [ -n "$PROXY_ADDR" ] && [ "$PROXY_MODE" = "mirror" ]; then
        PROXY_ADDR=$(gh_norm_mirror "$PROXY_ADDR")
    fi
    if [ -z "$PROXY_ADDR" ]; then PROXY_MODE="mirror"; fi
    gh_make_label
}

# 当前规格的字符串形式（写文件 / 传给下游）
gh_spec() {
    if [ -z "$PROXY_ADDR" ]; then
        printf '%s' ""
    else
        printf '%s|%s' "$PROXY_MODE" "$PROXY_ADDR"
    fi
}

# ── 统一网络出口 ──
# URL 必须作为第 1 个参数，其余参数原样转给 curl。三态：直连 / 镜像前缀拼接 / 全量代理（-x）。
# 注意：geo-IP 探测**故意不走这里**（必须直连，否则探测到的是代理出口）。
# Unified curl wrapper: URL first, remaining args pass through unchanged.
# NB: geo-IP probes intentionally bypass this — they must go direct.
gh_curl() {
    local _gu="$1"; shift
    if [ -z "$PROXY_ADDR" ]; then
        curl "$@" "$_gu"
    elif [ "$PROXY_MODE" = "proxy" ]; then
        curl -x "$PROXY_ADDR" "$@" "$_gu"
    else
        curl "$@" "${PROXY_ADDR}${_gu}"
    fi
}

# 复取（绕过镜像/CDN 缓存）：镜像模式下去掉前缀改直连；全量代理模式下仍走代理
# （全量代理是转发器、不是内容缓存源，直连反而可能不通）。
# Fresh re-fetch that bypasses a caching MIRROR: drop the prefix (go direct). With a full
# proxy we keep using it — a forward proxy is not the cache source, and direct may be blocked.
gh_curl_fresh() {
    local _fu="$1"; shift
    if [ -n "$PROXY_ADDR" ] && [ "$PROXY_MODE" = "proxy" ]; then
        curl -x "$PROXY_ADDR" "$@" "$_fu"
    else
        curl "$@" "$_fu"
    fi
}

# Apply the selected connection / 应用所选连接
# 基址始终为纯 URL（不带前缀）：所有请求都经 gh_curl，因此不存在「某个下载点绕过代理」的漏点。
# Bases stay plain URLs; every request goes through gh_curl so no download site can bypass the proxy.
gh_apply_conn() {
    RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
    AGH_INSTALL_URL="$AGH_INSTALL_URL_BASE"
    GH_API_BASE="https://api.github.com"
    if [ -n "$PROXY_ADDR" ]; then
        echo "proxy=$(gh_spec)" > /etc/adguardhome-dashboard.proxy 2>/dev/null || true
    else
        rm -f /etc/adguardhome-dashboard.proxy 2>/dev/null || true
    fi
    gh_make_label
}

# 手动输入代理：**先选类型，再填地址**，然后测试；循环直到可用，或留空中止。
# 两种类型语义不同，不能互相猜测（镜像源是 URL 前缀拼接，全量代理是 curl -x）。
# Manual proxy entry: pick the TYPE first, then the address, then test it; loop until
# reachable, or leave empty to abort. The two types are not interchangeable.
gh_prompt_custom() {
    while true; do
        echo ""
        log "$(_t "Custom proxy — two types are supported:" "自定义代理 —— 支持两种类型：")"
        echo "    1) $(_t "Mirror source (URL prefix), e.g. https://ghfast.top/ — mainland China only" "镜像源（URL 前缀），如 https://ghfast.top/ —— 仅中国大陆有效")"
        echo "    2) $(_t "Full proxy server (curl -x), e.g. http://127.0.0.1:7890 or socks5://127.0.0.1:1080 — any region" "全量代理服务器（curl -x），如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080 —— 任意地区可用")"
        printf "$(_t "Select type [1/2, default 1]: " "请选择类型 [1/2，默认 1]: ")"
        read_input _c_type || true
        _c_type=${_c_type:-1}

        if [ "$_c_type" = "2" ]; then
            _c_mode="proxy"
            printf "$(_t "Full proxy address, or leave empty to abort: " "全量代理地址，留空则中止: ")"
        else
            _c_mode="mirror"
            printf "$(_t "Mirror prefix, or leave empty to abort: " "镜像源前缀，留空则中止: ")"
        fi
        read_input USER_PROXY || true
        USER_PROXY=$(echo "$USER_PROXY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$USER_PROXY" ]; then return 1; fi

        if [ "$_c_mode" = "proxy" ]; then
            if ! gh_valid_proxy "$USER_PROXY"; then
                log "$(_t "Invalid proxy address (expect scheme://host:port or host:port)" "代理地址非法（应为 scheme://host:port 或 host:port）")"
                continue
            fi
            PROXY_MODE="proxy"; PROXY_ADDR="$USER_PROXY"
        else
            if ! gh_valid_mirror "$USER_PROXY"; then
                log "$(_t "Invalid mirror prefix (expect http(s)://...)" "镜像源前缀非法（应为 http(s)://...）")"
                continue
            fi
            PROXY_MODE="mirror"; PROXY_ADDR=$(gh_norm_mirror "$USER_PROXY")
        fi

        gh_make_label
        log "$(_t "Testing custom connection: $CONNECTION_LABEL" "正在测试自定义连接: $CONNECTION_LABEL")"
        if gh_curl "$TEST_URL" -fsSL -m 10 -o /dev/null 2>/dev/null; then
            log "$(_t "Custom connection reachable" "自定义连接可用")"
            return 0
        fi
        log "$(_t "Custom connection unreachable, please try another" "自定义连接不可用，请换一个")"
    done
}

# ── External IP / region detection ──
# Detect the router's egress public IP and region. If in mainland CN, direct GitHub may be
# blocked → a proxy node is recommended; outside CN, direct usually works.
# 检测路由器出口公网 IP 与归属地：身处中国大陆时直连 GitHub 可能受限 → 建议使用代理；
# 境外则直连通常可用。
# We query several public geo-IP services in order and stop at the first that replies (each
# has a short timeout). If all fail we cannot determine the region and stay conservative.
# 依次查询多个公开 geo-IP 服务，取第一个响应的（各自短超时）；全部失败则无法判定地区。
_json_get() {
    # $1=json  $2=key  → first "key":"value" scalar / 提取第一个 "key":"value" 标量
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

gh_detect_region() {
    IS_CN=""
    GEO_IP=""; GEO_COUNTRY=""; GEO_CC=""; GEO_REGION=""; GEO_CITY=""; GEO_SRC=""
    local _apis="https://ip-api.com/json/?fields=status,message,country,countryCode,regionName,city,query https://ipinfo.io/json https://api.ip.sb/geoip https://api.ipify.org?format=json"
    for _api in $_apis; do
        local _out
        # 注意：脚本开头是 set -e，裸赋值 `_out=$(curl ...)` 一旦 curl 失败（超时/DNS/HTTP 错误）
        # 会把整个安装流程直接终止 —— 必须用 `|| _out=""` 兜住，让探测优雅跳过该 API。
        # NB: the script runs under `set -e`; a bare `_out=$(curl ...)` aborts the whole install
        # the moment curl fails, so failure must be swallowed with `|| _out=""`.
        _out=$(curl -m 4 -fsSL "$_api" 2>/dev/null) || _out=""
        [ -z "$_out" ] && continue
        local _ip="" _cc="" _co="" _rg="" _ct=""
        case "$_api" in
            *ip-api.com*)
                _ip=$(_json_get "$_out" query)
                _co=$(_json_get "$_out" country)
                _cc=$(_json_get "$_out" countryCode)
                _rg=$(_json_get "$_out" regionName)
                _ct=$(_json_get "$_out" city)
                [ "$(_json_get "$_out" status)" = "fail" ] && _ip=""
                GEO_SRC="ip-api.com"
                ;;
            *ipinfo.io*)
                _ip=$(_json_get "$_out" ip)
                _cc=$(_json_get "$_out" country)
                _co="$_cc"   # ipinfo 的 country 是 2 位代码，直接当显示名用（否则日志会显示「： / 地区」） / ipinfo returns a 2-letter code; reuse it as the display name
                _rg=$(_json_get "$_out" region)
                _ct=$(_json_get "$_out" city)
                GEO_SRC="ipinfo.io"
                ;;
            *ip.sb*)
                _ip=$(_json_get "$_out" ip)
                _cc=$(_json_get "$_out" country_code)
                _co=$(_json_get "$_out" country)
                _rg=$(_json_get "$_out" region)
                _ct=$(_json_get "$_out" city)
                GEO_SRC="api.ip.sb"
                ;;
            *ipify*)
                _ip=$(_json_get "$_out" ip)
                GEO_SRC="api.ipify.org"
                ;;
        esac
        [ -z "$_ip" ] && continue
        GEO_IP="$_ip"; GEO_COUNTRY="$_co"; GEO_CC="$_cc"; GEO_REGION="$_rg"; GEO_CITY="$_ct"
        # CN judgment / 是否中国大陆判定
        if [ -n "$_cc" ]; then
            case "$_cc" in
                CN|cn) IS_CN="1" ;;
                *)     IS_CN="0" ;;
            esac
        fi
        case "$_co" in
            *中国*|*China*) IS_CN="1" ;;
        esac
        break
    done

    echo ""
    if [ -z "$GEO_IP" ]; then
        log "$(_t "Could not detect network egress IP (network may be restricted)" "未能检测网络出口 IP（可能网络受限）")"
    else
        if [ "$IS_CN" = "1" ]; then
            log "$(_t "Network egress: China · ${GEO_REGION} ${GEO_CITY} (IP ${GEO_IP})" "网络出口：中国 · ${GEO_REGION} ${GEO_CITY}（IP ${GEO_IP}）")"
            log "$(_t "Detected mainland China — direct GitHub may be blocked; a proxy node is recommended" "检测到位于中国大陆，直连 GitHub 可能受限，建议使用代理节点")"
        elif [ "$IS_CN" = "0" ]; then
            log "$(_t "Network egress: ${GEO_COUNTRY} / ${GEO_REGION} ${GEO_CITY} (IP ${GEO_IP})" "网络出口：${GEO_COUNTRY} / ${GEO_REGION} ${GEO_CITY}（IP ${GEO_IP}）")"
            log "$(_t "Detected outside mainland China — direct connection usually works; built-in mirrors are CN-only and will be skipped (proxy optional)" "检测到位于境外，直连通常可用；预置镜像仅在中国大陆有效将被跳过，代理为可选项")"
        else
            log "$(_t "Network egress: IP ${GEO_IP} (region unknown)" "网络出口：IP ${GEO_IP}（地区未知）")"
            log "$(_t "Could not determine region — pick a proxy manually if direct fails" "未能确定地区，如直连失败请手动选择代理")"
        fi
    fi
    echo ""
}

# 已移除自动顺序探测逻辑（auto-pick）：改为「测试后由用户按序号选择 → 当次固定使用 → 下载中确不可用才重新测试并交互改选」。
# Auto-sequential probing (auto-pick) removed: now it is test -> user picks by number -> fixed for the session
# -> re-test and let the user re-pick only when the chosen connection proves unusable during download.

# Test connectivity and prompt the user to select ONE connection
# 测试连通性并提示用户选择「一个」连接
gh_select_connection() {
    echo ""
    log "$(_t "Testing GitHub connectivity (direct + proxies)..." "正在测试 GitHub 连通性（直连 + 各代理）...")"

    # 预置镜像（ghfast.top / gh-proxy.com）仅在中国大陆有效：境外（IS_CN=0）时既不测试也不展示，
    # 只保留「直连」与「自定义代理 URL」——手动输入始终可用（也可用 GITHUB_PROXY 环境变量指定）。
    # Built-in mirrors (ghfast.top / gh-proxy.com) only serve mainland CN: outside CN (IS_CN=0) they are
    # neither tested nor listed — only "Direct" and "Custom proxy URL" remain. Manual input is always
    # available (or set GITHUB_PROXY). Region unknown (IS_CN="") keeps the full candidate list.
    _effective_proxies="$PROXY_LIST"
    if [ "$IS_CN" = "0" ]; then
        _effective_proxies=""
        log "$(_t "Outside mainland China: built-in mirrors are skipped (they only serve CN) — Direct / Custom only" "境外网络：预置镜像仅在中国大陆有效，已跳过；仅提供「直连」与「自定义」")"
    fi

    # Direct (lenient: retry up to 3× so a single slow probe isn't a false negative)
    # 直连（宽松：重试 3 次，避免单次慢连接被误判为不可用）
    _direct_ok="0"; _direct_ms="0"
    _t0=$(_now_ms); _attempt=0
    while [ "$_attempt" -lt 3 ]; do
        if curl -fsSL -m 12 -o /dev/null "$TEST_URL" 2>/dev/null; then _direct_ok="1"; break; fi
        _attempt=$((_attempt + 1))
    done
    if [ "$_direct_ok" = "1" ]; then _direct_ms=$(_elapsed_ms $_t0); fi

    # Each proxy (single attempt) / 各代理（单次探测）
    # 仅探测「本次有效候选」：境外时为空（预置镜像不测试） / Only probe the effective candidates; empty outside CN
    _results_file=$(mktemp 2>/dev/null || echo "/tmp/agh_proxy_results_$$")
    : > "$_results_file"
    # 结果行格式：status|ms|spec —— **规格必须放在最后**，因为规格本身含 "|"，
    # 只有最后一个 read 变量才能吃掉剩余分隔符（若把 spec 放前面，IFS='|' 会在竖线处截断）。
    # Row format: status|ms|spec — the spec MUST come last: it contains "|", and only the final
    # read variable absorbs the remaining separators (putting it first truncates at the "|").
    for _proxy in $_effective_proxies; do
        # 按规格探测（当前仅含镜像候选，但统一走 gh_curl 以便将来混入全量代理）
        # Probe by spec via gh_curl, so a full-proxy candidate would work too.
        gh_parse_spec "$_proxy"
        _t1=$(_now_ms)
        if gh_curl "$TEST_URL" -fsSL -m 10 -o /dev/null 2>/dev/null; then
            echo "ok|$(_elapsed_ms $_t1)|${_proxy}" >> "$_results_file"
        else
            echo "fail|0|${_proxy}" >> "$_results_file"
        fi
    done

    # Build the table / 展示表格
    echo ""
    echo "  #   $(_t "Node" "节点")                  $(_t "Status" "状态")"
    echo "  --------------------------------------------"
    if [ "$_direct_ok" = "1" ]; then
        printf "  1)  %-18s ✓ %sms\n" "$(_t "Direct" "直连")" "$_direct_ms"
    else
        printf "  1)  %-18s ✗ %s\n" "$(_t "Direct" "直连")" "$(_t "unavailable" "不可用")"
    fi
    _idx=2
    while IFS='|' read -r _s _ms _p; do
        [ -z "$_p" ] && continue
        _domain=$(printf '%s' "$_p" | sed 's/^mirror|//;s/^proxy|//;s|https\{0,1\}://||;s|/$||')
        # 标注适用范围：镜像型仅中国大陆；全量代理任意地区可用 / annotate applicability by type
        case "$_p" in
            proxy\|*) _ann="$(_t "any region" "任意地区可用")" ;;
            *)        _ann="$(_t "mainland CN only" "适用于中国大陆")" ;;
        esac
        if [ "$_s" = "ok" ]; then
            printf "  %d)  %-18s ✓ %sms  %s\n" "$_idx" "$_domain" "$_ms" "$_ann"
        else
            printf "  %d)  %-18s ✗ %s  %s\n" "$_idx" "$_domain" "$(_t "timeout" "超时")" "$_ann"
        fi
        _idx=$((_idx + 1))
    done < "$_results_file"
    _custom_opt=$_idx
    echo "  ${_custom_opt})  $(_t "Custom proxy — mirror source OR full proxy server" "自定义代理 —— 镜像源 或 全量代理服务器")"
    echo ""
    echo "  $(_t "Note: built-in mirrors serve mainland China only; elsewhere use Direct or a custom full proxy." "注意：预置镜像仅适用于中国大陆；境外请选择「直连」或自定义全量代理。")"
    echo "  $(_t "Note: connectivity test is for reference only; DNS hijacking/transparent proxy may affect accuracy" "注意：连通性测试仅供参考，DNS 劫持/透明代理可能导致测试不准")"
    echo ""

    # 默认：直连可达则默认直连；否则默认第一个可达代理；都不可达则默认自定义（回车即提示输入）
    # Default: Direct if reachable, else first reachable proxy, else custom (Enter prompts for a URL)
    if [ "$_direct_ok" = "1" ]; then
        _default_choice=1
    else
        _default_choice=$_custom_opt
        _i=2
        while IFS='|' read -r _s _ms _p; do
            [ -z "$_p" ] && continue
            if [ "$_s" = "ok" ]; then _default_choice=$_i; break; fi
            _i=$((_i + 1))
        done < "$_results_file"
    fi

    # 交互选择：选中某节点则固定使用（不静默跳到其它节点）；下载失败可交互重选 / Interactive: fixed-use of chosen node; re-pick on failure
    while true; do
        printf "$(_t "Select connection [1-%d, default %d]: " "请选择连接 [1-%d，默认 %d]: ")" "$_custom_opt" "$_default_choice"
        read_input CONN_CHOICE || true
        CONN_CHOICE=${CONN_CHOICE:-$_default_choice}

        if [ "$CONN_CHOICE" = "$_custom_opt" ]; then
            # ⚠ gh_prompt_custom 返回非 0（留空中止）是**预期分支**，必须放进 if 条件里：
            # `set -e` 下一条独立命令失败会直接终止整个安装，而且没有任何提示。
            # gh_prompt_custom returning non-zero is an EXPECTED branch, so it must be an `if`
            # condition — as a standalone failing command, `set -e` kills the install silently.
            if gh_prompt_custom; then
                break
            elif _is_interactive; then
                # 交互模式下留空 → 回到选择菜单，可改选直连/内置代理（不强制中止）
                # Interactive: empty input -> back to the menu so they can pick Direct/built-in instead
                log "$(_t "Custom proxy empty, please choose another option" "自定义代理为空，请选择其他选项")"
            else
                # 非交互（stdin 非 TTY，如管道为空）下留空 → 直接中止，避免无限循环
                # Non-interactive (non-TTY stdin, e.g. empty pipe): abort to avoid an infinite loop
                rm -f "$_results_file" 2>/dev/null
                return 1
            fi
        elif [ "$CONN_CHOICE" = "1" ]; then
            if [ "$_direct_ok" = "1" ]; then
                PROXY_MODE="mirror"; PROXY_ADDR=""; CONNECTION_LABEL="$(_t "Direct" "直连")"; break
            else
                log "$(_t "Direct is unavailable, please choose another" "直连不可用，请重新选择")"
            fi
        else
            _i=2; _picked=""
            while IFS='|' read -r _s _ms _p; do
                if [ "$_i" = "$CONN_CHOICE" ] && [ "$_s" = "ok" ]; then
                    # 按规格解析（预置候选虽均为镜像源，仍统一走 gh_parse_spec 以便将来混入全量代理）
                    # Parse the spec (built-in candidates are mirrors, but go through the parser anyway)
                    gh_parse_spec "$_p"; _picked="yes"; break
                fi
                _i=$((_i + 1))
            done < "$_results_file"
            if [ "$_picked" = "yes" ]; then break
            else
                log "$(_t "Selected node is unavailable, please choose another" "所选节点不可用，请重新选择")"
            fi
        fi
    done

    rm -f "$_results_file" 2>/dev/null
    gh_apply_conn
    log "$(_t "Using connection: $CONNECTION_LABEL" "使用的连接: $CONNECTION_LABEL")"
}

if [ "$OFFLINE" = "1" ]; then
    # 离线：完全跳过出口 IP 探测与连接选择，连接固定为「离线（不联网）」
    # Offline: skip the egress-IP probe and connection selection entirely.
    PROXY_MODE="direct"
    PROXY_ADDR=""
    CONNECTION_LABEL="$(_t "Offline (no network)" "离线（不联网）")"
    log "$(_t "Offline install mode: no network access will be used (files come from $LOCAL_FILES)" "离线安装模式：不使用任何网络（文件来自 $LOCAL_FILES）")"
    if [ "$OFFLINE_REASON" = "package" ]; then
        log "$(_t "Detected OFFLINE_PACKAGE marker — installing from the extracted release package" "检测到 OFFLINE_PACKAGE 标记 —— 使用已解压的发布包安装")"
    fi
else
    # External IP / region detection (informational; also drives the proxy recommendation below)
    # 出口 IP / 地区检测（信息展示；同时驱动下方的代理建议）
    gh_detect_region

    # If GITHUB_PROXY env is explicitly set, honor it without prompting (override)
    # 若显式设置 GITHUB_PROXY 环境变量，则直接使用（覆盖交互选择）
    # 显式类型前缀 `mirror|` / `proxy|` 优先；裸值以结尾斜杠区分：
    #   https://ghfast.top/   → 镜像源（仅中国大陆）
    #   http://127.0.0.1:7890 → 全量代理（curl -x）
    # An explicit `mirror|` / `proxy|` prefix wins; for a bare value the trailing slash decides.
    if [ -n "$GITHUB_PROXY" ]; then
        case "$GITHUB_PROXY" in
            mirror\|*|proxy\|*) _gps="$GITHUB_PROXY" ;;
            */)                 _gps="mirror|$GITHUB_PROXY" ;;
            *)                  _gps="proxy|$GITHUB_PROXY" ;;
        esac
        gh_parse_spec "$_gps"
        gh_apply_conn
        log "$(_t "Using proxy from GITHUB_PROXY env: $CONNECTION_LABEL" "使用环境变量指定代理: $CONNECTION_LABEL")"
    else
        gh_select_connection || { log "$(_t "Connection setup aborted." "连接设置已中止。")"; exit 1; }
    fi
fi

# ═══════════════════════════════════════════════════════════
# Part 1: install the AdGuard Home core / 第一部分：安装 AdGuard Home 核心
# ═══════════════════════════════════════════════════════════

log "$(_t "── Part 1: AdGuard Home core ──" "── 第一部分：AdGuard Home 核心 ──")"

# ── 本机 CPU 架构名（与 AdGuard Home 官方 install.sh 的映射保持一致）──
# 复刻官方映射表，用途有二：
#   1) 在目录内的多个核心 tarball 中挑出与本机匹配的那一个；
#   2) 未命中时能明确告诉用户「本机是什么架构、目录里有哪些架构」，
#      而不是笼统报一句「装不上」。
# CPU architecture name, mirroring AdGuardHome's official install.sh mapping.
agh_arch() {
    _aa=$(uname -m 2>/dev/null || echo "")
    case "$_aa" in
        x86_64|x86-64|x64|amd64) printf '%s' "amd64" ;;
        i386|i486|i686|i786|x86) printf '%s' "386" ;;
        armv5l)                  printf '%s' "armv5" ;;
        armv6l)                  printf '%s' "armv6" ;;
        armv7l|armv8l)           printf '%s' "armv7" ;;
        aarch64|arm64)           printf '%s' "arm64" ;;
        mips|mips64)
            # 端序判定用 hexdump：官方注释明说 OpenWrt 上有 hexdump 而没有 od
            # Byte order via hexdump — OpenWrt ships hexdump but not od.
            if printf 'I' | hexdump -o 2>/dev/null | awk '{ print substr($2, 6, 1); exit; }' | grep -q 1; then
                printf '%s' "${_aa}le_softfloat"
            else
                printf '%s' "${_aa}_softfloat"
            fi
            ;;
        mipsel)                  printf '%s' "mipsle_softfloat" ;;
        mips64el)                printf '%s' "mips64le_softfloat" ;;
        riscv64)                 printf '%s' "riscv64" ;;
        *)                       printf '%s' "" ;;
    esac
}

# ── 扫描目录内的 AdGuard Home 核心压缩包 ──
# 本项目**不随包提供** AGH 核心：把官方 tarball（AdGuardHome_linux_<arch>.tar.gz）
# 与本项目放在一起，安装脚本就地取用；没有则只装面板。
# 离线安装尤其依赖这条路径 —— 离线时它是核心的唯一供给来源。
# 扫描两级：项目目录本身，以及它的上级目录（用户常把两个压缩包放在同一层）。
# This project does NOT bundle the AGH core: drop the official tarball next to the
# project and the installer picks it up in place. Offline installs depend on exactly
# this path. Two levels are scanned: the project dir and its parent.
AGH_PKG=""          # 与本机架构匹配的核心包 / the tarball matching this machine
AGH_PKG_ARCHS=""    # 目录内所有核心包的架构名（未命中时展示） / arch names found

scan_agh_packages() {
    _sa_arch=$(agh_arch)
    _sa_parent=$(dirname "$PROJECT_ROOT" 2>/dev/null)
    for _sa_dir in "$PROJECT_ROOT" "${_sa_parent:-$PROJECT_ROOT}"; do
        for _sa_p in "$_sa_dir"/AdGuardHome_linux_*.tar.gz; do
            # 无匹配文件时 glob 会原样返回，用 -f 过滤；`|| continue` 在 set -e 下安全
            # An unmatched glob is returned literally, so filter with -f.
            [ -f "$_sa_p" ] || continue
            _sa_base=$(basename "$_sa_p")
            _sa_a=${_sa_base#AdGuardHome_linux_}
            _sa_a=${_sa_a%.tar.gz}
            AGH_PKG_ARCHS="$AGH_PKG_ARCHS $_sa_a"
            if [ -z "$AGH_PKG" ] && [ -n "$_sa_arch" ] && [ "$_sa_a" = "$_sa_arch" ]; then
                AGH_PKG="$_sa_p"
            fi
        done
        # 项目目录内已命中就不必再看上级目录 / stop at the first level that matches
        if [ -n "$AGH_PKG" ]; then break; fi
    done
    AGH_PKG_ARCHS=$(printf '%s' "$AGH_PKG_ARCHS" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')
}

# ── 用本地 tarball 安装 AGH 核心（完全离线）──
# 复刻官方 install.sh 的三步：解压到 /opt → ./AdGuardHome -s install。
# 官方脚本本身就只有这三步（服务脚本由 AGH 二进制自己写，内含 OpenWrt rc.common
# 支持，无需我们手写 init），因此这里没有任何需要额外发明的东西。
# Mirrors the three steps the official install.sh performs: unpack into /opt, then
# `./AdGuardHome -s install`. The service script is written by the binary itself.
install_agh_from_local() {
    _il_pkg="$1"

    # 覆盖安装必须先停服务并注销，否则 -s install 会与既有服务冲突。
    # 判据用**目录**而不是二进制：残留目录（二进制已丢但目录还在）同样要清掉，
    # 否则上一次安装的陈旧文件会残留进新装。
    # An overwrite must stop and unregister first. The check uses the DIRECTORY, not the
    # binary: a leftover dir (binary already gone) must be cleared too, or stale files
    # from the previous install would survive into the new one.
    if [ -d "$AGH_DIR" ]; then
        if [ -f "$AGH_BIN" ]; then
            if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
                log "$(_t "Stopping AdGuard Home service..." "正在停止 AdGuard Home 服务...")"
                "$AGH_BIN" -s stop 2>/dev/null || true
                sleep 2
                if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
                    killall AdGuardHome 2>/dev/null || true
                    sleep 1
                fi
            fi
            log "$(_t "Unregistering the existing core service..." "正在注销旧的核心服务...")"
            ( cd "$AGH_DIR" && "$AGH_BIN" -s uninstall ) 2>/dev/null || true
        fi
        rm -rf "$AGH_DIR"
    fi

    log "$(_t "Unpacking core package: $(basename "$_il_pkg")" "正在解压核心包: $(basename "$_il_pkg")")"
    mkdir -p /opt
    if ! tar -C /opt -x -z -f "$_il_pkg"; then
        log "$(_t "Unpack failed — the archive may be corrupt" "解压失败 —— 压缩包可能已损坏")"
        return 1
    fi

    if [ ! -f "$AGH_BIN" ]; then
        log "$(_t "No $AGH_BIN after unpacking — unexpected archive layout" "解压后未找到 $AGH_BIN —— 压缩包结构异常")"
        rm -rf "$AGH_DIR"
        return 1
    fi
    chmod 755 "$AGH_BIN" 2>/dev/null || true

    # 架构自检：内核无法执行该二进制时（Exec format error / 非法指令）会立即失败，
    # 比只看文件名可靠 —— 能挡住「文件名对、内容错」的情况。
    # Self-check by actually running it: the kernel rejects a mismatched binary
    # immediately, which catches "right file name, wrong contents".
    if ! "$AGH_BIN" --version > /dev/null 2>&1; then
        log "$(_t "The core binary cannot run on this machine (architecture mismatch or corrupt file); rolled back" "核心二进制无法在本机执行（架构不匹配或文件损坏），已回滚")"
        rm -rf "$AGH_DIR"
        return 1
    fi

    log "$(_t "Registering the system service..." "正在注册系统服务...")"
    if ! ( cd "$AGH_DIR" && "$AGH_BIN" -s install ); then
        log "$(_t "Service registration failed" "服务注册失败")"
        return 1
    fi
    log "$(_t "Core version: $("$AGH_BIN" --version 2>/dev/null | head -n1)" "核心版本: $("$AGH_BIN" --version 2>/dev/null | head -n1)")"
    return 0
}

# ── 核心包获取提示（「目录内没包」与「有包但架构不符」两处共用）──
# 两种失败都必须给出**可操作**的获取方式：精确到本机架构的文件名 + 可用的下载直链 +
# 发布页。只说「缺 AdGuardHome_linux_arm64.tar.gz」等于只说出了问题，没说怎么解决。
# 两条直链指向同一份文件：
#   ① AGH 官方 CDN（static.adtidy.org）—— 走不了 GitHub 镜像；
#   ② GitHub Release 资产 —— 中国大陆可加镜像前缀（如 https://ghfast.top/）。
# 离线机器请在另一台有网机器上下载后拷贝进来（本脚本此时零联网）。
# Shared hint for both "no package" and "arch mismatch": an exact filename for THIS machine
# plus working links, so the user learns how to obtain it rather than just what is missing.
AGH_DL_CDN="https://static.adtidy.org/adguardhome/release"
AGH_DL_GH="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download"

agh_download_hint() {
    # `|| _dh_arch=""`：set -e 下赋值语句的退出码取自命令替换，不能裸写
    _dh_arch=$(agh_arch) || _dh_arch=""

    if [ -z "$_dh_arch" ]; then
        log "$(_t "This machine's CPU could not be mapped to an official package name. Pick the matching build from:" "无法将本机 CPU 映射到官方包名，请从以下页面选择匹配本机架构的构建：")"
        log "  https://github.com/AdguardTeam/AdGuardHome/releases/latest"
        return 0
    fi

    _dh_file="AdGuardHome_linux_${_dh_arch}.tar.gz"
    log "$(_t "Put $_dh_file in this project's folder (or one level up), then re-run this installer." "把 $_dh_file 放入本项目目录（或上一级目录）后重新运行本脚本。")"
    log "$(_t "Download it on a machine with network access (both URLs serve the same file):" "请在可联网的机器上下载（两条直链是同一份文件）：")"
    log "  curl -fLO $AGH_DL_CDN/$_dh_file"
    log "  curl -fLO $AGH_DL_GH/$_dh_file"
    log "  $(_t "The second is GitHub; mainland CN may prefix it with a mirror, e.g. https://ghfast.top/" "第二条是 GitHub —— 中国大陆可加镜像前缀，如 https://ghfast.top/")"
    log "$(_t "Release page / all builds:" "发布页 / 全部构建：") https://github.com/AdguardTeam/AdGuardHome/releases/latest"
    log "$(_t "Other channels (beta/edge): same CDN path, replace 'release' with 'beta' or 'edge'." "其他渠道（beta/edge）：CDN 路径相同，把 release 换成 beta / edge。")"
}

if [ "$OFFLINE" = "1" ]; then
    # ── 离线 / Offline ──
    # 核心只能来自「与本项目放在一起的官方 tarball」。这里**不能**沿用在线分支的
    # `curl ... | sh`：管道退出码取自 sh，curl 失败喂进去的是空输入，sh 会"成功"
    # 执行空脚本 → 被误报成「AdGuard Home 安装完成」。
    # The core can only come from a tarball placed alongside this project. Do NOT reuse
    # the online `curl ... | sh`: the pipeline status comes from sh, which happily "runs"
    # the empty input when curl fails — reporting a bogus success.
    scan_agh_packages

    if [ -n "$AGH_PKG" ]; then
        log "$(_t "Found a core package: $(basename "$AGH_PKG") (this machine: $(agh_arch))" "发现项目目录内的核心包: $(basename "$AGH_PKG")（本机架构: $(agh_arch)）")"
        if [ -f "$AGH_BIN" ]; then
            # 已装核心 → 交互确认是否覆盖（无论在线还是离线都要问）
            # Existing core -> confirm the overwrite (asked in both online and offline runs).
            CURRENT_VER=$("$AGH_BIN" --version 2>&1 | awk '{print $NF}')
            case "$CURRENT_VER" in v*) ;; *) CURRENT_VER="v$CURRENT_VER" ;; esac
            log "$(_t "AdGuard Home is already installed: $CURRENT_VER" "检测到已安装 AdGuard Home：$CURRENT_VER")"
            echo ""
            echo "  1) $(_t "Overwrite with the core package found next to this project" "用项目目录内的核心包覆盖安装")"
            echo "  2) $(_t "Skip, keep current version" "跳过，保留当前版本")"
            echo ""
            printf "$(_t "Select [1/2, default 2]: " "请选择 [1/2，默认 2]: ")"
            read_input _agh_ovr || true
            _agh_ovr=${_agh_ovr:-2}
            if [ "$_agh_ovr" = "1" ]; then
                if install_agh_from_local "$AGH_PKG"; then
                    log "$(_t "AdGuard Home core installed" "AdGuard Home 核心安装完成")"
                else
                    log "$(_t "Core install failed; continuing with the panel only" "核心安装失败；继续安装面板")"
                fi
            else
                log "$(_t "Skipped AdGuard Home core install, keeping current version" "跳过 AdGuard Home 核心安装，保留当前版本")"
            fi
        else
            log "$(_t "AdGuard Home not detected — installing from the core package next to this project..." "未检测到 AdGuard Home，使用项目目录内的核心包安装...")"
            if install_agh_from_local "$AGH_PKG"; then
                log "$(_t "AdGuard Home core installed" "AdGuard Home 核心安装完成")"
            else
                log "$(_t "Core install failed; continuing with the panel only" "核心安装失败；继续安装面板")"
            fi
        fi
    elif [ -n "$AGH_PKG_ARCHS" ]; then
        # 有核心包但架构不匹配：必须说清「本机是什么 / 目录里有什么」，否则用户无从下手
        # Packages exist but none matches: state both sides explicitly, or the user is stuck.
        log "$(_t "Core package(s) found, but none matches this machine's architecture:" "发现核心包，但没有一个与本机架构匹配：")"
        log "  $(_t "this machine: " "本机: ")$(agh_arch)"
        log "  $(_t "in package dir: " "目录内: ")$AGH_PKG_ARCHS"
        agh_download_hint
        log "$(_t "The panel will still be installed." "面板仍会继续安装。")"
    else
        log "$(_t "Offline mode: no AdGuard Home core package found next to this project" "离线模式：未在项目目录内发现 AdGuard Home 核心压缩包")"
        log "$(_t "This project does not bundle the core. To install it, prepare the official tarball for THIS machine's architecture ($(agh_arch)):" "本项目不随包提供核心。如需安装，请自备与本机架构（$(agh_arch)）匹配的官方压缩包：")"
        agh_download_hint
        log "$(_t "The panel will still be installed." "面板仍会继续安装。")"
    fi
elif [ -f "$AGH_BIN" ]; then
    log "$(_t "Detected AdGuard Home installed ($AGH_BIN)" "检测到已安装 AdGuard Home ($AGH_BIN)")"

    CURRENT_VER=$("$AGH_BIN" --version 2>&1 | awk '{print $NF}')
    case "$CURRENT_VER" in v*) ;; *) CURRENT_VER="v$CURRENT_VER" ;; esac

    # 统一走 gh_curl（直连 / 镜像前缀 / 全量代理 三态）。
    # 不再是「先直连、再换 GH_API_BASE、再逐个试预置镜像」的静默跳代理链 —— 与「固定使用所选连接」策略一致；
    # 该连接不可用时仅提示无法获取在线版本，不会偷偷换线路。
    # All version probes go through gh_curl; no silent proxy hopping (matches the
    # "fixed connection" policy). A failed probe just means "online version unknown".
    # 离线模式下完全不查询（LATEST_VER 为空 → 只显示当前版本）。
    # Offline: skip the probe entirely; LATEST_VER stays empty and only the current version shows.
    LATEST_VER=""
    if [ "$OFFLINE" != "1" ]; then
        LATEST_VER=$(gh_curl "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" -fsSL -m 8 2>/dev/null \
            | awk -F'"' '/tag_name/{print $4; exit}')
    fi

    if [ -n "$CURRENT_VER" ] && [ -n "$LATEST_VER" ]; then
        log "$(_t "Current: $CURRENT_VER    Latest: $LATEST_VER" "当前版本: $CURRENT_VER    最新版本: $LATEST_VER")"
        if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
            log "$(_t "Already the latest version" "已是最新版本")"
        fi
    elif [ -n "$CURRENT_VER" ]; then
        log "$(_t "Current: $CURRENT_VER (could not fetch online version)" "当前版本: $CURRENT_VER (无法获取在线版本)")"
    elif [ -n "$LATEST_VER" ]; then
        log "$(_t "Current: unknown    Latest: $LATEST_VER" "当前版本: 未知    最新版本: $LATEST_VER")"
    fi

    echo ""
    echo "  1) $(_t "Re-download from official (overwrite current)" "从官方重新下载安装（覆盖当前版本）")"
    echo "  2) $(_t "Skip, keep current version" "跳过，保留当前版本")"
    echo ""
    printf "$(_t "Select [1/2, default 2]: " "请选择 [1/2，默认 2]: ")"
    # `|| true`：set -e 下 stdin 为 EOF（非交互/管道）时 read 返回非 0 会静默终止整个安装
    # `|| true` guards against set -e killing the install when stdin is EOF (non-interactive).
    read_input CHOICE || true
    CHOICE=${CHOICE:-2}

    if [ "$CHOICE" = "1" ]; then
        if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
            log "$(_t "Detected AdGuard Home running, stopping service first..." "检测到 AdGuard Home 正在运行，先停止服务...")"
            if [ -f /etc/init.d/AdGuardHome ]; then
                /etc/init.d/AdGuardHome stop 2>/dev/null || true
            elif [ -f /etc/init.d/adguardhome ]; then
                /etc/init.d/adguardhome stop 2>/dev/null || true
            else
                "$AGH_BIN" -s stop 2>/dev/null || true
            fi
            sleep 2
            if pgrep -f 'AdGuardHome' > /dev/null 2>&1; then
                log "$(_t "Warning: service did not stop cleanly, forcing termination..." "警告: 服务未能正常停止，尝试强制终止...")"
                killall AdGuardHome 2>/dev/null || true
                sleep 1
            fi
            log "$(_t "AdGuard Home stopped" "AdGuard Home 已停止")"
        fi

        log "$(_t "Reinstalling AdGuard Home from official script..." "从官方脚本重新安装 AdGuard Home...")"
        gh_curl "$AGH_INSTALL_URL" -fsSL | sh -s -- -r
        log "$(_t "AdGuard Home installation complete" "AdGuard Home 安装完成")"
    else
        log "$(_t "Skipped AdGuard Home core install, keeping current version" "跳过 AdGuard Home 核心安装，保留当前版本")"
    fi
else
    log "$(_t "AdGuard Home not detected, installing from official script..." "未检测到 AdGuard Home，开始从官方脚本安装...")"
    gh_curl "$AGH_INSTALL_URL" -fsSL | sh
    log "$(_t "AdGuard Home installation complete" "AdGuard Home 安装完成")"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Part 2: install the LuCI Dashboard management panel / 第二部分：安装 LuCI Dashboard 管理面板
# ═══════════════════════════════════════════════════════════

log "$(_t "── Part 2: LuCI Dashboard management panel ──" "── 第二部分：LuCI Dashboard 管理面板 ──")"

# ── 检测本项目是否已安装（在线 / 离线都要判断）──
# Detect an existing installation of THIS project (checked in both online and offline runs).
DASH_MANIFEST="/usr/share/adguardhome-dashboard/manifest.json"
DASH_CONTROLLER="/usr/lib/lua/luci/controller/adguardhome.lua"
DASH_INSTALLED=0
DASH_INSTALLED_VER=""
if [ -f "$DASH_MANIFEST" ]; then
    DASH_INSTALLED=1
    DASH_INSTALLED_VER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DASH_MANIFEST" | head -n1)
fi
# manifest 缺失但 controller 在 → 老版本安装（那时候还没有 manifest.json）
# manifest missing but controller present -> an older install (predates manifest.json).
if [ "$DASH_INSTALLED" = "0" ] && [ -f "$DASH_CONTROLLER" ]; then
    DASH_INSTALLED=1
fi

if [ "$DASH_INSTALLED" = "1" ]; then
    if [ -n "$DASH_INSTALLED_VER" ]; then
        log "$(_t "An existing installation of this project was detected: v$DASH_INSTALLED_VER" "检测到本项目已安装：v$DASH_INSTALLED_VER")"
    else
        log "$(_t "An existing installation of this project was detected (version unknown)" "检测到本项目已安装（版本未知）")"
    fi
    echo ""
    echo "  1) $(_t "Reinstall (overwrite the current version)" "重新安装（覆盖当前版本）")"
    echo "  2) $(_t "Skip, keep the current version" "跳过，保留当前版本")"
    echo ""
    printf "$(_t "Select [1/2, default 1]: " "请选择 [1/2，默认 1]: ")"
    read_input _dash_choice || true
    _dash_choice=${_dash_choice:-1}
    if [ "$_dash_choice" = "2" ]; then
        log "$(_t "Skipped the panel install — keeping the currently installed version" "已跳过面板安装 —— 保留当前版本")"
        echo ""
        echo "========================================================="
        echo " $(_t "No changes were made." "未做任何改动。")"
        echo "========================================================="
        # 此时 TMPDIR 尚未创建，无需清理
        # TMPDIR has not been created yet at this point, so there is nothing to clean up.
        exit 0
    fi
else
    log "$(_t "No existing installation of this project found — performing a fresh install" "未检测到本项目已安装 —— 执行全新安装")"
fi

# SCRIPT_DIR / PROJECT_ROOT / LOCAL_FILES 已在文件头部推导（离线判断需要它们先就绪）
# Already resolved at the top of the file (offline detection needs them before any networking).

TMPDIR=$(mktemp -d)
DOWNLOAD_DIR="$TMPDIR/download"
mkdir -p "$DOWNLOAD_DIR/luci/controller" "$DOWNLOAD_DIR/luci/menu.d" "$DOWNLOAD_DIR/luci/i18n" "$DOWNLOAD_DIR/view"

download_from_github() {
    log "$(_t "Downloading Dashboard files from GitHub..." "从 GitHub 下载 Dashboard 文件...")"
    _cb=$(date +%s 2>/dev/null || echo 0)
    _gh_raw="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

    dl() {
        local path="$1" dest="$2"
        local fname=$(basename "$dest")
        if gh_curl "${RAW_BASE}/${path}?_cb=${_cb}" -fsSL -m 30 --connect-timeout 10 --retry 1 \
            -o "$dest" 2>/dev/null; then
            log "  ✓ $fname"
            return 0
        fi
        log "  ✗ $(_t "Download failed: $fname (connection '$CONNECTION_LABEL' unreachable)" "下载失败: $fname（连接 '$CONNECTION_LABEL' 不可达）")"
        return 1
    }
    _fail=0
    dl "files/luci/controller/adguardhome.lua"                     "$DOWNLOAD_DIR/luci/controller/adguardhome.lua" || _fail=1
    dl "files/luci/menu.d/luci-app-adguardhome-dashboard.json"     "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json" || _fail=1
    dl "files/luci/acl.json"                                       "$DOWNLOAD_DIR/luci/acl.json" || _fail=1
    dl "files/view/dashboard.js"                                   "$DOWNLOAD_DIR/view/dashboard.js" || _fail=1
    dl "files/luci/i18n/adguardhome.lmo"                           "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo" || _fail=1
    dl "files/luci/i18n/adguardhome.zh-cn.lmo"                     "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo" || _fail=1
    dl "manifest.json"                                             "$DOWNLOAD_DIR/manifest.json" || _fail=1
    # checksums: use the selected connection only (no silent proxy hop)
    # 校验和清单：仅使用选定的连接（不静默跳代理）
    if gh_curl "${RAW_BASE}/checksums.sha256?_cb=${_cb}" -fsSL -m 30 --connect-timeout 10 --retry 1 \
        -o "$DOWNLOAD_DIR/checksums.sha256" 2>/dev/null; then
        log "  ✓ checksums.sha256"
    else
        log "  $(_t "Warning: checksums.sha256 download failed via '$CONNECTION_LABEL', will use semantic feature check only" "警告: checksums.sha256 经 '$CONNECTION_LABEL' 下载失败，将仅做语义特征校验")"
    fi
    log "$(_t "All files downloaded" "所有文件下载完成")"
    return $_fail
}

# 固定使用所选连接下载；仅当该连接在下载中确实不可用时，才重新测试并交互让用户改选
# （重选会同步重新测连通性并把结果显示在交互界面）。
# FIXEDLY use the chosen connection; only if it proves unusable during download do we re-test
# and let the user re-pick (re-selection re-tests connectivity and shows the results).
do_github_download() {
    _re=0; _max_re=5
    while true; do
        if download_from_github; then return 0; fi
        _re=$((_re + 1))
        if [ "$_re" -ge "$_max_re" ]; then
            log "$(_t "Download failed after $_max_re connection attempts. Aborting." "已尝试 $_max_re 次连接仍下载失败，终止。")"
            rm -rf "$TMPDIR"; exit 1
        fi
        log "$(_t "Selected connection '$CONNECTION_LABEL' failed during download. Re-selecting a connection (re-testing connectivity)..." "所选连接 '$CONNECTION_LABEL' 在下载中失败，正在重新测试并选择连接...")"
        if ! gh_select_connection; then
            log "$(_t "No connection selected; aborting." "未选择连接，终止。")"
            rm -rf "$TMPDIR"; exit 1
        fi
    done
}

if [ -f "$LOCAL_FILES/luci/controller/adguardhome.lua" ]; then
    log "$(_t "Detected local project files ($PROJECT_ROOT)" "检测到本地项目文件 ($PROJECT_ROOT)")"
    if [ "$OFFLINE" = "1" ]; then
        # 离线：直接用本地文件，不再询问（此时「删除并重新下载」没有意义）
        # Offline: use the local files directly; "delete and re-download" is meaningless here.
        SRC_CHOICE=1
    else
        echo ""
        echo "  1) $(_t "Install using local files" "使用本地文件安装")"
        echo "  2) $(_t "Delete local project then re-download from GitHub" "删除本地项目后从 GitHub 重新下载")"
        echo ""
        printf "$(_t "Select [1/2, default 1]: " "请选择 [1/2，默认 1]: ")"
        read_input SRC_CHOICE || true
        SRC_CHOICE=${SRC_CHOICE:-1}
    fi

    if [ "$SRC_CHOICE" = "2" ]; then
        # 防御：管道运行（curl ... | sh）下不存在磁盘上的项目目录，绝不删除任何东西。
        # Guard: under a piped run there is no on-disk project dir — never delete anything.
        if [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT" ]; then
            log "$(_t "Deleting local project directory: $PROJECT_ROOT" "删除本地项目目录: $PROJECT_ROOT")"
            rm -rf "$PROJECT_ROOT"
        fi
        do_github_download
    else
        log "$(_t "Copying local files..." "使用本地文件复制...")"
        cp "$LOCAL_FILES/luci/controller/adguardhome.lua" "$DOWNLOAD_DIR/luci/controller/"
        cp "$LOCAL_FILES/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/"
        cp "$LOCAL_FILES/luci/acl.json" "$DOWNLOAD_DIR/luci/"
        cp "$LOCAL_FILES/view/dashboard.js" "$DOWNLOAD_DIR/view/"
        cp "$LOCAL_FILES/luci/i18n/adguardhome.lmo" "$DOWNLOAD_DIR/luci/i18n/"
        cp "$LOCAL_FILES/luci/i18n/adguardhome.zh-cn.lmo" "$DOWNLOAD_DIR/luci/i18n/"
        cp "$PROJECT_ROOT/manifest.json" "$DOWNLOAD_DIR/manifest.json"
        # 校验清单一并复制：否则本地/离线安装会缺失 sha256 指纹校验，只剩语义特征兜底。
        # Copy the fingerprint manifest too — otherwise local/offline installs silently skip
        # the sha256 check and fall back to semantic feature checks only.
        if [ -f "$PROJECT_ROOT/checksums.sha256" ]; then
            cp "$PROJECT_ROOT/checksums.sha256" "$DOWNLOAD_DIR/checksums.sha256"
        fi
    fi
else
    if [ "$OFFLINE" = "1" ]; then
        log "$(_t "Offline mode but no local files found at: $LOCAL_FILES" "离线模式，但未在以下位置找到本地文件: $LOCAL_FILES")"
        log "$(_t "Make sure you extracted the release package and run: sh scripts/install.sh" "请确认已解压发布包，并执行: sh scripts/install.sh")"
        rm -rf "$TMPDIR"
        exit 1
    fi
    do_github_download
fi

# ── Helper: compute sha256 (falls back to openssl where sha256sum is unavailable) ──
# 辅助：计算 sha256（兼容无 sha256sum 的环境降级到 openssl）
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl sha256 "$1" 2>/dev/null | awk '{print $NF}'
    fi
}

# ── Content verification: sha256 fingerprint (primary) + semantic feature (fallback) ──
# 内容校验：sha256 指纹（主） + 语义特征（兜底）
# Prevent proxies/CDNs from serving a cached old build (ghfast.top once cached an old dashboard.js, dropping the backup feature).
# 防止代理/CDN 返回缓存中的旧版本（曾因 ghfast.top 缓存旧 dashboard.js 导致备份管理缺失）。
# sha256 comparison blocks ANY content diverging from the release manifest (not limited to a missing feature);
# 若 checksums.sha256 不可用，则降级为语义特征校验（fetchBackups / list_backups）。
verify_one() {
    _src="$1"; _f="$2"
    _ok=1
    if [ -f "$DOWNLOAD_DIR/checksums.sha256" ]; then
        _exp=$(grep -F " $_src" "$DOWNLOAD_DIR/checksums.sha256" 2>/dev/null | awk '{print $1}' | head -n1)
        if [ -n "$_exp" ]; then
            _act=$(sha256_of "$_f")
            if [ -n "$_act" ] && [ "$_exp" != "$_act" ]; then
                log "  ✗ $(_t "sha256 mismatch: $_src" "sha256 不匹配: $_src")"
                log "    $(_t "expected: $_exp" "期望: $_exp")"
                log "    $(_t "actual:   $_act" "实际: $_act")"
                log "    → $(_t "likely a cached old build from proxy/CDN" "极可能是代理/CDN 缓存的旧版本")"
                _ok=0
            fi
        fi
    fi
    case "$_src" in
        files/view/dashboard.js)
            grep -q 'fetchBackups' "$_f" 2>/dev/null || { log "  ✗ $(_t "dashboard.js missing backup feature (cached old build?)" "dashboard.js 缺少备份管理功能（代理缓存旧版？）")"; _ok=0; } ;;
        files/luci/controller/adguardhome.lua)
            grep -q 'list_backups' "$_f" 2>/dev/null || { log "  ✗ $(_t "adguardhome.lua missing backup API (cached old build?)" "adguardhome.lua 缺少备份 API（代理缓存旧版？）")"; _ok=0; } ;;
        manifest.json)
            grep -q '"version"' "$_f" 2>/dev/null || { log "  ✗ $(_t "manifest.json missing version field (cached old build?)" "manifest.json 缺少 version 字段（代理缓存旧版？）")"; _ok=0; } ;;
    esac
    # _ok=1 means pass, _ok=0 means fail; shell return 0=success, 1=failure, so invert: pass->0, fail->1.
    # _ok=1 表示通过、_ok=0 表示失败；但 shell 中 return 0=成功、return 1=失败，故需取反：通过→0，失败→1。
    # Never use `return $_ok` directly (it would mark valid files as failed and let bad files through).
    # 切勿直接 `return $_ok`（会导致合法文件被判失败、坏文件被放行）。
    return $((1 - $_ok))
}

log "$(_t "Verifying downloaded files (sha256 fingerprint + semantic features, to block proxy-cached old builds)..." "校验下载文件内容（sha256 指纹 + 语义特征，防止代理缓存旧版本）...")"
_fail=0
verify_one "files/luci/controller/adguardhome.lua"                  "$DOWNLOAD_DIR/luci/controller/adguardhome.lua" || _fail=1
verify_one "files/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json" || _fail=1
verify_one "files/luci/acl.json"                                    "$DOWNLOAD_DIR/luci/acl.json" || _fail=1
verify_one "files/view/dashboard.js"                                "$DOWNLOAD_DIR/view/dashboard.js" || _fail=1
verify_one "files/luci/i18n/adguardhome.lmo"                        "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo" || _fail=1
verify_one "files/luci/i18n/adguardhome.zh-cn.lmo"                 "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo" || _fail=1
verify_one "manifest.json"                                          "$DOWNLOAD_DIR/manifest.json" || _fail=1
if [ "$_fail" = "1" ]; then
    if [ "$OFFLINE" = "1" ]; then
        # 离线：不联网复验。包内文件与自带 checksums.sha256 不一致 = 包已损坏/被改，直接中止。
        # Offline: no re-fetch possible. A mismatch against the bundled manifest means the
        # package is corrupt or tampered with — abort instead of pretending to recover.
        log "$(_t "Content verification failed: files in this package do not match the bundled checksums.sha256" "内容校验失败：包内文件与自带的 checksums.sha256 不一致")"
        log "$(_t "The release package appears corrupt or modified. Please download it again." "发布包可能已损坏或被修改，请重新下载。")"
        rm -rf "$TMPDIR"
        exit 1
    fi
    log "$(_t "Content verification failed (likely proxy/CDN cached an old build); re-fetching while bypassing the mirror cache and re-verifying..." "内容校验失败，疑似代理/CDN 缓存了旧版本，正在绕过镜像缓存重新下载并复验...")"
    _cb=$(date +%s 2>/dev/null || echo 0)
    # re-fetch checksums bypassing the mirror cache (authoritative) / 绕过镜像缓存重新拉取校验和清单（权威）
    gh_curl_fresh "${_gh_raw}/checksums.sha256?_cb=${_cb}" -fsSL -m 30 --connect-timeout 10 --retry 2 \
        -o "$DOWNLOAD_DIR/checksums.sha256" 2>/dev/null \
        || log "  $(_t "Warning: fresh re-fetch of checksums.sha256 failed, re-verifying with the original file" "警告: 绕过缓存拉取 checksums.sha256 失败，仍用原文件复验")"
    # re-fetch all files bypassing the mirror cache / 绕过镜像缓存重新拉取全部文件
    for _line in \
        "files/luci/controller/adguardhome.lua|$DOWNLOAD_DIR/luci/controller/adguardhome.lua" \
        "files/luci/menu.d/luci-app-adguardhome-dashboard.json|$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json" \
        "files/luci/acl.json|$DOWNLOAD_DIR/luci/acl.json" \
        "files/view/dashboard.js|$DOWNLOAD_DIR/view/dashboard.js" \
        "files/luci/i18n/adguardhome.lmo|$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo" \
        "files/luci/i18n/adguardhome.zh-cn.lmo|$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo" \
        "manifest.json|$DOWNLOAD_DIR/manifest.json" ; do
        _fp=${_line%%|*}; _fd=${_line##*|}
        if gh_curl_fresh "${_gh_raw}/${_fp}?_cb=${_cb}" -fsSL -m 30 --connect-timeout 10 --retry 2 \
            -o "$_fd" 2>/dev/null; then
            log "  ↻ $(_t "re-downloaded bypassing cache: $(basename "$_fd")" "已绕过缓存重新下载: $(basename "$_fd")")"
        else
            log "  $(_t "Warning: fresh re-download failed (kept original): $(basename "$_fd")" "警告: 绕过缓存重新下载失败（保留原文件）: $(basename "$_fd")")"
        fi
    done
    # re-verify / 复验
    _fail=0
    verify_one "files/luci/controller/adguardhome.lua"                  "$DOWNLOAD_DIR/luci/controller/adguardhome.lua" || _fail=1
    verify_one "files/luci/menu.d/luci-app-adguardhome-dashboard.json" "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json" || _fail=1
    verify_one "files/luci/acl.json"                                    "$DOWNLOAD_DIR/luci/acl.json" || _fail=1
    verify_one "files/view/dashboard.js"                                "$DOWNLOAD_DIR/view/dashboard.js" || _fail=1
    verify_one "files/luci/i18n/adguardhome.lmo"                        "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo" || _fail=1
    verify_one "files/luci/i18n/adguardhome.zh-cn.lmo"                 "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo" || _fail=1
    verify_one "manifest.json"                                          "$DOWNLOAD_DIR/manifest.json" || _fail=1
    if [ "$_fail" = "1" ]; then
        log "$(_t "Content verification failed: direct re-verification still did not pass" "内容校验失败：直连复验仍未通过")"
        log "$(_t "Fix: check your network and retry; or manually download the release package from https://github.com/${REPO}" "解决: 请检查网络后重试；或手动从 https://github.com/${REPO} 下载发布包安装")"
        rm -rf "$TMPDIR"
        exit 1
    fi
    log "  ✓ $(_t "Passed direct re-verification (proxy/CDN cached old build excluded)" "已通过直连复验（已排除代理/CDN 缓存的旧版本）")"
fi
log "  ✓ $(_t "Content verification passed (sha256 fingerprint + semantic features)" "内容校验通过（sha256 指纹 + 语义特征）")"

# ── Back up currently-installed files (kept consistent with the panel-upgrade two-phase commit) ──
# 备份当前安装的文件（与面板升级的两阶段提交保持一致）
TS=$(date '+%Y%m%d_%H%M%S' 2>/dev/null || date +%s 2>/dev/null || echo 0)

# Backup targets: the existing files that map exactly to the cleanup/deploy below
# 备份目标：与下面清理/部署完全对应的现有文件
BACKUP_PAIRS="
/usr/lib/lua/luci/controller/adguardhome.lua|controller/adguardhome.lua
/usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json|menu.d/luci-app-adguardhome-dashboard.json
/usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json|acl.d/luci-app-adguardhome-dashboard.json
/usr/lib/lua/luci/i18n/adguardhome.lmo|i18n/adguardhome.lmo
/usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo|i18n/adguardhome.zh-cn.lmo
/www/luci-static/resources/view/adguardhome/dashboard.js|view/adguardhome/dashboard.js
/usr/share/adguardhome-dashboard/manifest.json|adguardhome-dashboard/manifest.json
"

# The backup type must describe WHAT is being overwritten. A backup directory is only ever
# populated when panel files already exist, i.e. this run is a panel UPGRADE — a fresh install
# has nothing to copy (it only logs "Fresh install detected" below). Hard-coding "install" made
# every upgrade show up as an install in the panel's backup manager.
# 备份类型必须描述「被覆盖的是什么」：只有已存在面板文件时才会写入备份目录，也就是本次运行
# 本质是一次面板「升级」（全新安装无内容可备份，只打印下面的 "Fresh install detected"）。
# 此前固定命名 install，导致每次升级在面板「备份管理」里都显示为「安装」。
_existing_panel=0
for pair in $BACKUP_PAIRS; do
    _p_exist=$(echo "$pair" | cut -d'|' -f1)
    if [ -f "$_p_exist" ]; then _existing_panel=$((_existing_panel + 1)); fi
done
if [ "$_existing_panel" -gt 0 ]; then
    BACKUP_DIR="/root/agh_backup_dashboard_${TS}"
else
    BACKUP_DIR="/root/agh_backup_install_${TS}"
fi

_backup_count=0
for pair in $BACKUP_PAIRS; do
    src=$(echo "$pair" | cut -d'|' -f1)
    rel=$(echo "$pair" | cut -d'|' -f2)
    if [ -f "$src" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        cp -a "$src" "$BACKUP_DIR/$rel" 2>/dev/null || cp "$src" "$BACKUP_DIR/$rel"
        _backup_count=$((_backup_count + 1))
        log "  $(_t "backed up: $src  ->  $BACKUP_DIR/$rel" "备份: $src  ->  $BACKUP_DIR/$rel")"
    fi
done

# Note: install does NOT back up the AdGuardHome core binary; core rollback is handled separately by AGH's official script and the core-upgrade flow
# 注意：install 不备份 AdGuardHome 核心二进制，核心安装/升级的回滚由 AGH 官方安装脚本和核心升级流程单独管理

if [ "$_backup_count" -gt 0 ]; then
    log "$(_t "Panel upgrade detected: backed up $_backup_count existing panel file(s) to: $BACKUP_DIR" "检测到面板升级：已备份 $_backup_count 个现有面板文件至: $BACKUP_DIR")"

    # Generate restore.sh: one-click restore to the pre-install state (panel files only, no AGH core)
    # 生成 restore.sh：用户可一键恢复到本次安装前的状态（仅面板文件，不含 AGH 核心）
    cat > "$BACKUP_DIR/restore.sh" <<EOF
#!/bin/sh
# One-click restore of the LuCI Dashboard to its pre-install state / 一键恢复 LuCI Dashboard 到安装前的状态
# Backup dir: $BACKUP_DIR / 备份目录: $BACKUP_DIR
# Restore panel files only; does not touch the AdGuardHome core binary / 仅恢复面板文件，不涉及 AdGuardHome 核心二进制
set -u
BACKUP_DIR='$BACKUP_DIR'

restore_one() {
    r_rel="\$1"
    r_dst="\$2"
    r_src="\$BACKUP_DIR/\$r_rel"
    if [ -f "\$r_src" ]; then
        mkdir -p "\$(dirname "\$r_dst")"
        cp -a "\$r_src" "\$r_dst" 2>/dev/null || cp "\$r_src" "\$r_dst"
        chmod 644 "\$r_dst" 2>/dev/null
        echo "  restored: \$r_dst"
    else
        echo "  (skip) no backup: \$r_rel"
    fi
}

echo "=== Restoring LuCI Dashboard from \$BACKUP_DIR ==="

echo ">> Restoring panel files..."
restore_one 'controller/adguardhome.lua'                                   '/usr/lib/lua/luci/controller/adguardhome.lua'
restore_one 'menu.d/luci-app-adguardhome-dashboard.json'                  '/usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json'
restore_one 'acl.d/luci-app-adguardhome-dashboard.json'                   '/usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json'
restore_one 'i18n/adguardhome.lmo'                                         '/usr/lib/lua/luci/i18n/adguardhome.lmo'
restore_one 'i18n/adguardhome.zh-cn.lmo'                                   '/usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo'
restore_one 'view/adguardhome/dashboard.js'                                '/www/luci-static/resources/view/adguardhome/dashboard.js'
restore_one 'adguardhome-dashboard/manifest.json'                      '/usr/share/adguardhome-dashboard/manifest.json'

echo ">> Clearing cache and restarting services..."
rm -rf /tmp/luci-* 2>/dev/null
rm -f /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null
find /tmp -name '*.luac' -delete 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null

echo "=== Restore complete (panel files only; AGH core untouched) ==="
echo "Please refresh your browser to see the changes."
EOF
    chmod 755 "$BACKUP_DIR/restore.sh" 2>/dev/null
    log "$(_t "Restore script generated: $BACKUP_DIR/restore.sh" "恢复脚本已生成: $BACKUP_DIR/restore.sh")"
else
    log "$(_t "Fresh install detected: no existing panel files to back up" "本次安装为全新部署，无旧文件可备份")"
fi

# ── Clean up old-version files ── / 清理旧版本文件
log "$(_t "Cleaning old-version files..." "清理旧版本文件...")"
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

# ── Create target directories ── / 创建目标目录
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /usr/lib/lua/luci/i18n
mkdir -p /www/luci-static/resources/view/adguardhome
mkdir -p /usr/share/adguardhome-dashboard

# ── Deploy files ── / 部署文件
log "$(_t "Deploying files to system directories..." "部署文件到系统目录...")"
cp "$DOWNLOAD_DIR/luci/controller/adguardhome.lua"                     /usr/lib/lua/luci/controller/adguardhome.lua
cp "$DOWNLOAD_DIR/luci/menu.d/luci-app-adguardhome-dashboard.json"     /usr/share/luci/menu.d/
cp "$DOWNLOAD_DIR/luci/acl.json"                                       /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json
cp "$DOWNLOAD_DIR/view/dashboard.js"                                   /www/luci-static/resources/view/adguardhome/dashboard.js
cp "$DOWNLOAD_DIR/luci/i18n/adguardhome.lmo"                           /usr/lib/lua/luci/i18n/
cp "$DOWNLOAD_DIR/luci/i18n/adguardhome.zh-cn.lmo"                     /usr/lib/lua/luci/i18n/
cp "$DOWNLOAD_DIR/manifest.json"                                       /usr/share/adguardhome-dashboard/manifest.json

# ── Set permissions ── / 设置权限
chmod 644 /usr/lib/lua/luci/controller/adguardhome.lua \
          /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json \
          /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json \
          /usr/lib/lua/luci/i18n/adguardhome.lmo \
          /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo \
          /usr/share/adguardhome-dashboard/manifest.json \
          /www/luci-static/resources/view/adguardhome/dashboard.js

# ── Clear cache & restart services ── / 清除缓存 & 重启服务
log "$(_t "Clearing LuCI cache and restarting services..." "清除 LuCI 缓存并重启服务...")"
rm -rf /tmp/luci-* 2>/dev/null || true
rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache.* 2>/dev/null || true
find /tmp -name '*.luac' -delete 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

# ── Deployment verification ── / 部署验证
log "$(_t "Verifying deployed files..." "验证部署文件...")"
if grep -q 'loadc' /usr/lib/lua/luci/controller/adguardhome.lua 2>/dev/null; then
    log "$(_t "Warning: controller.lua still contains old code (i18n.loadc)" "⚠ 警告: controller.lua 仍包含旧代码 (i18n.loadc)")"
    log "  $(_t "Possibly GitHub CDN cache not refreshed. Try:" "可能是 GitHub CDN 缓存未刷新，请尝试以下方法:")"
    log "  1) $(_t "wait a few minutes then re-run the installer" "等待几分钟后重新运行安装")"
    log "  2) $(_t "use a proxy: GITHUB_PROXY=https://ghfast.top/ sh install.sh (mirror, CN only) | GITHUB_PROXY=proxy|http://127.0.0.1:7890 sh install.sh (full proxy)" "使用代理: GITHUB_PROXY=https://ghfast.top/ sh install.sh（镜像源，仅中国大陆）| GITHUB_PROXY=proxy|http://127.0.0.1:7890 sh install.sh（全量代理）")"
    log "  3) $(_t "verify manually: curl -fsSL '${RAW_BASE}/files/luci/controller/adguardhome.lua' | grep loadc" "手动验证: curl -fsSL '${RAW_BASE}/files/luci/controller/adguardhome.lua' | grep loadc")"
else
    log "  ✓ $(_t "controller.lua verified" "controller.lua 验证通过")"
fi
if grep -q 'fetchBackups' /www/luci-static/resources/view/adguardhome/dashboard.js 2>/dev/null; then
    log "  ✓ $(_t "dashboard.js verified (includes backup management)" "dashboard.js 验证通过（含备份管理）")"
else
    log "$(_t "Warning: dashboard.js missing backup management (possibly a cached old build)" "⚠ 警告: dashboard.js 缺少备份管理功能（可能是代理缓存的旧版本）")"
    log "  $(_t "Re-pull manually: curl -fsSL '${RAW_BASE}/files/view/dashboard.js' -o /www/luci-static/resources/view/adguardhome/dashboard.js" "手动重拉: curl -fsSL '${RAW_BASE}/files/view/dashboard.js' -o /www/luci-static/resources/view/adguardhome/dashboard.js")"
fi
if [ -f /usr/share/adguardhome-dashboard/manifest.json ] && grep -q '"version"' /usr/share/adguardhome-dashboard/manifest.json 2>/dev/null; then
    log "  ✓ $(_t "manifest.json verified" "manifest.json 验证通过")"
else
    log "$(_t "Warning: manifest.json not deployed or missing version field" "⚠ 警告: manifest.json 未部署或缺少 version 字段")"
fi

rm -rf "$TMPDIR"

echo ""
echo "========================================================="
echo " $(_t "Installation complete!" "安装完成！")"
echo ""
echo " $(_t "AdGuard Home core:" "AdGuard Home 核心:")"
[ -f "$AGH_BIN" ] && echo "   ✓ $AGH_BIN" || echo "   ✗ $(_t "not installed" "未安装")"
echo ""
echo " $(_t "LuCI Dashboard:" "LuCI Dashboard:")"
echo "   Controller:  /usr/lib/lua/luci/controller/adguardhome.lua"
echo "   Menu:        /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json"
echo "   ACL:         /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json"
echo "   JS View:     /www/luci-static/resources/view/adguardhome/dashboard.js"
echo "   i18n (en):   /usr/lib/lua/luci/i18n/adguardhome.lmo"
echo "   i18n (zh):   /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo"
echo ""
if [ "$_backup_count" -gt 0 ] 2>/dev/null; then
    echo " $(_t "Backup info:" "备份信息:")"
    echo "   $(_t "Backup dir:   " "备份目录:   ")$BACKUP_DIR"
    echo "   $(_t "Backup files: " "备份文件数: ")$_backup_count"
    echo "   $(_t "Restore script:" "恢复脚本:   ")$BACKUP_DIR/restore.sh"
    echo ""
    echo "   $(_t "To restore to the pre-install state:" "恢复到安装前状态:")"
    echo "     sh $BACKUP_DIR/restore.sh"
    echo ""
    echo "   $(_t "Or via panel → Services → AdGuard Home → Backup Management" "或在面板 → 服务 → AdGuard Home → 备份管理 中操作")"
fi
echo ""
echo " $(_t "Please refresh your browser → LuCI → Services → AdGuard Home" "请刷新浏览器 → LuCI → 服务 → AdGuard Home")"
echo "========================================================="
