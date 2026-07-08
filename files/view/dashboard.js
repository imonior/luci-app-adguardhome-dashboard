'use strict';
'require view';
'require ui';
'require request';

return view.extend({
    statusData: null,
    logData: '',
    pollInterval: null,
    logPollInterval: null,
    rootNode: null,

    versionEl: null,
    runningEl: null,
    portEl: null,
    urlEl: null,
    logPre: null,
    latestVersionEl: null,
    upgradeBtn: null,
    checkUpdateBtn: null,
    refreshLogBtn: null,

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

    fetchLog: function() {
        return request.get(L.url('admin/services/adguardhome/log')).then(function(res) {
            return res.json();
        });
    },

    load: function() {
        var self = this;
        return Promise.all([
            self.fetchStatus().catch(function() {
                return { installed: false, service_installed: false, running: false, version: _('未知'), port: 3000 };
            }),
            self.fetchLog().catch(function() {
                return { log: _('获取日志失败') };
            })
        ]);
    },

    render: function(data) {
        var status = data[0];
        this.logData = data[1] ? (data[1].log || '') : '';
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

        var refreshLogBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            click: function() { self.refreshLog(); }
        }, _('刷新日志'));
        this.refreshLogBtn = refreshLogBtn;

        var logPre = E('pre', {
            style: 'max-height:400px; overflow-y:auto; background:#1e1e1e; color:#d4d4d4; padding:12px; border-radius:4px; font-size:12px; white-space:pre-wrap; word-wrap:break-word;'
        }, this.logData || _('暂无日志'));
        this.logPre = logPre;

        var node = E('div', { class: 'cbi-map' }, [
            E('h2', {}, _('AdGuard Home 控制中心')),
            E('div', { class: 'cbi-map-descr' }, _('实时状态监控 · 服务控制 · 日志查看 · 一键升级')),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('实时仪表盘')),
                E('table', { class: 'table cbi-section-table', style: 'width:100%; max-width:650px;' }, [
                    E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'width:32%;font-weight:bold' }, _('核心部署')),
                        E('td', { class: 'td' }, isBinInstalled
                            ? E('span', { style: 'color:#2dca73;font-weight:bold' }, _('✔ 已下载 (/opt/AdGuardHome/AdGuardHome)'))
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
                    !isServiceInstalled ? E('button', { class: 'btn cbi-button cbi-button-apply', style: 'background-color:#9b59b6;color:#fff', click: function() { self.execAction('install_service'); } }, _('注册系统服务')) : ''
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
            ]),

            E('div', { class: 'cbi-section' }, [
                E('h3', {}, _('日志查看器')),
                E('div', { style: 'padding:15px; background:#f9f9f9; border:1px solid #ddd; border-radius:4px' }, [
                    E('div', { style: 'margin-bottom:10px;' }, [refreshLogBtn]),
                    logPre
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

    startLogPolling: function() {
        var self = this;
        var startTime = Date.now();
        if (this.logPollInterval) {
            clearInterval(this.logPollInterval);
        }
        this.logPollInterval = setInterval(function() {
            if (!self.rootNode || !document.body.contains(self.rootNode)) {
                clearInterval(self.logPollInterval);
                self.logPollInterval = null;
                return;
            }
            if (Date.now() - startTime > 300000) {
                clearInterval(self.logPollInterval);
                self.logPollInterval = null;
                return;
            }
            self.fetchLog().then(function(data) {
                if (data && data.log !== undefined) {
                    self.logData = data.log;
                    if (self.logPre) {
                        self.logPre.textContent = data.log || _('暂无日志');
                        self.logPre.scrollTop = self.logPre.scrollHeight;
                    }
                    var lowerLog = (data.log || '').toLowerCase();
                    if (lowerLog.indexOf('done') !== -1 || lowerLog.indexOf('installed') !== -1 ||
                        lowerLog.indexOf('upgrade complete') !== -1) {
                        clearInterval(self.logPollInterval);
                        self.logPollInterval = null;
                        ui.addNotification(null, _('升级完成，正在刷新状态'), 'info');
                        self.fetchStatus().then(function(s) {
                            self.updateStatusUI(s);
                        });
                    }
                }
            }).catch(function() {});
        }, 2000);
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
                        ui.addNotification(null, _('升级任务已启动，请在下方日志查看器中查看进度'), 'info');
                        self.startLogPolling();
                    }).catch(function() {
                        ui.addNotification(null, _('升级任务启动失败'), 'error');
                    });
                }}, _('确认升级'))
            ])
        ]);
    },

    refreshLog: function() {
        var self = this;
        if (this.refreshLogBtn) {
            this.refreshLogBtn.disabled = true;
        }
        this.fetchLog().then(function(data) {
            if (data && data.log !== undefined) {
                self.logData = data.log;
                if (self.logPre) {
                    self.logPre.textContent = data.log || _('暂无日志');
                    self.logPre.scrollTop = self.logPre.scrollHeight;
                }
            }
        }).catch(function() {}).then(function() {
            if (self.refreshLogBtn) {
                self.refreshLogBtn.disabled = false;
            }
        });
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
