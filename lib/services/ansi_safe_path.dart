import 'package:jis0208/jis0208.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String toAnsiSafePath(String s) {
  return _isAnsiSafePath(s) ? s : _getShortPath(s);
}

bool _isAnsiSafePath(String s) {
  try {
    final encoded = Windows31JEncoder().convert(s);
    final decoded = Windows31JDecoder().convert(encoded);
    return s == decoded;
  } catch (_) {
    return false;
  }
}

String _getShortPath(String longPath, {int bufferLength = MAX_PATH}) {
  final pLong = longPath.toNativeUtf16();
  final pShort = calloc.allocate<Utf16>(bufferLength);

  final result = GetShortPathName(pLong, pShort, bufferLength);
  if (result == 0) {
    calloc.free(pLong);
    calloc.free(pShort);
    throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
  }
  if (result > bufferLength) {
    // Buffer too small, reallocate
    calloc.free(pLong);
    calloc.free(pShort);
    return _getShortPath(longPath, bufferLength: result);
  }

  final shortPath = pShort.toDartString();
  calloc.free(pLong);
  calloc.free(pShort);
  return shortPath;
}
