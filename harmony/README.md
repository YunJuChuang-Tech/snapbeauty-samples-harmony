# HarmonyOS 相机美颜示例

独立 ArkTS / CameraKit 工程，Bundle 名称 `ai.snapbeauty.samples`。通过 `@snapbeauty/core` 的公开 `SnapBeautyEngine`、`SkinParams` 和 `FaceParams` 接入，宿主安装器合并基础资源与自有妆容，不引用 SDK 工作区或私有原生接口。

相机页提供 11 项美肤、25 项美型、与 Android/iOS 同源的 15 套自制妆容及 27 个 LUT，支持妆容滤镜联动、独立浓度、双向参数中性值 0、单项还原、全重置、按住对比、面板收放、前后镜头和参数/选项保存。妆容与滤镜直接显示 ID。默认只启用基础美肤，美型中性，无妆容和滤镜；单项还原回中性，全重置回基础美肤默认值。

鸿蒙固定使用 OHPM 上的 SnapBeauty **1.3.0**，以根目录 `sdk.lock.json` 的大小与 SHA-256 为准。HAR 不含妆容贴图、唇色、面板图标和目录；`prepare_makeup.py` 从 `harmony/HostAssetsSource/` 的 53 份原创素材生成鸿蒙的宿主资源，`MakeupAssets.ets` 校验并合并图像索引后交给引擎。SDK 新增能力尚未全部提供示例 UI。美颜效果需要有效应用绑定 License；未授权时返回原图。TRTC、Agora、ZEGO 鸿蒙场景尚未实现。

## 准备与构建

需要 Python 3.9+、NumPy、Pillow、Node.js、OHPM 5.x，以及可编译 API12 的 DevEco / OpenHarmony 工具链。本次验证使用 OpenHarmony **5.0.0.71/API12** 和 Hvigor/plugin **5.7.0**，不是商业 HarmonyOS SDK 认证结果。

在仓库根目录准备并校验已发布的 HAR：

```powershell
python harmony/prepare.py
cd harmony
ohpm install
```

脚本从 OHPM 下载 HAR，校验大小、SHA-256、包身份和资源边界，保存一份到 `.local/snapbeauty.har` 供构建核对，并生成 `entry/src/main/resources/rawfile/demo-makeup/`。应用依赖由 OHPM 根据 `entry/oh-package.json5` 远程解析；也可用 `--har` 指定相同的本地 HAR 用于校验。原生库与基础 rawfile 由 Hvigor 自动合并；宿主妆容由本工程提供。随包 NOTICE 和 Monocypher 声明保留在应用内。修改共用妆容后重新运行 `python harmony/prepare_makeup.py`，或直接运行 `build.py`，构建会自动刷新。

DevEco Studio 打开 `harmony/`，Sync 后构建 entry/default；在 Signing Configs 配置设备签名后运行。签名私钥、设备证书、构建依赖和 SDK 载荷均不入库。

准备脚本默认使用仓库中的 samples 体验授权 `harmony/SampleLicense/snapbeauty.license`；自行获取的授权可放到忽略目录 `harmony/.local/snapbeauty.license`，它会优先于默认授权。授权需与应用匹配，重新运行 `prepare.py` 后生效；无效授权显示原图。

可选命令行复建（仓库根目录）：

```powershell
New-Item -ItemType Directory -Path harmony/.local/tooling -Force | Out-Null
Copy-Item harmony/tooling/package*.json harmony/.local/tooling/
npm.cmd ci --prefix harmony/.local/tooling --ignore-scripts --no-audit --no-fund --registry=https://repo.harmonyos.com/npm/
python harmony/build.py --sdk C:/path/to/sdk
node harmony/tests/check_models.cjs
```

SDK 路径须包含 `12/ets`、`12/js`、`12/native`、`12/toolchains`、`12/previewer`。脚本只写本项目配置、工具链接和构建目录，不改变全局 SDK 配置。输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`；校验收据 `build/build-report.json`。

## 帧与生命周期

CameraKit 投送至 `attach()` 返回的输入 Surface，SDK 绘制至 XComponent 显示 Surface。页面固定竖屏，通过 CameraKit 设置预览旋转，再将旋转后尺寸和前置镜像状态传入 `configureFrame()`。

全局串行队列确保只有一个 SDK 预览。切镜头、后台、页面隐藏或 Surface 销毁会使旧请求失效；停止 Session，释放 PreviewOutput、CameraInput 后才释放引擎。对比状态在手势取消和生命周期变化时清除。权限拒绝后，在系统设置授权，再点击“重试预览”。
