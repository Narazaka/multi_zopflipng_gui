import 'package:multi_zopflipng_gui/services/ansi_safe_path.dart';

/// Options for zopflipng compression
class ZopflipngOptions {
  final bool m;
  final bool lossyTransparent;
  final bool lossy8bit;
  final bool preserveExif;
  final bool preserveTextMetadata;

  const ZopflipngOptions({
    this.m = true,
    this.lossyTransparent = false,
    this.lossy8bit = false,
    this.preserveExif = false,
    this.preserveTextMetadata = true,
  });

  /// Build command line arguments for zopflipng
  List<String> buildArgs(String inputPath, String outputPath) {
    final args = <String>[];

    if (m) {
      args.add("-m");
    }
    if (lossyTransparent) {
      args.add("--lossy_transparent");
    }
    if (lossy8bit) {
      args.add("--lossy_8bit");
    }
    if (preserveExif || preserveTextMetadata) {
      final chunks = <String>[];
      if (preserveExif) {
        chunks.add("eXIf");
      }
      if (preserveTextMetadata) {
        chunks.addAll(["tEXt", "zTXt", "iTXt"]);
      }
      args.add("--keepchunks=${chunks.join(",")}");
    }
    args.add("-y");
    args.add(toAnsiSafePath(inputPath));
    args.add(toAnsiSafePath(outputPath));

    return args;
  }

  ZopflipngOptions copyWith({
    bool? m,
    bool? lossyTransparent,
    bool? lossy8bit,
    bool? preserveExif,
    bool? preserveTextMetadata,
  }) {
    return ZopflipngOptions(
      m: m ?? this.m,
      lossyTransparent: lossyTransparent ?? this.lossyTransparent,
      lossy8bit: lossy8bit ?? this.lossy8bit,
      preserveExif: preserveExif ?? this.preserveExif,
      preserveTextMetadata: preserveTextMetadata ?? this.preserveTextMetadata,
    );
  }
}
