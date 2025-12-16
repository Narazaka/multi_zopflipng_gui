import 'package:filesize/filesize.dart';

/// Base interface for all entry types
abstract class EntryInfo {
  bool get processing;
  set processing(bool value);
  bool get isProcessed;
  int get before;
  int? get after;
  int? get reduced;
  double? get reducedRate;
  String get displayPath;
  String get beforeSize;
  String get afterSize;
  String get reducedSize;
  String get reducedPercent;
}

/// Entry info for PNG files
class PngEntryInfo implements EntryInfo {
  final String path;
  @override
  final int before;
  @override
  bool processing = false;
  @override
  int? after;

  @override
  int? get reduced => isProcessed ? before - after! : null;

  @override
  double? get reducedRate => isProcessed && before > 0 ? reduced! / before : null;

  @override
  bool get isProcessed => after != null;

  @override
  String get displayPath => path;

  @override
  String get beforeSize => filesize(before);

  @override
  String get afterSize => isProcessed ? filesize(after!) : "";

  @override
  String get reducedSize => isProcessed ? "-${filesize(reduced!)}" : "";

  @override
  String get reducedPercent =>
      isProcessed ? "-${(reducedRate! * 100).toStringAsFixed(2)}" : "";

  PngEntryInfo(this.path, this.before);
}
