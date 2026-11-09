import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/game_models.dart';
import '../models/song_analysis.dart';
import '../models/tile_variant.dart';
import 'storage_service.dart';

class AnalysisService {
  static final instance = AnalysisService();
  static const channel = MethodChannel('echotiles/analysis');
  final Map<String, Map<String, dynamic>> _cache = {};
  final Map<String, SongAnalysis> _charts = {};
  void Function(double)? onProgress;

  AnalysisService() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        onProgress?.call((call.arguments as num).toDouble().clamp(0, 1));
      }
    });
  }

  Future<File> _file(SongItem song) async {
    final dir = await getApplicationSupportDirectory();
    final safeId = base64Url.encode(utf8.encode(song.id));
    return File('${dir.path}/analysis/$safeId.json');
  }

  static Future<SongAnalysis> _plan(
    Map<String, dynamic> raw,
    TileVariant variant,
  ) => Isolate.run(() => SongAnalysis.fromJson(raw, variant: variant));

  Future<SongAnalysis?> load(SongItem song, {TileVariant? variant}) async {
    final selected = variant ?? StorageService.getTileVariant();
    final key = '${song.id}/${selected.name}';
    try {
      final file = await _file(song);
      final saved =
          _cache[song.id] ??
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Only the current audio-evidence schema is reusable by the app. Old
      // files are replaced automatically when play is pressed, never silently
      // treated as a current analysis after an engine update.
      if (saved['version'] != SongAnalysis.version ||
          saved['candidates'] == null) {
        return null;
      }
      if (saved['source'] != song.assetAudio) return null;
      if (!song.assetAudio.startsWith('assets/') &&
          !song.assetAudio.startsWith('content:')) {
        final stat = await File(song.assetAudio).stat();
        if (saved['size'] != stat.size ||
            saved['modified'] != stat.modified.millisecondsSinceEpoch) {
          return null;
        }
      }
      if (_charts[key] case final chart?) return chart;
      final analysis = await _plan(saved, selected);
      _cache[song.id] = saved;
      _charts[key] = analysis;
      return analysis;
    } catch (_) {
      return null;
    }
  }

  Future<SongAnalysis> analyze(SongItem song, {TileVariant? variant}) async {
    final selected = variant ?? StorageService.getTileVariant();
    final result = await channel.invokeMapMethod<String, dynamic>('analyze', {
      'path': song.assetAudio,
    });
    final raw = result!;
    final analysis = await _plan(raw, selected);
    final saved = {...analysis.toJson(), 'source': song.assetAudio};
    if (!song.assetAudio.startsWith('assets/') &&
        !song.assetAudio.startsWith('content:')) {
      final stat = await File(song.assetAudio).stat();
      saved.addAll({
        'size': stat.size,
        'modified': stat.modified.millisecondsSinceEpoch,
      });
    }
    final file = await _file(song);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(saved), flush: true);
    await temporary.rename(file.path);
    _cache[song.id] = saved;
    _charts.removeWhere((key, _) => key.startsWith('${song.id}/'));
    _charts['${song.id}/${selected.name}'] = analysis;
    return analysis;
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');

  Future<void> remove(SongItem song) async {
    _cache.remove(song.id);
    _charts.removeWhere((key, _) => key.startsWith('${song.id}/'));
    final file = await _file(song);
    if (await file.exists()) await file.delete();
  }
}
