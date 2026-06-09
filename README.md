# SeewoPan

SeewoPan 是一个基于 Flutter 开发的「希沃品课云盘」第三方客户端，用于在桌面端、移动端和 Web 端浏览、管理、上传、下载希沃品课云盘中的资料。项目还内置本地 WebDAV 代理，方便把希沃云盘挂载到系统文件管理器或其他支持 WebDAV 的客户端中使用。

> 本项目为第三方客户端，与希沃官方无隶属关系。使用前需要自行准备可访问 `pinco.seewo.com` 的账号 Cookie。

## 功能作用

- 云盘文件管理：浏览云盘目录，进入文件夹，搜索资料，按名称、大小、时间等方式排序。
- 文件操作：上传文件、新建文件夹、重命名、移动、删除、批量选择、批量移动、批量删除。
- 下载与上传队列：统一管理上传和下载任务，显示进度、速度和状态，支持暂停、继续、取消、失败重试。
- 本地文件下载：可设置默认下载目录，下载完成后可直接打开文件或所在文件夹。
- 文件预览：支持图片、PDF、音视频、Office 文档和部分 3D 文件的在线预览；不支持的类型可复制地址后用外部应用打开。
- 分享能力：可创建文件分享链接，设置有效期和私密分享，并复制分享信息。
- 账号与容量：通过 Cookie 访问云盘资料，支持查看用户信息、空间占用和每日签到入口。
- 本地 WebDAV 代理：可在设置页启动 WebDAV 服务，通过用户名、密码和端口配置把云盘暴露给本机或局域网客户端。
- 多端适配：使用 Material Design 3，目标平台覆盖 Android、iOS、Web、macOS、Windows、Linux。

## 适用场景

- 在非官方客户端环境下集中管理希沃品课云盘资料。
- 批量上传、下载教学文件，并跟踪传输状态。
- 在桌面系统中把希沃云盘作为 WebDAV 目录访问。
- 通过本地 API 获取云盘文件的官方下载链接，接入自动化脚本或其他工具。

## 快速开始

准备 Flutter stable 环境后执行：

```bash
flutter pub get
flutter run
```

如果 `flutter` 未加入 PATH，可使用绝对路径：

```bash
~/flutter/bin/flutter pub get
~/flutter/bin/flutter run
```

运行后在「我的」页填写并保存 Cookie，再回到「云盘」页加载资料。

## WebDAV 使用

在应用「设置」页可配置并启动 WebDAV 代理：

- 默认端口：`8088`
- 认证方式：HTTP Basic Auth
- 用户名和密码：在设置页自行配置
- 访问地址：启动后页面会显示本地服务地址

除标准 WebDAV 方法外，服务还提供下载链接查询接口。详见 [WebDAV HTTP API](docs/webdav-api.md)。

## 命令行工具

仓库内包含一个 Node.js 命令行工具，位于 `cli/` 目录，可用于上传文件、上传目录、删除文件、创建文件夹、列出云盘文件和查询容量。

```bash
cd cli
node src/cli.js help
```

更多用法见 [CLI 文档](cli/README.md)。

## 项目结构

```text
lib/
  app/        应用入口、主题、主导航和首页状态编排
  features/   云盘、传输、我的、设置、WebDAV 等业务模块
  shared/     API Client、模型、下载目录等通用能力
test/         Flutter 单元测试和组件测试
docs/         项目补充文档
cli/          希沃云盘 Node.js 命令行工具
android/      Android 平台工程
ios/          iOS 平台工程
web/          Web 平台工程
macos/        macOS 平台工程
windows/      Windows 平台工程
linux/        Linux 平台工程
```

## 开发与检查

```bash
flutter analyze
flutter test
```

本仓库使用 `flutter_lints` 做基础代码规范检查。涉及功能行为变化时，应补充或更新对应测试。

## 文档

- [WebDAV HTTP API](docs/webdav-api.md)
- [CLI 文档](cli/README.md)
