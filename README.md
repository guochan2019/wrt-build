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
- **定时编译**：每周六凌晨自动编译

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
