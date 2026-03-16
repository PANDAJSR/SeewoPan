import 'package:path_provider/path_provider.dart';

Future<String> resolveDefaultDownloadDirectoryPath() async {
  try {
    final directory = await getDownloadsDirectory().timeout(
      const Duration(milliseconds: 500),
    );
    return directory?.path ?? '';
  } catch (_) {
    return '';
  }
}
