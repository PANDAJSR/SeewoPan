part of 'pinco_api_client.dart';

class DriveMaterialPreview {
  const DriveMaterialPreview({
    required this.previewUrl,
    this.showUrl,
    this.downloadUrl,
    this.storeType,
  });

  final String previewUrl;
  final String? showUrl;
  final String? downloadUrl;
  final int? storeType;
}

extension PincoApiClientPreviewExtension on PincoApiClient {
  Future<DriveMaterialPreview> getMaterialPreview({
    required String cookie,
    required String materialId,
  }) async {
    final normalizedCookie = cookie.trim();
    final normalizedMaterialId = materialId.trim();

    if (normalizedCookie.isEmpty) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie cannot be empty.');
    }
    if (normalizedMaterialId.isEmpty) {
      throw ArgumentError.value(
        materialId,
        'materialId',
        'Material ID cannot be empty.',
      );
    }

    final data = await _postAction(
      actionName: 'GetV1DriveMaterialsByMaterialId',
      cookie: normalizedCookie,
      payload: <String, dynamic>{'materialId': normalizedMaterialId},
    );

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Missing material preview data.');
    }

    final showUrl = _normalizedUrl(_pick(data, ['showUrl', 'previewUrl']));
    final downloadUrl = _normalizedUrl(
      _pick(data, ['downloadUrl', 'url', 'accessUrl']),
    );
    final previewUrl = showUrl ?? downloadUrl;
    if (previewUrl == null) {
      throw const FormatException('Missing material preview url.');
    }

    return DriveMaterialPreview(
      previewUrl: previewUrl,
      showUrl: showUrl,
      downloadUrl: downloadUrl,
      storeType: _toNullableInt(_pick(data, ['storeType'])),
    );
  }

  String? _normalizedUrl(dynamic value) {
    final url = value?.toString().trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }

  int? _toNullableInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
