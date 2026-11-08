import 'dart:math';

import 'game_models.dart';

/// Spatial hit rules from the original F-Droid 1.0.0 build (upstream
/// 6829d30c6975e9ac213cb62f7e7e02c63b4dd1bb, game_screen.dart).
/// Both painting and input use these same bounds; audio/event timestamps do
/// not participate in deciding whether a visible tile was tapped.
class TileHitTest {
  static const tileHeightFactor = 0.20;
  static double height(GameTile tile) => tileHeightFactor * tile.length;
  static double top(GameTile tile) => tile.y - height(tile);

  static GameTile? select(
    List<GameTile> tiles,
    int lane,
    double tapY,
    double targetLine,
  ) {
    final unhit = tiles
        .where((t) => !t.isHit && !t.isHolding && !t.isMissed)
        .toList();
    final candidates = unhit.where((t) => t.lane == lane).toList()
      ..sort((a, b) => b.y.compareTo(a.y));
    for (final tile in candidates) {
      final tileTop = top(tile);
      final isDirectTap = tapY >= tileTop - 0.08 && tapY <= tile.y + 0.08;
      final isTargetLineHit =
          tile.y >= targetLine - 0.18 &&
          tileTop <= targetLine + 0.18 &&
          (tapY - targetLine).abs() <= 0.18;
      if (isDirectTap || isTargetLineHit) {
        if (unhit.any((t) => t.id < tile.id && top(t) > 1.0)) return null;
        return tile;
      }
    }
    return null;
  }

  static HitQuality quality(GameTile tile, double targetLine) {
    final tileTop = top(tile);
    final distance = targetLine >= tileTop && targetLine <= tile.y
        ? 0.0
        : min((tile.y - targetLine).abs(), (tileTop - targetLine).abs());
    if (distance < 0.05) return HitQuality.perfect;
    if (distance < 0.11) return HitQuality.great;
    return HitQuality.good;
  }

  static bool isMissed(GameTile tile) =>
      !tile.isHit && !tile.isHolding && !tile.isMissed && tile.y > 1.02;
}
