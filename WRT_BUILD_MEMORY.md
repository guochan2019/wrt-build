# wrt-build 项目记忆

> 最后更新: 2026-07-23
> 仓库: `guochan2019/wrt-build`
> 本地: `/home/hellomax/wrt-build/`

---

## 一、项目结构

```
wrt-build/
├── .github/workflows/build.yml     # 云编译 workflow
├── .config                          # 编译配置（x86_64, 8943 行）
├── feeds.conf.default               # Feed 源（4 官方 + 8 第三方）
├── diy-part1.sh                     # feeds update 前定制（当前无定制）
├── diy-part2.sh                     # feeds install 后定制（核心修改）
├── WRT_BUILD_MEMORY.md              # 本文档
└── README.md                        # 项目说明
```

---

## 二、Feed 源（12 个）

### 官方源（4 个）
| Feed | 仓库 | 分支 |
|------|------|------|
| immortalwrt 主源 | `immortalwrt/immortalwrt` | `openwrt-25.12` |
| packages | `immortalwrt/packages` | `openwrt-25.12` |
| luci | `immortalwrt/luci` | `openwrt-25.12` |
| routing | `openwrt/routing` | `openwrt-25.12` |
| telephony | `openwrt/telephony` | `openwrt-25.12` |
| video | `openwrt/video` | `openwrt-25.12` |

### 第三方源（7 个）
| Feed | 仓库 | 分支 |
|------|------|------|
| OpenClash | `vernesong/OpenClash` | 默认 |
| Nikki | `nikkinikki-org/OpenWrt-nikki` | `main` |
| Momo | `nikkinikki-org/OpenWrt-momo` | `main` |
| Lucky | `gdy666/luci-app-lucky` | 默认 |
| quickfile | `sbwml/luci-app-quickfile` | 默认 |
| mosdns | `sbwml/luci-app-mosdns` | `v5` |
| daed | `QiuSimons/luci-app-daed` | `kix` |
| myownpack | `guochan2019/myown-packages` | `openwrt-25.12` |

---

## 三、.config 修改内容

### 固件大小
```
CONFIG_TARGET_ROOTFS_PARTSIZE=512 → 256
```

### 已移除的插件
| 插件 | 原因 |
|------|------|
| Aria2 | 用户要求 |
| qBittorrent | 用户要求 |
| vsftpd (FTP 服务器) | 用户要求 |

---

## 四、diy-part2.sh 编译定制（7 项）

### 1. 默认 IP
`192.168.50.5`，无密码（`/etc/config/generate` 自动生成空密码）

### 2. 翻译修改
`frp 客户端` → `Frp 客户端`（`feeds/luci/applications/luci-app-frpc/po/zh_Hans/frpc.po`）

### 3. Tailscale 版本自动更新
通过 GitHub API 查询 `https://api.github.com/repos/tailscale/tailscale/releases/latest`
- 获取最新 tag → 更新 `PKG_VERSION`
- 下载源码包 → 计算 SHA256 → 更新 `PKG_HASH`
- 失败时保持默认版本

### 4. nginx 配置替换（Quickfile）
替换 `feeds/packages/nginx-util/files/nginx.config` 为：
```
config main 'global'
	option uci_enable 'true'

config server '_lan'
	option server_name '_lan'
	list listen '80 default_server'
	list listen '[::]:80 default_server'
	list include 'conf.d/*.locations'
	option access_log 'off; # logd openwrt'
```

### 5. Mosdns 替换
从 feeds 中删除官方 mosdns 和 v2ray-geodata：
```
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/v2ray-geodata
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
```
修改 `package/v2ray-geodata/Makefile` 中：
```
GEOIP_URL:=https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip.dat
```

### 6. Nikki 启动脚本
在 `package/base-files/files/etc/rc.local` 中 exit 0 前加入：
```
ln -s /usr/share/v2ray/*.* /etc/nikki/run/
```

### 7. Daed 编译环境
Feed 源中 `QiuSimons/luci-app-daed;kix` 已包含所有依赖。
编译前确保执行了 `./scripts/feeds install -a`，daed 会自动出现在 LUCI → Applications 菜单。
注意：运行环境的 BTF 支持通过 `CONFIG_KERNEL_DEBUG_INFO_BTF=y` 已在 .config 中启用。

---

## 五、Workflow 编译流程

```
Checkout (含 .config/feeds/diy 脚本)
  → Free Disk Space (删 Android/Dotnet/Haskell/缓存)
  → Install Dependencies (60+ 编译工具)
  → Clone immortalwrt (openwrt-25.12)
  → 加载 feeds.conf.default + diy-part1.sh
  → ./scripts/feeds update -a
  → ./scripts/feeds install -a
  → 加载 .config + diy-part2.sh (所有定制)
  → make defconfig
  → make download -j8
  → make -j$(nproc)
  → 整理固件 → 发布 Release
  → 清理旧工作流 + 保留最近 3 个 Release
```

**触发器：**
- 手动触发（workflow_dispatch）
- 定时触发（每周六 0:00）

**注意：** 第一次编译需要 2-3 小时，后续增量编译更快。

---

## 六、已知注意事项

1. **第三方 feed 优先：** feeds.conf.default 中官方源在前、第三方源在后，install 时后者覆盖前者同名包，实现"以第三方为准"
2. **Tailscale 版本检查：** 每次编译时实时查询 GitHub 最新 release
3. **Daed 依赖：** 编译环境需要 clang/llvm/pnpm（workflow 已安装），运行时需 eBPF + BTF（.config 已配置）
4. **Nikki 启动：** rc.local 中 ln -s 需在 Nikki 目录创建后执行，rc.local 在启动最后阶段运行
5. **Quickfile 依赖 nginx：** nginx 包未在 .config 中显式启用？检查 .config 中 `CONFIG_PACKAGE_nginx=y` 是否已配置

---

## 七、文件来源说明

| 文件 | 来源 | 备注 |
|------|------|------|
| `.config` | 用户本地编译导出 | 已按需求修改 |
| `feeds.conf.default` | 用户本地虚拟机 | 未修改 |
| `diy-part1.sh` | 新建 | 空白模板 |
| `diy-part2.sh` | 新建 | 7 项定制 |
| `.github/workflows/build.yml` | 参考 P3TERX/Actions-OpenWrt 模板 | 适配 ImmortalWrt 25.12 |
