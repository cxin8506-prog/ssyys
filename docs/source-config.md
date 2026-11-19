# 源配置项声明

App 不再固定「登录态 / 音色 / 线路」这套表单。**源自己声明需要哪些配置项**，
App 只按声明把输入控件画出来，值统一存在源的配置里。

## 一、在 manifest.json 里声明（推荐）

```json
{
  "id": "my-source",
  "name": "我的源",
  "type": "audio",
  "entry": "main.js",
  "config": [
    { "key": "cookie", "name": "登录态", "type": "textarea",
      "hint": "token=xxx; uid=123", "desc": "不填只能看免费内容" },
    { "key": "voiceId", "name": "音色", "type": "select", "source": "voices" },
    { "key": "lineId",  "name": "线路", "type": "select", "source": "lines" },
    { "key": "quality", "name": "音质", "type": "radio",
      "options": [ { "value": "std", "label": "标准" },
                   { "value": "hq",  "label": "高清" } ] },
    { "key": "adFree",  "name": "过滤广告", "type": "switch", "default": true },
    { "key": "retry",   "name": "重试次数", "type": "number", "default": 2 }
  ]
}
```

`config` 也可以叫 `configs` / `settings` / `params` / `fields`。

## 二、在脚本里声明（运行时生成）

脚本导出 `getConfig()`（或 `config()` / `settings()`），返回同样的数组：

```js
function getConfig() {
  return [
    { key: 'cookie', name: '登录态', type: 'textarea' },
    { key: 'voiceId', name: '音色', type: 'select', source: 'voices' }
  ];
}
```

适合选项要到运行时才能确定的场景。也支持把配置声明写成全局对象 `config = [...]`。

## 三、字段类型

| type | 控件 | 值类型 |
|---|---|---|
| `text` | 单行输入框 | string |
| `textarea` | 多行输入框 | string |
| `password` | 密码输入框 | string |
| `number` | 数字输入框 | number |
| `switch` | 开关 | bool |
| `select` | 下拉（选项多时） | string |
| `radio` | 单选标签 | string |
| `action` | 按钮，点了调源方法 | — |

## 四、选项从哪来

- **静态**：`options: [{ value, label }]`，也接受 `["标准", "高清"]` 或 `{ "std": "标准" }`
- **动态**：`source: "voices"` 表示调用源的 `voices()` 方法取值，App 会自动拉取一次，
  也可以让用户在页面上点「从源获取」重新拉

## 五、源怎么读这些值

JS 源：

```js
async function search(keyword, page) {
  const cookie = host.config.cookie || '';       // 自己声明的 key
  const token  = host.getConfig('token');        // 等价的写法
  const ua = host.ua;
  return await host.httpJson('https://api.example.com/search?q=' + keyword, {
    Cookie: cookie,
    'User-Agent': ua
  });
}
```

JAR 源：主类里提供 `setConfig(String json)` / `initConfig(String)` / `applyConfig(String)`，
App 在加载源和每次调用前会把整份配置 JSON 推过去。

## 六、兼容

老源不声明配置项时：

- 源有 `voices()` → 自动给一个「音色」下拉
- 源有 `lines()` → 自动给一个「线路」下拉
- 都没有 → 显示「这个源不需要配置」

老的 `host.config.loginState` / `host.config.voiceId` / `host.config.lineId` / `host.config.extra`
仍然可用，不会因为改成声明式而失效。
