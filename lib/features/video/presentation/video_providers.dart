import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 视频模块 provider 占位（视频列表复用 libraryRepository，按 type=video 查询）
/// 后续可在此扩展视频专属状态（如当前线路、音量、亮度记忆）。
final videoSpeedProvider = Provider<double>((ref) => 1.0);
