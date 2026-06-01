part of 'pinco_api_client.dart';

extension PincoApiClientDownloadStreamExtension on PincoApiClient {
  Future<http.StreamedResponse> openMaterialDownloadStream({
    required String cookie,
    required String materialId,
    String? range,
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

    final request = http.Request(
      'GET',
      Uri.parse(buildMaterialDownloadUrl(normalizedMaterialId)),
    );
    request.headers.addAll(<String, String>{
      'Accept': '*/*',
      'Cookie': normalizedCookie,
      'Origin': PincoApiClient._origin,
      'Referer': PincoApiClient._referer,
    });
    final normalizedRange = range?.trim();
    if (normalizedRange != null && normalizedRange.isNotEmpty) {
      request.headers['Range'] = normalizedRange;
    }

    return _httpClient.send(request);
  }
}
