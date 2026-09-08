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
  - 路由器管理地址（默认 192.168.1.1）
  - 固件大小 MB（默认 512）
- **定时编译**：每周一 0:00（北京时间）自动编译；`workflow_dispatch` 的 inputs 为空，自动从 `.config` 读取固件大小（CONFIG_TARGET_ROOTFS_PARTSIZE）与 IP（CONFIG_TARGET_PREINIT_IP）作为默认值

## 工作流定制（按执行顺序）

| 定制项 | 位置 | 说明 |
|--------|------|------|
| LLVM 22 覆盖 + dwarves | build.yml Install Dependencies | daed 编译需要 clang >= 16，覆盖安装 llvm-22；vmlinux-btf 需要 pahole（dwarves 包） |
| vmlinux-btf 添加到 feeds | build.yml Add vmlinux-btf | clone QiuSimons/vmlinux-btf 到 `feeds/packages/net/` + 重新索引，为 daed CO-RE 提供独立 BTF |
| 路由器 IP | workflow input + build.yml Read Default Params | 手动触发用输入值；schedule 触发从 `.config` 读 `CONFIG_TARGET_PREINIT_IP`（192.168.1.1）兜底 → diy-part2.sh §1 sed config_generate | 
| 固件大小 | workflow input + build.yml Read Default Params | 手动触发用输入值；schedule 触发从 `.config` 读 `CONFIG_TARGET_ROOTFS_PARTSIZE`（512MB）兜底 |
| 删除官方冲突包 | build.yml Remove conflicting | `feeds install -a` 前删除 `net/v2ray-geodata`, `net/daed`, `luci/applications/luci-app-daed` + 重新索引 feeds |
| v2ray-geodata + GEOIP_URL | diy-part2.sh §6 | clone sbwml/v2ray-geodata 到 `package/`，Makefile 中 GEOIP_URL 改为国内全量包（Loyalsoldier 源） |
| nginx 配置 | diy-part2.sh §5 | 替换 `feeds/packages/net/nginx-util/files/nginx.config` 为 Quickfile 所需配置 |
| Frp 客户端翻译 | diy-part2.sh §3 | `feeds/luci/applications/luci-app-frpc/po/zh_Hans/frpc.po` 中 "frp 客户端" → "Frp 客户端" |
| Nikki 启动脚本 | diy-part2.sh §7 | `rc.local` 追加 `ln -s /usr/share/v2ray/*.* /etc/nikki/run/` |
| daed pnpm 修复 | diy-part2.sh §8 | daed Makefile 中 `pnpm install` 加 `--no-frozen-lockfile`，解决 CI 下 `turbo: not found` |
| NAS 菜单翻译 | diy-part2.sh §9 | zh_Hans base.po 追加 `msgid "NAS"` / `msgstr "存储"` |
| Go 工具链多版本按需 | diy-part2.sh §10 | golang1.26 保底自动追 1.26.x patch；检测到更新 major（如 1.27）时以 golang1.26 为模板合成 golang1.27 包备用并 feeds 安装；bootstrap 按官方规则联动（Go 1.N 需 ≥ N-2 取偶） |

## 编译流程

1. 安装依赖 → 2. 克隆 immortalwrt 源码 → 3. 加载 feeds → 4. 更新/安装 feeds → 5. 加载 .config → 6. 下载源码包 → 7. 编译固件 → 8. 发布 Release

## Feed 源

包含 11 个 feed 源（5 官方 + 6 第三方）：

| Feed | 仓库 |
|------|------|
| Nikki | `nikkinikki-org/OpenWrt-nikki` |
| Momo | `nikkinikki-org/OpenWrt-momo` |
| Lucky | `gdy666/luci-app-lucky` |
| Quickfile | `sbwml/luci-app-quickfile` |
| Daed | `QiuSimons/luci-app-daed` |
| myownpack | `guochan2019/myown-packages` |

## 固件

- 目标：x86_64
- 内核：Linux 6.12
- 输出：ext4-combined-efi / squashfs-combined-efi 等
- 发布：GitHub Release（保留最近 3 个版本）
