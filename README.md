# SnapBeauty HarmonyOS Samples

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-HarmonyOS-blue.svg)](harmony/README.md)
[![API](https://img.shields.io/badge/API-12%2B-brightgreen.svg)](harmony/README.md)

本仓库提供 SnapBeauty 移动端美颜/美妆 SDK 在 HarmonyOS（鸿蒙）平台的接入示例，演示基于 ArkTS、CameraKit 与 XComponent 的本地相机实时美颜集成方案。

---

## 特性亮点

- **全功能美颜控制**：包含 11 项美肤（磨皮、美白、红润、锐化等）、25 项微整形美型、15 套原创数学生成整妆与 27 个动态 LUT 调色滤镜。详见 [效果与参数清单](docs/EFFECTS.md)。
- **原生 CameraKit 与 XComponent 架构**：通过 CameraKit 采集投送至 SDK 输入 Surface，由美颜引擎渲染至宿主 XComponent 显示 Surface，支持前后置摄像头切换、预览旋转与镜像自适应。
- **开箱即用体验授权**：仓库默认内置官方 Samples 体验授权文件（`harmony/SampleLicense/snapbeauty.license`），开发者克隆后可直接运行验证，无需前置申请。
- **数学程序化原创素材**：内置 53 份美妆纹理（`harmony/HostAssetsSource/`）均由数学公式程序化生成，无第三方图片版权争议。详见 [素材来源](docs/ASSETS.md)。

---

## 快速开始

### 环境要求

- DevEco Studio 5.0+ / OpenHarmony SDK API 12（版本 5.0.0.71 及以上）
- Hvigor 5.7.0+ / OHPM 5.x
- Node.js 18+ / Python 3.9+（附带 NumPy 与 Pillow）

### 依赖准备与安装

在仓库根目录下执行准备脚本，从 OHPM 下载并校验 `@snapbeauty/core` 1.3.0 HAR 包，并自动准备宿主美妆资源：

```powershell
# 校验并准备 SDK 依赖与宿主美妆资源
python harmony/prepare.py

# 进入 harmony 工程目录安装依赖
cd harmony
ohpm install
```

### 构建与运行

1. 使用 DevEco Studio 打开仓库中的 `harmony/` 目录。
2. 待项目 Sync 完成后，在 **File > Project Structure > Project > Signing Configs** 中配置设备签名。
3. 选择 `entry` 模块直接运行到 HarmonyOS 物理设备。

#### 自定义授权说明 (License)

准备脚本默认使用仓库内的体验授权；如需使用自行申请的正式商业授权，请将其放置于本地忽略路径：
```text
harmony/.local/snapbeauty.license
```
重新执行 `python harmony/prepare.py` 即可优先载入生效；未提供或授权无效时，SDK 将自动旁路直出原图。

详细构建流程与自动化测试说明见 [鸿蒙工程详细说明](harmony/README.md)。

---

## 目录结构

```text
snapbeauty-samples-harmony/
├── harmony/                         # HarmonyOS 完整工程根目录
│   ├── AppScope/                    # 应用全局资源与配置
│   ├── HostAssetsSource/            # 示例原创美妆素材源文件
│   ├── SampleLicense/               # 官方公开体验授权
│   ├── entry/                       # 示例主应用模块 (ArkTS/UI)
│   ├── prepare.py                   # 依赖下载、哈希核验与资源准备脚本
│   ├── prepare_makeup.py            # 美妆资源转换与打包脚本
│   └── README.md                    # 鸿蒙工程环境与构建详解
├── sdk.lock.json                    # SDK 版本、文件大小与 SHA-256 锁定文件
├── THIRD_PARTY_NOTICES.md           # 第三方依赖与开源声明
└── LICENSE                          # 开源许可证 (Apache 2.0)
```

---

## 许可证与法律声明

1. **示例工程源码**：本项目除第三方组件外的示例代码及自有素材均遵循 [Apache License 2.0](LICENSE) 开源。
2. **底层 SDK 说明**：`@snapbeauty/core` 为商业专有美颜 SDK，从 OHPM 官方仓库获取，其使用及商业再分发遵循 SnapBeauty 官方商业授权条款。
3. **第三方声明**：有关运行时依赖与开源许可详情，参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
