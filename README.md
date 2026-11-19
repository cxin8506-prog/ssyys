# 随意听书

安卓端听书 / 视频播放器。内容来自导入的插件源（JS/ZIP、JAR），在线流式播放，不下载到本地。

## 安装

到 [Releases](https://github.com/cxin8506-prog/ssyys/releases/latest) 下载 apk，Android 7 及以上。

## 功能

- 首页：当前源推荐、继续收听
- 发现：按当前源分类浏览
- 书架：收藏与进度
- 搜索：可搜全部源，按源分组
- 播放：倍速、断点续播、后台播放、多线路切换
- 源登录：内嵌网页登录，登录后自动同步 Cookie

## 源格式

见 [docs/source-config.md](docs/source-config.md)。

## 构建

```bash
flutter build apk --release
```
