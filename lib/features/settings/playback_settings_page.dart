import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../shared/widgets/common.dart';

/// 播放设置页。
///
/// 全部真接线（播放器组按这些值执行；本页只负责改值 + 落盘）：
/// 默认倍速 1.0（0.5–3.0）、快退/快进步长 15 秒（5/10/15/30/60）、
/// 自动播下一集开、启动恢复开（恢复到断点但不自动播）、跳过无声开、
/// 锁屏滑杆开、熄屏保活开、暂停后自动倒带开、睡眠定时默认值、
/// 自动换线开。
///
/// 不留没接线的开关：锁屏显示、耳机拔出暂停、离开播放页自动暂停、
/// 定时关闭是否完全退出、桌面小工具、选择启动图标全部不做。
class PlaybackSettingsPage extends ConsumerWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(defaultSpeedProvider);
    final seekStep = ref.watch(seekStepProvider);
    final sleepDefault = ref.watch(sleepTimerDefaultProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('播放设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ValueRow(
            title: '默认倍速',
            subtitle: '${speed.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}x',
            info: '新开一本书的默认倍速，默认 1.0，范围 0.5–3.0。单本书单独存过倍速就用那本书的，换书自动切换。',
            onTap: () => _pickSpeed(context, ref, speed),
          ),
          _ValueRow(
            title: '快退 / 快进步长',
            subtitle: '$seekStep 秒',
            info: '快退/快进一次跳多少秒，默认 15 秒，选项 5 / 10 / 15 / 30 / 60 秒。锁屏按钮的快退/快进间隔跟着这个值走。',
            onTap: () => _pickSeekStep(context, ref, seekStep),
          ),
          _SwitchRow(
            title: '自动播放下一集',
            subtitle: ref.watch(autoNextProvider) ? '开' : '关',
            info: '播完一集自动进下一集，从头开始并跳过片头。关了播完就停住。音频和视频都管。',
            value: ref.watch(autoNextProvider),
            onChanged: (v) =>
                saveBoolSetting(ref, autoNextProvider, 'auto_next', v),
          ),
          _SwitchRow(
            title: '启动时恢复上次播放',
            subtitle: ref.watch(resumeEnabledProvider) ? '开' : '关',
            info: '默认开：打开 App 恢复到上次的断点，但不自动播。关了不再存新断点。',
            value: ref.watch(resumeEnabledProvider),
            onChanged: (v) => saveBoolSetting(
                ref, resumeEnabledProvider, 'resume_enabled', v),
          ),
          _SwitchRow(
            title: '跳过无声',
            subtitle: ref.watch(skipSilenceProvider) ? '开' : '关',
            info: '默认开：跳过音频里的无声部分。单本书单独存过就用那本书的。',
            value: ref.watch(skipSilenceProvider),
            onChanged: (v) => saveBoolSetting(
                ref, skipSilenceProvider, 'skip_silence', v),
          ),
          _SwitchRow(
            title: '锁屏滑杆',
            subtitle: ref.watch(lockScreenSliderProvider) ? '开' : '关',
            info: '默认开：锁屏通知上有可拖动的进度条。关了锁屏通知就只有按钮，没有拖动条。',
            value: ref.watch(lockScreenSliderProvider),
            onChanged: (v) => saveBoolSetting(
                ref, lockScreenSliderProvider, 'lockscreen_slider', v),
          ),
          _SwitchRow(
            title: '熄屏保活（WakeLock）',
            subtitle: ref.watch(wakeLockProvider) ? '开' : '关',
            info: '默认开：屏幕关着也保住 Wi-Fi、继续播。介意耗电可关。电池优化白名单还要去系统设置里加。',
            value: ref.watch(wakeLockProvider),
            onChanged: (v) =>
                saveBoolSetting(ref, wakeLockProvider, 'wake_lock', v),
          ),
          _SwitchRow(
            title: '暂停后自动倒带',
            subtitle: ref.watch(rewindAfterPauseProvider) ? '开' : '关',
            info: '默认开：暂停后恢复按停顿时长分档倒带（<1 分钟 0.8 秒、1 分钟 3 秒、1 小时 10 秒、1 天 20 秒），不越过章节开头；播完的书不倒带。',
            value: ref.watch(rewindAfterPauseProvider),
            onChanged: (v) => saveBoolSetting(
                ref, rewindAfterPauseProvider, 'rewind_after_pause', v),
          ),
          _ValueRow(
            title: '睡眠定时默认值',
            subtitle: _sleepLabel(sleepDefault),
            info: '进播放页自动套用的定时：不设置、5 / 15 / 30 / 60 分钟、播到章末停，或自定义 1–240 分钟。结束前 10 秒淡出。',
            onTap: () => _pickSleepDefault(context, ref, sleepDefault),
          ),
          _SwitchRow(
            title: '自动换线',
            subtitle: ref.watch(autoChangeLineProvider) ? '开' : '关',
            info: '默认开：当前线路播不出来时自动按顺序试下一条线，每步都会提示正在切换到哪条线。',
            value: ref.watch(autoChangeLineProvider),
            onChanged: (v) => saveBoolSetting(
                ref, autoChangeLineProvider, 'auto_change_line', v),
          ),
        ],
      ),
    );
  }

  String _sleepLabel(int v) {
    if (v == 0) return '不设置';
    if (v == -1) return '播到章末停';
    return '$v 分钟';
  }

  Future<void> _pickSpeed(
      BuildContext context, WidgetRef ref, double current) async {
    const options = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('默认倍速'),
        children: [
          for (final v in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Row(
                children: [
                  Text('${v}x'),
                  const Spacer(),
                  if (current == v) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await saveDoubleSetting(
          ref, defaultSpeedProvider, 'playback_speed', picked);
    }
  }

  Future<void> _pickSeekStep(
      BuildContext context, WidgetRef ref, int current) async {
    const options = [5, 10, 15, 30, 60];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('快退 / 快进步长'),
        children: [
          for (final v in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Row(
                children: [
                  Text('$v 秒'),
                  const Spacer(),
                  if (current == v) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await saveIntSetting(
          ref, seekStepProvider, 'seek_step_seconds', picked);
    }
  }

  Future<void> _pickSleepDefault(
      BuildContext context, WidgetRef ref, int current) async {
    const options = [0, 5, 15, 30, 60, -1];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('睡眠定时默认值'),
        children: [
          for (final v in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Row(
                children: [
                  Text(_sleepLabel(v)),
                  const Spacer(),
                  if (current == v) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -2),
            child: const Text('自定义分钟数…'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    if (picked == -2) {
      final controller = TextEditingController();
      final custom = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('自定义分钟数'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: '1–240'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim()) ?? 30;
                Navigator.pop(ctx, v.clamp(1, 240));
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (custom != null) {
        await saveIntSetting(
            ref, sleepTimerDefaultProvider, 'sleep_timer_default', custom);
      }
      return;
    }
    await saveIntSetting(
        ref, sleepTimerDefaultProvider, 'sleep_timer_default', picked);
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String info;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.info,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      title: title,
      subtitle: subtitle,
      info: info,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String info;
  final VoidCallback onTap;

  const _ValueRow({
    required this.title,
    required this.subtitle,
    required this.info,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      title: title,
      subtitle: subtitle,
      info: info,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle,
              style: TextStyle(fontSize: 13, color: context.subtleColor)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: context.subtleColor),
        ],
      ),
      onTap: onTap,
    );
  }
}
