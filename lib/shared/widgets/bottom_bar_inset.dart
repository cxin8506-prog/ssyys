import 'package:flutter/material.dart';

/// 底栏高度（贴底标准 BottomNavigationBar 的实际高度）。
const double kBottomBarHeight = 56;

/// 页面底部避让高度：系统手势条 + 底栏高度 + 一点余量。
///
/// 旧坑：这个工具写了没人用（0 处调用），而且只加了系统边距、
/// 没把底栏高度算进去。重写后每个列表页底部都用它留空，
/// 最后一行不许被底栏盖住；底栏本身包在 SafeArea 里，不被手势条挡住。
double bottomBarInset(BuildContext context, {double extra = 8}) =>
    MediaQuery.of(context).padding.bottom + kBottomBarHeight + extra;

/// 列表底部统一留空（sliver 版）。
Widget bottomBarSliverSpace(BuildContext context) =>
    SliverToBoxAdapter(child: SizedBox(height: bottomBarInset(context)));

/// 列表底部统一留空（普通 widget 版）。
Widget bottomBarSpace(BuildContext context) =>
    SizedBox(height: bottomBarInset(context));
