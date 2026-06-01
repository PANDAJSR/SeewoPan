import 'dart:convert';
import 'dart:io';

import 'webdav_settings.dart';

bool isWebDavAuthorized(HttpRequest request, WebDavSettings settings) {
  if (!settings.hasAuth) {
    return true;
  }
  final raw = request.headers.value(HttpHeaders.authorizationHeader);
  if (raw == null || !raw.startsWith('Basic ')) {
    return false;
  }
  try {
    final decoded = utf8.decode(base64.decode(raw.substring(6).trim()));
    final separator = decoded.indexOf(':');
    if (separator < 0) {
      return false;
    }
    return decoded.substring(0, separator) == settings.username &&
        decoded.substring(separator + 1) == settings.password;
  } catch (_) {
    return false;
  }
}
