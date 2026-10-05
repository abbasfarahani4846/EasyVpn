import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';

import 'endpoint_healer.dart';

bool get _fa => PlatformDispatcher.instance.locale.languageCode == 'fa';

String repairMessage(EndpointHealReport report) {
  final fa = _fa;
  return [
    for (final r in report.repaired)
      fa
          ? '${r.name}: پورت ${r.from} جواب نداد، به ${r.to} تغییر کرد'
          : '${r.name}: port ${r.from} did not answer, switched to ${r.to}',
    for (final f in report.failed)
      fa
          ? '${f.name}: روی پورت ${f.tried.join('، ')} جواب نداد'
          : '${f.name}: no answer on port ${f.tried.join(', ')}',
  ].join('\n');
}

/// Run on every downloaded profile before it is saved.
Future<Uint8List> healProfileBytes(Uint8List bytes) async {
  final EndpointHealReport report;
  try {
    report = await EndpointHealer.heal(
      utf8.decode(bytes, allowMalformed: true),
    );
  } catch (_) {
    return bytes;
  }
  if (report.repaired.isNotEmpty || report.failed.isNotEmpty) {
    dialogs.showNotifier(
      repairMessage(report),
      level: report.failed.isEmpty ? MessageLevel.info : MessageLevel.error,
    );
  }
  return report.changed ? Uint8List.fromList(utf8.encode(report.yaml)) : bytes;
}
