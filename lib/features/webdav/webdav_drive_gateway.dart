import 'dart:io';

import '../../shared/models/drive_material.dart';
import '../../shared/pinco_api_client.dart';

class WebDavDriveGateway {
  const WebDavDriveGateway({
    required PincoApiClient apiClient,
    required String Function() cookie,
  })  : _apiClient = apiClient,
        _cookie = cookie;

  final PincoApiClient _apiClient;
  final String Function() _cookie;

  Future<ResolvedWebDavMaterial> resolve(List<String> segments) async {
    if (segments.isEmpty) {
      return const ResolvedWebDavMaterial(parentFolderId: '0');
    }
    var parentFolderId = '0';
    DriveMaterial? current;
    for (final segment in segments) {
      current = await findChild(parentFolderId, segment);
      if (current == null) {
        return ResolvedWebDavMaterial(parentFolderId: parentFolderId);
      }
      parentFolderId = current.id;
    }
    return ResolvedWebDavMaterial(
      material: current,
      parentFolderId: segments.length == 1 ? '0' : current?.folderId ?? '0',
    );
  }

  Future<DriveMaterial?> findChild(String folderId, String name) async {
    final children = await listAll(folderId);
    for (final child in children) {
      if (child.name == name) {
        return child;
      }
    }
    return null;
  }

  Future<List<DriveMaterial>> listAll(String folderId) async {
    const pageSize = 100;
    final all = <DriveMaterial>[];
    for (var page = 0; page < 100; page += 1) {
      final items = await _apiClient.getMaterials(
        cookie: _cookie(),
        folderId: folderId,
        page: page,
        size: pageSize,
        forceRefresh: true,
      );
      all.addAll(items);
      if (items.length < pageSize) {
        break;
      }
    }
    return all;
  }

  ContentType contentTypeFor(DriveMaterial material) {
    final value = material.mimeType.trim();
    if (value.isNotEmpty && value.contains('/')) {
      return ContentType.parse(value);
    }
    return ContentType.binary;
  }
}

class ResolvedWebDavMaterial {
  const ResolvedWebDavMaterial({
    this.material,
    required this.parentFolderId,
  });

  final DriveMaterial? material;
  final String parentFolderId;
}
