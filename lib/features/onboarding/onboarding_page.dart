import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';

/// 首次使用简单引导
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.headphones, color: Theme.of(context).colorScheme.primary, size: 96),
              const SizedBox(height: 24),
              Text('随意听书', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 12),
              Text(
                '一个完全属于自己的播放器。\n听书、看视频，所有数据只保存在本机，\n不用登录，也不依赖服务器。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
              _buildFeature(context, Icons.folder_open, '导入本地内容',
                  '音频文件、文件夹、JAR/ZIP 音频包、本地视频'),
              const SizedBox(height: 16),
              _buildFeature(context, Icons.play_circle_outline, '断点续播',
                  '记住进度、倍速、定时关闭、书签'),
              const SizedBox(height: 16),
              _buildFeature(context, Icons.backup_outlined, '数据安全',
                  '本地 zip 备份，整个文件夹拷走即可迁移'),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final prefs = ref.read(sharedPrefsProvider);
                    await prefs.setBool(AppConstants.keyOnboardDone, true);
                    Navigator.of(context).pushReplacementNamed('/home');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('开始使用'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(
          BuildContext context, IconData icon, String title, String subtitle) =>
      Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
}
