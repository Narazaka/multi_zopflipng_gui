import 'package:filesize/filesize.dart';

/// Entry info for PNG files
class PngEntryInfo {
  final String path;
  final int before;
  bool processing = false;
  int? after;

  int? get reduced => isProcessed ? before - after! : null;
  double? get reducedRate => isProcessed ? reduced! / before : null;
  bool get isProcessed => after != null;
  String get beforeSize => filesize(before);
  String get afterSize => isProcessed ? filesize(after!) : "";
  String get reducedSize => isProcessed ? "-${filesize(reduced!)}" : "";
  String get reducedPercent =>
      isProcessed ? "-${(reducedRate! * 100).toStringAsFixed(2)}" : "";

  PngEntryInfo(this.path, this.before);
}
