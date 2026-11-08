import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/game_models.dart';
import '../models/song_analysis.dart';

class AnalysisService {
  static final instance = AnalysisService();
  static const channel = MethodChannel('echotiles/analysis');
  final Map<String, SongAnalysis> _cache = {};
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

  Future<SongAnalysis?> load(SongItem song) async {
    if (_cache.containsKey(song.id)) return _cache[song.id];
    try {
      final file = await _file(song);
      final saved =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (saved['source'] != song.assetAudio) return null;
      if (!song.assetAudio.startsWith('assets/') &&
          !song.assetAudio.startsWith('content:')) {
        final stat = await File(song.assetAudio).stat();
        if (saved['size'] != stat.size ||
            saved['modified'] != stat.modified.millisecondsSinceEpoch) {
          return null;
        }
      }
      final analysis = SongAnalysis.fromJson(saved);
      _cache[song.id] = analysis;
      return analysis;
    } catch (_) {
      return null;
    }
  }

  Future<SongAnalysis> analyze(SongItem song) async {
    final result = await channel.invokeMapMethod<String, dynamic>('analyze', {
      'path': song.assetAudio,
    });
    final analysis = SongAnalysis.fromJson(result!);
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
    _cache[song.id] = analysis;
    return analysis;
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');

  Future<void> remove(SongItem song) async {
    _cache.remove(song.id);
    final file = await _file(song);
    if (await file.exists()) await file.delete();
  }
}
