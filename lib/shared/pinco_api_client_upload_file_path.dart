part of 'pinco_api_client.dart';

extension PincoApiClientUploadFilePathExtension on PincoApiClient {
  Future<void> _uploadFilePathToOss({
    required String host,
    required Map<String, dynamic> fields,
    required Map<String, dynamic> headers,
    required String filePath,
    required String fileName,
    required String mimeType,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData();
    const preferredOrder = <String>[
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
      'x-oss-forbid-overwrite',
    ];
    final appended = <String>{};

    for (final field in preferredOrder) {
      final value = fields[field];
      if (_hasValue(value)) {
        formData.fields.add(MapEntry(field, value.toString()));
        appended.add(field);
      }
    }
    for (final entry in fields.entries) {
      if (!appended.contains(entry.key) && _hasValue(entry.value)) {
        formData.fields.add(MapEntry(entry.key, entry.value.toString()));
      }
    }
    formData.files.add(
      MapEntry(
        'file',
        await MultipartFile.fromFile(
          filePath,
          filename: fileName,
          contentType: DioMediaType.parse(mimeType),
        ),
      ),
    );

    final requestHeaders = <String, dynamic>{
      'Accept': '*/*',
      'Origin': PincoApiClient._origin,
      'Referer': '${PincoApiClient._baseUrl}/',
      ...headers,
    };
    requestHeaders.removeWhere(
      (key, value) => value == null || key.toLowerCase() == 'content-type',
    );

    final response = await _dioClient.post<dynamic>(
      host,
      data: formData,
      options:
          Options(headers: requestHeaders, responseType: ResponseType.plain),
      cancelToken: cancelToken,
      onSendProgress: onProgress,
    );
    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception('OSS upload failed ($statusCode)');
    }
  }
}
