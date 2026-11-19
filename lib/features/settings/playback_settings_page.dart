import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';

/// 播放设置页
class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState
    extends ConsumerState<PlaybackSettingsPage> {
  late SharedPreferences _prefs;
  bool _lockScreenShow = true;
  bool _headsetPause = true;
  bool _skipSilence = false;
  bool _pauseOnLeave = false;
  bool _sleepTimerExitApp = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = ref.read(sharedPrefsProvider);
    setState(() {
      _lockScreenShow =
          _prefs.getBool(AppConstants.keyLockScreenShow) ?? true;
      _headsetPause = _prefs.getBool(AppConstants.keyHeadsetPause) ?? true;
      _skipSilence = _prefs.getBool(AppConstants.keySkipSilence) ?? false;
      _pauseOnLeave = _prefs.getBool(AppConstants.keyPauseOnLeave) ?? false;
      _sleepTimerExitApp =
          _prefs.getBool(AppConstants.keySleepTimerExitApp) ?? false;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('播放设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final speed = ref.watch(defaultSpeedProvider);
    final autoNext = ref.watch(autoNextProvider);
    final resume = ref.watch(resumeEnabledProvider);
    final sleepDefault = ref.watch(sleepTimerDefaultProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('播放设置')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          _section(context, [
            ListTile(
              title: const Text('默认倍速'),
              subtitle: Text('下次打开播放器默认用这个倍速'),
              trailing: Text('${speed}x',
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary)),
              onTap: () => _pickSpeed(context, speed),
            ),
            ListTile(
              title: const Text('缓存设置'),
              subtitle: const Text(
                  '在播放时根据一定的时间规则，自动缓存后续章节。注意：暂停时不触发缓存。缓存过的书籍在没有网络时可从我的收藏打开进行离线播放。'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () =>
                  Navigator.of(context).pushNamed('/cache-settings'),
            ),
            SwitchListTile(
              title: const Text('自动播放下一集'),
              subtitle: const Text('开了播完一集自动播下一集，关了播完停住'),
              value: autoNext,
              onChanged: (v) {
                ref.read(autoNextProvider.notifier).state = v;
                _prefs.setBool(AppConstants.keyAutoNext, v);
              },
            ),
            SwitchListTile(
              title: const Text('锁屏显示'),
              subtitle: const Text('锁屏显示正在播的内容，能暂停 / 继续'),
              value: _lockScreenShow,
              onChanged: (v) {
                setState(() => _lockScreenShow = v);
                _prefs.setBool(AppConstants.keyLockScreenShow, v);
              },
            ),
            SwitchListTile(
              title: const Text('耳机拔出暂停'),
              subtitle: const Text('拔掉耳机自动暂停'),
              value: _headsetPause,
              onChanged: (v) {
                setState(() => _headsetPause = v);
                _prefs.setBool(AppConstants.keyHeadsetPause, v);
              },
            ),
            ListTile(
              title: const Text('定时关闭默认值'),
              subtitle: const Text('听书定时关闭的默认时长'),
              trailing: Text(
                  sleepDefault == 0 ? '不设置' : '$sleepDefault 分钟',
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary)),
              onTap: () => _pickSleepDefault(context, sleepDefault),
            ),
            SwitchListTile(
              title: const Text('断点续播'),
              subtitle: const Text('开了记住断点接着播，关了每次从头播'),
              value: resume,
              onChanged: (v) {
                ref.read(resumeEnabledProvider.notifier).state = v;
                _prefs.setBool(AppConstants.keyResumeEnabled, v);
              },
            ),
            SwitchListTile(
              title: const Text('跳过无声部分'),
              subtitle: const Text('慎开！音频里停顿多会造成加速的感觉，下次播放时生效'),
              value: _skipSilence,
              onChanged: (v) {
                setState(() => _skipSilence = v);
                _prefs.setBool(AppConstants.keySkipSilence, v);
              },
            ),
            SwitchListTile(
              title: const Text('离开播放页自动暂停'),
              subtitle: const Text('播视频时离开播放页就暂停'),
              value: _pauseOnLeave,
              onChanged: (v) {
                setState(() => _pauseOnLeave = v);
                _prefs.setBool(AppConstants.keyPauseOnLeave, v);
              },
            ),
            SwitchListTile(
              title: const Text('定时关闭是否完全退出'),
              subtitle: const Text('开了定时到了彻底退出 App，关了只停止播放'),
              value: _sleepTimerExitApp,
              onChanged: (v) {
                setState(() => _sleepTimerExitApp = v);
                _prefs.setBool(AppConstants.keySleepTimerExitApp, v);
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, indent: 16, color: context.palette.outline),
          ],
        ],
      ),
    );
  }

  void _pickSpeed(BuildContext context, double current) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('默认倍速'),
        children: [0.5, 1.0, 1.25, 1.5, 2.0].map((v) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(defaultSpeedProvider.notifier).state = v;
              _prefs.setDouble(AppConstants.keyPlaybackSpeed, v);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text('${v}x', style: const TextStyle(fontSize: 15)),
                if ((v - current).abs() < 0.01) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _pickSleepDefault(BuildContext context, int current) {
    final options = [0, 15, 30, 60];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('定时关闭默认值'),
        children: options.map((v) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(sleepTimerDefaultProvider.notifier).state = v;
              _prefs.setInt(AppConstants.keySleepTimerDefault, v);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text(v == 0 ? '不设置' : '$v 分钟',
                    style: const TextStyle(fontSize: 15)),
                if (v == current) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
