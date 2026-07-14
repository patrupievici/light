import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/local_account_data_wiper.dart';

void main() {
  group('LocalAccountDataWiper', () {
    test(
        'removes known databases, progress photos, image caches and share artifacts',
        () async {
      final root =
          await Directory.systemTemp.createTemp('zvelt-account-erase-');
      final docs = Directory('${root.path}${Platform.pathSeparator}docs')
        ..createSync();
      final temp = Directory('${root.path}${Platform.pathSeparator}temp')
        ..createSync();
      final docShare =
          File('${docs.path}${Platform.pathSeparator}zvelt_session.png')
            ..writeAsStringSync('x');
      final tempShare =
          File('${temp.path}${Platform.pathSeparator}zvelt_activity_1.png')
            ..writeAsStringSync('x');
      final export =
          File('${temp.path}${Platform.pathSeparator}zvelt-data-export.json')
            ..writeAsStringSync('{}');
      final keep = File('${docs.path}${Platform.pathSeparator}keep.txt')
        ..writeAsStringSync('keep');
      var progressCleared = false;
      var databasesCleared = false;
      var imageCacheCleared = false;

      final wiper = LocalAccountDataWiper(
        clearProgressPhotos: () async => progressCleared = true,
        clearEncryptedDatabases: () async => databasesCleared = true,
        clearImageCaches: () async => imageCacheCleared = true,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => temp,
      );

      final result = await wiper.wipe();

      expect(result.completed, isTrue);
      expect(progressCleared, isTrue);
      expect(databasesCleared, isTrue);
      expect(imageCacheCleared, isTrue);
      expect(await docShare.exists(), isFalse);
      expect(await tempShare.exists(), isFalse);
      expect(await export.exists(), isFalse);
      expect(await keep.exists(), isTrue);
      await root.delete(recursive: true);
    });

    test(
        'continues cleanup and reports a failed step instead of aborting deletion',
        () async {
      final root =
          await Directory.systemTemp.createTemp('zvelt-account-erase-failure-');
      final failures = <String>[];
      var laterStepRan = false;
      final wiper = LocalAccountDataWiper(
        clearProgressPhotos: () async => throw StateError('photo DB locked'),
        clearEncryptedDatabases: () async => laterStepRan = true,
        clearImageCaches: () async {},
        documentsDirectory: () async => root,
        temporaryDirectory: () async => root,
        onFailure: (_, __, reason) => failures.add(reason),
      );

      final result = await wiper.wipe();

      expect(result.completed, isFalse);
      expect(result.failedSteps, contains('progress-photos'));
      expect(laterStepRan, isTrue);
      expect(failures, contains('account-erasure:progress-photos'));
      await root.delete(recursive: true);
    });
  });
}
