import 'ua_constants.dart';
import 'ua_repository.dart';

/// 按源解析应使用的 UserAgent。
///
/// 规则（对应需求）：
/// - 关闭自动选择：返回 null，调用方完全沿用原来的行为（手机默认 / 插件自身配置），
///   不做任何自动切换。
/// - 开启自动选择：
///   - 命中 PC-only 源（哔哩哔哩等）-> 电脑 UA 列表第一项
///   - 其余源 -> 手机 UA 列表第一项
///
/// 第一版没有插件业务逻辑，本解析器先把规则实现好并暴露给二期插件引擎调用；
/// 播放页等本地场景不会主动触发它（本地文件无需 UA）。
class UaResolver {
  final UaRepository _repo;

  UaResolver(this._repo);

  /// 返回给定源应使用的 UA 字符串；null 表示"沿用原行为，不指定"。
  Future<String?> resolve(String sourceNameOrUrl) async {
    final auto = await _repo.autoSelect();
    if (!auto) return null;

    final lower = sourceNameOrUrl.toLowerCase();
    final isPcOnly = UaConstants.pcOnlyKeywords
        .any((k) => lower.contains(k.toLowerCase()));

    if (isPcOnly) return _repo.desktopCurrent();
    return _repo.mobileCurrent();
  }

  /// 该源是否为"只认电脑 UA"的源（供 UI 展示/调试）
  bool isPcOnly(String sourceNameOrUrl) {
    final lower = sourceNameOrUrl.toLowerCase();
    return UaConstants.pcOnlyKeywords
        .any((k) => lower.contains(k.toLowerCase()));
  }
}
