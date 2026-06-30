#!/bin/sh

MENU="/usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json"
ACL="/usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json"
VIEW="/www/luci-static/resources/view/adguardhome"

rm -f "$MENU" "$ACL"
rm -rf "$VIEW"

rm -f /etc/adguardhome-dashboard.version

rm -rf /tmp/luci*

/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

echo "Uninstalled"
