# openchat

[DeepSeek 开源 Chat Demo](https://github.com/deepseek-ai/chat-demo) 的非官方 HarmonyOS 原生移植。项目使用 ArkTS 和 ArkUI，支持手机、平板和 2 合 1 设备。构建目标为 HarmonyOS 7.0（API 26），最低兼容 HarmonyOS 6.1（API 23）。

## 运行

在 DevEco Studio 安装 API 26 SDK 并打开本目录。连接 API 23 或以上的模拟器后，可使用 DevEco CLI 构建和运行。

```sh
devecocli build
devecocli run
```

首启进入设置的「数据管理」。输入在 [DeepSeek 开放平台](https://platform.deepseek.com/api_keys) 创建的 API Key，验证通过后即可聊天。请求直接发往 DeepSeek。密钥由 HarmonyOS 关键资产服务保存，聊天记录写入应用沙箱。

仓库里的构建配置可生成未签名的调试 HAP。安装到真机前，请在 DevEco Studio 为本机配置调试签名，并把生成的签名配置留在本地。

## 移植范围

- 按官方开源网页的颜色、图标、字号和窄屏断点重建首页、输入框、边栏、对话与设置。系统状态栏、键盘及字体渲染由 HarmonyOS 提供。
- 侧栏支持按会话标题和消息正文即时筛选。搜索在设备端完成。
- API 26 及以上可在「通用设置」切换桌面图标。默认图标之外提供「困困」「开心」「认真」三款鲸鱼娘图标。
- 聊天使用 DeepSeek Anthropic Messages 接口，支持流式回复、停止、续写、深度思考、搜索、链接阅读、来源、附件和语音。编辑提问或重新生成会保留消息分支。
- 支持中英文、主题、朗读音色及手选位置。对话 ZIP 使用上游 v3 基本结构，保留会话、分支、文本和部分来源及附件元数据。目前不复制附件原件，导入后的历史附件需重新上传才能送给模型。
- 回复通过 [lv-markdown-in](https://gitee.com/luvi/lv-markdown-in) 渲染 Markdown，支持代码高亮、表格和离线 LaTeX 公式。行内公式支持 `$…$` 和 `\(…\)`，独立公式支持 `$$…$$` 和 `\[…\]`。Mermaid 图表以代码显示。

## 许可

项目沿用上游 [MIT 许可](LICENSE)。带华为版权声明的 Ability 模板文件适用 [Apache License 2.0](LICENSES/Apache-2.0.txt)。依赖与图标的署名见 [第三方许可](entry/src/main/resources/rawfile/THIRD-PARTY-NOTICES.txt)。鲸鱼娘美术素材单独适用 [CC BY-NC-SA 4.0](LICENSES/CC-BY-NC-SA-4.0.txt)。
