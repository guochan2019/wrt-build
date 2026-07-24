#!/bin/bash
# diy-part2.sh — 在 feeds install 后执行
# 用途：编译定制、包冲突解决、配置修改

# 1. 设置默认 IP 192.168.50.5（无密码）
# ------------------------------------------------------------
sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# 2. 第三方包优先：在 feed install 后，第三方 src-git 源自动覆盖同名包
#    feeds.conf.default 中第三方源排在官方后面，install 时后者覆盖前者
#    无需额外操作

# 3. luci-app-frpc: 修改翻译 "frp 客户端" → "Frp 客户端"
# ------------------------------------------------------------
FRPC_PO="feeds/luci/applications/luci-app-frpc/po/zh_Hans/frpc.po"
[ -f "$FRPC_PO" ] && sed -i 's/frp 客户端/Frp 客户端/g' "$FRPC_PO"

# 4. tailscale: 自动获取最新版本
# ------------------------------------------------------------
TS_MAKEFILE="feeds/packages/net/tailscale/Makefile"
if [ -f "$TS_MAKEFILE" ]; then
  TS_VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['tag_name'].lstrip('v'))" 2>/dev/null \
    || echo "")
  if [ -n "$TS_VERSION" ]; then
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$TS_VERSION/" "$TS_MAKEFILE"
    # 更新哈希（自动下载并计算）
    TS_SRC="https://github.com/tailscale/tailscale/archive/v${TS_VERSION}.tar.gz"
    TS_HASH=$(curl -sL "$TS_SRC" | sha256sum | cut -d' ' -f1)
    if [ -n "$TS_HASH" ]; then
      sed -i "s/PKG_HASH:=.*/PKG_HASH:=$TS_HASH/" "$TS_MAKEFILE"
    fi
    echo "tailscale 已更新到 v${TS_VERSION}"
  else
    echo "tailscale 版本查询失败，保持默认版本"
  fi
fi

# 5. luci-app-quickfile: 替换 nginx 默认配置
# ------------------------------------------------------------
NGINX_CONF="feeds/packages/nginx-util/files/nginx.config"
if [ -f "$NGINX_CONF" ]; then
  cat > "$NGINX_CONF" << 'NGINXEOF'
config main 'global'
	option uci_enable 'true'

config server '_lan'
	option server_name '_lan'
	list listen '80 default_server'
	list listen '[::]:80 default_server'
	list include 'conf.d/*.locations'
	option access_log 'off; # logd openwrt'
NGINXEOF
  echo "nginx.config 已替换"
fi

# 6. luci-app-mosdns: 替换 feeds 包 + v2ray-geodata
# ------------------------------------------------------------
# 删除官方 mosdns（改用 sbwml 源），同时清理 feeds install 产生的悬空软链接
rm -rf feeds/packages/net/mosdns
rm -f package/feeds/packages/mosdns                    # 删悬空链接
mkdir -p package/feeds/mosdns
ln -sf ../../../feeds/mosdns/mosdns package/feeds/mosdns/mosdns  # 指向 sbwml 源

rm -rf feeds/packages/net/v2ray-geodata
rm -f package/feeds/packages/v2ray-geodata             # 删官方源引起的悬空链接
git clone --depth 1 https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# 修改 geodata 下载源
GEODATA_MK="package/v2ray-geodata/Makefile"
if [ -f "$GEODATA_MK" ]; then
  sed -i 's|GEOIP_URL:=.*|GEOIP_URL:=https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip.dat|' "$GEODATA_MK"
  echo "v2ray-geodata Makefile 已更新"
fi

# 7. 添加 nikki 启动脚本到 rc.local
# ------------------------------------------------------------
mkdir -p package/base-files/files/etc
RCLOCAL="package/base-files/files/etc/rc.local"
if [ -f "$RCLOCAL" ]; then
  # 在 exit 0 前插入
  sed -i '/^exit 0/i\ln -s /usr/share/v2ray/*.* /etc/nikki/run/' "$RCLOCAL"
else
  cat > "$RCLOCAL" << 'RCEOF'
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

ln -s /usr/share/v2ray/*.* /etc/nikki/run/
exit 0
RCEOF
  chmod +x "$RCLOCAL"
fi
echo "rc.local 已更新"

# 8. golang: 升级 Go 工具链到 1.26.5（tailscale 1.98.9+ 需要）
#     ImmortalWrt openwrt-25.12 默认 Go 1.26.4，但 tailscale 1.98.9
#     go.mod 要求 >=1.26.5。GOTOOLCHAIN=local 阻止自动下载，
#     因此手动升 OpenWrt 的 golang1.26 包。
#     注意：如果上游 ImmortalWrt 更新 golang1.26 到 1.26.5+，这段可删除。
# ------------------------------------------------------------
GO_MK="feeds/packages/lang/golang/golang1.26/Makefile"
if [ -f "$GO_MK" ]; then
  CURRENT_PATCH=$(grep -oP 'GO_VERSION_PATCH:=\K\d+' "$GO_MK")
  if [ "$CURRENT_PATCH" = "4" ]; then
    sed -i 's/GO_VERSION_PATCH:=4/GO_VERSION_PATCH:=5/' "$GO_MK"
    sed -i 's/PKG_HASH:=.*/PKG_HASH:=495be4bc87176ac567392e5b4116abd98466d33d7b49d41e764ccc6976b2dc42/' "$GO_MK"
    echo "Go 已从 1.26.4 升级到 1.26.5"
  else
    echo "Go 版本已是 1.26.$CURRENT_PATCH，无需升级"
  fi
fi

exit 0
