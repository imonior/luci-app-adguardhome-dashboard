module("luci.controller.adguardhome", package.seeall)

local util = require "luci.util"
local fs = require "nixio.fs"
local http = require "luci.http"
local i18n = require "luci.i18n"

local BIN_PATHS = {
    "/opt/AdGuardHome/AdGuardHome",
    "/usr/bin/AdGuardHome",
    "/usr/local/bin/AdGuardHome"
}

local INIT_SCRIPTS = {
    "/etc/init.d/AdGuardHome",
    "/etc/init.d/adguardhome"
}

local CONFIG_PATHS = {
    "/opt/AdGuardHome/AdGuardHome.yaml",
    "/etc/AdGuardHome.yaml",
    "/etc/adguardhome/adguardhome.yaml"
}

local UPGRADE_LOG = "/tmp/agh_upgrade.log"
local PROXY_CONF = "/etc/adguardhome-dashboard.proxy"

-- 代理列表: 安装时写入的配置优先，否则使用内置列表
local PROXY_LIST = {}

local function load_proxies()
    -- 读取安装时保存的代理配置
    if fs.access(PROXY_CONF) then
        local content = fs.readfile(PROXY_CONF)
        if content then
            local saved = content:match("proxy%s*=%s*(%S+)")
            if saved and saved ~= "" then
                PROXY_LIST[1] = saved
            end
        end
    end
    -- 内置代理兜底
    local builtins = {
        "https://ghfast.top/",
        "https://gh-proxy.com/",
        "https://kkgithub.com/"
    }
    for _, p in ipairs(builtins) do
        local found = false
        for _, existing in ipairs(PROXY_LIST) do
            if existing == p then found = true; break end
        end
        if not found then
            PROXY_LIST[#PROXY_LIST + 1] = p
        end
    end
end

local function gh_url(raw_url)
    if PROXY_LIST[1] and PROXY_LIST[1] ~= "" then
        return PROXY_LIST[1] .. raw_url
    end
    return raw_url
end

local function try_with_proxies(url)
    -- 如果已配置代理，优先走代理（避免直连超时浪费 10 秒）
    if PROXY_LIST[1] and PROXY_LIST[1] ~= "" then
        for _, proxy in ipairs(PROXY_LIST) do
            local proxied = util.exec("curl -m 10 -fsSL '" .. proxy .. url .. "' 2>/dev/null")
            if proxied and #proxied > 10 then
                return proxied
            end
        end
    else
        -- 无配置代理时先尝试直连
        local direct = util.exec("curl -m 10 -fsSL '" .. url .. "' 2>/dev/null")
        if direct and #direct > 10 then
            return direct
        end
        -- 直连失败则逐个尝试内置代理
        for _, proxy in ipairs(PROXY_LIST) do
            local proxied = util.exec("curl -m 10 -fsSL '" .. proxy .. url .. "' 2>/dev/null")
            if proxied and #proxied > 10 then
                return proxied
            end
        end
    end
    return ""
end

local function find_binary()
    for _, p in ipairs(BIN_PATHS) do
        if fs.access(p, 'r') then
            return p
        end
    end
    local which_out = util.exec("which AdGuardHome 2>/dev/null")
    which_out = which_out and which_out:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if which_out ~= "" and fs.access(which_out, 'r') then
        return which_out
    end
    return nil
end

local function find_init_script()
    for _, p in ipairs(INIT_SCRIPTS) do
        if fs.access(p) then
            return p
        end
    end
    return nil
end

function index()
    -- 加载 i18n 翻译目录（确保 JS view 的 _() 函数能获取翻译）
    i18n.loadc("adguardhome")

    -- 菜单入口由 menu.d/luci-app-adguardhome-dashboard.json 注册（LuCI 2.0 标准）
    -- 此处仅注册 API 子路由
    entry({"admin", "services", "adguardhome", "status"}, call("get_status"), nil, true)
    entry({"admin", "services", "adguardhome", "action"}, call("do_action"), nil, true)
    entry({"admin", "services", "adguardhome", "check_update"}, call("check_update"), nil, true)
    entry({"admin", "services", "adguardhome", "upgrade"}, call("do_upgrade"), nil, true)
    entry({"admin", "services", "adguardhome", "log"}, call("get_log"), nil, true)
end

function get_status()
    local status = {
        installed = false,
        service_installed = false,
        running = false,
        pid = nil,
        version = "",
        port = 3000,
        bin_path = "",
        init_script = ""
    }

    local bin_path = find_binary()
    local init_script = find_init_script()

    status.installed = bin_path ~= nil
    status.service_installed = init_script ~= nil
    status.bin_path = bin_path or ""
    status.init_script = init_script or ""

    local pid_out = util.exec("pgrep -f 'AdGuardHome' 2>/dev/null")
    local pid = pid_out and pid_out:match("(%d+)") or nil
    if pid then
        status.running = true
        status.pid = tonumber(pid)
    elseif init_script then
        local svc_out = util.exec(init_script .. " status 2>&1")
        if svc_out and svc_out:match("[Rr]unning") then
            status.running = true
        end
    end

    if bin_path then
        local ver = util.exec(bin_path .. " --version 2>&1")
        if ver then
            local v = ver:match("version v?([%d%.]+)")
            if v then
                status.version = "v" .. v
            else
                v = ver:match("([%d%.]+)")
                if v then
                    status.version = "v" .. v
                end
            end
        end
    end

    for _, p in ipairs(CONFIG_PATHS) do
        if fs.access(p) then
            local content = fs.readfile(p)
            if content then
                -- AdGuardHome.yaml: web admin 端口在 clients 段为 web_port，
                -- 通用 port: 可能是 DNS (53) 等其他端口，优先匹配 web_port
                local port = content:match("web_port:%s*(%d+)")
                if not port then
                    port = content:match("port:%s*(%d+)")
                end
                if port then
                    status.port = tonumber(port)
                    break
                end
            end
        end
    end

    http.prepare_content("application/json")
    http.write_json(status)
end

function do_action()
    local action = http.formvalue("action")

    if action ~= "start" and action ~= "stop" and action ~= "restart" and action ~= "install_service" then
        http.prepare_content("application/json")
        http.write_json({ success = false, error = "invalid action" })
        return
    end

    local bin_path = find_binary()
    local init_script = find_init_script()
    local cmd

    if action == "install_service" then
        if bin_path then
            cmd = bin_path .. " -s install"
        else
            http.prepare_content("application/json")
            http.write_json({ success = false, error = "binary not found" })
            return
        end
    else
        if init_script then
            cmd = init_script .. " " .. action
        elseif bin_path then
            cmd = bin_path .. " -s " .. action
        else
            http.prepare_content("application/json")
            http.write_json({ success = false, error = "no init script or binary found" })
            return
        end
    end

    local result = util.exec(cmd .. " 2>&1")
    http.prepare_content("application/json")
    http.write_json({ success = true, output = result })
end

function check_update()
    load_proxies()
    local output = try_with_proxies("https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest")
    local latest = ""
    if output and #output > 0 then
        latest = output:match('"tag_name"%s*:%s*"(.-)"') or ""
    end
    http.prepare_content("application/json")
    http.write_json({ latest_version = latest })
end

function do_upgrade()
    load_proxies()
    local install_url = gh_url("https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh")
    os.execute("echo '=== AdGuardHome 升级任务开始 ===' > " .. UPGRADE_LOG)
    os.execute("curl -fsSL '" .. install_url .. "' | sh >> " .. UPGRADE_LOG .. " 2>&1 &")
    http.prepare_content("application/json")
    http.write_json({ success = true })
end

function get_log()
    local content = ""

    -- 优先返回升级日志
    if fs.access(UPGRADE_LOG) then
        local data = fs.readfile(UPGRADE_LOG)
        if data and #data > 100 then
            content = data
        end
    end

    -- 无升级日志则返回系统日志
    if content == "" then
        content = util.exec("logread -e AdGuardHome 2>/dev/null | tail -n 30")
        if not content or content == "" then
            content = util.exec("logger -s -t AdGuardHome 2>/dev/null; logread | grep -i adguard | tail -n 30 2>/dev/null")
        end
    end

    if not content or content == "" then
        content = "No logs available"
    end

    http.prepare_content("application/json")
    http.write_json({ content = content })
end
