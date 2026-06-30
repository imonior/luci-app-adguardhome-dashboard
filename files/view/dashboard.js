'use strict';
'require view';
'require fs';

return view.extend({

    load: function () {
        // 只读取 install.sh 写入的状态文件
        return fs.read('/etc/adguardhome-dashboard.version');
    },

    render: function (data) {

        var text = (data || '').trim();

        var lines = text.split('\n');

        var version = 'Unknown';
        var agh = 'Unknown';
        var time = 'Unknown';

        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf('VERSION=') === 0) {
                version = lines[i].split('=')[1];
            }
            if (lines[i].indexOf('AGH=') === 0) {
                agh = lines[i].split('=')[1];
            }
            if (lines[i].indexOf('INSTALL_TIME=') === 0) {
                time = lines[i].split('=')[1];
            }
        }

        return `
            <div class="cbi-map">
                <h2>AdGuard Home Dashboard</h2>

                <div style="padding:10px 0;">
                    <p><b>Dashboard Version:</b> ${version}</p>
                    <p><b>AdGuard Home:</b> ${agh}</p>
                    <p><b>Install Time:</b> ${time}</p>
                </div>

                <div style="margin-top:20px;">
                    <a class="btn cbi-button cbi-button-action"
                       href="http://192.168.1.1:3000"
                       target="_blank">
                        Open AdGuard Home UI
                    </a>
                </div>

                <div style="margin-top:10px;color:#888;">
                    LuCI → Services → AdGuard Home
                </div>
            </div>
        `;
    }
});
