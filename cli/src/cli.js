#!/usr/bin/env node

import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_BASE_URL = 'https://pinco.seewo.com';
const DEFAULT_OSS_HOST = 'https://cstore-private.oss-cn-hangzhou.aliyuncs.com/';
const DEFAULT_DOWNLOAD_BASE = 'https://cstore-pri-pinco-bs.seewo.com/';

function printHelp() {
  const text = `seewo CLI\n\nUsage:\n  seewo <command> [options]\n\nCommands:\n  upload <file>          Upload a local file and return download URL\n  upload-dir <dir>       Upload local directory by iterating files\n  delete <resId>         Delete a single material by id\n  mkdir <name>           Create a folder\n  list                   List uploaded files\n  capacity               Query drive capacity\n  help                   Show this help\n\nShared environment variables:\n  SEEWO_COOKIE           Required. Full Cookie header value from browser request\n  SEEWO_BASE_URL         Optional. Default: https://pinco.seewo.com\n  SEEWO_CDN_BASE         Optional. Default: https://cstore-pri-pinco-bs.seewo.com/\n  SEEWO_X_SERVER         Optional. Default: default\n  SEEWO_X_CSRF_TOKEN     Optional. Default: undefined\n  SEEWO_LANGUAGE         Optional. Default: zh_CHS\n  SEEWO_USER_AGENT       Optional. Browser-like User-Agent\n\nCommand options:\n  upload <file>\n    --name <string>              Override file name\n    --mime-type <string>         Override MIME type\n    --parent-folder-id <id>      Default: 0\n    --debug                      Print upload policy diagnostics\n    --json                       Print JSON output\n\n  upload-dir <dir>\n    --parent-folder-id <id>      Default: 0\n    --remote-folder-name <name>  Remote root folder name (default: local dir name)\n    --no-root                    Do not create root folder; upload into parent folder directly\n    --flat                       Upload all files into one folder (ignore local subdirs)\n    --debug                      Print upload policy diagnostics\n    --json                       Print JSON output\n\n  delete <resId>\n    --id <resId>                 Material id\n    --json                       Print JSON output\n\n  mkdir <name>\n    --parent-folder-id <id>      Default: 0\n    --json                       Print JSON output\n\n  list\n    --folder-id <id>             Default: 0\n    --page <number>              Default: 0\n    --size <number>              Default: 50\n    --keyword <string>           Default: empty\n    --tag-name <string>          Default: resource,folder (both)\n    --resolve-url                Resolve auth URL to temporary signed URL\n    --all                        Load all pages\n    --json                       Print JSON output\n\n  capacity\n    --type <number>              Default: 1\n    --json                       Print JSON output\n\nExamples:\n  SEEWO_COOKIE='x-token=...;' seewo upload ./daily-quote.txt\n  SEEWO_COOKIE='...' seewo upload-dir ./assets\n  SEEWO_COOKIE='...' seewo delete 770339e1238a4cbb8c558fb8d2d319ac\n  SEEWO_COOKIE='...' seewo mkdir chapter-01\n  SEEWO_COOKIE='...' seewo list --all\n`;
  process.stdout.write(text);
}

function parseOptions(argv) {
  const options = {};
  const positionals = [];

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      positionals.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      options[key] = true;
      continue;
    }

    options[key] = next;
    i += 1;
  }

  return { options, positionals };
}

function isScalar(value) {
  return ['string', 'number', 'boolean'].includes(typeof value);
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function collectScalarFields(obj, excluded = new Set()) {
  const out = {};
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    return out;
  }

  for (const [key, value] of Object.entries(obj)) {
    if (excluded.has(key)) {
      continue;
    }
    if (value === undefined || value === null) {
      continue;
    }
    if (isScalar(value)) {
      out[key] = String(value);
    }
  }

  return out;
}

function pickObject(obj, keys) {
  if (!isPlainObject(obj)) {
    return undefined;
  }

  for (const key of keys) {
    const value = obj[key];
    if (isPlainObject(value)) {
      return value;
    }
  }
  return undefined;
}

function keyValueArrayToObject(items) {
  const out = {};
  if (!Array.isArray(items)) {
    return out;
  }

  for (const item of items) {
    if (!isPlainObject(item)) {
      continue;
    }
    const key = item.key;
    if (typeof key !== 'string' || key.length === 0) {
      continue;
    }
    const value = item.value;
    if (value === undefined || value === null) {
      continue;
    }
    out[key] = String(value);
  }

  return out;
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function randomTraceId() {
  return randomUUID().replaceAll('-', '');
}

function pick(obj, keys) {
  for (const key of keys) {
    if (obj && Object.prototype.hasOwnProperty.call(obj, key) && obj[key] !== undefined && obj[key] !== null) {
      return obj[key];
    }
  }
  return undefined;
}

function ensureTrailingSlash(value) {
  if (!value) {
    return value;
  }
  return value.endsWith('/') ? value : `${value}/`;
}

function extWithoutDot(fileName) {
  const ext = path.extname(fileName || '').toLowerCase();
  return ext.startsWith('.') ? ext.slice(1) : ext;
}

function guessMimeType(fileName) {
  const ext = extWithoutDot(fileName);
  const map = {
    txt: 'text/plain',
    csv: 'text/csv',
    json: 'application/json',
    pdf: 'application/pdf',
    doc: 'application/msword',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    xls: 'application/vnd.ms-excel',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ppt: 'application/vnd.ms-powerpoint',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    zip: 'application/zip',
    rar: 'application/vnd.rar',
    mp4: 'video/mp4',
    mov: 'video/quicktime',
    mp3: 'audio/mpeg',
    wav: 'audio/wav',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    webp: 'image/webp',
    gif: 'image/gif',
    heic: 'image/heic',
    avif: 'image/avif'
  };

  return map[ext] || 'application/octet-stream';
}

function buildFileKey(fileName, prefix = 'seewo-pinco-private/') {
  const ext = extWithoutDot(fileName) || 'bin';
  const randomPart = randomUUID().replaceAll('-', '').slice(0, 32);
  return `${prefix}${randomPart}.${ext}`;
}

function formatBytes(bytes) {
  const value = Number(bytes || 0);
  if (value < 1024) {
    return `${value} B`;
  }

  const units = ['KB', 'MB', 'GB', 'TB'];
  let n = value / 1024;
  let idx = 0;
  while (n >= 1024 && idx < units.length - 1) {
    n /= 1024;
    idx += 1;
  }

  return `${n.toFixed(2)} ${units[idx]}`;
}

function formatDurationMs(ms) {
  return `${(Number(ms || 0) / 1000).toFixed(3)}s`;
}

function buildUploadMetrics(fileSizeBytes, totalElapsedMs, uploadElapsedMs) {
  const uploadSeconds = Number(uploadElapsedMs || 0) / 1000;
  const uploadSpeedBps = uploadSeconds > 0 ? Number(fileSizeBytes || 0) / uploadSeconds : 0;

  return {
    fileSizeBytes: Number(fileSizeBytes || 0),
    fileSizeHuman: formatBytes(fileSizeBytes),
    totalElapsedMs: Number(totalElapsedMs || 0),
    totalElapsedHuman: formatDurationMs(totalElapsedMs),
    uploadElapsedMs: Number(uploadElapsedMs || 0),
    uploadElapsedHuman: formatDurationMs(uploadElapsedMs),
    uploadSpeedBps,
    uploadSpeedHuman: `${formatBytes(uploadSpeedBps)}/s`
  };
}

function printUploadResult(result) {
  process.stdout.write(result.deduplicated ? `Upload skipped (matched existing file).\n` : `Upload successful.\n`);
  if (result.id) {
    process.stdout.write(`id: ${result.id}\n`);
  }
  process.stdout.write(`fileKey: ${result.fileKey}\n`);
  if (result.authDownloadUrl && result.authDownloadUrl !== '-' && result.authDownloadUrl !== result.downloadUrl) {
    process.stdout.write(`authDownloadUrl: ${result.authDownloadUrl}\n`);
  }
  process.stdout.write(`downloadUrl: ${result.downloadUrl}\n`);
  if (result.metrics) {
    process.stdout.write(`size: ${result.metrics.fileSizeHuman} (${result.metrics.fileSizeBytes} B)\n`);
    process.stdout.write(`totalElapsed: ${result.metrics.totalElapsedHuman}\n`);
    process.stdout.write(`uploadElapsed: ${result.metrics.uploadElapsedHuman}\n`);
    process.stdout.write(`uploadSpeed: ${result.metrics.uploadSpeedHuman} (${result.metrics.uploadSpeedBps.toFixed(2)} B/s)\n`);
  }
}

function unwrapApiResponse(raw, actionName) {
  if (raw === null || raw === undefined) {
    throw new Error(`Empty response from ${actionName}`);
  }

  if (typeof raw !== 'object') {
    return raw;
  }

  const code = pick(raw, ['code', 'statusCode', 'errno']);
  if (code !== undefined) {
    const normalized = Number(code);
    const okCodes = new Set([0, 1, 200]);
    if (!Number.isNaN(normalized) && !okCodes.has(normalized)) {
      const message = pick(raw, ['msg', 'message', 'error', 'errorMsg']) || `Request failed with code ${code}`;
      throw new Error(`${actionName}: ${message}`);
    }
  }

  const success = pick(raw, ['success', 'ok']);
  if (success === false) {
    const message = pick(raw, ['msg', 'message', 'error', 'errorMsg']) || 'Request failed';
    throw new Error(`${actionName}: ${message}`);
  }

  return pick(raw, ['data', 'result']) ?? raw;
}

function normalizeUploadPolicy(payload, fileName) {
  const policyData = pickObject(payload, ['policyData', 'uploadPolicy', 'data', 'result']) || payload;
  const policyEntry = Array.isArray(policyData?.policyList) ? policyData.policyList.find((item) => isPlainObject(item)) : undefined;
  const formLike = {
    ...collectScalarFields(pickObject(policyData, ['form', 'formData', 'fields']) || {}),
    ...keyValueArrayToObject(policyEntry?.formFields)
  };
  const headerLike = keyValueArrayToObject(policyEntry?.headerFields);
  const genericUrl = pick(policyData, ['url']);
  const isOssEndpoint = (value) => typeof value === 'string' && /(aliyuncs\\.com|oss-)/i.test(value);
  const hostCandidate = pick(policyEntry, ['uploadUrl', 'host', 'uploadHost', 'endpoint']) || pick(policyData, ['host', 'uploadHost', 'endpoint', 'uploadUrl']);
  const host = hostCandidate || (isOssEndpoint(genericUrl) ? genericUrl : DEFAULT_OSS_HOST);
  const keyPrefix = pick(policyData, ['keyPrefix', 'prefix']) || 'seewo-pinco-private/';
  const key = pick(policyEntry, ['fileKey', 'key']) || pick(policyData, ['key', 'fileKey']) || formLike.key || buildFileKey(fileName, keyPrefix);
  const downloadUrl =
    pick(policyEntry, ['downloadUrl', 'accessUrl']) ||
    pick(policyData, ['downloadUrl', 'accessUrl']) ||
    (typeof genericUrl === 'string' && !isOssEndpoint(genericUrl) ? genericUrl : undefined);

  const fields = { ...formLike };

  fields.key = fields.key || key;
  fields.OSSAccessKeyId = fields.OSSAccessKeyId || pick(policyEntry, ['OSSAccessKeyId', 'accessKeyId']) || pick(policyData, ['OSSAccessKeyId', 'accessKeyId']);
  fields.policy = fields.policy || pick(policyEntry, ['policy']) || pick(policyData, ['policy']);
  fields.Signature = fields.Signature || fields.signature || pick(policyEntry, ['Signature', 'signature']) || pick(policyData, ['Signature', 'signature']);
  fields.callback = fields.callback || pick(policyEntry, ['callback']) || pick(policyData, ['callback']);
  fields['x:appid'] = fields['x:appid'] || pick(policyEntry, ['x:appid']) || pick(policyData, ['x:appid', 'appId']);
  fields['x:sessionid'] = fields['x:sessionid'] || pick(policyEntry, ['x:sessionid']) || pick(policyData, ['x:sessionid']);
  fields['x:bucketid'] = fields['x:bucketid'] || pick(policyEntry, ['x:bucketid']) || pick(policyData, ['x:bucketid']);
  fields['x-oss-forbid-overwrite'] =
    fields['x-oss-forbid-overwrite'] || pick(policyEntry, ['x-oss-forbid-overwrite']) || pick(policyData, ['x-oss-forbid-overwrite']);
  if (!fields.success_action_status && fields.successActionStatus) {
    fields.success_action_status = fields.successActionStatus;
  }
  if (!fields.success_action_status) {
    fields.success_action_status = '200';
  }
  if (!fields.Signature && fields.signature) {
    fields.Signature = fields.signature;
  }
  if (!fields.signature && fields.Signature) {
    fields.signature = fields.Signature;
  }
  if (!fields.OSSAccessKeyId && fields.accessKeyId) {
    fields.OSSAccessKeyId = fields.accessKeyId;
  }

  return { host, key: fields.key, downloadUrl, fields, headers: headerLike };
}

function extractListItems(data) {
  if (Array.isArray(data)) {
    return data;
  }

  const list = pick(data, ['list', 'records', 'items', 'rows', 'content']);
  if (Array.isArray(list)) {
    return list;
  }

  return [];
}

function summarizeItem(item) {
  const id = pick(item, ['id', 'materialId', 'fileId', 'resId']);
  return {
    id,
    resId: id,
    type: detectItemType(item),
    name: pick(item, ['name', 'fileName']) || '-',
    mimeType: pick(item, ['mimeType', 'type']) || '-',
    size: Number(pick(item, ['size', 'fileSize']) || 0),
    fileKey: pick(item, ['fileKey', 'key']) || '-',
    downloadUrl: pick(item, ['downloadUrl', 'url', 'accessUrl']) || '-',
    createdAt: pick(item, ['createdAt', 'createTime', 'gmtCreate']) || '-',
    updatedAt: pick(item, ['updatedAt', 'updateTime', 'gmtModified']) || '-'
  };
}

function detectItemType(item) {
  const fileFlag = pick(item, ['file', 'isFile']);
  if (typeof fileFlag === 'boolean') {
    return fileFlag ? 'file' : 'folder';
  }

  const folderFlag = pick(item, ['folder', 'isFolder']);
  if (typeof folderFlag === 'boolean') {
    return folderFlag ? 'folder' : 'file';
  }

  const mimeValue = pick(item, ['mimeType', 'type']);
  if (typeof mimeValue === 'string') {
    const mime = mimeValue.trim().toLowerCase();
    if (mime === 'folder' || mime === 'directory' || mime === 'dir') {
      return 'folder';
    }
    if (mime === 'resource' || mime === 'file') {
      return 'file';
    }
    if (mime.includes('folder')) {
      return 'folder';
    }
    if (mime.includes('/')) {
      return 'file';
    }
  }

  if (typeof mimeValue === 'number') {
    if (mimeValue === 9) {
      return 'folder';
    }
    if (mimeValue === 99) {
      return 'file';
    }
  }

  const typeTag = Number(pick(item, ['typeTag']));
  if (typeTag === 1) {
    return 'folder';
  }
  if (typeTag === 255) {
    return 'file';
  }

  return 'file';
}

function resolveListTagNames(inputTagName) {
  if (inputTagName === undefined || inputTagName === null || String(inputTagName).trim() === '') {
    return ['resource', 'folder'];
  }

  const tags = [];
  for (const rawTag of String(inputTagName).split(',')) {
    const tag = rawTag.trim();
    if (!tag) {
      continue;
    }

    const lowerTag = tag.toLowerCase();
    if (lowerTag === 'all' || tag === '*') {
      tags.push('resource', 'folder');
      continue;
    }

    tags.push(tag);
  }

  return [...new Set(tags)];
}

function dedupeSummarizedItems(items) {
  const seen = new Set();
  const out = [];

  for (const item of items) {
    const key = `${item.id}|${item.mimeType}|${item.name}`;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(item);
  }

  return out;
}

class PincoClient {
  constructor() {
    this.baseUrl = process.env.SEEWO_BASE_URL || DEFAULT_BASE_URL;
    this.cookie = requiredEnv('SEEWO_COOKIE');
    this.origin = this.baseUrl;
    this.referer = `${this.baseUrl}/teacher/main/drive/resource`;
    this.xServer = process.env.SEEWO_X_SERVER || 'default';
    this.csrfToken = process.env.SEEWO_X_CSRF_TOKEN || 'undefined';
    this.language = process.env.SEEWO_LANGUAGE || 'zh_CHS';
    this.userAgent =
      process.env.SEEWO_USER_AGENT ||
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:148.0) Gecko/20100101 Firefox/148.0';
    this.debugActions = process.env.SEEWO_DEBUG_ACTIONS === '1';
  }

  async postAction(actionName, payload, extraHeaders = {}) {
    const url = `${this.baseUrl}/teacher/api.json?actionName=${encodeURIComponent(actionName)}`;
    const headers = {
      'User-Agent': this.userAgent,
      Accept: 'application/json, text/plain, */*',
      'Content-Type': 'application/json;charset=utf-8',
      'x-req-traceid': randomTraceId(),
      'x-csrf-token': this.csrfToken,
      'x-server': this.xServer,
      Origin: this.origin,
      Referer: this.referer,
      Cookie: this.cookie,
      ...extraHeaders
    };

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload)
    });

    const text = await response.text();
    if (this.debugActions) {
      process.stdout.write(`[debug:action] ${actionName} -> HTTP ${response.status} ${text.slice(0, 500)}\n`);
    }
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      throw new Error(`${actionName}: non-JSON response: ${text.slice(0, 240)}`);
    }

    if (!response.ok) {
      throw new Error(`${actionName}: HTTP ${response.status}: ${text.slice(0, 240)}`);
    }

    return unwrapApiResponse(data, actionName);
  }

  async getMaterials(params) {
    return this.postAction(
      'GetV1DriveMaterials',
      {
        keyword: params.keyword ?? '',
        size: params.size ?? 50,
        tagName: params.tagName ?? 'resource',
        page: params.page ?? 0,
        folderId: params.folderId ?? '0'
      },
      {
        'x-language': this.language,
        Accept: '*/*'
      }
    );
  }

  async getCapacity(type = 1) {
    return this.postAction(
      'GetV1DriveMaterialsCapacity',
      { type },
      {
        'x-language': this.language,
        Accept: '*/*'
      }
    );
  }

  async deleteMaterials(resIds) {
    return this.postAction(
      'DeleteV1DriveMaterials',
      { resIds },
      {
        'x-language': this.language,
        Accept: '*/*'
      }
    );
  }

  async createFolder(name, parentFolderId = '0') {
    return this.postAction(
      'PostV1DriveMaterialsFolders',
      { name, parentFolderId },
      {
        'x-language': this.language,
        Accept: '*/*'
      }
    );
  }

  buildMaterialDownloadUrl(materialId) {
    return `${this.baseUrl}/server-main/api/v1/drive/materials/download?resId=${encodeURIComponent(materialId)}`;
  }

  async resolveDownloadUrl(url) {
    if (!url) {
      return url;
    }

    const response = await fetch(url, {
      method: 'GET',
      redirect: 'manual',
      headers: {
        'User-Agent': this.userAgent,
        Accept: '*/*',
        Origin: this.origin,
        Referer: this.referer,
        Cookie: this.cookie
      }
    });

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location');
      if (location) {
        return location;
      }
    }

    return url;
  }
}

async function fileMd5(filePath) {
  const buffer = await fs.readFile(filePath);
  const hash = createHash('md5').update(buffer).digest('hex');
  return { hash, buffer };
}

async function uploadToOss({ host, fields, fileName, mimeType, buffer, origin, referer, userAgent, extraHeaders = {} }) {
  const form = new FormData();

  const preferredOrder = [
    'OSSAccessKeyId',
    'accessKeyId',
    'policy',
    'Signature',
    'signature',
    'key',
    'callback',
    'success_action_status',
    'x:appid',
    'x:sessionid',
    'x:bucketid',
    'x-oss-forbid-overwrite'
  ];

  const appended = new Set();

  for (const field of preferredOrder) {
    const value = fields[field];
    if (value !== undefined && value !== null && value !== '') {
      form.append(field, String(value));
      appended.add(field);
    }
  }

  for (const [field, value] of Object.entries(fields)) {
    if (appended.has(field)) {
      continue;
    }
    if (value !== undefined && value !== null && value !== '') {
      form.append(field, String(value));
      appended.add(field);
    }
  }

  form.append('file', new Blob([buffer], { type: mimeType }), fileName);

  const response = await fetch(host, {
    method: 'POST',
    headers: {
      Accept: '*/*',
      ...(origin ? { Origin: origin } : {}),
      ...(referer ? { Referer: referer } : {}),
      ...(userAgent ? { 'User-Agent': userAgent } : {}),
      ...Object.fromEntries(
        Object.entries(extraHeaders).filter(([k, v]) => {
          if (!v) return false;
          return k.toLowerCase() !== 'content-type';
        })
      )
    },
    body: form
  });

  const text = await response.text();

  if (!response.ok) {
    throw new Error(`OSS upload failed (${response.status}): ${text.slice(0, 240)}`);
  }

  return { status: response.status, raw: text };
}

async function uploadSingleFile(inputPath, options, client) {
  const totalStartMs = Date.now();
  const absolutePath = path.resolve(process.cwd(), inputPath);
  const stat = await fs.stat(absolutePath);
  if (!stat.isFile()) {
    throw new Error(`Not a file: ${absolutePath}`);
  }

  const name = options.name || path.basename(absolutePath);
  const mimeType = options['mime-type'] || guessMimeType(name);
  const parentFolderId = String(options['parent-folder-id'] || '0');

  const { hash, buffer } = await fileMd5(absolutePath);

  const fileMeta = {
    fileMd5: hash,
    fileSize: stat.size,
    fileName: name,
    mimeType
  };

  const matchResponse = await client.postAction('PostV1DriveMaterialsMatch', fileMeta);
  const matchExists = Boolean(pick(matchResponse, ['matched', 'exists', 'alreadyExist', 'isExist', 'hit']));
  const matchedUrl = pick(matchResponse, ['downloadUrl', 'url', 'accessUrl']);
  const matchedKey = pick(matchResponse, ['fileKey', 'key']);

  if (matchExists && matchedUrl && matchedKey) {
    const totalElapsedMs = Date.now() - totalStartMs;
    return {
      deduplicated: true,
      id: pick(matchResponse, ['id', 'materialId', 'fileId']),
      name,
      size: stat.size,
      mimeType,
      fileMd5: hash,
      fileKey: matchedKey,
      authDownloadUrl: matchedUrl,
      downloadUrl: matchedUrl,
      message: 'File matched existing content; skipped upload.',
      metrics: buildUploadMetrics(stat.size, totalElapsedMs, 0),
      raw: matchResponse
    };
  }

  const suffix = extWithoutDot(name) || 'bin';
  const policyResponse = await client.postAction('PostV3CstoreUploadPolicy', { keySuffix: suffix });
  const policy = normalizeUploadPolicy(policyResponse, name);
  const debug = Boolean(options.debug);

  if (debug) {
    process.stdout.write(`[debug] policy.host=${policy.host}\n`);
    process.stdout.write(`[debug] policy.key=${policy.key}\n`);
    process.stdout.write(`[debug] policy.downloadUrl=${policy.downloadUrl || '-'}\n`);
    process.stdout.write(`[debug] policy.fields=${Object.keys(policy.fields).sort().join(',')}\n`);
    process.stdout.write(`[debug] policy.headers=${Object.keys(policy.headers || {}).sort().join(',') || '-'}\n`);
  }

  const missing = [];
  if (!policy.fields.policy) missing.push('policy');
  if (!policy.fields.Signature && !policy.fields.signature) missing.push('Signature/signature');
  if (!policy.fields.OSSAccessKeyId && !policy.fields.accessKeyId) missing.push('OSSAccessKeyId/accessKeyId');
  if (!policy.fields.key) missing.push('key');
  if (missing.length > 0) {
    throw new Error(`PostV3CstoreUploadPolicy missing required upload fields: ${missing.join(', ')}`);
  }

  const uploadStartMs = Date.now();
  await uploadToOss({
    host: policy.host,
    fields: policy.fields,
    fileName: name,
    mimeType,
    buffer,
    origin: client.origin,
    referer: `${client.baseUrl}/`,
    userAgent: client.userAgent,
    extraHeaders: policy.headers
  });
  const uploadElapsedMs = Date.now() - uploadStartMs;

  const cdnBase = ensureTrailingSlash(process.env.SEEWO_CDN_BASE || DEFAULT_DOWNLOAD_BASE);
  const commitPayload = {
    fileSize: stat.size,
    downloadUrl: policy.downloadUrl || `${cdnBase}${policy.key}`,
    fileKey: policy.key,
    fileMd5: hash,
    name,
    parentFolderId,
    size: stat.size,
    mimeType
  };

  const commitResponse = await client.postAction('PostV1DriveMaterialsCstoreWay', commitPayload);
  const materialId = pick(commitResponse, ['id', 'materialId', 'fileId']);
  const authDownloadUrl =
    pick(commitResponse, ['downloadUrl', 'url', 'accessUrl']) || (materialId ? client.buildMaterialDownloadUrl(materialId) : undefined);
  const committedDownloadUrl = (await client.resolveDownloadUrl(authDownloadUrl)) || authDownloadUrl || commitPayload.downloadUrl;
  const committedFileKey = pick(commitResponse, ['fileKey', 'key']) || commitPayload.fileKey;
  const totalElapsedMs = Date.now() - totalStartMs;

  return {
    deduplicated: false,
    id: materialId,
    name,
    size: stat.size,
    mimeType,
    fileMd5: hash,
    fileKey: committedFileKey,
    authDownloadUrl: authDownloadUrl || '-',
    downloadUrl: committedDownloadUrl,
    metrics: buildUploadMetrics(stat.size, totalElapsedMs, uploadElapsedMs),
    raw: commitResponse
  };
}

async function handleUpload(positionals, options, client) {
  const inputPath = positionals[0];
  if (!inputPath) {
    throw new Error('upload command requires a local file path');
  }

  const result = await uploadSingleFile(inputPath, options, client);
  if (options.json) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } else {
    printUploadResult(result);
  }
}

async function walkLocalFiles(dirPath) {
  const entries = await fs.readdir(dirPath, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const absPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walkLocalFiles(absPath)));
      continue;
    }
    if (entry.isFile()) {
      files.push(absPath);
    }
  }

  return files;
}

async function ensureRemoteFolderPath(client, folderCache, rootFolderId, relativeDirPath) {
  if (!relativeDirPath || relativeDirPath === '.' || relativeDirPath === path.sep) {
    return rootFolderId;
  }

  const normalized = relativeDirPath.split(path.sep).filter(Boolean).join('/');
  if (folderCache.has(normalized)) {
    return folderCache.get(normalized);
  }

  const segments = normalized.split('/');
  let parentId = rootFolderId;
  let traversed = '';

  for (const segment of segments) {
    traversed = traversed ? `${traversed}/${segment}` : segment;
    if (folderCache.has(traversed)) {
      parentId = folderCache.get(traversed);
      continue;
    }

    const created = await client.createFolder(segment, parentId);
    const createdId = pick(created, ['id', 'folderId', 'resId']);
    if (!createdId) {
      throw new Error(`Create folder failed for "${traversed}": missing id in response`);
    }
    parentId = String(createdId);
    folderCache.set(traversed, parentId);
  }

  return parentId;
}

async function handleUploadDir(positionals, options, client) {
  const inputDir = positionals[0];
  if (!inputDir) {
    throw new Error('upload-dir command requires a local directory path');
  }

  const absoluteDir = path.resolve(process.cwd(), inputDir);
  const stat = await fs.stat(absoluteDir);
  if (!stat.isDirectory()) {
    throw new Error(`Not a directory: ${absoluteDir}`);
  }

  const files = await walkLocalFiles(absoluteDir);
  if (files.length === 0) {
    throw new Error(`No files found in directory: ${absoluteDir}`);
  }

  const parentFolderId = String(options['parent-folder-id'] || '0');
  const createRoot = !Boolean(options['no-root']);
  const flat = Boolean(options.flat);
  const rootFolderName = options['remote-folder-name'] || path.basename(absoluteDir);

  let targetRootFolderId = parentFolderId;
  const createdFolders = [];
  if (createRoot) {
    const createdRoot = await client.createFolder(rootFolderName, parentFolderId);
    const rootId = pick(createdRoot, ['id', 'folderId', 'resId']);
    if (!rootId) {
      throw new Error('Create root folder failed: missing id in response');
    }
    targetRootFolderId = String(rootId);
    createdFolders.push({ name: rootFolderName, id: targetRootFolderId, parentFolderId });
  }

  const folderCache = new Map();
  folderCache.set('', targetRootFolderId);
  folderCache.set('.', targetRootFolderId);

  const results = [];
  const failures = [];

  for (const filePath of files) {
    const relative = path.relative(absoluteDir, filePath);
    const relativeDir = path.dirname(relative);
    const fileName = path.basename(filePath);

    try {
      let fileParentFolderId = targetRootFolderId;
      if (!flat && relativeDir && relativeDir !== '.') {
        fileParentFolderId = await ensureRemoteFolderPath(client, folderCache, targetRootFolderId, relativeDir);
      }

      const result = await uploadSingleFile(
        filePath,
        {
          ...options,
          name: fileName,
          'parent-folder-id': fileParentFolderId
        },
        client
      );

      results.push({
        localPath: filePath,
        relativePath: relative,
        parentFolderId: fileParentFolderId,
        ...result
      });
    } catch (error) {
      failures.push({
        localPath: filePath,
        relativePath: relative,
        error: error.message
      });
    }
  }

  const summary = {
    localDir: absoluteDir,
    remoteRootFolderId: targetRootFolderId,
    createRoot,
    flat,
    totalFiles: files.length,
    successCount: results.length,
    failureCount: failures.length,
    createdFolders,
    failures,
    results
  };

  if (options.json) {
    process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
    return;
  }

  process.stdout.write(`Directory upload finished.\n`);
  process.stdout.write(`localDir: ${absoluteDir}\n`);
  process.stdout.write(`remoteRootFolderId: ${targetRootFolderId}\n`);
  process.stdout.write(`totalFiles: ${summary.totalFiles}\n`);
  process.stdout.write(`success: ${summary.successCount}\n`);
  process.stdout.write(`failed: ${summary.failureCount}\n`);
  if (failures.length > 0) {
    for (const item of failures) {
      process.stdout.write(`- failed: ${item.relativePath} -> ${item.error}\n`);
    }
  }
}

async function handleDelete(positionals, options, client) {
  const resId = String(options.id || positionals[0] || '').trim();
  if (!resId) {
    throw new Error('delete command requires a material id, e.g. seewo delete <resId>');
  }

  const data = await client.deleteMaterials([resId]);
  const result = { resId, raw: data };

  if (options.json) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }

  process.stdout.write(`Delete request sent.\n`);
  process.stdout.write(`resId: ${resId}\n`);
}

async function handleMkdir(positionals, options, client) {
  const name = String(positionals[0] || options.name || '').trim();
  if (!name) {
    throw new Error('mkdir command requires a folder name, e.g. seewo mkdir lesson-1');
  }

  const parentFolderId = String(options['parent-folder-id'] || '0');
  const data = await client.createFolder(name, parentFolderId);
  const result = {
    id: pick(data, ['id', 'folderId', 'resId']) || '-',
    name: pick(data, ['name']) || name,
    parentFolderId,
    raw: data
  };

  if (options.json) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }

  process.stdout.write(`Folder created.\n`);
  process.stdout.write(`id: ${result.id}\n`);
  process.stdout.write(`name: ${result.name}\n`);
  process.stdout.write(`parentFolderId: ${parentFolderId}\n`);
}

async function handleList(options, client) {
  const folderId = options['folder-id'] || '0';
  const page = Number(options.page ?? 0);
  const size = Number(options.size ?? 50);
  const keyword = options.keyword || '';
  const tagNames = resolveListTagNames(options['tag-name']);
  const all = Boolean(options.all);
  const resolveUrl = Boolean(options['resolve-url']);

  const items = [];

  if (!all) {
    for (const tagName of tagNames) {
      const data = await client.getMaterials({ folderId, page, size, keyword, tagName });
      items.push(...extractListItems(data));
    }
  } else {
    for (const tagName of tagNames) {
      let currentPage = page;
      while (true) {
        const data = await client.getMaterials({ folderId, page: currentPage, size, keyword, tagName });
        const pageItems = extractListItems(data);
        items.push(...pageItems);

        if (pageItems.length < size) {
          break;
        }
        currentPage += 1;

        if (currentPage - page > 500) {
          break;
        }
      }
    }
  }

  const normalized = dedupeSummarizedItems(items.map(summarizeItem));
  if (resolveUrl) {
    for (const item of normalized) {
      if (
        item.type === 'file' &&
        typeof item.downloadUrl === 'string' &&
        item.downloadUrl.includes('/server-main/api/v1/drive/materials/download')
      ) {
        item.downloadUrl = await client.resolveDownloadUrl(item.downloadUrl);
      }
    }
  }

  if (options.json) {
    process.stdout.write(`${JSON.stringify({ total: normalized.length, items: normalized }, null, 2)}\n`);
    return;
  }

  process.stdout.write(`Total: ${normalized.length}\n`);
  for (const item of normalized) {
    process.stdout.write(`- ${item.name}\n`);
    process.stdout.write(`  type: ${item.type}\n`);
    process.stdout.write(`  resId: ${item.resId}\n`);
    process.stdout.write(`  size: ${formatBytes(item.size)}\n`);
    process.stdout.write(`  mime: ${item.mimeType}\n`);
    process.stdout.write(`  fileKey: ${item.fileKey}\n`);
    process.stdout.write(`  downloadUrl: ${item.downloadUrl}\n`);
    process.stdout.write(`  updatedAt: ${item.updatedAt}\n`);
  }
}

async function handleCapacity(options, client) {
  const type = Number(options.type ?? 1);
  const data = await client.getCapacity(type);

  if (options.json) {
    process.stdout.write(`${JSON.stringify(data, null, 2)}\n`);
    return;
  }

  const used = Number(pick(data, ['used', 'usedSize', 'usedCapacity']) || 0);
  const total = Number(pick(data, ['total', 'totalSize', 'capacity']) || 0);
  const remain = Number(pick(data, ['remain', 'remainSize', 'available']) || Math.max(0, total - used));

  process.stdout.write(`Capacity\n`);
  process.stdout.write(`- Used: ${formatBytes(used)}\n`);
  process.stdout.write(`- Total: ${formatBytes(total)}\n`);
  process.stdout.write(`- Remaining: ${formatBytes(remain)}\n`);
}

async function main() {
  const [, , cmd = 'help', ...rest] = process.argv;
  const { options, positionals } = parseOptions(rest);

  if (cmd === 'help' || cmd === '--help' || cmd === '-h') {
    printHelp();
    return;
  }

  const client = new PincoClient();

  if (cmd === 'upload') {
    await handleUpload(positionals, options, client);
    return;
  }

  if (cmd === 'upload-dir') {
    await handleUploadDir(positionals, options, client);
    return;
  }

  if (cmd === 'delete') {
    await handleDelete(positionals, options, client);
    return;
  }

  if (cmd === 'mkdir') {
    await handleMkdir(positionals, options, client);
    return;
  }

  if (cmd === 'list') {
    await handleList(options, client);
    return;
  }

  if (cmd === 'capacity') {
    await handleCapacity(options, client);
    return;
  }

  throw new Error(`Unknown command: ${cmd}`);
}

main().catch((error) => {
  process.stderr.write(`Error: ${error.message}\n`);
  process.exitCode = 1;
});
