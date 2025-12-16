import 'dart:io';

import 'zopflipng_options.dart';

/// Result of PNG compression
class CompressionResult {
  final bool success;
  final int? newSize;
  final String? error;

  CompressionResult.success(this.newSize)
      : success = true,
        error = null;

  CompressionResult.failure(this.error)
      : success = false,
        newSize = null;
}

/// Service for compressing PNG files using zopflipng
class PngCompressor {
  final Set<Process> _processes = {};

  /// Currently running processes
  Set<Process> get processes => _processes;

  /// Compress a PNG file in place
  Future<CompressionResult> compress(
    String filePath,
    ZopflipngOptions options,
  ) async {
    return compressTo(filePath, filePath, options);
  }

  /// Compress a PNG file to a specified output path
  Future<CompressionResult> compressTo(
    String inputPath,
    String outputPath,
    ZopflipngOptions options,
  ) async {
    Process? process;
    try {
      final args = options.buildArgs(inputPath, outputPath);
      process = await Process.start("zopflipng.exe", args);
      _processes.add(process);

      final exitCode = await process.exitCode;
      _processes.remove(process);

      if (exitCode != 0) {
        return CompressionResult.failure('Exit code: $exitCode');
      }

      final newSize = await File(outputPath).length();
      return CompressionResult.success(newSize);
    } catch (e) {
      if (process != null) {
        _processes.remove(process);
      }
      return CompressionResult.failure(e.toString());
    }
  }

  /// Kill all running processes
  void killAll() {
    for (final p in _processes.toList()) {
      p.kill(ProcessSignal.sigkill);
    }
    _processes.clear();
  }
}
