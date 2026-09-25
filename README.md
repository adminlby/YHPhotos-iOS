# YHPhotos iOS

YHPhotos 航摄图库的原生 SwiftUI 客户端，支持 iPhone 与 iPad，最低系统版本为 iOS / iPadOS 17。

## 当前实现

- 发现首页、社区统计与航空 / 铁路 / 模拟飞行分区
- 作品详情、全站搜索、地图浏览与百科入口
- 外部用户详情、个人中心、消息与原生上传流程
- 与网站共用 Casdoor SSO，通过系统认证会话回调 App
- DeviceCheck App Attest 校验原生客户端来源；会话和来源令牌保存在 Keychain
- iOS 26 使用系统 Liquid Glass，iOS 17–18 使用原生 Material 回退
- 自定义悬浮玻璃底栏，四周均与设备边缘保持间距

## 开发配置

- Xcode 工程：[YHPhotos.xcodeproj](YHPhotos.xcodeproj)
- Debug API：`https://dev.yhphotos.top`
- Release API：`https://www.yhphotos.top`
- Bundle ID：`com.yhphotos.app`
- 当前签名 Team ID：`U93J9KY6T7`
- SSO 回调 Scheme：`yhphotos://sso-callback`

真机运行需要在签名能力中启用 App Attest。App Attest 不支持普通模拟器环境，因此登录和联网接口应使用已签名真机验证。

## 设计参考

- [iPhone / iPad 视觉方向与参考图](Design/README.md)

## 本地构建验证

```sh
xcodebuild -project YHPhotos.xcodeproj \
  -scheme YHPhotos \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```
