import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 封面图：有路径显示图片，否则显示占位首字
class CoverImage extends StatelessWidget {
  final String? path;
  final String title;
  final double size;
  final bool isVideo;

  const CoverImage({
    super.key,
    this.path,
    required this.title,
    this.size = 64,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return Container(
      width: size,
      height: size * 1.35,
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCover
          ? Image.file(File(path!),
              fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(context))
          : _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isVideo ? Icons.movie_outlined : Icons.headphones_outlined,
            size: size * 0.4,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.55),
          ),
          Positioned(
            bottom: 6,
            child: Text(
              title.isEmpty ? '?' : title.substring(0, 1),
              style: TextStyle(color: context.subtleColor, fontSize: 11),
            ),
          ),
        ],
      );
}

/// 空状态提示
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: context.subtleColor.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: onAction, child: Text(actionLabel ?? '添加')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 简单加载指示
class LoadingOverlay extends StatelessWidget {
  final String message;
  const LoadingOverlay({super.key, this.message = '处理中...'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
