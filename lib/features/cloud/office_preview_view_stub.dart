import 'dart:typed_data';

import 'package:flutter/widgets.dart';

Widget buildOfficePreviewView(Uint8List bytes) {
  return const Center(
    child: Text('当前平台暂不支持内嵌 Office 预览，请复制地址后在浏览器中打开。'),
  );
}
