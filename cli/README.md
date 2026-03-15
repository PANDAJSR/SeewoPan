# seewo-cli

用于 `pinco.seewo.com` 网盘资源的命令行工具（Node.js 18+）。

支持能力：
- 上传本地文件并返回下载链接
- 上传本地文件夹（逐文件模拟上传）
- 删除单个文件（按 `resId`）
- 创建文件夹
- 罗列网盘文件（可全量翻页）
- 查询容量

说明：上传返回的 `downloadUrl` 为临时签名直链（有过期时间）。

## 1. 安装与运行

当前仓库是纯 Node.js 脚本实现，无第三方依赖。

```bash
node -v
# 需要 >= 18
```

直接运行：

```bash
node src/cli.js help
```

也可以通过 `bin` 方式：

```bash
npm link
seewo help
```

## 2. 鉴权配置

从浏览器开发者工具复制请求头里的完整 `Cookie`，设置到环境变量：

```bash
export SEEWO_COOKIE='acw_tc=...; x-token=...; x-samesite-none-token=...; ...'
```

可选环境变量：

- `SEEWO_BASE_URL`：默认 `https://pinco.seewo.com`
- `SEEWO_CDN_BASE`：默认 `https://cstore-pri-pinco-bs.seewo.com/`
- `SEEWO_X_SERVER`：默认 `default`
- `SEEWO_X_CSRF_TOKEN`：默认 `undefined`
- `SEEWO_LANGUAGE`：默认 `zh_CHS`
- `SEEWO_USER_AGENT`：自定义 UA

## 3. 命令用法

### 3.1 上传文件

```bash
node src/cli.js upload ./daily-quote.txt
```

可选参数：

- `--name <string>`：覆盖上传文件名
- `--mime-type <string>`：覆盖 MIME 类型
- `--parent-folder-id <id>`：父目录 ID，默认 `0`
- `--debug`：打印上传策略调试信息（排查 403/签名问题）
- `--json`：JSON 输出

示例：

```bash
SEEWO_COOKIE='...' node src/cli.js upload ./daily-quote.txt --json
```

上传成功后会输出：

- 文件大小（Bytes + 人类可读）
- 总耗时（从开始请求到完成）
- 上传耗时（OSS 直传阶段）
- 上传速度（按 `文件大小 / 上传耗时` 计算）

### 3.2 列出文件

```bash
node src/cli.js list
```

可选参数：

- `--folder-id <id>`：目录 ID，默认 `0`
- `--page <number>`：页码，默认 `0`
- `--size <number>`：每页数量，默认 `50`
- `--keyword <string>`：关键词过滤
- `--tag-name <string>`：默认 `resource`
- `--resolve-url`：把鉴权下载地址解析为临时签名直链
- `--all`：自动翻页拉取全部
- `--json`：JSON 输出

示例：

```bash
SEEWO_COOKIE='...' node src/cli.js list --all --json
```

说明：

- `list --json` 里的 `id` 与 `resId` 是同一个值，都可用于 `delete <resId>`。

### 3.3 删除单文件

```bash
node src/cli.js delete <resId>
```

可选参数：

- `--id <resId>`：素材 ID（与位置参数等价）
- `--json`：JSON 输出

示例：

```bash
SEEWO_COOKIE='...' node src/cli.js delete 770339e1238a4cbb8c558fb8d2d319ac
```

### 3.4 创建文件夹

```bash
node src/cli.js mkdir lesson-01
```

可选参数：

- `--parent-folder-id <id>`：父目录 ID，默认 `0`
- `--json`：JSON 输出

示例：

```bash
SEEWO_COOKIE='...' node src/cli.js mkdir lesson-01 --parent-folder-id 0 --json
```

### 3.5 上传本地目录

```bash
node src/cli.js upload-dir ./my-folder
```

可选参数：

- `--parent-folder-id <id>`：父目录 ID，默认 `0`
- `--remote-folder-name <name>`：远端根目录名（默认本地目录名）
- `--no-root`：不新建根目录，直接上传到 `parent-folder-id`
- `--flat`：忽略本地子目录层级，所有文件上传到同一目录
- `--debug`：打印单文件上传调试信息
- `--json`：JSON 输出

示例：

```bash
SEEWO_COOKIE='...' node src/cli.js upload-dir ./assets --json
```

### 3.6 查询容量

```bash
node src/cli.js capacity
```

可选参数：

- `--type <number>`：默认 `1`
- `--json`：JSON 输出

示例：

```bash
SEEWO_COOKIE='...' node src/cli.js capacity --json
```

## 4. 上传流程说明

CLI 内部按以下顺序调用接口：

1. `PostV1DriveMaterialsMatch`：按 `md5 + size` 检查是否可命中已有文件。
2. `PostV3CstoreUploadPolicy`：获取 OSS 直传策略（policy/signature/key/callback 等）。
3. 上传到阿里云 OSS：向 `cstore-private.oss-cn-hangzhou.aliyuncs.com` 提交 multipart 表单。
4. `PostV1DriveMaterialsCstoreWay`：把 OSS 对象注册成网盘素材，返回最终素材信息。

如果第 1 步返回命中并给出有效 `fileKey/downloadUrl`，CLI 会直接跳过上传。

## 5. API 文档

- OpenAPI 规范（可导入 Swagger/Apifox）：`docs/openapi.yaml`
- 使用讲解（逐个接口解释）：`docs/api-usage.md`
