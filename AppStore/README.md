# YHPhotos App Store 截图素材

App Preview 已从交付物和调试代码中移除。当前提供简体中文、繁体中文和英文三套宣传截图；每套包含 6 张 iPhone 6.9 英寸截图与 3 张 iPad 13 英寸截图。

Apple 允许每种设备尺寸、每种语言上传 1–10 张截图：

- <https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/>
- <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/>

## 上传目录

| App Store Connect 语言 | iPhone 6.9 英寸 | iPad 13 英寸 |
| --- | --- | --- |
| 简体中文 | `Screenshots-iPhone/` | `Screenshots-iPad/` |
| 繁体中文 | `Screenshots-iPhone-zh-Hant/` | `Screenshots-iPad-zh-Hant/` |
| 英语 | `Screenshots-iPhone-en/` | `Screenshots-iPad-en/` |

iPhone 文件均为 1320 × 2868 RGB JPEG；iPad 文件均为 2064 × 2752 RGB JPEG。全部无透明通道，文件名前缀即建议上传顺序。

## 本地化说明

- 英文宣传图使用英文 App UI、英文示例数据和英文宣传文案。
- 繁体中文宣传图使用繁体宣传文案及繁体示例数据。
- 当前工程的 `Localizable.xcstrings` 与 Xcode `knownRegions` 尚未声明 `zh-Hant`；直接以繁体系统语言启动时，App UI 会回退到英文。因此截图脚本暂时让通用界面使用中文源语言，避免出现英文 UI 与繁体资料混排。完整上架前，仍建议补齐正式 `zh-Hant` String Catalog 本地化。

## 生成与复现

- `Raw*` 目录保存各语言的真实 Simulator 截图。
- `capture_localized_screenshots.sh` 负责启动本地演示数据并截图。
- `render_store_screens.swift` 将真实截图与艺术背景排版成三套商店成品。
- Debug 演示数据由 `#if DEBUG` 隔离，不进入 Release 功能路径。

重新排版全部语言：

```sh
CLANG_MODULE_CACHE_PATH=/tmp/YHPhotosSwiftCache \
SWIFT_MODULECACHE_PATH=/tmp/YHPhotosSwiftCache \
swift AppStore/render_store_screens.swift
```

## 艺术背景

生成文件：`background-blue-hour.png`

生成提示词：

> Use case: ads-marketing. Asset type: reusable App Store screenshot backdrop, portrait. Primary request: create a premium abstract background inspired by an aviation photography darkroom at blue hour; deep near-black navy at the bottom, subtle cool cyan glow and very faint runway-light bokeh near the upper third, restrained and elegant. Style/medium: polished cinematic photographic abstraction, soft depth, high-end Apple-like product presentation backdrop. Composition/framing: portrait 9:19.5, calm negative space, no focal object, no device frame. Lighting/mood: low-key, quiet, precise, premium. Color palette: #05080D, midnight blue, muted cyan, tiny hints of cool silver. Constraints: background only; no aircraft, no people, no app UI, no icons, no text, no logos, no trademarks, no watermark; must stay dark enough for white typography and a bright phone screenshot card.

提交前请确认示例照片及地图内容拥有在 App Store 营销素材中展示的权利。
