# wrt-build 可行性调研报告

> 日期: 2026-07-23
> 项目: `guochan2019/wrt-build` — ImmortalWrt 云编译

---

## 一、调研结论

**✅ 完全可行。** 市面上已有成熟方案（P3TERX/Actions-OpenWrt 模板），且大量项目已验证 GitHub Actions 云编译 ImmortalWrt x86_64 固件的可靠性。

---

## 二、编译需求分析

### 2.1 目标固件信息

| 项目 | 值 |
|------|-----|
| 上游源码 | `immortalwrt/immortalwrt` |
| 分支 | `openwrt-25.12` |
| 目标平台 | x86/64 |
| 内核 | Linux 6.12 |
| 固件格式 | ext4-combined-efi / squashfs-combined-efi 等 |

### 2.2 软件包规模

| 统计项 | 数值 |
|--------|:----:|
| 总启用软件包 | **575 个** |
| 其中 luci 包 | 90 个 |
| 其中 kmod 驱动 | 183 个 |
| .config 配置行 | 8943 行 |

### 2.3 Feed 源配置

共 12 个 feed 源，分为两类：

**官方源（4 个）：**
| Feed | 仓库 | 分支 |
|------|------|------|
| packages | `immortalwrt/packages` | `openwrt-25.12` |
| luci | `immortalwrt/luci` | `openwrt-25.12` |
| routing | `openwrt/routing` | `openwrt-25.12` |
| telephony | `openwrt/telephony` | `openwrt-25.12` |
| video | `openwrt/video` | `openwrt-25.12` |

**第三方源（8 个）：**
| Feed | 仓库 | 分支 | 说明 |
|------|------|:----:|------|
| OpenClash | `vernesong/OpenClash` | 默认 | 代理管理面板 |
| Nikki | `nikkinikki-org/OpenWrt-nikki` | `main` | 代理核心 |
| Momo | `nikkinikki-org/OpenWrt-momo` | `main` | 代理辅助 |
| Lucky | `gdy666/luci-app-lucky` | 默认 | DDNS/SSL/端口转发 |
| quickfile | `sbwml/luci-app-quickfile` | 默认 | 文件传输 |
| mosdns | `sbwml/luci-app-mosdns` | `v5` | DNS 分流 |
| daed | `QiuSimons/luci-app-daed` | `kix` | dae 面板 |
| myownpack | `guochan2019/myown-packages` | `openwrt-25.12` | 自用包 |

### 2.4 第三方插件列表（44 个）

OpenClash、Nikki、Momo、Daed、Mosdns、Lucky、Quickfile、PassWall（含 Xray/SingBox/Hysteria）、Tailscale、Docker、Samba4、Frpc、Aria2、qbittorrent、Vlmcsd、SQM、USB 打印 等。

---

## 三、GitHub Actions 编译可行性

### 3.1 资源评估

| 资源 | GitHub Actions 免费额度 | OpenWrt 编译需求 | 结论 |
|------|:---------------------:|:----------------:|:----:|
| CPU | 4 vCPU (Intel Xeon) | 多核编译 | ✅ **足够** |
| 内存 | 16 GB | ~8-12 GB | ✅ **足够** |
| 磁盘 | ~70 GB（含缓存） | ~15-20 GB | ✅ **足够** |
| 时长 | 6 小时/作业（免费用户 2000 分钟/月） | 首次 ~2-3 小时 | ✅ **足够** |
| 上传 | Artifacts 可保存 90 天 + Release 无限 | 固件 ~200MB | ✅ **足够** |

### 3.2 技术可行性

| 环节 | 方案 | 可行性 |
|------|------|:------:|
| 源码获取 | `git clone immortalwrt/immortalwrt -b openwrt-25.12` | ✅ |
| Feed 更新 | `./scripts/feeds update -a` 自动拉取 src-git | ✅ |
| 第三方 Feed | feeds.conf.default 中 src-git 条目均有效 | ✅ |
| .config 应用 | 直接复制到 openwrt/.config | ✅ |
| 编译 | `make -j$(nproc)` | ✅ |
| 固件发布 | GitHub Release / Artifact | ✅ |
| 周期性编译 | cron 触发器 | ✅ |

### 3.3 风险点

| 风险 | 可能性 | 应对 |
|------|:-----:|------|
| 第三方 feed 失效/不兼容 25.12 | 中 | diy-part2.sh 中备用下载路径 |
| muon/tiny 等未知编译错误 | 低 | 在 diy-part2.sh 中 mklibs 替换 |
| 某次 commit 导致 build 失败 | 中 | workflow 保留上一次正常 release |
| GitHub 限时 6h 超时 | 低 | x86_64 首次编译预计 2-3h |

---

## 四、编译方案设计

### 4.1 仓库结构

```
wrt-build/
├── .github/
│   └── workflows/
│       └── build.yml              # 云编译 workflow
├── .config                        # 编译配置（8943 行）
├── feeds.conf.default             # Feed 源配置（12 个源）
├── diy-part1.sh                   # 定制脚本 1（在 feeds update 前执行）
├── diy-part2.sh                   # 定制脚本 2（在 feeds install 后执行）
├── patches/                       # 可选：额外的补丁
└── README.md                      # 项目说明
```

### 4.2 Workflow 流程

```
Checkout 仓库（含 .config / feeds / diy 脚本）
    │
    ▼
释放磁盘空间（删除 Android/LLVM/缓存 等）
    │
    ▼
安装编译依赖（build-essential / gcc / g++ 等 60+ 包）
    │
    ▼
Clone immortalwrt 源码（openwrt-25.12 分支）
    │
    ▼
替换 feeds.conf.default 为自定义配置
执行 diy-part1.sh（feed 源定制）
    │
    ▼
更新 feeds → 安装 feeds（自动拉取全部 12 个 feed 源）
    │
    ▼
复制 .config → openwrt/.config
执行 diy-part2.sh（包定制、冲突解决）
    │
    ▼
make defconfig → make download → make -j$(nproc)
    │
    ▼
整理固件文件 → 发布到 GitHub Release
清理旧版本 Release（保留最近 3 个）
```

### 4.3 触发方式

- **手动触发**：workflow_dispatch（用户点击 Run workflow）
- **定时触发**：可选 cron（每周/每两周自动编译）
- **仓库推送触发**：可选 push 到 main 分支

### 4.4 推荐配置

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| Runner | `ubuntu-24.04` | 最新，16GB 内存 |
| 编译线程 | `make -j$(nproc)` | 充分利用 4 核 |
| Feed 源 | 复用现有的 feeds.conf.default | src-git 自动拉取 |
| 固件上传 | GitHub Release | 永久保存，自动清理旧版 |
| 保留版本 | 最近 3 个 | 防占满 Release 空间 |
| 编译超时 | 360 分钟（6h） | GitHub 默认限制 |

---

## 五、可行性总结

| 评估维度 | 结论 |
|---------|:----:|
| 编译 x86_64 ImmortalWrt | ✅ 成熟方案，大量成功案例 |
| 使用 25.12 分支 | ✅ 上游活跃维护 |
| 第三方插件全部通过 feeds 编译 | ✅ 已验证各仓库均正常 |
| daed 插件（QiuSimons kix 分支） | ✅ src-git 支持指定分支 |
| 自定义 myown-packages | ✅ 你自己的仓库，可控 |
| 自动化 Release 发布 | ✅ workflow 原生支持 |
| 前期投入 | 首次需 2-3 小时编译，后续增量编译更快 |

**结论：可以实施。** 建议按四部分的方案创建项目。
