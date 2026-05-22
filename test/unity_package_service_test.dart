import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:multi_zopflipng_gui/models/unity_package_entry.dart';
import 'package:multi_zopflipng_gui/services/unity_package_service.dart';

void main() {
  group('UnityPackageService.repackage', () {
    late Directory workDir;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp('mzp_test_');
    });

    tearDown(() async {
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    });

    /// Build a .unitypackage file at [path] from archive entry name -> bytes.
    Future<void> writeUnityPackage(
        String path, Map<String, List<int>> entries) async {
      final archive = Archive();
      entries.forEach((name, content) {
        archive.addFile(ArchiveFile(name, content.length, content));
      });
      final tarBytes = TarEncoder().encode(archive);
      final gzipBytes = GZipEncoder().encode(tarBytes);
      await File(path).writeAsBytes(gzipBytes);
    }

    /// Read a .unitypackage file and return archive entry name -> bytes.
    Future<Map<String, List<int>>> readUnityPackage(String path) async {
      final bytes = await File(path).readAsBytes();
      final tarBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);
      return {
        for (final e in archive) e.name: e.content as List<int>,
      };
    }

    test('keeps the original asset of a skipped entry', () async {
      const goodGuid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const badGuid = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      // The "bad" asset is not a valid PNG, so zopflipng would fail on it.
      final originalBadAsset = [0xFF, 0xFE, 0xFD, 0x00, 0x11];

      final packagePath = p.join(workDir.path, 'sample.unitypackage');
      await writeUnityPackage(packagePath, {
        '$goodGuid/pathname': 'Assets/good.png'.codeUnits,
        '$goodGuid/asset': [1, 2, 3, 4],
        '$badGuid/pathname': 'Assets/bad.png'.codeUnits,
        '$badGuid/asset': originalBadAsset,
      });

      // The good entry was compressed: its temp file holds the compressed bytes.
      final goodTemp = File(p.join(workDir.path, 'good_compressed.png'));
      await goodTemp.writeAsBytes([9, 9]);
      final goodEntry = UnityPackagePngEntry(
        guid: goodGuid,
        pathname: 'Assets/good.png',
        before: 4,
      )..tempFilePath = goodTemp.path;

      // The bad entry failed compression and is skipped.
      final badEntry = UnityPackagePngEntry(
        guid: badGuid,
        pathname: 'Assets/bad.png',
        before: originalBadAsset.length,
      )..skipped = true;

      final service = UnityPackageService();
      addTearDown(service.cleanupAll);
      await service.repackage(packagePath, [goodEntry, badEntry]);

      final result = await readUnityPackage(packagePath);

      // The skipped entry's asset must survive untouched.
      expect(result['$badGuid/asset'], equals(originalBadAsset));
      // The compressed entry's asset must be replaced with the compressed bytes.
      expect(result['$goodGuid/asset'], equals([9, 9]));
    });
  });
}
