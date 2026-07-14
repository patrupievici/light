import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '_crash_reporter.dart';
import 'photo_progress_service.dart';
import 'secure_db.dart';

class LocalAccountDataWipeResult {
  const LocalAccountDataWipeResult(this.failedSteps);

  final List<String> failedSteps;
  bool get completed => failedSteps.isEmpty;
}

/// Removes every known user-owned artifact after the server has confirmed an
/// account erasure. Each cleanup step is isolated so one broken cache cannot
/// leave the user signed in or prevent the remaining artifacts from being
/// removed.
class LocalAccountDataWiper {
  LocalAccountDataWiper({
    Future<void> Function()? clearProgressPhotos,
    Future<void> Function()? clearEncryptedDatabases,
    Future<void> Function()? clearImageCaches,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
    void Function(Object, StackTrace, String)? onFailure,
  })  : _clearProgressPhotos = clearProgressPhotos ??
            PhotoProgressService.instance.eraseAllLocalData,
        _clearEncryptedDatabases =
            clearEncryptedDatabases ?? SecureDb.instance.eraseAllLocalData,
        _clearImageCaches = clearImageCaches ?? _clearDefaultImageCaches,
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _onFailure = onFailure ??
            ((error, stackTrace, reason) =>
                reportError(error, stackTrace, reason: reason));

  static final LocalAccountDataWiper instance = LocalAccountDataWiper();

  final Future<void> Function() _clearProgressPhotos;
  final Future<void> Function() _clearEncryptedDatabases;
  final Future<void> Function() _clearImageCaches;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final void Function(Object, StackTrace, String) _onFailure;

  static Future<void> _clearDefaultImageCaches() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await DefaultCacheManager().emptyCache();
  }

  /// Used on sign-out as well as erasure so a new account on the same device
  /// cannot render a previous user's already-decoded or disk-cached media.
  static Future<void> clearMediaCaches() => _clearDefaultImageCaches();

  Future<LocalAccountDataWipeResult> wipe() async {
    final failedSteps = <String>[];
    await _attempt(
      'progress-photos',
      _clearProgressPhotos,
      failedSteps,
    );
    await _attempt(
      'encrypted-databases',
      _clearEncryptedDatabases,
      failedSteps,
    );
    await _attempt('image-cache', _clearImageCaches, failedSteps);
    await _attempt(
      'documents-share-artifacts',
      () async => _deleteGeneratedArtifacts(await _documentsDirectory()),
      failedSteps,
    );
    await _attempt(
      'temporary-share-artifacts',
      () async => _deleteGeneratedArtifacts(await _temporaryDirectory()),
      failedSteps,
    );
    return LocalAccountDataWipeResult(List.unmodifiable(failedSteps));
  }

  Future<void> _attempt(
    String step,
    Future<void> Function() action,
    List<String> failedSteps,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      failedSteps.add(step);
      _onFailure(error, stackTrace, 'account-erasure:$step');
    }
  }

  static bool _isGeneratedUserArtifact(FileSystemEntity entity) {
    if (entity is! File) return false;
    final name = entity.uri.pathSegments.isEmpty
        ? ''
        : entity.uri.pathSegments.last.toLowerCase();
    return RegExp(r'^zvelt_(?:activity_)?[^/]+\.png$').hasMatch(name) ||
        RegExp(r'^zvelt-data-export(?:-[^/]+)?\.json$').hasMatch(name);
  }

  static Future<void> _deleteGeneratedArtifacts(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (_isGeneratedUserArtifact(entity)) await entity.delete();
    }
  }
}
