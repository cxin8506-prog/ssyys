# 本地多媒体 App 技术方案（第一版）

> 状态：需求已确认，方案待实现
> 更新日期：2026-11-19
> 说明：本文档是开发蓝图，不是代码。所有决策均来自需求确认过程。

---

## 一、已确认的决策（项目基线）

| 项目 | 决定 |
|---|---|
| 平台 | **只做安卓端**（最低安卓 7 / API 24），电脑版整体推迟 |
| 内容类型 | **听书 + 视频** 两大块，漫画已取消 |
| 模块隔离 | 听书与视频的**源、搜索、收藏、历史、书签完全分开** |
| 数据 | 全部本地保存，不登录、不依赖服务器 |
| 插件/源 | 第一版**不做**，但架构**预留**；二期再做 |
| 插件参考 | 听书：随身听书（JS/ZIP）、我的听书（JAR）；漫画源（Mihon）已不需要 |
| 版本底线 | 安卓 7（API 24），避免因版本问题砍掉老设备 |
| 界面 | 深色优先、现代简洁；出错给清晰提示并写日志 |

> 备注：之前曾考虑提到安卓 8.0 以便用 Mihon 官方源，因漫画取消，已改回安卓 7。

---

## 二、技术选型

| 领域 | 选型 | 理由 |
|---|---|---|
| 框架 | Flutter（锁定支持 API 24 的稳定版） | 一套代码、安卓兼容好、UI 现代；`minSdkVersion` 设为 24 |
| 语言 | Dart | — |
| 状态管理 | Riverpod | 类型安全、适合长期迭代 |
| 路由 | go_router | 声明式、深链友好 |
| 音频播放 | just_audio + audio_service | 格式全（MP3/M4A/M4B/FLAC/AAC/WAV）、倍速、后台播放、通知栏控制 |
| 视频播放 | media_kit（基于 libmpv） | 格式全、手势/倍速/多线路/硬解支持好，适合二期扩展 |
| 本地数据库 | drift（SQLite） | 类型安全、单文件便于备份、关系型数据合适 |
| 压缩包解析 | archive（纯 Dart） | 直接把 JAR/ZIP 当压缩包读，解析内部音频 |
| 文件选择 | file_picker + path_provider | 导入本地文件/文件夹 |
| 权限 | permission_handler | 存储权限、后台播放 |
| 亮度/音量 | screen_brightness / volume_controller | 视频手势调节 |
| 图片缓存 | flutter_cache_manager | 封面缓存 |
| 备份打包 | archive | 本地 zip 备份/恢复 |
| 日志 | logging + 写文件 | 关键操作与错误落盘、可导出 |
| 设置存储 | drift 中的 kv 表（或 shared_preferences） | 设置集中管理 |

> 二期插件引擎预留：`flutter_js`（QuickJS）执行 JS 插件；JAR 插件走独立适配层。

---

## 三、目录结构

采用 **feature-first（按功能模块分层）** 结构，每个模块内再分 data / domain / presentation，方便 AI 后续定位与迭代。

```
lib/
├── main.dart                       # 入口
├── app.dart                        # MaterialApp / Riverpod / 路由装配
├── core/                           # 通用基础设施
│   ├── constants/                  # 全局常量、类型枚举
│   ├── theme/                      # 深色主题、颜色、字体
│   ├── router/                     # go_router 路由表
│   ├── database/                   # drift 数据库、表定义、DAO
│   ├── utils/                      # 自然排序、文件工具、路径工具
│   ├── log/                        # 日志服务（写文件、查看、清空、导出）
│   └── di/                         # 依赖注入（Provider 装配）
├── features/
│   ├── audio/                      # 听书模块
│   │   ├── data/                   # 数据源：本地文件、JAR/ZIP 解析、仓库实现
│   │   ├── domain/                 # 实体、用例（导入、排序、播放控制）
│   │   └── presentation/           # 书架、播放页、章节、书签 UI
│   ├── video/                      # 视频模块
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/           # 播放页、手势、全屏、锁定
│   ├── library/                    # 通用书架/收藏/历史/书签（按 type 隔离展示）
│   ├── search/                     # 听书搜索、视频搜索（两套独立入口）
│   ├── settings/                   # 设置页
│   ├── backup/                     # 本地 zip 备份/恢复
│   └── onboarding/                 # 首次引导
├── shared/                         # 共享 Widget、通用 Model
└── plugins/                        # 【二期预留，第一版只放接口骨架】
    ├── model/                      # Source 定义、SourceConfig 数据模型
    ├── engine/                     # JS 引擎封装（flutter_js）
    ├── jar/                        # 我的听书 JAR 适配层
    └── repository/                 # 插件导入/启用/禁用/删除、源管理
```

---

## 四、本地数据存放结构（安卓）

统一放在 App 私有目录，便于整体备份与迁移：

```
/sdcard/Android/data/<包名>/files/
├── database/
│   └── app.db              # drift SQLite 数据库（书架/进度/收藏/历史/书签/设置）
├── books/                  # 导入的音频/视频文件（或记录原路径引用）
├── covers/                 # 封面图片
├── cache/                  # 缓存（大小上限可调、可清）
├── logs/
│   └── app.log             # 运行日志
└── backups/                # 本地 zip 备份文件
└── plugins/                # 【二期】插件包 & 源配置
```

> 所有业务数据集中在 `files/` 下，备份时打包该目录即可。

---

## 五、数据模型（核心表）

听书与视频用 `type` 字段区分（`audio` / `video`），但所有查询、搜索、收藏、历史都按 type 过滤，实现"严格分开"。

| 表 | 主要字段 | 说明 |
|---|---|---|
| `media_item` | id, type, title, author, path, coverPath, size, duration/pages, addedAt, lastReadAt, status, sortOrder | 书/视频主记录 |
| `chapter` | id, itemId, title, orderIndex, path/url, duration, isCorrupted | 章节（音频按文件名自然排序） |
| `progress` | itemId, chapterId, positionMs, speed, updatedAt | 断点续播进度 |
| `bookmark` | id, itemId, chapterId, positionMs/page, note, createdAt | 书签（时间点/页码） |
| `favorite` | id, itemId, type, groupName, createdAt | 收藏（按 type 分开） |
| `history` | id, itemId, type, visitedAt | 最近记录（与收藏分开） |
| `log` | id, level, message, detail, createdAt | 日志 |
| `kv_setting` | key, value | 设置项（含缓存上限、视频总开关等） |
| `source_config` | sourceId, type, enabled, loginState, voiceList, selectedVoiceId, lineList, selectedLineId, extra | 【二期预留】源配置中心 |

---

## 六、核心模块设计

### 1. 导入模块（听书 / 视频共用思路）
- 本地文件/文件夹导入；文件夹内图片自动作封面；用文件名/文件夹名当标题。
- **JAR / ZIP 音频包**：用 `archive` 当压缩包读，内部音频按**文件名自然排序**（1、2、10 正确排序）。
- 自然排序工具：`core/utils/natural_sort.dart`，第一版必须做对。
- 损坏文件：解析/播放失败时跳过，写日志，不崩溃。

### 2. 听书播放
- just_audio 播放 + audio_service 通知栏（播放/暂停/上下首/进度）。
- 倍速、定时关闭（结束前音量渐弱）、断点续播、书签、自动下一章。
- `M4B` 按 M4A 处理（本质是带章节的 M4A）。

### 3. 视频播放
- media_kit 播放；手势：左右滑调进度、上下滑调音量/亮度。
- 画面比例（适应/填充/原始）、全屏、重力转屏、界面锁定。
- 文件夹内多视频连续播放；视频总开关（一键隐藏视频入口）。
- 损坏视频跳过并记日志。

### 4. 书架 / 收藏 / 历史 / 书签
- 排序（名称/导入时间/进度/最近）、筛选（全部/未读/在读/已读）。
- 长按/更多菜单：改名、改封面、删除（**二次确认 + 短时间可撤销**）。
- 详情页：路径、大小、时长/页数。
- 首页"继续阅读/播放"快捷入口。
- 收藏、历史、书签三套独立；听书与视频再按 type 分开。

### 5. 搜索
- 听书搜索、视频搜索两个独立入口，结果分类清晰。
- 第一版只搜本地内容；源搜索等二期插件就绪再开。

### 6. 备份 / 日志 / 缓存
- 本地 zip 备份/恢复：打包数据库、封面、设置、日志、书签等。
- 日志：记录关键操作与错误（解析失败、损坏文件等），可查看、清空、导出。
- 缓存：上限可调，查看占用、一键清除，超限提示。

---

## 七、源配置中心（二期预留，第一版只留接口与字段）

> 目的：二期接入插件时不用推倒重来，第一版先把数据结构和接口位置留好。

用户明确要求的三类"每个源/每本书独立记忆"的设置：

| 配置项 | 作用 | 对应字段 |
|---|---|---|
| 网站登录态 | 需要登录的源，保存账号/Cookie，搜索解析自动带上 | `loginState` |
| **音色选择** | 番茄类源，一本书有多个声音版本，手动挑想要的并记住 | `voiceList` / `selectedVoiceId` |
| 视频线路选择 | 多线路视频源，手动切换并记住 | `lineList` / `selectedLineId` |

插件形态（二期）：
- **听书 JS/ZIP 插件**：参考随身听书，`manifest.json` + `.js`，用 `flutter_js` 执行，宿主提供网络/HTML 解析接口。
- **听书 JAR 插件**：参考我的听书，独立适配层加载 JAR。
- 两套写法不同，**分别适配，不共用**。
- 协议注意：随身听书是 PolyForm Strict（禁二次开发），**只参考格式规范、不抄源码**；我的听书教程仅供写源参考；引擎自己实现。

---

## 八、关键技术风险与对策

| 风险 | 对策 |
|---|---|
| 安卓 7 兼容 | Flutter `minSdkVersion=24`；依赖库逐一确认支持 API 24；避免高版本专属 API |
| 通知栏/后台播放被杀 | audio_service 前台服务；引导用户关闭电池优化 |
| 存储权限 | 安卓 10+ 用分区存储，导入走 file_picker 的 SAF； appropriate 权限声明 |
| 大文件/JAR 解析卡顿 | 后台 isolate 解析，避免阻塞 UI |
| 音频/视频格式差异 | just_audio / media_kit 覆盖主流格式；失败跳过并记日志 |

---

## 九、分期开发路线图

**第一版（本方案）**
1. 项目骨架：Flutter 工程、主题、路由、数据库、日志、DI。
2. 导入模块：本地文件/文件夹、JAR/ZIP 音频包、自然排序、封面。
3. 听书播放：just_audio、通知栏、倍速、定时渐弱、断点、书签。
4. 视频播放：media_kit、手势、比例、全屏/锁定、连播、总开关。
5. 书架/收藏/历史/书签/搜索/设置/首页继续。
6. 备份/日志/缓存/首次引导。
7. 全链路测试（重点：安卓 7 真机、损坏文件、断点续播）。

**二期**
1. 源配置中心落地（登录/音色/线路）。
2. 听书 JS/ZIP 插件引擎。
3. 我的听书 JAR 插件适配。
4. 视频插件/源、画中画。
5. 源搜索。
6. 电脑版（另立方案）。

---

## 十、给后续 AI 的提示

- 严格按上面的目录结构放文件；每个 feature 内部分 data/domain/presentation。
- 数据模型改动先改 `core/database` 的表定义，再跑 codegen 生成。
- 新增功能先写测试，尤其是自然排序、断点续播、损坏文件跳过。
- 任何用户可见的错误都要：清晰提示 + 写日志。
- 插件相关代码只放在 `lib/plugins/`，第一版不要实现业务逻辑，只留接口。
