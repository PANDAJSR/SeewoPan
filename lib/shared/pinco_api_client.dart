import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'models/drive_material.dart';
import 'models/drive_materials_capacity.dart';
import 'models/user_profile.dart';

part 'pinco_api_client_materials.dart';
part 'pinco_api_client_download_stream.dart';
part 'pinco_api_client_preview.dart';
part 'pinco_api_client_upload.dart';
part 'pinco_api_client_upload_file_path.dart';
part 'pinco_api_client_upload_stream.dart';
part 'pinco_api_client_parsing.dart';

typedef UploadProgressCallback = void Function(UploadProgress progress);

class UploadProgress {
  const UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.elapsed,
    this.estimatedProgress,
  });

  final int sentBytes;
  final int totalBytes;
  final Duration elapsed;
  final double? estimatedProgress;

  double get progress {
    if (estimatedProgress != null) {
      return estimatedProgress!.clamp(0.0, 1.0);
    }
    if (totalBytes <= 0) {
      return 0;
    }
    return sentBytes / totalBytes;
  }

  double get speedBps {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds <= 0) {
      return 0;
    }
    return sentBytes / seconds;
  }
}

class UploadMetrics {
  const UploadMetrics({
    required this.fileSizeBytes,
    required this.totalElapsed,
    required this.uploadElapsed,
    required this.uploadSpeedBps,
  });

  final int fileSizeBytes;
  final Duration totalElapsed;
  final Duration uploadElapsed;
  final double uploadSpeedBps;
}

class UploadFileResult {
  const UploadFileResult({
    required this.deduplicated,
    required this.name,
    required this.size,
    required this.mimeType,
    required this.fileMd5,
    required this.fileKey,
    required this.metrics,
    this.id,
    this.authDownloadUrl,
    this.downloadUrl,
    this.message,
  });

  final bool deduplicated;
  final String? id;
  final String name;
  final int size;
  final String mimeType;
  final String fileMd5;
  final String fileKey;
  final String? authDownloadUrl;
  final String? downloadUrl;
  final String? message;
  final UploadMetrics metrics;
}

class PincoApiClient {
  PincoApiClient({http.Client? httpClient, Dio? dioClient})
      : _httpClient = httpClient ?? http.Client(),
        _dioClient = dioClient ?? Dio();

  static final _random = Random();
  static const String _baseUrl = 'https://pinco.seewo.com';
  static const String _origin = _baseUrl;
  static const String _referer =
      'https://pinco.seewo.com/teacher/main/drive/resource';
  static const String _defaultOssHost =
      'https://cstore-private.oss-cn-hangzhou.aliyuncs.com';
  static const String _defaultCdnBase =
      'https://cstore-pri-pinco-bs.seewo.com/';
  static const int _uploadChunkSizeBytes = 256 * 1024;

  final http.Client _httpClient;
  final Dio _dioClient;
  final Map<String, UserProfile> _userProfileCache = <String, UserProfile>{};
  final Map<String, List<DriveMaterial>> _materialsCache =
      <String, List<DriveMaterial>>{};
  final Map<String, DriveMaterialsCapacity> _materialsCapacityCache =
      <String, DriveMaterialsCapacity>{};
}

class _NormalizedUploadPolicy {
  const _NormalizedUploadPolicy({
    required this.host,
    required this.key,
    required this.downloadUrl,
    required this.fields,
    required this.headers,
  });

  final String host;
  final String key;
  final String? downloadUrl;
  final Map<String, dynamic> fields;
  final Map<String, dynamic> headers;
}
