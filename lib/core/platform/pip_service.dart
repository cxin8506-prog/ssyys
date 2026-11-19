import 'package:flutter/services.dart';

/// 画中画（Android 8.0+）
///
/// Flutter 侧只负责发起请求，真正的 PiP 由原生 MainActivity 完成。
class PipService {
  static const MethodChannel _channel = MethodChannel('suishou/pip');

  /// 当前设备/系统是否支持画中画
  static Future<bool> isAvailable() async {
    try {
      final v = await _channel.invokeMethod<bool>('available');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 进入画中画，返回是否成功
  static Future<bool> enter({int width = 16, int height = 9}) async {
    try {
      final v = await _channel.invokeMethod<bool>(
          'enter', {'width': width, 'height': height});
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已经在画中画里
  static Future<bool> isInPip() async {
    try {
      final v = await _channel.invokeMethod<bool>('isIn');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
