# Seewo 网盘 API 使用说明

本文基于你提供的抓包整理，目标是解释这些 API 在上传/列表流程里的角色与调用顺序。

## 1. 总览

业务 API 统一走：

- `POST https://pinco.seewo.com/teacher/api.json?actionName=<ActionName>`

对象存储上传走：

- `POST https://cstore-private.oss-cn-hangzhou.aliyuncs.com/`

你给出的完整链路是：

1. `PostV1DriveMaterialsMatch`
2. `PostV3CstoreUploadPolicy`
3. `OSS POST /`（multipart 文件直传）
4. `PostV1DriveMaterialsCstoreWay`
5. `GetV1DriveMaterials`
6. `GetV1DriveMaterialsCapacity`
7. `GET /server-main/api/v1/drive/materials/download?resId=...`（下载重定向）
8. `DeleteV1DriveMaterials`
9. `PostV1DriveMaterialsFolders`

## 2. 公共请求头与鉴权

业务 API 常见头：

- `Cookie`: 核心鉴权信息，通常包含 `x-token` 与 `x-samesite-none-token`
- `x-req-traceid`: 请求追踪 ID（每次随机）
- `x-csrf-token`: 抓包里是 `undefined`，建议保持与浏览器一致
- `x-server: default`
- `Origin` / `Referer`: 通常来自 `https://pinco.seewo.com`

建议：

- 由登录态浏览器复制完整 `Cookie`，CLI 通过环境变量注入
- token 过期会导致业务 API 返回鉴权失败，需要重新抓取

## 3. 各接口作用与参数

## 3.1 `PostV1DriveMaterialsMatch`

用途：

- 通过 `fileMd5 + fileSize + fileName + mimeType` 检查文件是否命中已有内容（秒传/去重）。

请求体：

```json
{
  "fileMd5": "44d9f02273f3766086d4336640b6c585",
  "fileSize": 2669,
  "fileName": "daily-quote.txt",
  "mimeType": "text/plain"
}
```

实现建议：

- 如果响应里给出 `matched/exists` 且有 `fileKey/downloadUrl`，可以跳过直传。
- 若未命中，则进入 `PostV3CstoreUploadPolicy`。

## 3.2 `PostV3CstoreUploadPolicy`

用途：

- 获取 OSS 直传临时策略，包括 `policy/signature/key/callback` 等字段。

请求体：

```json
{
  "keySuffix": "txt"
}
```

说明：

- `keySuffix` 通常是扩展名（不带点）。
- 返回信息一般含上传 host、对象 key、签名信息、callback 参数等。

## 3.3 `POST https://cstore-private.oss-cn-hangzhou.aliyuncs.com/`

用途：

- 按策略向 OSS 直接上传二进制文件。

关键点：

- `multipart/form-data` 必须带齐策略字段（`OSSAccessKeyId`、`policy`、`Signature`、`key`、`callback` 等）
- `file` 表单项里是真实文件内容
- 常见成功状态是 `200` 或 `204`

## 3.4 `PostV1DriveMaterialsCstoreWay`

用途：

- 直传成功后，把 OSS 对象“入库”为网盘素材。

请求体（示例）：

```json
{
  "fileSize": 2669,
  "downloadUrl": "https://cstore-pri-pinco-bs.seewo.com/...",
  "fileKey": "seewo-pinco-private/xxx.txt",
  "fileMd5": "44d9f02273f3766086d4336640b6c585",
  "name": "daily-quote.txt",
  "parentFolderId": "0",
  "size": 2669,
  "mimeType": "text/plain"
}
```

说明：

- 这个接口决定文件是否最终出现在网盘列表中。
- `parentFolderId` 控制目录位置，根目录一般是 `0`。

## 3.5 `GetV1DriveMaterials`

用途：

- 分页查询素材列表。

请求体：

```json
{
  "keyword": "",
  "size": 50,
  "tagName": "resource",
  "page": 0,
  "folderId": "0"
}
```

说明：

- `page` 从 `0` 开始。
- 需要全量时循环分页直到返回数量 `< size`。

## 3.6 `GetV1DriveMaterialsCapacity`

用途：

- 查询空间容量（已用/总量/剩余）。

请求体：

```json
{
  "type": 1
}
```

## 3.7 `GET /server-main/api/v1/drive/materials/download`

用途：

- 用 `resId` 换取实际可下载地址（通常 302 到带签名参数的 OSS URL）。

示例：

```text
GET https://pinco.seewo.com/server-main/api/v1/drive/materials/download?resId=<素材ID>
```

说明：

- `cstore-private` 桶是私有桶，裸路径（不带签名参数）会返回 `AccessDenied`。
- 需要通过该下载接口获取临时签名 URL（带 `Expires/OSSAccessKeyId/Signature`）。

## 3.8 `DeleteV1DriveMaterials`

用途：

- 删除素材（支持 `resIds` 数组；单文件删除时传 1 个 ID）。

请求体：

```json
{
  "resIds": [
    "770339e1238a4cbb8c558fb8d2d319ac"
  ]
}
```

## 3.9 `PostV1DriveMaterialsFolders`

用途：

- 在指定父目录下创建文件夹。

请求体：

```json
{
  "name": "aaa",
  "parentFolderId": "0"
}
```

## 4. 推荐的上传时序（CLI 实现标准流程）

1. 本地读取文件，计算 `md5` 与 `size`
2. 调 `PostV1DriveMaterialsMatch`
3. 未命中则调 `PostV3CstoreUploadPolicy`
4. 使用策略字段向 OSS 直传文件
5. 调 `PostV1DriveMaterialsCstoreWay` 完成素材登记
6. 基于素材 `id` 调下载接口，解析重定向得到临时签名 `downloadUrl`
7. 输出 `downloadUrl`、`fileKey`

目录上传（本地文件夹）通常是循环执行上述单文件流程，并在需要时先调 `PostV1DriveMaterialsFolders` 建立远端目录结构。

## 5. 常见失败原因

- `Cookie` 过期或缺少 `x-token` 相关字段
- 上传策略超时（policy 有过期时间）
- `mimeType` 与策略允许范围不匹配
- `downloadUrl` / `fileKey` 传参不一致导致入库失败
- 目录 ID 无效（`parentFolderId`）

## 6. 安全建议

- 不要把 Cookie、签名、回调参数提交到仓库
- CLI 使用环境变量读取敏感信息
- 日志避免打印完整 token 与 cookie
