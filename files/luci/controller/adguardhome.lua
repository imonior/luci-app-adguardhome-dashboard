module("luci.controller.adguardhome", package.seeall)

local util = require "luci.util"
local fs = require "nixio.fs"
local http = require "luci.http"

local BIN_PATH = "/opt/AdGuardHome/AdGuardHome"
local INIT_SCRIPT = "/etc/init.d/AdGuardHome"
local UPGRADE_LOG = "/tmp/agh_upgrade.log"

local CONFIG_PATHS = {
    "/opt/AdGuardHome/AdGuardHome.yaml",
    "/etc/AdGuardHome.yaml",
    "/etc/adguardhome/adguardhome.yaml"
}

function index()
    local e
    e = entry({"admin", "services", "adguardhome", "status"}, call("get_status"))
    e.leaf = true
    e = entry({"admin", "services", "adguardhome", "action"}, call("do_action"))
    e.leaf = true
    e = entry({"admin", "services", "adguardhome", "check_update"}, call("check_update"))
    e.leaf = true
    e = entry({"admin", "services", "adguardhome", "upgrade"}, call("do_upgrade"))
    e.leaf = true
    e = entry({"admin", "services", "adguardhome", "log"}, call("get_log"))
    e.leaf = true
end

function get_status()
    local status = {
        installed = false,
        service_installed = false,
        running = false,
        pid = nil,
        version = "未知",
        port = 3000
    }

    status.installed = fs.access(BIN_PATH) and true or false
    status.service_installed = fs.access(INIT_SCRIPT) and true or false

    local pid_out = util.exec("pgrep -f AdGuardHome 2>/dev/null")
    local pid = pid_out and pid_out:match("(%d+)") or nil
    if pid then
        status.running = true
        status.pid = tonumber(pid)
    else
        local svc_out = util.exec(INIT_SCRIPT .. " status 2>&1")
        if svc_out and svc_out:match("running") then
            status.running = true
        end
    end

    if status.installed then
        local ver = util.exec(BIN_PATH .. " --version 2>&1")
        if ver then
            local v = ver:match("version v?([%d%.]+)")
            if v then
                status.version = "v" .. v
            end
        end
    end

    for _, p in ipairs(CONFIG_PATHS) do
        if fs.access(p) then
            local content = fs.readfile(p)
            if content then
                local port = content:match("port:%s*(%d+)")
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

    local cmd
    if action == "install_service" then
        cmd = BIN_PATH .. " -s install"
    else
        cmd = INIT_SCRIPT .. " " .. action
    end

    local result = util.exec(cmd .. " 2>&1")
    http.prepare_content("application/json")
    http.write_json({ success = true, output = result })
end

function check_update()
    local output = util.exec("curl -m 8 -fsSL 'https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest' 2>&1")
    local latest = "未知"
    if output then
        latest = output:match('"tag_name"%s*:%s*"(.-)"') or "未知"
    end
    http.prepare_content("application/json")
    http.write_json({ latest_version = latest })
end

function do_upgrade()
    os.execute("echo '=== AdGuardHome 升级任务开始 ===' > " .. UPGRADE_LOG)
    os.execute("curl -fsSL 'https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh' | sh >> " .. UPGRADE_LOG .. " 2>&1 &")
    http.prepare_content("application/json")
    http.write_json({ success = true })
end

function get_log()
    local log_data = ""

    if fs.access(UPGRADE_LOG) then
        local stat = fs.stat(UPGRADE_LOG)
        if stat and stat.size > 100 then
            log_data = fs.readfile(UPGRADE_LOG) or ""
        end
    end

    if log_data == "" then
        log_data = util.exec("logread -e AdGuardHome 2>/dev/null | tail -n 30")
        if log_data == "" then
            log_data = "暂无相关运行日志 (若刚启动，请等待几秒后刷新)..."
        end
    end

    http.prepare_content("application/json")
    http.write_json({ log = log_data })
end
