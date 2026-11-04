# Syllapace 标志

标志由两个相差 180° 的厚弧模块组成，留出的负形表达日程向前推进的节拍。它延续主界面的青绿色，以简单、独立的几何轮廓建立识别。

用户提供的风格参考为 Codex、Slack 和 Linear（参考入口：[OpenAI](https://openai.com/brand/)、[Slack](https://app.slack.com/media-kit)、[Linear](https://linear.app/brand)）；这里借鉴的是少元素、大负形、单色可用的设计方式。图形路径为本项目自绘，没有使用这些品牌的图形资产，也没有使用 SF Symbols、外部字体或书本／日历图案。

## 文件

| 文件 | 用途 |
| --- | --- |
| [logo.svg](logo.svg) | 默认青绿版本，`#26786e`，透明背景 |
| [logo-black.svg](logo-black.svg) | 近黑版本，`#161c1b`，透明背景 |
| [logo-white.svg](logo-white.svg) | 白色版本，`#ffffff`，透明背景，适合深色底 |
| [logo-preview.png](logo-preview.png) | 512 × 512 浅色背景查看预览；不是矢量母版 |

三个 SVG 都由相同的两个填充路径组成，不嵌入位图，不使用渐变、阴影、滤镜、描边、字体或外部依赖。需要放大、印刷或继续编辑时，使用 SVG。

## 尺寸与留白

- `viewBox="224 224 576 576"`。图形本身在原坐标的 256–768 范围，四周预留 32 单位净空。
- 保持宽高比与两个路径的相对位置。现有 32 单位为最小留白；拥挤背景可增加留白。
- 建议显示宽度至少 16 px；需要清晰展示两个模块间的负形时，优先使用 24 px 及以上。
- 青绿和近黑版本用于浅底，白色版本用于深底；不要把低对比度配色用于小尺寸标志。

## App icon

应用图标位于 [Icon/AppIcon.icon](../Icon/AppIcon.icon)，使用同源的 [上弧](../Icon/AppIcon.icon/Assets/pace-upper.svg) 与 [下弧](../Icon/AppIcon.icon/Assets/pace-lower.svg) 路径，在 1024 画布中以中心点放大 1.0625 倍并分为两层。图标的材质、圆角遮罩与外观适配由 Icon Composer / macOS 生成；这些系统效果不写入独立 logo 母版。

本轮交付图形标志，可直接用于应用、项目主页和文档。
