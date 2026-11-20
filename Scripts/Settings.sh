#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
# find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

#修改默认WIFI账号密码
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
ROUTER_TOOL="./package/emortal/luci-app-router-tool/root/etc/config/router-tool"
for file in "$ROUTER_TOOL" "$WIFI_UC"; do
	[ -f "$file" ] && sed -i "s/ssid '.*'/ssid '$WRT_SSID'/g; s/key '.*'/key '$WRT_WORD'/g" "$file"
done

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
# echo "CONFIG_PACKAGE_luci=y" >> ./.config
# echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
# echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
# echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
# echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config


# LuCI 基础组件与中文支持
cat >> ./.config <<'EOF'
CONFIG_PACKAGE_luci=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-theme-aurora=y
EOF

# 首次启动时设置 Aurora 为默认主题
THEME_DIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$THEME_DIR"

cat > "$THEME_DIR/99-set-aurora-theme" <<'EOF'
#!/bin/sh

if [ -d /www/luci-static/aurora ]; then
    uci set luci.main.mediaurlbase='/luci-static/aurora'
    uci commit luci
fi

exit 0
EOF

chmod +x "$THEME_DIR/99-set-aurora-theme"


#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "$WRT_WIFI" == "WIFI-NO" ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# ==================================================
# CPU / PPE / TCP / UDP 硬件卸载监控
# 固件首次启动时自动安装
# ==================================================

mkdir -p ./package/base-files/files/etc/uci-defaults

cat > ./package/base-files/files/etc/uci-defaults/99-cpuusage-monitor <<'INIT_SCRIPT'
#!/bin/sh

# 检查原始 cpuusage 是否存在
[ -x /sbin/cpuusage ] || exit 0

# 备份原始 CPU/PPE 统计脚本
if [ ! -f /sbin/cpuusage.original ]; then
    cp -p /sbin/cpuusage /sbin/cpuusage.original || exit 1
fi

# 安装增强版统计脚本
cat > /sbin/cpuusage.new <<'CPU_SCRIPT'
#!/bin/sh

# 保留原来的 CPU / PPE 数据
BASE=$(/sbin/cpuusage.original)

# 读取 TCP、UDP 和硬件卸载连接数量
if [ -r /proc/net/nf_conntrack ]; then
    STATS=$(awk '
    $3=="tcp" {tcp++}
    $3=="udp" {udp++}
    $3=="tcp" && /HW_OFFLOAD/ {tcp_hw++}
    $3=="udp" && /HW_OFFLOAD/ {udp_hw++}
    END {
        printf "TCP: %d (HW: %d) UDP: %d (HW: %d)", \
            tcp, tcp_hw, udp, udp_hw
    }
    ' /proc/net/nf_conntrack)
else
    STATS="TCP/UDP: unavailable"
fi

printf '%s %s\n' "$BASE" "$STATS"
CPU_SCRIPT

chmod 755 /sbin/cpuusage.new
mv -f /sbin/cpuusage.new /sbin/cpuusage

exit 0
INIT_SCRIPT

chmod 755 ./package/base-files/files/etc/uci-defaults/99-cpuusage-monitor

echo "CPU/PPE/TCP/UDP monitor integration ready."

