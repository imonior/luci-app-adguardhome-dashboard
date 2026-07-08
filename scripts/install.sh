#!/bin/sh
#=============================================================================
# 🧩 AdGuardHome LuCI Dashboard - 完全自包含安装器 v2.0
#=============================================================================
set -e

log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    echo "[$ts] $1"
}

log "=== AdGuardHome LuCI Dashboard 安装开始 ==="

mkdir -p /usr/share/luci/controller /usr/share/rpcd/acl.d /usr/lib/lua/luci/i18n /www/luci-static/resources/view/adguardhome

cat > /usr/share/luci/controller/adguardhome.lua << 'LUAEOF'
module("luci.controller.adguardhome", package.seeall)

local util = require "luci.util"
local fs = require "nixio.fs"
local http = require "luci.http"

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
    entry({"admin", "services", "adguardhome"}, template("adguardhome/dashboard"), _("AdGuard Home"), 60)
    entry({"admin", "services", "adguardhome", "status"}, call("get_status"), nil, true)
    entry({"admin", "services", "adguardhome", "action"}, call("do_action"), nil, true)
    entry({"admin", "services", "adguardhome", "check_update"}, call("check_update"), nil, true)
    entry({"admin", "services", "adguardhome", "upgrade"}, call("do_upgrade"), nil, true)
end

function get_status()
    local status = {
        installed = false,
        service_installed = false,
        running = false,
        pid = nil,
        version = "",
        port = 3000,
        bin_path = ""
    }

    local bin_path = find_binary()
    local init_script = find_init_script()

    status.installed = bin_path ~= nil
    status.service_installed = init_script ~= nil
    status.bin_path = bin_path or ""

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
    local output = util.exec("curl -m 8 -fsSL 'https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest' 2>&1")
    local latest = ""
    if output then
        latest = output:match('"tag_name"%s*:%s*"(.-)"') or ""
    end
    http.prepare_content("application/json")
    http.write_json({ latest_version = latest })
end

function do_upgrade()
    os.execute("echo '=== AdGuardHome 升级任务开始 ===' > /tmp/agh_upgrade.log")
    os.execute("curl -fsSL 'https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh' | sh >> /tmp/agh_upgrade.log 2>&1 &")
    http.prepare_content("application/json")
    http.write_json({ success = true })
end
LUAEOF

cat > /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json << 'EOF'
{
    "luci-app-adguardhome-dashboard": {
        "description": "AdGuardHome Dashboard ACL",
        "read": { "ubus": { "*": [ "*" ] } },
        "write": { "ubus": { "*": [ "*" ] }, "uci": [ "*" ] }
    }
}
EOF

log "编译 i18n 翻译文件..."
lua << 'LUAEOF'
local fs = require('nixio.fs')

local function xor(a, b)
    local res = 0
    local mask = 1
    while a > 0 or b > 0 do
        if (a % 2) ~= (b % 2) then res = res + mask end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        mask = mask * 2
    end
    return res
end

local function fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = xor(h, s:byte(i))
        h = (h * 16777619) % 4294967296
    end
    return h
end

local function compile(t, out_path)
    local entries = {}
    for k, v in pairs(t) do table.insert(entries, {k, v}) end

    local strings = ''
    local index = {}
    for _, e in ipairs(entries) do
        local offset = #strings
        strings = strings .. e[2] .. '\0'
        table.insert(index, {fnv1a(e[1]), offset, #e[2]})
    end

    table.sort(index, function(a, b) return a[1] < b[1] end)

    local function pack32(n)
        return string.char((n>>24)&0xff, (n>>16)&0xff, (n>>8)&0xff, n&0xff)
    end

    local lmo = 'LMO\0' .. pack32(#index)
    for _, entry in ipairs(index) do
        lmo = lmo .. pack32(entry[1]) .. pack32(entry[2]) .. pack32(entry[3])
    end
    lmo = lmo .. strings

    fs.writefile(out_path, lmo)
end

compile({
    ["AdGuard Home"] = "AdGuard Home",
    ["核心部署"] = "Core Deployment",
    ["核心版本"] = "Version",
    ["服务状态"] = "Service Status",
    ["运行状态"] = "Running Status",
    ["Web 端口"] = "Web Port",
    ["管理入口"] = "Management",
    ["服务控制台"] = "Service Console",
    ["启动服务"] = "Start",
    ["重启服务"] = "Restart",
    ["停止服务"] = "Stop",
    ["注册系统服务"] = "Register Service",
    ["版本更新"] = "Version Update",
    ["当前版本"] = "Current Version",
    ["最新版本"] = "Latest Version",
    ["检查更新"] = "Check Update",
    ["一键升级"] = "Upgrade",
    ["未发现程序"] = "Not Found",
    ["请运行官网命令安装"] = "Please install from official source",
    ["未知"] = "Unknown",
    ["未注册服务"] = "Service Not Registered",
    ["使用二进制保底控制"] = "Binary Control",
    ["已停止"] = "Stopped",
    ["运行中"] = "Running",
    ["服务未启动"] = "Service Not Started",
    ["检查失败"] = "Check Failed",
    ["未检查"] = "Not Checked",
    ["AdGuardHome 控制中心"] = "AdGuard Home Control Center",
    ["实时状态监控"] = "Real-time Monitoring",
    ["服务控制"] = "Service Control",
    ["实时仪表盘"] = "Real-time Dashboard",
    ["当前控制模式"] = "Current Control Mode",
    ["AdGuardHome 二进制直接控制"] = "Binary Direct Control",
    ["命令保底"] = "Fallback",
    ["● 正在运行"] = "● Running",
    ["■ 已停止"] = "■ Stopped",
    ["✔ 已下载"] = "✔ Downloaded",
    ["✔ 已安装系统服务 | ✔ 开机自启已注册"] = "✔ Service Installed | ✔ Boot Enabled",
    ["Init.d 系统服务级调用"] = "Init.d Service Control",
    ["操作执行成功"] = "Operation Successful",
    ["操作失败: "] = "Operation Failed: ",
    ["未知错误"] = "Unknown Error",
    ["执行异常: "] = "Execution Error: ",
    ["检查中..."] = "Checking...",
    ["确认升级"] = "Confirm Upgrade",
    ["将下载并安装最新版本的 AdGuard Home 核心。升级期间服务可能短暂中断。"] = "Will download and install the latest AdGuard Home version. Service may be temporarily interrupted during upgrade.",
    ["取消"] = "Cancel",
    ["确认升级"] = "Confirm Upgrade",
    ["升级任务已启动，状态将自动刷新"] = "Upgrade task started, status will refresh automatically",
    ["升级任务启动失败"] = "Upgrade task failed to start"
}, '/usr/lib/lua/luci/i18n/adguardhome.lmo')

compile({
    ["AdGuard Home"] = "AdGuard Home",
    ["核心部署"] = "核心部署",
    ["核心版本"] = "核心版本",
    ["服务状态"] = "服务状态",
    ["运行状态"] = "运行状态",
    ["Web 端口"] = "Web 端口",
    ["管理入口"] = "管理入口",
    ["服务控制台"] = "服务控制台",
    ["启动服务"] = "启动服务",
    ["重启服务"] = "重启服务",
    ["停止服务"] = "停止服务",
    ["注册系统服务"] = "注册系统服务",
    ["版本更新"] = "版本更新",
    ["当前版本"] = "当前版本",
    ["最新版本"] = "最新版本",
    ["检查更新"] = "检查更新",
    ["一键升级"] = "一键升级",
    ["未发现程序"] = "未发现程序",
    ["请运行官网命令安装"] = "请运行官网命令安装",
    ["未知"] = "未知",
    ["未注册服务"] = "未注册服务",
    ["使用二进制保底控制"] = "使用二进制保底控制",
    ["已停止"] = "已停止",
    ["运行中"] = "运行中",
    ["服务未启动"] = "服务未启动",
    ["检查失败"] = "检查失败",
    ["未检查"] = "未检查",
    ["AdGuardHome 控制中心"] = "AdGuardHome 控制中心",
    ["实时状态监控"] = "实时状态监控",
    ["服务控制"] = "服务控制",
    ["实时仪表盘"] = "实时仪表盘",
    ["当前控制模式"] = "当前控制模式",
    ["AdGuardHome 二进制直接控制"] = "AdGuardHome 二进制直接控制",
    ["命令保底"] = "命令保底",
    ["● 正在运行"] = "● 正在运行",
    ["■ 已停止"] = "■ 已停止",
    ["✔ 已下载"] = "✔ 已下载",
    ["✔ 已安装系统服务 | ✔ 开机自启已注册"] = "✔ 已安装系统服务 | ✔ 开机自启已注册",
    ["Init.d 系统服务级调用"] = "Init.d 系统服务级调用",
    ["操作执行成功"] = "操作执行成功",
    ["操作失败: "] = "操作失败: ",
    ["未知错误"] = "未知错误",
    ["执行异常: "] = "执行异常: ",
    ["检查中..."] = "检查中...",
    ["确认升级"] = "确认升级",
    ["将下载并安装最新版本的 AdGuard Home 核心。升级期间服务可能短暂中断。"] = "将下载并安装最新版本的 AdGuard Home 核心。升级期间服务可能短暂中断。",
    ["取消"] = "取消",
    ["确认升级"] = "确认升级",
    ["升级任务已启动，状态将自动刷新"] = "升级任务已启动，状态将自动刷新",
    ["升级任务启动失败"] = "升级任务启动失败"
}, '/usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo')

print('.lmo files created')
LUAEOF

cat > /www/luci-static/resources/view/adguardhome/dashboard.js << 'EOF'
'use strict';
'require view';
'require ui';
'require request';

return view.extend({
    statusData: null,
    pollInterval: null,
    rootNode: null,

    versionEl: null,
    runningEl: null,
    portEl: null,
    urlEl: null,
    latestVersionEl: null,
    upgradeBtn: null,
    checkUpdateBtn: null,

    fetchStatus: function() {
        return request.get(L.url('admin/services/adguardhome/status')).then(function(res) {
            return res.json();
        });
    },

    sendAction: function(action) {
        return request.post(L.url('admin/services/adguardhome/action'), { action: action }).then(function(res) {
            return res.json();
        });
    },

    fetchUpdate: function() {
        return request.get(L.url('admin/services/adguardhome/check_update')).then(function(res) {
            return res.json();
        });
    },

    sendUpgrade: function() {
        return request.post(L.url('admin/services/adguardhome/upgrade')).then(function(res) {
            return res.json();
        });
    },

    load: function() {
        var self = this;
        return Promise.all([
            self.fetchStatus().catch(function() {
                return { installed: false, service_installed: false, running: false, version: _('未知'), port: 3000 };
            })
        ]);
    },

    render: function(data) {
        var status = data[0];
        this.statusData = status;

        var isBinInstalled = !!status.installed;
        var isServiceInstalled = !!status.service_installed;
        var isRunning = !!status.running;
        var pid = status.pid || '—';
        var versionStr = status.version || _('未知');
        var port = status.port || 3000;
        var targetUrl = isRunning
            ? window.location.protocol + '//' + window.location.hostname + ':' + port
            : '#';

        var self = this;

        var versionCode = E('code', {}, versionStr);
        this.versionEl = versionCode;

        var runningSpan = E('span', {
            style: isRunning ? 'color:#2dca73;font-weight:bold' : 'color:#e74c3c;font-weight:bold'
        }, isRunning ? _('● 正在运行') + (pid !== '—' ? ' (PID ' + pid + ')' : '') : _('■ 已停止'));
        this.runningEl = runningSpan;

        var portSpan = E('span', {}, String(port));
        this.portEl = portSpan;

        var urlContainer = E('span', {}, isRunning
            ? [E('a', { href: targetUrl, target: '_blank', style: 'font-weight:bold;color:#007bff' }, targetUrl)]
            : _('服务未启动')
        );
        this.urlEl = urlContainer;

        var latestVersionCode = E('code', { style: 'margin-right:20px' }, _('未检查'));
        this.latestVersionEl = latestVersionCode;

        var checkUpdateBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'margin-right:10px',
            click: function() { self.checkUpdate(); }
        }, _('检查更新'));
        this.checkUpdateBtn = checkUpdateBtn;

        var upgradeBtn = E('button', {
            class: 'btn cbi-button cbi-button-apply',
            style: 'display:none',
            click: function() { self.doUpgrade(); }
        }, _('一键升级'));
        this.upgradeBtn = upgradeBtn;

        var node = E('div', { class: 'cbi-map' }, [
            E('h2', {}, _('AdGuard Home 控制中心')),
            E('div', { class: 'cbi-map-descr' }, _('实时状态监控 · 服务控制 · 一键升级')),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('实时仪表盘')),
                E('table', { class: 'table cbi-section-table', style: 'width:100%; max-width:650px;' }, [
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'width:32%;font-weight:bold' }, _('核心部署')),
                        E('td', { class: 'td' }, isBinInstalled
                            ? E('span', { style: 'color:#2dca73;font-weight:bold' }, _('✔ 已下载') + ' (' + (status.bin_path || '/opt/AdGuardHome/AdGuardHome') + ')')
                            : E('span', { style: 'color:#e74c3c;font-weight:bold' }, _('✖ 未发现程序 (请运行官网命令安装)'))
                        )
                    ]),
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'font-weight:bold' }, _('核心版本')),
                        E('td', { class: 'td' }, [versionCode])
                    ]),
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'font-weight:bold' }, _('服务状态')),
                        E('td', { class: 'td' }, isServiceInstalled
                            ? E('span', { style: 'color:#2dca73' }, _('✔ 已安装系统服务 | ✔ 开机自启已注册'))
                            : E('span', { style: 'color:#f39c12;font-weight:bold' }, _('⚠️ 未注册服务 (使用二进制保底控制)'))
                        )
                    ]),
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'font-weight:bold' }, _('运行状态')),
                        E('td', { class: 'td' }, [runningSpan])
                    ]),
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'font-weight:bold' }, _('Web 端口')),
                        E('td', { class: 'td' }, [portSpan])
                    ]),
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'font-weight:bold' }, _('管理入口')),
                        E('td', { class: 'td' }, [urlContainer])
                    ])
                ])
            ]),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('服务控制台')),
                E('div', { style: 'padding:15px; background:#f9f9f9; border:1px solid #ddd; border-radius:4px' }, [
                    E('div', { style: 'margin-bottom:12px;' }, [
                        E('strong', {}, _('当前控制模式：')),
                        E('span', { style: isServiceInstalled ? 'color:#2dca73;font-weight:bold' : 'color:#f39c12;font-weight:bold' },
                            isServiceInstalled ? _('Init.d 系统服务级调用') : _('AdGuardHome 二进制直接控制（命令保底）'))
                    ]),
                    E('button', { class: 'btn cbi-button cbi-button-apply', style: 'margin-right:10px', click: function() { self.execAction('start'); } }, _('启动服务')),
                    E('button', { class: 'btn cbi-button cbi-button-action', style: 'margin-right:10px', click: function() { self.execAction('restart'); } }, _('重启服务')),
                    E('button', { class: 'btn cbi-button cbi-button-reset', style: 'margin-right:10px', click: function() { self.execAction('stop'); } }, _('停止服务')),
                    !isServiceInstalled ? E('button', { class: 'btn cbi-button cbi-button-apply', style: 'background-color:#9b59b6;color:#ffffff!important; text-shadow:0 -1px 0 rgba(0,0,0,0.3); font-weight:bold' }, _('注册系统服务')) : ''
                ])
            ]),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('版本更新')),
                E('div', { style: 'padding:15px; background:#f9f9f9; border:1px solid #ddd; border-radius:4px' }, [
                    E('div', { style: 'margin-bottom:12px;' }, [
                        E('strong', {}, _('当前版本：')),
                        E('code', { style: 'margin-right:20px' }, versionStr),
                        E('strong', {}, _('最新版本：')),
                        latestVersionCode
                    ]),
                    checkUpdateBtn,
                    upgradeBtn
                ])
            ])
        ]);

        this.rootNode = node;
        this.startPolling();

        return node;
    },

    updateStatusUI: function(status) {
        this.statusData = status;
        var isRunning = !!status.running;
        var pid = status.pid || '—';
        var versionStr = status.version || _('未知');
        var port = status.port || 3000;

        if (this.versionEl) {
            this.versionEl.textContent = versionStr;
        }

        if (this.runningEl) {
            this.runningEl.textContent = isRunning
                ? _('● 正在运行') + (pid !== '—' ? ' (PID ' + pid + ')' : '')
                : _('■ 已停止');
            this.runningEl.style.color = isRunning ? '#2dca73' : '#e74c3c';
            this.runningEl.style.fontWeight = 'bold';
        }

        if (this.portEl) {
            this.portEl.textContent = String(port);
        }

        if (this.urlEl) {
            this.urlEl.innerHTML = '';
            if (isRunning) {
                var targetUrl = window.location.protocol + '//' + window.location.hostname + ':' + port;
                this.urlEl.appendChild(E('a', { href: targetUrl, target: '_blank', style: 'font-weight:bold;color:#007bff' }, targetUrl));
            } else {
                this.urlEl.textContent = _('服务未启动');
            }
        }
    },

    startPolling: function() {
        var self = this;
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
        }
        this.pollInterval = setInterval(function() {
            if (!self.rootNode || !document.body.contains(self.rootNode)) {
                clearInterval(self.pollInterval);
                self.pollInterval = null;
                return;
            }
            self.fetchStatus().then(function(data) {
                self.updateStatusUI(data);
            }).catch(function() {});
        }, 5000);
    },

    execAction: function(action) {
        var self = this;
        ui.showModal(null, [E('p', { class: 'spinning' }, _('执行中...'))]);
        this.sendAction(action).then(function(res) {
            ui.hideModal();
            if (res && res.success) {
                ui.addNotification(null, _('操作执行成功'), 'info');
                setTimeout(function() {
                    self.fetchStatus().then(function(data) {
                        self.updateStatusUI(data);
                    });
                }, 1000);
            } else {
                ui.addNotification(null, _('操作失败: ') + ((res && res.output) || (res && res.error) || _('未知错误')), 'error');
            }
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, _('执行异常: ') + err, 'error');
        });
    },

    checkUpdate: function() {
        var self = this;
        if (this.checkUpdateBtn) {
            this.checkUpdateBtn.disabled = true;
            this.checkUpdateBtn.textContent = _('检查中...');
        }
        this.fetchUpdate().then(function(res) {
            var latest = (res && res.latest_version) || _('未知');
            if (self.latestVersionEl) {
                self.latestVersionEl.textContent = latest;
            }
            var current = self.statusData ? (self.statusData.version || '') : '';
            if (latest !== _('未知') && latest !== current && self.upgradeBtn) {
                self.upgradeBtn.style.display = '';
            }
        }).catch(function() {
            if (self.latestVersionEl) {
                self.latestVersionEl.textContent = _('检查失败');
            }
        }).then(function() {
            if (self.checkUpdateBtn) {
                self.checkUpdateBtn.disabled = false;
                self.checkUpdateBtn.textContent = _('检查更新');
            }
        });
    },

    doUpgrade: function() {
        var self = this;
        ui.showModal(null, [
            E('h4', {}, _('确认升级')),
            E('p', {}, _('将下载并安装最新版本的 AdGuard Home 核心。升级期间服务可能短暂中断。')),
            E('div', { style: 'text-align:right; margin-top:15px;' }, [
                E('button', { class: 'btn cbi-button', click: function() { ui.hideModal(); } }, _('取消')),
                E('button', { class: 'btn cbi-button cbi-button-apply', style: 'margin-left:10px', click: function() {
                    ui.hideModal();
                    self.sendUpgrade().then(function() {
                        ui.addNotification(null, _('升级任务已启动，状态将自动刷新'), 'info');
                    }).catch(function() {
                        ui.addNotification(null, _('升级任务启动失败'), 'error');
                    });
                }}, _('确认升级'))
            ])
        ]);
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
EOF

chmod 644 /usr/share/luci/controller/adguardhome.lua \
          /usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json \
          /usr/lib/lua/luci/i18n/adguardhome.lmo \
          /usr/lib/lua/luci/i18n/adguardhome.zh-cn.lmo \
          /www/luci-static/resources/view/adguardhome/dashboard.js

rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-htmlcache /tmp/luci-cbi-*
rm -f /usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json /usr/share/luci/menu.d/luci-app-adguardhome.json

/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

log "=== 安装完成 ==="
echo "========================================================="
echo " ✅ AdGuardHome LuCI Dashboard 安装成功！"
echo " ℹ️  请刷新浏览器进入 LuCI -> [服务] -> [AdGuard Home]"
echo "========================================================="
