---
name: web-screenshot
description: Use when 用户说"截图"/"screenshot"/"拍个图"/"截屏"/"截一下 dashboard"/"给 localhost 截个图"/"截下 #foo 元素"/"点 X 按钮再截图"，或要把任何 URL 拍成 PNG 时触发。
---

# web-screenshot

## Overview

把"拍网页"做成自然语言交互：用户说要啥，Claude Code 现写 `capture.mjs` 临时剧本，跑 Node + puppeteer-core + chrome-headless-shell，出 PNG。

**Core principle:** skill 自己装所有运行时依赖到 `~/.cache/web-screenshot/`，用户只要 Node 18+。已有 Playwright / Puppeteer 缓存自动复用。

## When to Use

触发症状：
- "给 https://example.com 截个图"
- "截一下 dashboard 的 #sidebar"
- "先点登录按钮，等加载完再截首页"
- "截个手机版（390 宽）的 #pricing"
- 给 localhost 服务、远程公网站点、SPA 里特定元素拍 PNG

**不要用：**
- 截桌面应用 / 你本地打开的浏览器窗口 → skill 只能截 URL，不能截已打开的窗口
- 截要登录的页面 → 需要 cookie 注入，本 skill 不管
- 跑 visual regression diff → 那是 percy/chromatic 的活
- 管 README 里图片排版 → 出图就完事，排版另说

## 工作流（按顺序执行）

### 步骤 1 — 跟用户对齐 5 件事

如果用户的请求里没明确，**逐项问清楚**：

| 问题 | 默认值（用户没说时） |
|---|---|
| 1. URL 是啥？ | 必须问，没默认 |
| 2. 拍哪些图？（描述每张要拍的内容） | 必须问 |
| 3. 有交互吗？（要点击/填表/等加载吗） | 没的话默认无 |
| 4. 图存到哪？ | `/tmp/screenshots-<timestamp>/` |
| 5. 视口多大？Retina 吗？ | 1440×900, dpr=2 |

**如果用户已经说清楚了，不要再问**。比如 "给 localhost:8787 的 #patterns-panel 截个图存到 /tmp/foo.png" — 一切都明确，直接动手。

### 步骤 2 — 找/装无头浏览器

```bash
bash ~/.claude/skills/web-screenshot/lib/find-chrome.sh
```

stdout 是浏览器路径。脚本会先扫多个常见缓存位置，没有的话**自动下载**（约 80MB，一次性，进 `~/.cache/web-screenshot/chrome/`）。如果失败（没 npx / 没网 / 设了 `WEB_SCREENSHOT_NO_AUTO_INSTALL=1`），按 stderr 里的提示帮用户解决。

### 步骤 3 — 准备 Node 运行时

```bash
bash ~/.claude/skills/web-screenshot/lib/prep-runtime.sh
```

stdout 是已经 `npm install puppeteer-core` 完毕的目录路径。第一次要 ~10-20s 装依赖；之后秒回。

如果用户没装 Node 18+，按 stderr 的提示装。

### 步骤 4 — 写 capture.mjs

抄 `lib/template.mjs` 起一份 `/tmp/screenshot-<timestamp>/capture.mjs`。模板里有：
- 启动参数（已经把所有避坑配置写好了）
- 5 种拍法的注释样例（fullPage / element / clip / interaction / responsive）

按用户的需求**填进 SHOTS 区块**。删掉用不到的样例。

### 步骤 5 — 跑

```bash
WEB_SCREENSHOT_RUNTIME=<runtime_dir_from_step_3> \
  CHROME=<path_from_step_2> \
  URL=<user_url> \
  OUT=<user_output_dir> \
  node /tmp/screenshot-<ts>/capture.mjs
```

**`WEB_SCREENSHOT_RUNTIME` 必须传**——template.mjs 用 `createRequire` 从这个路径加载 puppeteer-core（不能简单 cd，因为 ESM `import` 从脚本文件位置解析 node_modules 不是 cwd）。

可选 env：
- `VW=1440 VH=900` 视口宽高
- `DPR=2` 像素密度（1=普通屏，2=Retina）
- `INITIAL_WAIT_MS=4000` goto 后等多久才拍

### 步骤 6 — 报告

告诉用户：
- 拍了几张图
- 每张存哪了
- 总耗时
- 有错误的话贴出来

## 写 capture.mjs 的避坑手册（**最重要**）

每条都是真踩过的坑。生成剧本时**默认按这些来**，除非用户明确要别的。

### 必须的

1. **`waitUntil: 'domcontentloaded'`，不是 `networkidle0`**
   原因：很多 dashboard 自动每 N 秒刷新（拉数据/心跳），networkidle 永远不会满足，hang 住。
   配套：goto 之后加 `setTimeout(4000)` 给 chart/动画渲染时间。

2. **`deviceScaleFactor: 2`**
   不加的话 README 里图片会糊（Retina 屏幕上看尤其明显）。

3. **`headless: 'shell'`**
   配 chrome-headless-shell 用的，不是 `headless: true`。

4. **启动参数**
   ```js
   args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars',
          '--disable-features=PaintHolding']
   ```
   - `--hide-scrollbars`：每张图右边没有丑滚动条
   - `--disable-features=PaintHolding`：Chromium 默认会 hold 第一帧防闪屏，headless 下导致前几帧拍到空白

### 拍法的优先级（**永远从上往下选**）

1. **元素自截** `await el.screenshot({ path })` —— 最干净，puppeteer 自动按元素 bounding rect 裁
2. **截到锚点** `page.screenshot({ clip: {x, y: 0, width, height: anchorTop} })` —— 截"页面顶部到某分界元素之前"
3. **手算坐标 clip** —— 最次，只在前两种都不行时用

### 等"东西"出现/消失，**永远用 `waitForFunction`，不要硬 setTimeout**

```js
// ✅ 对：等到 spinner 真的消失
await page.waitForFunction(() => !document.querySelector('.spinner'),
  { timeout: 60_000, polling: 500 });

// ❌ 错：盲等 30 秒（可能不够也可能浪费）
await new Promise(r => setTimeout(r, 30_000));
```

例外：goto 之后等 chart 渲染那个 4 秒可以硬等（没好的 DOM 信号）。

### 用 `page.evaluate(() => ...)` 算位置时返回的是字符串/数字

不是 DOM 节点。需要在 evaluate 里 `getBoundingClientRect()` 然后返回数值。

### LLM 接口慢的话 timeout 给到 130 秒

如果交互后等待的元素由慢接口生成（LLM 调用、外部 API），等待常常 30-90 秒。waitForFunction timeout 给 120-130 秒留 buffer，不要默认的 30 秒。

### 文件用 .mjs 而不是 .js 或 .ts

- `.mjs` 让 Node 用 ESM 模式（支持 `import` + top-level await）
- 不用 `.ts` 因为要避免依赖 TypeScript 运行器（tsx/ts-node/bun）
- 不用 `.js` 因为默认 CJS，要写 `require()` 麻烦

### `import 'puppeteer-core'` 在 ESM 里要走 createRequire 套路

Node ESM 的 `import` 从**脚本文件位置**找 node_modules，不像 CJS 从 cwd 找。capture.mjs 在 /tmp/，puppeteer-core 在 `~/.cache/web-screenshot/runtime/node_modules/`，直接 `import` 必崩。

`lib/template.mjs` 已经用 `createRequire(file://${RUNTIME}/)` + `require('puppeteer-core')` 解决了。生成新剧本时**必须保留这套**，不要简化成普通 `import`。

### 自动下载 chrome 后第一次跑可能慢

`npx @puppeteer/browsers install` 第一次跑要先下载 `@puppeteer/browsers` 包本身（~30s）再下载 chrome-headless-shell（~80MB / 1-3 分钟）。期间脚本不响应。如果用户不想等 / 网烂，加 `WEB_SCREENSHOT_NO_AUTO_INSTALL=1` 让 find-chrome.sh 直接报错而不是阻塞。

## Canonical example

用户："给 localhost:8787 的整个页面截一张图"
- URL 明确、无交互、无 selector → 不要再问，直接动手
- 拍法：`page.screenshot({ fullPage: true })`
- 输出：默认 `/tmp/screenshots-<ts>/`

## 留 capture.mjs 还是扔

默认**扔**（写到 /tmp 自然清理）。

如果用户在某个项目根目录下跑、并且明确说"留一份"或者"以后好重跑"，把 capture.mjs 复制到该项目的 `docs/screenshots/capture.mjs` 一份。

## 重置 / 故障排查

skill 自管的所有缓存都在 `~/.cache/web-screenshot/`：

```
~/.cache/web-screenshot/
├── chrome/                 自动下载的 chrome-headless-shell（~80MB）
└── runtime/                npm install puppeteer-core 的目录
```

要彻底重置：`rm -rf ~/.cache/web-screenshot/`。下次跑 skill 会自动重建。

