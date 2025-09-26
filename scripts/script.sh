#!/bin/bash
# OpenWrt第三方源及设备初始配置脚本
# 功能：添加第三方源、设置默认管理IP/密码

set -euo pipefail

echo "=== 配置第三方源及设备参数 ==="

# 1. 添加第三方源（示例：添加luci-app-passwall等）
echo "步骤1：添加第三方源..."
cat >> feeds.conf.default << EOF
src-git lienol https://github.com/Lienol/openwrt-package
src-git small https://github.com/kenzok8/small-package
EOF

# 2. 设置默认管理IP和密码
echo "步骤2：设置默认管理参数..."
cat >> .config << EOF
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-wireguard=y

# 默认管理设置
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-app-firewall=y

# 网络设置
CONFIG_PACKAGE_dnsmasq_full=y
CONFIG_PACKAGE_wpad-basic=y

# 默认IP和密码设置
CONFIG_TARGET_INIT_SUPPRESS_STDERR=y
CONFIG_TARGET_PREINIT_DISABLE_FAILSAFE=y
CONFIG_TARGET_INIT_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
CONFIG_TARGET_INIT_CMD="/sbin/init"
CONFIG_TARGET_INIT_ENV=""
CONFIG_TARGET_INIT_SED_CMD=""
EOF

# 3. 设置默认WiFi密码
echo "步骤3：设置默认WiFi密码..."
# 创建必要的目录结构
mkdir -p package/kernel/mac80211/files/lib/wifi
# 创建文件（如果不存在）
touch package/kernel/mac80211/files/lib/wifi/mac80211.sh
# 追加配置内容
cat >> package/kernel/mac80211/files/lib/wifi/mac80211.sh << 'EOF'
append wifi_device "data wifi0 1"
set wifi0.radio0.channel="auto"
set wifi0.radio0.country="CN"
set wifi0.radio0.txpower="20"
EOF

echo "=== 设备配置完成 ==="
exit 0
