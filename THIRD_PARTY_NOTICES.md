# Third-party notices

The sample source and original artwork follow the repository Apache 2.0 license. The SnapBeauty SDK, models and effect resources are separately licensed; check the provider terms and bundled notices for use and redistribution.

The HarmonyOS sample uses `@snapbeauty/core` 1.3.9 published on OHPM; its HAR and dependencies are not committed. OpenHarmony SDK and Hvigor are acquired separately and subject to their own licenses.

The makeup artwork in `harmony/HostAssetsSource` was authored for this sample using equations and pigment values; SDK layer identifiers and UV anchors are used for interoperability. The HarmonyOS application icon is original artwork.

## 滤镜 LUT（CC BY-SA 4.0）

`harmony/HostAssetsSource/host-filters/luts/` 中的 10 张滤镜（`bright3`、`rose3`、`stylized11`、`mono1`、`warm1`、`warm2`、`fresh1`、`muted5`、`natural2`、`natural4`）不属于 SnapBeauty SDK，由本示例随 App 一起打包，由 `prepare_makeup.py` 解码为 RGBA 后随 HAP 打包，启动时用 SDK 的 `registerFilter` 注册，之后和 SDK 内置滤镜一样用 `setFilter` 选择。

- 素材来源：RawTherapee Film Simulation Collection 2015-09-20（https://rawtherapee.com/shared/HaldCLUT.zip ），作者 **Pat David、Pavlov Dmitry、Michael Ezra**。
- 改动：重采样为 64³，用强度、提亮、冷暖、色调、饱和度、对比度六个全局参数调整，再三线性采样为 16³ 并量化为 RGB8（256×16）。
- 许可：原素材与改编后的 LUT 均按 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 提供，不适用本仓库的 Apache 2.0。逐项来源、改动说明与许可全文与 LUT 放在同一目录（`NOTICE.md`、`LICENSE-CC-BY-SA-4.0.txt`、`RawTherapee-README.txt`），会打包进 App。署名不表示原作者认可本项目。
- 基于本示例发布 App 时，如保留这些滤镜，须一并保留上述署名与许可文件；不需要时删除该目录即可，其余功能不受影响。
