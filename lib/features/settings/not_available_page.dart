import 'package:flutter/material.dart';

/// 还没接入的功能入口：留出入口，点进去说明情况，不藏起来
class NotAvailablePage extends StatelessWidget {
  final String title;
  const NotAvailablePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('「$title」还没接入',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('入口先留在这里，后面接入了就能直接用',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
