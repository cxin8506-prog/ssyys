import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 封面取色（照 Voice 的 CoverSeedColors 思路重写）。
///
/// - 种子色按封面地址存：内存 + 磁盘（SharedPreferences），启动时先恢复，
///   取不到才现算，算完写回；失败的不缓存，下次重试。
/// - 不只取平均色：种子色派生一整套配色（primary / container /
///   onPrimary 按深浅两套算，Vibrant 风格），不是只把按钮刷成平均色。
/// - 太暗 / 太淡的种子钳制亮度，保证深色 / 浅色下字都看得清。
class CoverColorCache {
  CoverColorCache._();

  static final Map<String, Color> _memory = <String, Color>{};
  static SharedPreferences? _prefs;
  static bool _restored = false;

  static const String _prefsKey = 'cover_seed_colors_v1';
  static const int _maxStored = 200;

  /// 启动时先恢复磁盘里存过的种子色（main 里调一次，不阻塞启动）。
  static Future<void> restore(SharedPreferences prefs) async {
    _prefs = prefs;
    if (_restored) return;
    _restored = true;
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is Map) {
        map.forEach((key, value) {
          final v = int.tryParse('$value');
          if (key is String && v != null) {
            _memory[key] = Color(v);
          }
        });
      }
    } catch (_) {
      // 磁盘缓存坏了就丢掉，下次重算，不拦截启动。
    }
  }

  static Color? seedInMemory(String coverUrl) => _memory[coverUrl];

  static Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final entries = _memory.entries.toList();
      final keep = entries.length > _maxStored
          ? entries.sublist(entries.length - _maxStored)
          : entries;
      final map = <String, int>{};
      for (final e in keep) {
        map[e.key] = e.value.value;
      }
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {
      // 写缓存失败不报错，下次重算。
    }
  }

  static void _store(String coverUrl, Color seed) {
    _memory[coverUrl] = seed;
    unawaited(_persist());
  }
}

/// 取封面主色（种子色）。
///
/// 流程：内存 → 磁盘（restore 时已进内存）→ 现算（下载封面缩到 48px
/// 采样，跳过透明/太暗/太淡/低饱和像素求平均）→ 写回缓存。
/// 取不到返回 null（调用方用主题色兜底），失败不缓存。
Future<Color?> dominantCoverColor(String? coverUrl) async {
  if (coverUrl == null || coverUrl.isEmpty) return null;
  final cached = CoverColorCache.seedInMemory(coverUrl);
  if (cached != null) return cached;
  try {
    final uri = Uri.tryParse(coverUrl);
    if (uri == null || !uri.hasScheme) return null;
    final resp = await http
        .get(uri)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final seed = await _seedFromBytes(resp.bodyBytes);
    if (seed == null) return null;
    CoverColorCache._store(coverUrl, seed);
    return seed;
  } catch (_) {
    // 失败不缓存，下次重试。
    return null;
  }
}

Future<Color?> _seedFromBytes(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 48,
      targetHeight: 48,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;
    final data = byteData.buffer.asUint8List();
    var r = 0;
    var g = 0;
    var b = 0;
    var count = 0;
    for (var i = 0; i + 3 < data.length; i += 4) {
      final a = data[i + 3];
      final pr = data[i];
      final pg = data[i + 1];
      final pb = data[i + 2];
      if (a < 128) continue;
      // 跳过太暗（<40）、太淡（>235）的像素。
      if (pr < 40 && pg < 40 && pb < 40) continue;
      if (pr > 235 && pg > 235 && pb > 235) continue;
      // 跳过低饱和像素（通道差 <24，近似灰色）。
      final maxC = pr > pg ? (pr > pb ? pr : pb) : (pg > pb ? pg : pb);
      final minC = pr < pg ? (pr < pb ? pr : pb) : (pg < pb ? pg : pb);
      if (maxC - minC < 24) continue;
      r += pr;
      g += pg;
      b += pb;
      count++;
    }
    if (count == 0) return null;
    final seed = Color.fromARGB(
      255,
      (r / count).round().clamp(0, 255).toInt(),
      (g / count).round().clamp(0, 255).toInt(),
      (b / count).round().clamp(0, 255).toInt(),
    );
    return clampSeedBrightness(seed);
  } catch (_) {
    return null;
  }
}

/// 钳制种子亮度：太暗的提亮、太淡的压暗，保证深色/浅色下字都看得清。
Color clampSeedBrightness(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  // 相对亮度太低（<0.18）提亮到 0.25；太高（>0.85）压到 0.75。
  double l = hsl.lightness;
  if (l < 0.18) l = 0.25;
  if (l > 0.85) l = 0.75;
  // 饱和度太低的颜色当主色会发灰，提到至少 0.45。
  double s = hsl.saturation;
  if (s < 0.45) s = 0.45;
  return hsl.withLightness(l).withSaturation(s).toColor();
}

/// 种子色派生一整套配色（Vibrant 风格，深色/浅色两套）。
class CoverScheme {
  final Color primary;
  final Color container;
  final Color onPrimary;
  final Color surfaceTint;

  const CoverScheme({
    required this.primary,
    required this.container,
    required this.onPrimary,
    required this.surfaceTint,
  });
}

CoverScheme coverSchemeFor(Color seed, bool dark) {
  final base = clampSeedBrightness(seed);
  final hsl = HSLColor.fromColor(base);
  if (dark) {
    final primary = hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    final container = hsl
        .withLightness((hsl.lightness * 0.35).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0))
        .toColor();
    return CoverScheme(
      primary: primary,
      container: container,
      onPrimary: Colors.white,
      surfaceTint: primary,
    );
  } else {
    final primary = hsl.withLightness((hsl.lightness * 0.72).clamp(0.0, 1.0)).toColor();
    final container = hsl
        .withLightness((0.55 + hsl.lightness * 0.4).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0))
        .toColor();
    return CoverScheme(
      primary: primary,
      container: container,
      onPrimary: Colors.white,
      surfaceTint: primary,
    );
  }
}
