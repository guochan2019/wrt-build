#!/bin/bash
# diy-part2.sh — 在 feeds install 后执行
# 用途：编译定制、包冲突解决、配置修改

# 1. 设置默认 IP（来自 workflow input，默认 192.168.50.5）无密码
# ------------------------------------------------------------
[ -n "$CUSTOM_ROUTER_IP" ] && sed -i "s/192.168.1.1/$CUSTOM_ROUTER_IP/g" package/base-files/files/bin/config_generate

# 2. 第三方包优先：同名包在 feeds install 时先装官方、第三方被跳过。
#    已改为在 workflow 中 feeds install 前删官方冲突源，这里无需处理。

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
NGINX_CONF="feeds/packages/net/nginx-util/files/nginx.config"
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

# 6. 第三方包覆盖：官方冲突包已在 workflow 中预先删除
#    feeds install 时第三方版本正常安装，无需软链接 hack
# ------------------------------------------------------------
# v2ray-geodata: clone sbwml 版到 package/（顶层覆盖）
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

# 8. daed: pnpm install 在 CI 默认 --frozen-lockfile，导致 turbo 不链接到 PATH
#     pnpm build --filter daed 调 turbo run build 会报 "turbo: not found"
#     加 --no-frozen-lockfile 让 pnpm 正确链接 devDependencies
# ------------------------------------------------------------
DAED_MK="feeds/daed/daed/Makefile"
if [ -f "$DAED_MK" ]; then
  sed -i 's/pnpm install ;/pnpm install --no-frozen-lockfile ;/' "$DAED_MK"
  echo "daed Makefile: pnpm install 已加 --no-frozen-lockfile"
fi

# 9. NAS 菜单翻译：一级菜单 "NAS" → "存储"
#     luci-base.json 定义 "title": "NAS"，经 .po 翻译后显示
#     zh_Hans 已有 Status/System/Services/Network/VPN 的翻译，缺 NAS
# ------------------------------------------------------------
NAS_PO="feeds/luci/modules/luci-base/po/zh_Hans/base.po"
if [ -f "$NAS_PO" ]; then
  # 避免重复添加
  grep -q 'msgid "NAS"' "$NAS_PO" || {
    echo "" >> "$NAS_PO"
    echo "msgid \"NAS\"" >> "$NAS_PO"
    echo "msgstr \"存储\"" >> "$NAS_PO"
    echo "NAS 翻译已添加: NAS → 存储"
  }
fi

# 10. golang: 1.26.x 保留为默认工具链 + 新版按需引入
#     A. golang1.26 自动追最新 1.26.x patch（绝大多数包用它，保持稳定）
#     B. API 检测到最新稳定版 major.minor > 1.26 时，以 golang1.26 为模板
#        合成 golang1.27 包（版本+哈希从 go.dev API 取），feeds 重索引安装
#     C. 需要新 Go 的包逐个 pin（当前: tailscale 自动更新、go.mod 要求激进）
#     bootstrap 规则: Go 1.N 需 bootstrap ≥ N-2 向下取偶（官方文档）
#     参考: https://go.dev/doc/install/source (Minimum version of Go required)
# ------------------------------------------------------------
GO_MK="feeds/packages/lang/golang/golang1.26/Makefile"
BOOT_MK="feeds/packages/lang/golang/golang-bootstrap/Makefile"
if [ -f "$GO_MK" ]; then
  GOLANG_INFO=$(curl -s --connect-timeout 10 https://go.dev/dl/?mode=json 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    latest = next(x for x in d if x['stable'])
    lver = latest['version'][2:]
    lsrc = next((f for f in latest['files'] if f['filename'] == 'go' + lver + '.src.tar.gz'), None)
    v126 = next((x for x in d if x['stable'] and x['version'].startswith('go1.26.')), None)
    v126ver = v126['version'][2:] if v126 else ''
    v126src = next((f for f in v126['files'] if f['filename'] == 'go' + v126ver + '.src.tar.gz'), None) if v126 else None
    if lsrc and v126ver:
        print(lver, lsrc['sha256'], v126ver, v126src['sha256'] if v126src else '')
except Exception:
    pass" 2>/dev/null || echo "")
  LATEST_VER=$(echo "$GOLANG_INFO" | cut -d' ' -f1)
  LATEST_HASH=$(echo "$GOLANG_INFO" | cut -d' ' -f2)
  V126_VER=$(echo "$GOLANG_INFO" | cut -d' ' -f3)
  V126_HASH=$(echo "$GOLANG_INFO" | cut -d' ' -f4)
  if [ -n "$LATEST_VER" ] && [ -n "$V126_VER" ]; then
    CUR_MM=$(grep -oP 'GO_VERSION_MAJOR_MINOR:=\K[0-9.]+' "$GO_MK")
    CUR_PATCH=$(grep -oP 'GO_VERSION_PATCH:=\K\d+' "$GO_MK")
    # A. golang1.26 追最新 1.26.x patch
    V126_PATCH=$(echo "$V126_VER" | cut -d. -f3)
    if [ "$CUR_MM" = "1.26" ] && [ "$V126_PATCH" -gt "$CUR_PATCH" ] 2>/dev/null; then
      sed -i "s/GO_VERSION_PATCH:=[0-9]*/GO_VERSION_PATCH:=$V126_PATCH/" "$GO_MK"
      sed -i "s/PKG_HASH:=.*/PKG_HASH:=$V126_HASH/" "$GO_MK"
      echo "Go 1.26.x 已从 1.26.$CUR_PATCH 升级到 $V126_VER"
    else
      echo "Go 1.26.x 无需升级（当前 1.26.$CUR_PATCH）"
    fi
    # B. 新版 Go 按需引入（最新 major.minor > 1.26 时合成对应包）
    LATEST_MM=$(echo "$LATEST_VER" | cut -d. -f1-2)
    LATEST_PATCH=$(echo "$LATEST_VER" | cut -d. -f3)
    NEW_MM=""
    if [ "$LATEST_MM" != "$CUR_MM" ]; then
      NEW_DIR="feeds/packages/lang/golang/golang$LATEST_MM"
      if [ ! -f "$NEW_DIR/Makefile" ]; then
        mkdir -p "$NEW_DIR"
        cp "$GO_MK" "$NEW_DIR/Makefile"
        sed -i "s/PKG_NAME:=golang[0-9.]*/PKG_NAME:=golang$LATEST_MM/" "$NEW_DIR/Makefile"
        sed -i "s/GO_VERSION_MAJOR_MINOR:=[0-9.]*/GO_VERSION_MAJOR_MINOR:=$LATEST_MM/" "$NEW_DIR/Makefile"
        sed -i "s/GO_VERSION_PATCH:=[0-9]*/GO_VERSION_PATCH:=$LATEST_PATCH/" "$NEW_DIR/Makefile"
        sed -i "s/PKG_HASH:=.*/PKG_HASH:=$LATEST_HASH/" "$NEW_DIR/Makefile"
        ./scripts/feeds update -i packages
        ./scripts/feeds install "golang$LATEST_MM"
        echo "golang$LATEST_MM 已按需引入（Go $LATEST_VER）"
      else
        echo "golang$LATEST_MM 已存在"
      fi
      NEW_MM="$LATEST_MM"
      # bootstrap 检查：Go 1.N 需 bootstrap ≥ N-2 向下取偶
      if [ -f "$BOOT_MK" ]; then
        LATEST_MINOR=$(echo "$LATEST_VER" | cut -d. -f2)
        BOOT_REQ=$((LATEST_MINOR - 2))
        [ $((BOOT_REQ % 2)) -eq 1 ] && BOOT_REQ=$((BOOT_REQ - 1))
        BOOT_CUR_MINOR=$(grep -oP 'GO_VERSION_MAJOR_MINOR:=\K[0-9.]+' "$BOOT_MK" | cut -d. -f2)
        if [ "$BOOT_CUR_MINOR" -lt "$BOOT_REQ" ] 2>/dev/null; then
          BOOT_INFO=$(curl -s --connect-timeout 10 https://go.dev/dl/?mode=json 2>/dev/null \
            | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    v = next(x for x in d if x['stable'] and x['version'].startswith('go$BOOT_REQ.'))
    ver = v['version'][2:]
    src = next((f for f in v['files'] if f['filename'] == 'go' + ver + '.src.tar.gz'), None)
    if src:
        print(ver, src['sha256'])
except Exception:
    pass" 2>/dev/null || echo "")
          BOOT_VER=$(echo "$BOOT_INFO" | cut -d' ' -f1)
          BOOT_HASH=$(echo "$BOOT_INFO" | cut -d' ' -f2)
          if [ -n "$BOOT_VER" ]; then
            BOOT_MM=$(echo "$BOOT_VER" | cut -d. -f1-2)
            BOOT_PATCH=$(echo "$BOOT_VER" | cut -d. -f3)
            sed -i "s/GO_VERSION_MAJOR_MINOR:=[0-9.]*/GO_VERSION_MAJOR_MINOR:=$BOOT_MM/" "$BOOT_MK"
            sed -i "s/GO_VERSION_PATCH:=[0-9]*/GO_VERSION_PATCH:=$BOOT_PATCH/" "$BOOT_MK"
            sed -i "s/PKG_HASH:=.*/PKG_HASH:=$BOOT_HASH/" "$BOOT_MK"
            echo "bootstrap 已从 $BOOT_CUR_MINOR.x 升级到 $BOOT_VER（Go $LATEST_VER 要求 ≥ $BOOT_REQ）"
          else
            echo "警告: bootstrap 版本查询失败，Go $LATEST_VER 可能编译失败"
          fi
        else
          echo "bootstrap $BOOT_CUR_MINOR.x 满足要求（≥ $BOOT_REQ），无需升级"
        fi
      fi
    fi
    # C. 需要新 Go 的包逐个 pin（当前: tailscale）
    if [ -n "$NEW_MM" ]; then
      TS_MK="feeds/packages/net/tailscale/Makefile"
      if [ -f "$TS_MK" ]; then
        if grep -q "PKG_BUILD_DEPENDS:=golang$NEW_MM/host" "$TS_MK"; then
          echo "tailscale 已 pin 到 golang$NEW_MM/host"
        else
          sed -i "s|PKG_BUILD_DEPENDS:=golang/host|PKG_BUILD_DEPENDS:=golang$NEW_MM/host|" "$TS_MK"
          echo "tailscale 已 pin 到 golang$NEW_MM/host"
        fi
      fi
    fi
  else
    echo "Go 版本查询失败，保持当前版本"
  fi
fi

exit 0
