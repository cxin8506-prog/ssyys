# 配置项声明

插件自己声明需要哪些配置项，App 只按声明画输入控件，值统一存在插件的配置里。

## 声明方式

manifest.json 里的 `config` 数组（也接受 `configs` / `settings` / `params` / `fields`）：

```json
{
  "id": "my-plugin",
  "name": "我的插件",
  "entry": "main.js",
  "config": [
    { "key": "voiceId", "name": "音色", "type": "select", "source": "voices" },
    { "key": "quality", "name": "音质", "type": "radio",
      "options": [{ "value": "std", "label": "标准" }, { "value": "hq", "label": "高清" }] },
    { "key": "adFree", "name": "过滤广告", "type": "switch", "default": true }
  ]
}
```

也可以在脚本里导出 `getConfig()`（或 `config()` / `settings()`）返回同样的数组，适合选项要到运行时才能确定的场景；也支持写成全局对象 `config = [...]`。

## 字段类型

| type | 控件 | 值类型 |
|---|---|---|
| `text` | 单行输入框 | string |
| `textarea` | 多行输入框 | string |
| `password` | 密码输入框 | string |
| `number` | 数字输入框 | number |
| `switch` | 开关 | bool |
| `select` | 下拉（选项多时） | string |
| `radio` | 单选标签 | string |
| `action` | 按钮，点了调插件方法 | — |

选项：静态用 `options: [{ value, label }]`（也接受 `["标准", "高清"]` 或 `{ "std": "标准" }`）；动态用 `source: "voices"`，表示调插件的 `voices()` 方法取值，App 会自动拉一次，页面上也能点「从插件获取」重拉。

## 兼容

不声明配置项的老插件：有 `voices()` 自动给「音色」下拉，有 `lines()` 自动给「线路」下拉，都没有就显示「这个插件不需要配置」。
