'use strict';
'require view';
'require fs';
'require ui';
'require rpc';

var BIN_PATH = '/opt/AdGuardHome/AdGuardHome';
var INIT_SCRIPT = '/etc/init.d/AdGuardHome';
var CONFIG_PATHS = ['/opt/AdGuardHome/AdGuardHome.yaml', '/etc/AdGuardHome.yaml', '/etc/adguardhome/adguardhome.yaml'];

return view.extend({
    getServiceStatus: rpc.declare({ object: 'service', method: 'list', params: ['name'], expect: { 'AdGuardHome': {} } }),
    getNetworkConnections: rpc.declare({ object: 'network', method: 'connections', expect: { 'connections': [] } }),
    callServiceAction: rpc.declare({ object: 'service', method: 'vcall', params: ['name', 'action'] }),

    load: function() {
        return Promise.all([
            fs.stat(BIN_PATH).catch(() => null),
            this.getServiceStatus('AdGuardHome').catch(() => null),
            fs.stat(INIT_SCRIPT).catch(() => null),
            this.getNetworkConnections().catch(() => null),
            fs.read(CONFIG_PATHS[0]).catch(() => fs.read(CONFIG_PATHS[1]).catch(() => fs.read(CONFIG_PATHS[2]).catch(() => null)))
        ]);
    },

    render: function(data) {
        var binStat = data[0], ubusStatus = data[1], initStat = data[2], connections = data[3], configContent = data[4];
        
        // 1. 状态分析
        var isRunning = false, currentPid = null;
        if (ubusStatus && ubusStatus.instances) {
            var instance = ubusStatus.instances.instance1 || Object.values(ubusStatus.instances)[0];
            if (instance && instance.running === true) { isRunning = true; currentPid = instance.pid; }
        }

        // 2. 智能端口侦测
        var listenPort = '';
        if (isRunning && currentPid && connections && Array.isArray(connections.connections)) {
            for (var i = 0; i < connections.connections.length; i++) {
                if (connections.connections[i].pid == currentPid && connections.connections[i].local_port > 1024) {
                    listenPort = connections.connections[i].local_port; break;
                }
            }
        }
        if (!listenPort && configContent) {
            var m = (typeof configContent === 'string' ? configContent : configContent.data || '').match(/port:\s*(\d+)/);
            if (m) listenPort = m[1];
        }
        listenPort = listenPort || 3000;

        var targetUrl = isRunning ? (window.location.protocol + '//' + window.location.hostname + ':' + listenPort) : '#';

        // 3. UI 渲染
        return E('div', { class: 'cbi-map' }, [
            E('h2', {}, _('AdGuard Home 控制中心')),
            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('实时仪表盘')),
                E('table', { class: 'table cbi-section-table', style: 'width:100%; max-width:650px;' }, [
                    E('tr', { class: 'tr' }, [E('td', { class: 'td', style: 'width:32%;font-weight:bold' }, _('运行状态')), 
                        E('td', { class: 'td' }, isRunning ? E('span', { style: 'color:#2dca73;font-weight:bold' }, '● 正在运行 (PID ' + currentPid + ')') : E('span', { style: 'color:#e74c3c' }, '■ 已停止'))]),

					// 仅展示核心运维信息，把二进制的健康状态浓缩在“启动配置”中
					E('tr', { class: 'tr' }, [E('td', { class: 'td', style: 'font-weight:bold' }, _('启动配置')), 
    					E('td', { class: 'td' }, [
        					!!initStat ? '✔ 自启 ' : '✖ 自启 ',
        					// 如果 binStat 存在，说明程序装好了；如果不存在，显示缺失警告
        					binStat ? ((binStat.mode & 0o100) ? ' | ✔ 运行权限' : ' | ⚠️ 需 chmod +x') : ' | ⚠️ 核心二进制未发现'
    					])]),

                    E('tr', { class: 'tr' }, [E('td', { class: 'td', style: 'font-weight:bold' }, _('Web 端口')), E('td', { class: 'td' }, listenPort)]),
                    
                    E('tr', { class: 'tr' }, [E('td', { class: 'td', style: 'font-weight:bold' }, _('管理入口')), 
                        E('td', { class: 'td' }, isRunning ? E('a', { href: targetUrl, target: '_blank', style: 'font-weight:bold;color:#007bff' }, targetUrl) : _('服务未启动'))])
                ])
            ]),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('Procd 系统服务控制')),
                E('div', { style: 'padding:10px; background:#f9f9f9; border:1px solid #ddd; border-radius:4px' }, [
                    E('button', { class: 'btn cbi-button cbi-button-apply', style: 'margin-right:10px', click: () => this.doAction('start') }, _('启动')),
                    E('button', { class: 'btn cbi-button cbi-button-action', style: 'margin-right:10px', click: () => this.doAction('restart') }, _('重启')),
                    E('button', { class: 'btn cbi-button cbi-button-reset', click: () => this.doAction('stop') }, _('停止'))
                ])
            ])
        ]);
    },

    doAction: function(action) {
        ui.showModal(null, [E('p', { class: 'spinning' }, _('正在通过 UBus 总线指令与内核通讯...'))]);
        this.callServiceAction('AdGuardHome', action).then(() => { 
            ui.hideModal(); 
            setTimeout(() => location.reload(), 1200); 
        });
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});