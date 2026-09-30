import 'dart:io';

import 'package:path/path.dart' as p;

import 'core_transport.dart';
import 'ffi_transport.dart';
import 'process_transport.dart';
import 'unavailable_transport.dart';

/// Opens the best available transport for this platform:
///   Android          -> FFI (`libeasycore.so` bundled in jniLibs)
///   Windows/macOS/Linux -> child process (`easycoreproc`), FFI library as a dev fallback
///   iOS              -> not implemented yet (needs the PacketTunnel extension) -> unavailable
Future<CoreTransport> openCoreTransport({required String cacheDir}) async {
  final override = Platform.environment['EASYCORE_PATH'];
  try {
    if (Platform.isAndroid) {
      return await FfiTransport.open(
        libPath: 'libeasycore.so',
        cacheDir: cacheDir,
      );
    }
    if (Platform.isIOS) {
      return UnavailableTransport(
        'iOS core requires the PacketTunnel extension (not built in this release)',
      );
    }
    for (final exe in _processCandidates(override)) {
      if (File(exe).existsSync()) {
        return await ProcessTransport.open(executable: exe, cacheDir: cacheDir);
      }
    }
    for (final lib in _libCandidates(override)) {
      if (File(lib).existsSync()) {
        return await FfiTransport.open(libPath: lib, cacheDir: cacheDir);
      }
    }
    return UnavailableTransport(
      'no core binary found (looked next to the app and in ../bin)',
    );
  } on CoreUnavailable catch (e) {
    return UnavailableTransport(e.reason);
  } catch (e) {
    return UnavailableTransport('$e');
  }
}

String get _osTag =>
    Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'darwin' : 'linux');

List<String> _searchDirs() {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  return [
    exeDir,
    p.join(exeDir, 'data'),
    p.join(exeDir, 'lib'),
    p.normalize(p.join(exeDir, '..', 'Frameworks')),
    p.normalize(p.join(exeDir, '..', 'Resources')),
    // development checkouts: <repo>/bin next to the working directory
    p.join(Directory.current.path, 'bin'),
    p.normalize(p.join(Directory.current.path, '..', 'bin')),
  ];
}

List<String> _processCandidates(String? override) {
  final names = Platform.isWindows
      ? ['easycoreproc.exe', 'easycoreproc-windows-amd64.exe']
      : [
          'easycoreproc',
          'easycoreproc-$_osTag-amd64',
          'easycoreproc-$_osTag-arm64',
        ];
  return [
    ?override,
    for (final d in _searchDirs())
      for (final n in names) p.join(d, n),
  ];
}

List<String> _libCandidates(String? override) {
  final names = Platform.isWindows
      ? ['easycore.dll']
      : (Platform.isMacOS ? ['libeasycore.dylib'] : ['libeasycore.so']);
  return [
    ?override,
    for (final d in _searchDirs())
      for (final n in names) p.join(d, n),
  ];
}
