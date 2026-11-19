import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';

/// 桌面小工具和锁屏
class WidgetLockPage extends ConsumerStatefulWidget {
  const WidgetLockPage({super.key});

  @override
  ConsumerState<WidgetLockPage> createState() => _WidgetLockPageState();
}

class _WidgetLockPageState extends ConsumerState<WidgetLockPage> {
  late SharedPreferences _prefs;
  bool _followCover = true;
  String _buttonSize = '大';
  bool _lockCoverBg = true;
  bool _forceDefaultCover = false;
  String _defaultCover = '';
  String _launchIcon = '新版图标';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = ref.read(sharedPrefsProvider);
    setState(() {
      _followCover =
          _prefs.getBool(AppConstants.keyWidgetFollowCover) ?? true;
      _buttonSize =
          _prefs.getString(AppConstants.keyWidgetButtonSize) ?? '大';
      _lockCoverBg =
          _prefs.getBool(AppConstants.keyLockScreenCoverBg) ?? true;
      _forceDefaultCover =
          _prefs.getBool(AppConstants.keyForceDefaultCover) ?? false;
      _defaultCover =
          _prefs.getString(AppConstants.keyDefaultCoverPath) ?? '';
      _launchIcon =
          _prefs.getString(AppConstants.keyLaunchIcon) ?? '新版图标';
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('桌面小工具和锁屏')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小工具和锁屏')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          _section(context, [
            SwitchListTile(
              title: const Text('桌面小工具主题采用封面颜色'),
              subtitle: const Text('开了小工具的主题色跟着当前播的书的封面颜色走'),
              value: _followCover,
              onChanged: (v) {
                setState(() => _followCover = v);
                _prefs.setBool(AppConstants.keyWidgetFollowCover, v);
              },
            ),
            ListTile(
              title: const Text('桌面小工具按钮大小'),
              trailing: Text(_buttonSize,
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary)),
              onTap: () => _pickButtonSize(context),
            ),
            SwitchListTile(
              title: const Text('在锁屏显示封面背景'),
              subtitle: const Text('仅部分系统可用，重启或者换书生效；关了手表上不能显示封面'),
              value: _lockCoverBg,
              onChanged: (v) {
                setState(() => _lockCoverBg = v);
                _prefs.setBool(AppConstants.keyLockScreenCoverBg, v);
              },
            ),
            SwitchListTile(
              title: const Text('播放页面强制使用默认封面'),
              subtitle: const Text('开了播放页一律用下面选的默认封面'),
              value: _forceDefaultCover,
              onChanged: (v) {
                setState(() => _forceDefaultCover = v);
                _prefs.setBool(AppConstants.keyForceDefaultCover, v);
              },
            ),
            ListTile(
              title: const Text('选择默认封面'),
              subtitle: Text(_defaultCover.isEmpty
                  ? '书籍封面报错时用的默认封面，点一下填本地图片路径'
                  : _defaultCover),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _pickDefaultCover(context),
            ),
            ListTile(
              title: const Text('选择启动图标'),
              subtitle: Text('当前：$_launchIcon（需要重启手机）'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _pickLaunchIcon(context),
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

  void _pickButtonSize(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('桌面小工具按钮大小'),
        children: ['大', '中', '小'].map((v) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _buttonSize = v);
              _prefs.setString(AppConstants.keyWidgetButtonSize, v);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text(v, style: const TextStyle(fontSize: 15)),
                if (v == _buttonSize) ...[
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

  void _pickDefaultCover(BuildContext context) {
    final ctrl = TextEditingController(text: _defaultCover);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择默认封面'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: '填手机里一张图片的完整路径',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              setState(() => _defaultCover = ctrl.text.trim());
              _prefs.setString(AppConstants.keyDefaultCoverPath,
                  ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _pickLaunchIcon(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择启动图标'),
        children: ['新版图标', '经典图标', '月亮声波'].map((v) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _launchIcon = v);
              _prefs.setString(AppConstants.keyLaunchIcon, v);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('已保存，重启手机后生效')));
            },
            child: Row(
              children: [
                Text(v, style: const TextStyle(fontSize: 15)),
                if (v == _launchIcon) ...[
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
