import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:open_filex/open_filex.dart';

/// Desktop builds are replaced by a script that waits for the app to exit.
class EasyInstaller {
  const EasyInstaller._();

  static const windowsScript = r'''
param([int]$AppPid, [string]$Source, [string]$Dest, [string]$Exe)
$log = Join-Path (Split-Path $Source) 'update.log'
try { Wait-Process -Id $AppPid -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Get-Process -Name EasyVpnCore -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -and $_.Path.StartsWith($Dest, [StringComparison]::OrdinalIgnoreCase) } |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
robocopy $Source $Dest /E /R:5 /W:1 /NFL /NDL /NJH /NJS 2>&1 | Out-File $log -Encoding utf8
Start-Process -FilePath $Exe
''';

  static const linuxScript = r'''#!/bin/sh
APP_PID="$1"; SOURCE="$2"; DEST="$3"; EXE="$4"
i=0
while kill -0 "$APP_PID" 2>/dev/null && [ "$i" -lt 60 ]; do sleep 1; i=$((i + 1)); done
cp -rf "$SOURCE"/. "$DEST"/ > "$(dirname "$SOURCE")/update.log" 2>&1
chmod +x "$EXE" 2>/dev/null
nohup "$EXE" >/dev/null 2>&1 &
''';

  static String installDirectory() =>
      File(Platform.resolvedExecutable).parent.path;

  static Directory contentRoot(Directory extracted, String marker) {
    if (File(
      '${extracted.path}${Platform.pathSeparator}$marker',
    ).existsSync()) {
      return extracted;
    }
    final children = extracted.listSync();
    if (children.length == 1 && children.first is Directory) {
      return children.first as Directory;
    }
    return extracted;
  }

  static Future<void> install(File file, {required String platform}) async {
    switch (platform) {
      case 'android':
        final result = await OpenFilex.open(
          file.path,
          type: 'application/vnd.android.package-archive',
        );
        if (result.type != ResultType.done) throw Exception(result.message);
      case 'windows':
        final work = await _fresh(file, 'extracted');
        await extractFileToDisk(file.path, work.path);
        final source = contentRoot(work, 'EasyVpn.exe');
        final script = File(
          '${file.parent.path}${Platform.pathSeparator}apply_update.ps1',
        );
        await script.writeAsString(windowsScript);
        await Process.start('powershell.exe', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          script.path,
          '-AppPid',
          '$pid',
          '-Source',
          source.path,
          '-Dest',
          installDirectory(),
          '-Exe',
          Platform.resolvedExecutable,
        ], mode: ProcessStartMode.detached);
      case 'linux':
        final work = await _fresh(file, 'extracted');
        final tar = await Process.run('tar', [
          '-xzf',
          file.path,
          '-C',
          work.path,
        ]);
        if (tar.exitCode != 0) throw Exception('${tar.stderr}');
        final bundle = Directory('${work.path}/bundle');
        final source = bundle.existsSync() ? bundle : work;
        final script = File('${file.parent.path}/apply_update.sh');
        await script.writeAsString(linuxScript);
        await Process.start('sh', [
          script.path,
          '$pid',
          source.path,
          installDirectory(),
          Platform.resolvedExecutable,
        ], mode: ProcessStartMode.detached);
      default:
        throw UnsupportedError('This platform cannot update itself');
    }
  }

  static Future<Directory> _fresh(File file, String name) async {
    final dir = Directory('${file.parent.path}${Platform.pathSeparator}$name');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return dir;
  }
}
