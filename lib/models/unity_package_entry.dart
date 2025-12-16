import 'package:filesize/filesize.dart';
import 'package:uuid/uuid.dart';

import 'entry_info.dart';

const _uuid = Uuid();

/// Entry info for PNG files inside a UnityPackage
class UnityPackagePngEntry implements EntryInfo {
  final String guid;
  final String pathname;
  @override
  final int before;
  String? tempFilePath;
  @override
  int? after;
  @override
  bool processing = false;

  @override
  int? get reduced => isProcessed ? before - after! : null;

  @override
  double? get reducedRate => isProcessed && before > 0 ? reduced! / before : null;

  @override
  bool get isProcessed => after != null;

  @override
  String get displayPath => pathname;

  @override
  String get beforeSize => filesize(before);

  @override
  String get afterSize => isProcessed ? filesize(after!) : "";

  @override
  String get reducedSize => isProcessed ? "-${filesize(reduced!)}" : "";

  @override
  String get reducedPercent =>
      isProcessed ? "-${(reducedRate! * 100).toStringAsFixed(2)}" : "";

  UnityPackagePngEntry({
    required this.guid,
    required this.pathname,
    required this.before,
  });
}

/// Entry info for UnityPackage files
class UnityPackageEntry implements EntryInfo {
  /// Unique identifier for this entry (used for temp file naming)
  final String id;
  final String path;
  @override
  final int before;
  final List<UnityPackagePngEntry> pngEntries;
  @override
  int? after;
  @override
  bool processing = false;

  bool get allPngsProcessed => pngEntries.every((e) => e.isProcessed);

  @override
  bool get isProcessed => after != null;

  @override
  String get displayPath => path;

  @override
  int? get reduced => isProcessed ? before - after! : null;

  @override
  double? get reducedRate => isProcessed && before > 0 ? reduced! / before : null;

  @override
  String get beforeSize => filesize(before);

  @override
  String get afterSize => isProcessed ? filesize(after!) : "";

  @override
  String get reducedSize => isProcessed ? "-${filesize(reduced!)}" : "";

  @override
  String get reducedPercent =>
      isProcessed ? "-${(reducedRate! * 100).toStringAsFixed(2)}" : "";

  /// Total before size of all PNG entries
  int get totalPngBefore => pngEntries.fold(0, (sum, e) => sum + e.before);

  /// Total after size of all processed PNG entries
  int get totalPngAfter =>
      pngEntries.where((e) => e.isProcessed).fold(0, (sum, e) => sum + e.after!);

  /// Count of processed PNG entries
  int get processedPngCount => pngEntries.where((e) => e.isProcessed).length;

  UnityPackageEntry({
    required this.path,
    required this.before,
    required this.pngEntries,
  }) : id = _uuid.v4();
}
