import 'package:flutter_test/flutter_test.dart';
import 'package:seewopan/shared/pinco_api_client.dart';

void main() {
  test('buildMaterialDownloadUrl should encode resId', () {
    final client = PincoApiClient();
    const materialId = 'id with space/&?';

    final url = client.buildMaterialDownloadUrl(materialId);

    expect(
      url,
      'https://pinco.seewo.com/server-main/api/v1/drive/materials/download'
      '?resId=id+with+space%2F%26%3F',
    );
  });
}
