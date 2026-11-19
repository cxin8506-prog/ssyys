# 本地影音（local_media_app）

一个**本地优先、无需登录、不依赖服务器**的多媒体播放器，目前聚焦**安卓端**，支持**听书**和**视频**两大模块（严格分开）。数据全部保存在本机，可整体备份迁移。

> 详细需求与技术方案见 [`本地多媒体App-技术方案.md`](本地多媒体App-技术方案.md)。

## 已完成功能（第一版）

### 基础
- Flutter 项目，最低 **安卓 7（API 24）**
- 深色优先的现代界面、首次使用引导
- 本地数据目录统一管理（数据库 / 封面 / 缓存 / 日志 / 备份）
- 日志系统：关键操作与错误落盘，可查看、清空、导出

### 听书
- 导入本地音频（MP3 / M4A / M4B / FLAC / AAC / WAV 等）
- 导入音频文件夹、JAR / ZIP 音频包（当压缩包解析）
- **文件名自然排序**（1、2、10 正确排列）
- 书架（封面 / 进度 / 状态）、排序筛选、改名、删除（可撤销）、详情
- 播放：断点续播、倍速（0.75x~3x）、定时关闭（结束前渐弱）、自动下一章
- 安卓通知栏控制、后台播放（audio_service + just_audio）
- 听书书签、收藏、历史

### 视频
- 导入本地视频、文件夹连续播放
- 播放控制、倍速、断点续播
- 手势：左右滑进度、上下滑音量/亮度
- 画面比例切换、全屏、界面锁定、视频总开关
- 损坏视频自动跳过并记日志

### 通用管理
- 首页"继续听/继续看"快捷入口
- 收藏 / 历史 / 书签独立管理，听书与视频分开
- 听书 / 视频各自独立搜索
- 设置：主题、视频开关、缓存上限、缓存清理
- 本地 zip 备份 / 恢复

### 二期预留（已留接口与数据字段，未实现业务逻辑）
- 插件/源管理（`lib/plugins/`）
- 源配置中心：登录态、**音色选择**（番茄类源）、视频线路选择
- 插件形态：听书 JS/ZIP（随身听书风格）、听书 JAR（我的听书风格）

## 项目结构

```
lib/
├── core/                  # 常量、主题、日志、数据库、工具、DI
│   ├── database/          # drift 表定义 + 生成的 app_database.g.dart
│   ├── utils/             # natural_sort.dart（自然排序）、path_utils.dart
│   └── theme/             # 深色/浅色主题
├── features/
│   ├── audio/             # 听书：导入器、仓库、播放服务、书架/播放页
│   ├── video/             # 视频：书架、播放页
│   ├── library/           # 收藏/历史/书签
│   ├── search/ settings/ backup/ onboarding/ presentation/  # 通用页面
├── shared/widgets/        # 通用组件（封面、空状态等）
└── plugins/               # 二期插件引擎骨架（不实现业务逻辑）
```

## 编译与运行

### 环境要求
- Flutter（本项目在 **Flutter 3.0.0 / Dart 2.17** 上开发与验证）
- Android SDK（compileSdk 32、build-tools 32.0.0）
- JDK 11（Flutter 3.0 的 Gradle 7.4 对高版本 JDK 兼容性差，推荐 JDK 11）

### 步骤
```bash
flutter pub get
# 生成 drift 数据库代码
dart run build_runner build --delete-conflicting-outputs

# 连接安卓设备/模拟器后运行
flutter run

# 或打包
flutter build apk --debug
flutter build apk --release
```

> 说明：`android/local.properties` 指向 Flutter 与 Android SDK 路径。本仓库当前配置为沙箱环境路径，换机器时请按实际情况修改。

### 依赖版本说明
本项目受限于沙箱中 Flutter 3.0.0 的较老版本，依赖做了精确版本锁定，并用 `dependency_overrides` 处理了 `string_scanner` 冲突。若升级到较新 Flutter，可放宽约束。

## 验证状态
- `flutter analyze`：**0 个 error**（仅少量 const / lint 提示，不影响运行）
- `dart run build_runner`：数据库代码生成成功
- APK 编译：需在你本地 Android Studio / SDK 环境完成（沙箱内 Gradle 发行版下载受限）

## 后续用 AI 迭代的建议
- 代码按 feature-first 分层；改数据库先改 `core/database/tables.dart` 再重新 codegen
- 插件相关只改 `lib/plugins/`，第一版不实现业务逻辑
- 新增功能先写测试（见 `test/`），重点覆盖自然排序、断点续播、损坏文件跳过
