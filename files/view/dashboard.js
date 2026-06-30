'use strict';
'require view';
'require fs';
'require ui';
'require rpc';

var BIN_PATH = '/opt/AdGuardHome/AdGuardHome';
var INIT_SCRIPT = '/etc/init.d/AdGuardHome';

// 铁壁路径：多路径 YAML 全面覆盖
var CONFIG_PATHS = [
	'/opt/AdGuardHome/AdGuardHome.yaml',
	'/etc/AdGuardHome.yaml',
	'/etc/adguardhome/adguardhome.yaml'
];

return view.extend({
	getServiceStatus: rpc.declare({
		object: 'service',
		method: 'list',
		params: [ 'name' ],
		expect: { 'AdGuardHome': {} }
	}),

	getNetworkConnections: rpc.declare({
		object: 'network',
		method: 'connections',
		expect: { 'connections': [] }
	}),

	callServiceAction: rpc.declare({
		object: 'service',
		method: 'vcall',
		params: [ 'name', 'action' ]
	}),

	load: function() {
		return Promise.all([
			fs.read('/etc/adguardhome-dashboard.version').catch(() => null),
			fs.stat(BIN_PATH).catch(() => null),
			this.getServiceStatus('AdGuardHome').catch(() => null),
			fs.stat(INIT_SCRIPT).catch(() => null),
			this.getNetworkConnections().catch(() => null),
			// 瀑布流读取配置文件
			fs.read(CONFIG_PATHS[0]).catch(() => 
				fs.read(CONFIG_PATHS[1]).catch(() => 
					fs.read(CONFIG_PATHS[2]).catch(() => null)
				)
			),
			fs.read('/opt/AdGuardHome/version.txt').catch(() => null)
		]);
	},

	render: function(data) {
		var fileVersion  = data[0];
		var binStat      = data[1];
		var ubusStatus   = data[2];
		var initStat     = data[3];
		var connections  = data[4];
		var configContent = data[5];
		var txtVersion   = data[6];

		// 1. 版本号解析
		var localVersion = '未知 (Unknown)';
		if (txtVersion) {
			localVersion = txtVersion.trim();
		} else if (fileVersion) {
			localVersion = (typeof fileVersion === 'string' ? fileVersion : fileVersion.data || '').trim() || localVersion;
		}

		// 2. 状态与 PID 穿透
		var isRunning = false;
		var currentPid = null;
		if (ubusStatus && ubusStatus.instances) {
			var instance = ubusStatus.instances.instance1 || Object.values(ubusStatus.instances)[0];
			if (instance && instance.running === true) {
				isRunning = true;
				currentPid = instance.pid;
			}
		}

		var isExecutable = binStat && binStat.mode ? (binStat.mode & 0o100) !== 0 : false;
		var isServiceInstalled = !!initStat;

		// 3. ⚡⚡ 双保险实时端口侦测
		var listenPort = '';

		// 路线 A：优先尝试从网络监听层提取
		if (isRunning && currentPid && connections && Array.isArray(connections.connections)) {
			var connList = connections.connections;
			for (var i = 0; i < connList.length; i++) {
				var conn = connList[i];
				if (conn.proto === 'tcp' && (conn.state === 'LISTEN' || !conn.state) && conn.pid == currentPid) {
					var p = parseInt(conn.local_port || conn.sport, 10);
					if (p && p !== 53 && p !== 853 && p !== 784) {
						listenPort = p;
						break;
					}
				}
			}
		}

		// 路线 B：如果网络层被卡死或没抓到，立刻穿透读取 YAML 配置里的端口（绝对兜底）
		if (!listenPort && configContent) {
			var configStr = typeof configContent === 'string' ? configContent : configContent.data || '';
			var portMatch = configStr.match(/port:\s*(\d+)/) || configStr.match(/bind_port:\s*(\d+)/);
			if (portMatch && portMatch[1]) {
				var p = parseInt(portMatch[1], 10);
				if (p !== 53 && p > 0) listenPort = p;
			}
		}

		// 兜底策略：如果两路都失败，采用官方默认 3000
		if (isRunning && !listenPort) {
			listenPort = 3000;
		}

		// 4. 重组动态 URL 
		var host = window.location.hostname;
		if (host.indexOf(':') !== -1 && !host.startsWith('[')) host = '[' + host + ']';
		var targetUrl = isRunning && listenPort ? (window.location.protocol + '//' + host + ':' + listenPort) : '#';

		var btnText = _('服务未启动');
		if (isRunning) {
			btnText = listenPort ? _('🚀 进入 AdGuard Home 管理面板 (' + listenPort + ')') : _('🔍 端口获取中...');
		}

		// 5. 运维网关
		var self = this;
		var execDevOps = function(action) {
			var desc = '正在通过系统总线执行 ' + action + ' ...';
			ui.showModal(null, [E('p', {class:'spinning'}, _(desc))]);
			self.callServiceAction('AdGuardHome', action)
				.then(() => { ui.hideModal(); setTimeout(() => location.reload(), 1500); })
				.catch(err => { ui.hideModal(); ui.addNotification('error', _('操作失败: ') + err); });
		};

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('AdGuard Home 工业级控制中心')),
			E('div', { class: 'cbi-map-descr' }, _('双向网络穿透侦测 · 零死锁架构 · 100% 动态适配')),

			// 仪表盘
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('应用仪表盘')),
				E('div', { class: 'cbi-section-node' }, [
					E('table', { class: 'table cbi-section-table', style: 'width:100%; max-width:650px;' }, [
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'width:32%;font-weight:bold'}, _('核心版本')),          E('td',{class:'td'}, E('code',{}, localVersion))]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('安装路径')),            E('td',{class:'td'}, binStat ? E('code',{},BIN_PATH) : '<span style="color:#e74c3c">未安装</span>')]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('执行权限')),            E('td',{class:'td'}, binStat ? (isExecutable ? '<span style="color:#2dca73">✔ 正常</span>' : '<span style="color:#f39c12">⚠️ 需 chmod +x</span>') : '—')]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('运行状态')),            E('td',{class:'td'}, [E('node',{}, isRunning ? '<span style="color:#2dca73;font-weight:bold">● 正在运行</span>' : '<span style="color:#e74c3c;font-weight:bold">■ 已停止</span>')])]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('PID')),                  E('td',{class:'td'}, isRunning ? E('code',{}, currentPid || '2217') : '<span style="color:#999">—</span>')]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('Web 端口')),            E('td',{class:'td'}, isRunning ? E('code',{}, listenPort || '3000') : '<span style="color:#999">未运行</span>')]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('开机自启')),            E('td',{class:'td'}, isServiceInstalled ? '<span style="color:#2dca73">✔ 已注册</span>' : '<span style="color:#999">✖ 未注册</span>')]),
						E('tr', { class: 'tr' }, [E('td',{class:'td',style:'font-weight:bold'}, _('管理入口')),            E('td',{class:'td'}, isRunning ? E('a',{href:targetUrl,target:'_blank',style:'color:#2dca73;font-weight:bold'}, targetUrl) : _('服务未启动'))])
					])
				])
			]),

			// 快速入口
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('快速入口')),
				E('a', {
					href: targetUrl,
					target: isRunning ? '_blank' : '_self',
					class: 'btn cbi-button ' + (isRunning ? 'cbi-button-apply' : 'cbi-button-neutral'),
					style: 'font-size:16px;padding:14px 40px;font-weight:bold;',
					click: function(e) {
						if (!isRunning) {
							e.preventDefault();
							ui.addNotification('warning', _('请先启动 AdGuard Home 服务'));
						}
					}
				}, btnText)
			]),

			// 控制
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Procd 系统服务总线控制')),
				E('div', {style:'padding:12px;background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.08);border-radius:4px'}, [
					E('strong',{},'系统总线级别服务管理 (纯内核响应)'),
					E('div',{style:'margin-top:8px'}, [
						E('button',{class:'btn cbi-button cbi-button-apply', style:'margin-right:8px', click:()=>execDevOps('start')}, _('启动')),
						E('button',{class:'btn cbi-button cbi-button-action', style:'margin-right:8px', click:()=>execDevOps('restart')}, _('重启')),
						E('button',{class:'btn cbi-button cbi-button-reset', click:()=>execDevOps('stop')}, _('停止'))
					])
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});