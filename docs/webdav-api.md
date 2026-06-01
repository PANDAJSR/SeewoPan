# WebDAV HTTP API

SeewoPan 的本地 WebDAV 服务除标准 WebDAV 方法外，还提供一个 JSON API，用于获取希沃云盘文件的直连下载链接。该链接由希沃云盘接口返回，客户端可直接请求该 URL 下载文件，不经过 SeewoPan 本地代理转发。

## 基础信息

- Base URL：`http://0.0.0.0:{port}`（服务默认监听 `0.0.0.0`，局域网设备请使用运行 SeewoPan 设备的局域网 IP 访问）
- 默认端口：`8088`
- 认证：沿用设置页中的 WebDAV 用户名和密码，使用 HTTP Basic Auth。
- Content-Type：响应为 `application/json`。

## 获取文件直连下载链接

```http
GET /__seewopan/api/download-link?path=/课程/试卷.pdf
```

也可以直接用希沃云盘 materialId 查询：

```http
GET /__seewopan/api/download-link?id=material-id
```

### Query 参数

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `path` | 与 `id` 二选一 | WebDAV 路径，必须指向文件，支持中文和空格等 URL 编码字符。 |
| `id` | 与 `path` 二选一 | 希沃云盘文件 materialId。使用 `id` 时响应中不保证包含 `name`、`size`、`mimeType`。 |

### 成功响应

```json
{
  "materialId": "file-material-id",
  "name": "试卷.pdf",
  "size": 1048576,
  "mimeType": "application/pdf",
  "url": "https://cstore-pri-pinco-bs.seewo.com/...",
  "source": "downloadUrl"
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `materialId` | 希沃云盘文件 ID。 |
| `name` | 文件名；使用 `id` 查询时可能为 `null`。 |
| `size` | 文件大小；使用 `id` 查询时可能为 `null`。 |
| `mimeType` | MIME 类型；使用 `id` 查询时可能为 `null`。 |
| `url` | 希沃云盘返回的直连下载 URL。 |
| `source` | URL 来源，优先为 `downloadUrl`，缺失时回退为 `previewUrl`。 |

### 错误响应

```json
{
  "error": "File not found.",
  "statusCode": 404
}
```

常见状态码：

| 状态码 | 场景 |
| --- | --- |
| `400` | 未提供 `path` 或 `id`。 |
| `401` | Basic Auth 认证失败。 |
| `404` | `path` 指向的文件不存在。 |
| `405` | 请求方法不是 `GET`，或 `path` 指向文件夹。 |
| `503` | 尚未在应用中配置希沃 Cookie。 |

## curl 示例

```bash
curl -u 'seewopan:your-password' \
  'http://192.168.1.10:8088/__seewopan/api/download-link?path=%2F%E8%AF%BE%E7%A8%8B%2F%E8%AF%95%E5%8D%B7.pdf'
```

下载文件：

```bash
url="$(curl -s -u 'seewopan:your-password' \
  'http://192.168.1.10:8088/__seewopan/api/download-link?path=%2F%E8%AF%BE%E7%A8%8B%2F%E8%AF%95%E5%8D%B7.pdf' \
  | jq -r '.url')"
curl -L "$url" -o "试卷.pdf"
```
