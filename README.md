# wrt-build

ImmortalWrt 25.12 x86_64 云编译项目。

## 项目结构

```
├── .github/workflows/build.yml     # 云编译 workflow
├── .config                          # 编译配置
├── feeds.conf.default               # Feed 源配置
├── diy-part1.sh                     # 定制脚本 1（feeds update 前）
├── diy-part2.sh                     # 定制脚本 2（feeds install 后）
└── README.md
```

## 触发方式

- **手动编译**：Actions → Build ImmortalWrt → Run workflow
  可选参数：
  - 路由器管理地址（默认 192.168.50.5）
  - 固件大小 MB（默认 512）
- **定时编译**：每周六凌晨自动编译（使用默认参数）

## 工作流定制

| 定制项 | 位置 | 说明 |
|--------|------|------|
| 路由器 IP | workflow input + diy-part2.sh §1 | 编译时通过 sed 替换，默认 192.168.50.5 |
| 固件大小 | workflow input + build.yml | 编译前 sed 修改 CONFIG_TARGET_ROOTFS_PARTSIZE |
| nginx 配置 | diy-part2.sh §5 | 替换 feeds/packages/net/nginx-util/files/nginx.config |
| NAS 菜单翻译 | diy-part2.sh §9 | zh_Hans base.po 追加 msgid "NAS" → "网络存储" |
| daed pnpm 修复 | diy-part2.sh §8 | pnpm install 加 --no-frozen-lockfile 解决 CI 下 turbo not found |
| Go 工具链升级 | diy-part2.sh §10 | golang 1.26.4 → 1.26.5（tailscale 1.98.9+ 需要） |

## 编译流程

1. 安装依赖 → 2. 克隆 immortalwrt 源码 → 3. 加载 feeds → 4. 更新/安装 feeds → 5. 加载 .config → 6. 下载源码包 → 7. 编译固件 → 8. 发布 Release

## Feed 源

包含 12 个 feed 源（4 官方 + 8 第三方）：

| Feed | 仓库 |
|------|------|
| OpenClash | `vernesong/OpenClash` |
| Nikki | `nikkinikki-org/OpenWrt-nikki` |
| Momo | `nikkinikki-org/OpenWrt-momo` |
| Lucky | `gdy666/luci-app-lucky` |
| Quickfile | `sbwml/luci-app-quickfile` |
| Mosdns | `sbwml/luci-app-mosdns` |
| Daed | `QiuSimons/luci-app-daed` |
| myownpack | `guochan2019/myown-packages` |

## 固件

- 目标：x86_64
- 内核：Linux 6.12
- 输出：ext4-combined-efi / squashfs-combined-efi 等
- 发布：GitHub Release（保留最近 3 个版本）
