# Molian

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 故障排除

### 控制台出现 `background.js`、`FrameIsBrowserFrameError`、`utils.js` / `extensionState.js` 找不到

这些报错**来自浏览器扩展**（如 VPN、广告拦截、隐私插件等），不是本应用代码。扩展在部分页面（如新标签页、chrome://）注入脚本时会触发 `FrameIsBrowserFrameError`，`ERR_FILE_NOT_FOUND` 多为扩展自身资源路径错误。

**建议**：在浏览器中调试或测试登录/注册时，用无痕模式并关闭扩展，或暂时禁用可能改请求的扩展，以排除干扰。

### 更换 IP 或网络后无法注册/登录

应用已对认证接口（注册、登录、/auth/me）在连接超时或连接错误时**自动重试一次**，并适当提高了超时时间。若仍失败，请检查：

- 当前网络能否访问 API 基地址（默认 `https://molian-api.zhih2333.workers.dev`）；
- 是否有浏览器扩展拦截或修改请求（参见上文）。
