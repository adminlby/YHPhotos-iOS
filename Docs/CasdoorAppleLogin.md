# Casdoor + Sign in with Apple 配置清单

YHPhotos iOS 使用系统浏览器完成 Casdoor SSO，Apple 是 Casdoor 内的登录方式。App 不保存 Apple `.p8` 密钥、Casdoor Client Secret 或用户 Apple 凭据。

## 1. Apple Developer

1. 在 App ID `com.yhphotos.app` 上开启 **Sign in with Apple**，并将它设为 Primary App ID。
2. 创建或选择给 Web SSO 使用的 **Services ID**。这个 identifier 是 Casdoor Apple Provider 的 `Client ID`，不是 iOS Bundle ID。
3. 在 Services ID 的 Sign in with Apple Web 配置中：
   - Primary App ID：`com.yhphotos.app`
   - Domains and Subdomains：`auth.yhphotos.top`
   - Return URL：从 Casdoor Apple Provider 页面复制显示的 Redirect URL，必须完全一致。
4. 创建 Sign in with Apple Key，关联 `com.yhphotos.app`，记录 Key ID，下载仅能下载一次的 `.p8`。
5. Team ID：`U93J9KY6T7`。

## 2. Casdoor Apple Provider

在 Casdoor 后台创建 Apple Provider，填写：

- Client ID：Apple Services ID
- Team ID：`U93J9KY6T7`
- Key ID：Apple Key ID
- Key Text：`.p8` 的完整内容，包含 BEGIN/END 行
- Redirect URL：用于 Apple Services ID 的 Return URL

在 YHPhotos 的 Casdoor Application 内启用该 Provider：

- `Can sign up`：开
- `Can sign in`：开
- `Can unlink`：开，作为用户主动解绑/换绑入口
- `Binding rule`：仅选 `Email`
- `Enable Email linking`：当前保持关闭；确认部署版本已修复下述 MFA 绑定问题后再开启

GitHub 安全公告 [GHSA-gv4m-v8c8-hr3g](https://github.com/advisories/GHSA-gv4m-v8c8-hr3g) 显示，Casdoor 2.362.0 及更早版本的社交登录绑定路径可绕过已配置 MFA，且公告当前没有列出已修复版本。因此，在部署版本或自有补丁未经验证前，仅保留用户在账号中心的显式绑定。YHPhotos 后端的已验证邮箱首次绑定逻辑已就绪，安全条件满足后只需打开该开关。

## 3. YHPhotos 服务端

```env
CASDOOR_ACCOUNT_URL=https://auth.yhphotos.top/account
```

服务端的绑定不变式：

- `issuer + subject` 精确匹配时直接登录。
- 仅已验证邮箱可触发首次自动绑定。
- 仅未绑定 Casdoor 的本地账号可被自动绑定。
- 已绑定账号不会因为相同邮箱而替换 subject。
- Apple “隐藏我的邮箱”导致邮箱不匹配时，用户先登录原账号，再在 App 的“账号与安全”打开 Casdoor 账号中心显式绑定。

## 4. 验收

1. 新用户使用 Apple 登录，只创建一个 YHPhotos 账号。
2. 已有未绑定账号，Apple 返回相同已验证邮箱时自动合并。
3. 未验证邮箱不得自动合并。
4. 已绑定账号遇到不同 subject 时返回 `sso_account_conflict`，不更改原绑定。
5. 隐藏邮箱的用户能从 App 打开账号中心完成手动绑定。

> 当前 App 走 Casdoor Web SSO，所以 Xcode target 不需要 Sign in with Apple entitlement。只有改为原生 `AuthenticationServices` 直连 Apple 时，才在 target 中加该 entitlement。
