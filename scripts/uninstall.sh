#!/bin/sh
set -e

MENU_FILE="/usr/share/luci/menu.d/luci-app-adguardhome-dashboard.json"
ACL_FILE="/usr/share/rpcd/acl.d/luci-app-adguardhome-dashboard.json"
VIEW_FILE="/www/luci-static/resources/view/adguardhome/dashboard.js"

echo "[uninstall] start"

rm -f "$MENU_FILE"
rm -f "$ACL_FILE"
rm -f "$VIEW_FILE"

echo "[uninstall] done"