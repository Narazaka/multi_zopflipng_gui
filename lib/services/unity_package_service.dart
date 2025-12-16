import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/unity_package_entry.dart';

/// Service for handling UnityPackage files
class UnityPackageService {
  /// Temporary directory for extracted files
  Directory? _tempDir;

  /// Get or create the temporary directory
  Future<Directory> _getTempDir() async {
    _tempDir ??= await Directory.systemTemp.createTemp('multi_zopflipng_');
    return _tempDir!;
  }

  /// Scan a unitypackage file for PNG entries
  Future<List<UnityPackagePngEntry>> scanPngEntries(String packagePath) async {
    final file = File(packagePath);
    final bytes = await file.readAsBytes();

    // Decode gzip
    final gzipDecoder = GZipDecoder();
    final tarBytes = gzipDecoder.decodeBytes(bytes);

    // Decode tar
    final tarDecoder = TarDecoder();
    final archive = tarDecoder.decodeBytes(tarBytes);

    // Map to store pathname by GUID
    final pathnameMap = <String, String>{};
    // Map to store asset size by GUID
    final assetSizeMap = <String, int>{};

    for (final entry in archive) {
      final parts = entry.name.split('/');
      if (parts.length < 2) continue;

      final guid = parts[0];
      final fileName = parts[1];

      if (fileName == 'pathname') {
        // Read pathname content
        final content = String.fromCharCodes(entry.content as List<int>).trim();
        pathnameMap[guid] = content;
      } else if (fileName == 'asset') {
        assetSizeMap[guid] = entry.size;
      }
    }

    // Find PNG entries
    final pngEntries = <UnityPackagePngEntry>[];
    for (final entry in pathnameMap.entries) {
      final guid = entry.key;
      final pathname = entry.value;

      // Check if it's a PNG file
      if (pathname.toLowerCase().endsWith('.png')) {
        final size = assetSizeMap[guid];
        if (size != null && size > 0) {
          pngEntries.add(UnityPackagePngEntry(
            guid: guid,
            pathname: pathname,
            before: size,
          ));
        }
      }
    }

    return pngEntries;
  }

  /// Extract a specific PNG entry to a temporary file
  Future<String> extractPngToTemp(
    String packagePath,
    UnityPackagePngEntry entry,
  ) async {
    final tempDir = await _getTempDir();
    final file = File(packagePath);
    final bytes = await file.readAsBytes();

    // Decode gzip
    final gzipDecoder = GZipDecoder();
    final tarBytes = gzipDecoder.decodeBytes(bytes);

    // Decode tar
    final tarDecoder = TarDecoder();
    final archive = tarDecoder.decodeBytes(tarBytes);

    // Find the asset file for this GUID
    for (final archiveEntry in archive) {
      if (archiveEntry.name == '${entry.guid}/asset') {
        // Write to temp file
        final tempFile = File(p.join(tempDir.path, '${entry.guid}.png'));
        await tempFile.writeAsBytes(archiveEntry.content as List<int>);
        return tempFile.path;
      }
    }

    throw Exception('Asset not found for GUID: ${entry.guid}');
  }

  /// Repackage the unitypackage with compressed PNG files
  Future<int> repackage(
    String packagePath,
    List<UnityPackagePngEntry> pngEntries,
  ) async {
    final file = File(packagePath);
    final bytes = await file.readAsBytes();

    // Decode original archive
    final gzipDecoder = GZipDecoder();
    final tarBytes = gzipDecoder.decodeBytes(bytes);
    final tarDecoder = TarDecoder();
    final originalArchive = tarDecoder.decodeBytes(tarBytes);

    // Create a set of PNG GUIDs for quick lookup
    final pngGuids = pngEntries.map((e) => e.guid).toSet();

    // Create new archive
    final newArchive = Archive();

    // Copy non-PNG entries from original archive
    for (final entry in originalArchive) {
      final parts = entry.name.split('/');
      if (parts.length < 2) {
        // Keep entries that don't follow GUID/filename pattern
        newArchive.addFile(ArchiveFile(
          entry.name,
          entry.size,
          entry.content,
        ));
        continue;
      }

      final guid = parts[0];
      final fileName = parts[1];

      // If this is a PNG asset file, skip it (we'll add the compressed version)
      if (pngGuids.contains(guid) && fileName == 'asset') {
        continue;
      }

      // Copy other files as-is
      newArchive.addFile(ArchiveFile(
        entry.name,
        entry.size,
        entry.content,
      ));
    }

    // Add compressed PNG files
    for (final pngEntry in pngEntries) {
      if (pngEntry.tempFilePath == null) continue;

      final compressedFile = File(pngEntry.tempFilePath!);
      if (!await compressedFile.exists()) continue;

      final compressedBytes = await compressedFile.readAsBytes();
      newArchive.addFile(ArchiveFile(
        '${pngEntry.guid}/asset',
        compressedBytes.length,
        compressedBytes,
      ));
    }

    // Encode to tar
    final tarEncoder = TarEncoder();
    final newTarBytes = tarEncoder.encode(newArchive);

    // Encode to gzip with archtemp.tar filename
    final gzipBytes = _createGzipWithFilename(newTarBytes, 'archtemp.tar');

    // Write to file
    await file.writeAsBytes(gzipBytes);

    return gzipBytes.length;
  }

  /// Create a gzip file with a specific filename in the header
  List<int> _createGzipWithFilename(List<int> data, String filename) {
    // Use GZipEncoder for compression, CRC32, and size calculation
    final gzipData = GZipEncoder().encode(data);

    // GZipEncoder output: [header 10 bytes][compressed data][footer 8 bytes]
    // We need to insert filename after header byte 10, and set FNAME flag (0x08) at byte 3
    final filenameBytes = filename.codeUnits;

    return [
      // Header with FNAME flag
      gzipData[0], // ID1: 0x1f
      gzipData[1], // ID2: 0x8b
      gzipData[2], // CM: 8
      gzipData[3] | 0x08, // FLG: set FNAME flag
      gzipData[4], gzipData[5], gzipData[6], gzipData[7], // MTIME
      gzipData[8], // XFL
      0, // OS (0 for FAT filesystem)
      // Filename (null-terminated)
      ...filenameBytes,
      0,
      // Rest of gzip data (compressed data + footer)
      ...gzipData.sublist(10),
    ];
  }

  /// Clean up temporary files for a package
  Future<void> cleanupTempFiles(List<UnityPackagePngEntry> pngEntries) async {
    for (final entry in pngEntries) {
      if (entry.tempFilePath != null) {
        final file = File(entry.tempFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        entry.tempFilePath = null;
      }
    }
  }

  /// Clean up all temporary files
  Future<void> cleanupAll() async {
    if (_tempDir != null && await _tempDir!.exists()) {
      await _tempDir!.delete(recursive: true);
      _tempDir = null;
    }
  }
}
