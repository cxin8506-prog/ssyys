import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import 'ua_constants.dart';
import 'ua_repository.dart';

/// [UaResolver] provider：JS、JAR、TingShu 三个引擎统一走这一个解析器，
/// 不许再出现“只有 JS 引擎吃 UA”。
///
/// 注意：契约把 provider 写在 `lib/features/ua/data/ua_resolver.dart`，
/// 本次分工把 UA 文件放在 `lib/features/ua/`（扁平目录），provider 在此文件。
final uaResolverProvider = Provider<UaResolver>((ref) {
  return UaResolver(UaRepository(ref.read(databaseProvider)));
});

/// 按源解析应使用的 UserAgent。
///
/// 优先级（契约）：源配置写死的 UA > 按站记忆 > 域名/关键词规则表 > 自动选择。
/// - 源配置写死：调用方把源自己的配置 UA 传进 [sourceConfigUa]，永远最先赢。
/// - 按站记忆：用户在某个源/站手动切过 UA，下次打开这个源还用它。
/// - 规则表：域名/关键词 → 电脑版/手机版，用户可增删改、每条可开关。
/// - 自动选择：按调用方给的 [desktop] 标志取两条当前值之一。
/// 自动选择关了：规则表不生效，但源配置和按站记忆仍有效（那是用户/源明确指定的）。
/// 换 UA 立即生效：调用方改完当前值后调 [setMobileCurrent]/[setDesktopCurrent]，
/// 解析器会发 [onUaChanged]，引擎监听到后清会话、重建 WebView、重载或重播。
class UaResolver {
  final UaRepository _repo;

  UaResolver(this._repo);

  final _changedController = StreamController<void>.broadcast();

  /// UA 换了：引擎/页面监听这个流，清会话、重建 WebView、重载或重播。
  Stream<void> get onUaChanged => _changedController.stream;

  void notifyUaChanged() {
    if (!_changedController.isClosed) _changedController.add(null);
  }

  /// 返回给定源应使用的 UA 字符串（永远非空：兜底是两条当前值之一）。
  Future<String> resolve({
    required String sourceId,
    required String sourceName,
    String? url,
    String? sourceConfigUa,
    bool desktop = false,
  }) async {
    // 1. 源配置写死的 UA
    if (sourceConfigUa != null && sourceConfigUa.trim().isNotEmpty) {
      return sourceConfigUa.trim();
    }
    // 2. 按站记忆
    final remembered = await _repo.siteUa(sourceId);
    if (remembered != null && remembered.isNotEmpty) return remembered;
    // 3. 规则表（只在自动选择开着时生效）
    final auto = await _repo.autoSelect();
    if (auto) {
      final target = '${url ?? ''} $sourceName'.toLowerCase();
      final rules = await _repo.rules();
      for (final rule in rules) {
        if (!rule.enabled) continue;
        if (rule.pattern.isEmpty) continue;
        if (target.contains(rule.pattern.toLowerCase())) {
          return rule.desktop
              ? await _repo.desktopCurrent()
              : await _repo.mobileCurrent();
        }
      }
    }
    // 4. 自动选择：按 desktop 标志取两条当前值之一
    return desktop
        ? await _repo.desktopCurrent()
        : await _repo.mobileCurrent();
  }

  /// 搜索专用的 UA（抄 TVBox 的 SUserAgent）：搜索 UA > 源配置 UA > 其余同 resolve。
  Future<String> resolveSearch({
    required String sourceId,
    required String sourceName,
    String? url,
    String? sourceConfigUa,
    bool desktop = false,
  }) async {
    final searchUa = await _repo.searchUa(sourceId);
    if (searchUa != null && searchUa.isNotEmpty) return searchUa;
    return resolve(
      sourceId: sourceId,
      sourceName: sourceName,
      url: url,
      sourceConfigUa: sourceConfigUa,
      desktop: desktop,
    );
  }

  /// 该源/站是否命中了“用电脑版”的规则（供 UI 展示/调试）。
  Future<bool> isDesktopByRule({
    required String sourceName,
    String? url,
  }) async {
    if (!await _repo.autoSelect()) return false;
    final target = '${url ?? ''} $sourceName'.toLowerCase();
    final rules = await _repo.rules();
    for (final rule in rules) {
      if (!rule.enabled || rule.pattern.isEmpty) continue;
      if (target.contains(rule.pattern.toLowerCase())) return rule.desktop;
    }
    return false;
  }

  /// 用户在某个源/站手动切过 UA：记住它，下次打开这个源还用它。
  Future<void> rememberSiteUa(String sourceId, String ua) =>
      _repo.setSiteUa(sourceId, ua);

  Future<void> clearSiteUa(String sourceId) => _repo.clearSiteUa(sourceId);

  /// 改手机当前值并通知所有监听方立即生效。
  Future<void> setMobileCurrent(String ua) async {
    await _repo.setMobileCurrent(ua);
    notifyUaChanged();
  }

  /// 改电脑当前值并通知所有监听方立即生效。
  Future<void> setDesktopCurrent(String ua) async {
    await _repo.setDesktopCurrent(ua);
    notifyUaChanged();
  }

  /// “换个 UA 再试”：在同平台的内置推荐里换下一个（调用方最多试 2–3 个就停）。
  /// 返回换到的那条 UA；当前值不在推荐列表里时从第一条开始。
  String nextUa({required String current, bool desktop = false}) {
    final list = desktop
        ? UaConstants.desktopPresets
        : UaConstants.mobilePresets;
    final idx = list.indexWhere((p) => p.ua == current);
    if (idx < 0) return list.first.ua;
    return list[(idx + 1) % list.length].ua;
  }

  void dispose() {
    _changedController.close();
  }
}
