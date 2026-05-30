import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:microsoft_viewer/microsoft_viewer.dart';

Widget buildOfficePreviewView(Uint8List bytes) {
  return MicrosoftViewer(bytes, true);
}
