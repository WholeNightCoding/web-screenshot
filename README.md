# web-screenshot

> Claude Code skill：用自然语言驱动浏览器自动截图，**开箱即用**。

跟 Claude Code 说"给 localhost:3000 截个图"、"截一下 dashboard 的顶部"、"点 AI 按钮等结果出来再截图"——这个 skill 接管，写临时剧本、跑无头浏览器、出 PNG。

## 怎么工作的

```
你 → "截个图..."
       ↓
Claude Code 调 web-screenshot skill
       ↓
跟你对齐 5 件事（URL / 拍哪 / 有交互吗 / 存哪 / 视口）
       ↓
现写一份 capture.mjs
       ↓
跑：node + puppeteer-core + chrome-headless-shell
       ↓
PNG 出来 → 报告路径
```

技术栈：
- **Node 18+** — 跑 ESM JavaScript 的运行器
- **puppeteer-core** — 浏览器遥控器（skill 自己装到 `~/.cache/web-screenshot/runtime/`）
- **chrome-headless-shell** — 没界面的 Chrome（已经有 Playwright/Puppeteer 缓存就复用，否则 skill 自己下载到 `~/.cache/web-screenshot/chrome/`）

## 安装

```bash
git clone <repo> ~/.claude/skills/web-screenshot
chmod +x ~/.claude/skills/web-screenshot/lib/*.sh
```

**唯一硬依赖**：Node 18+
- macOS：`brew install node`
- 其他：[nodejs.org](https://nodejs.org/) 下载，或 nvm/fnm

第一次跑 skill 会自动：
1. 装 puppeteer-core 到 `~/.cache/web-screenshot/runtime/`（~10s）
2. 下载 chrome-headless-shell 到 `~/.cache/web-screenshot/chrome/`（~80MB / 1-3 min）

之后所有调用都秒回。

## 怎么用

跟 Claude Code 直接说就行：

```
"给 localhost:8787 截个图"
"给 dashboard 的 #sidebar 截个图存到 ./docs/sidebar.png"
"截个 mobile 的，390 宽，整页"
"先点 #login 按钮，等加载完，再截 #welcome-page"
```

skill 会问清楚细节、跑、出图、报告。

## 文件结构

```
~/.claude/skills/web-screenshot/
├── SKILL.md              ← Claude Code 看的指令书
├── README.md             ← 你看的（本文件）
└── lib/
    ├── find-chrome.sh    ← 找 chrome-headless-shell（缓存复用 + 自动下载 fallback）
    ├── prep-runtime.sh   ← 准备 Node + npm install puppeteer-core
    └── template.mjs      ← capture.mjs 的样板（5 种拍法注释样例）
```

## 跨机器分发

设计目标就是分发出去开箱即用。在新机器上：

```bash
git clone <repo> ~/.claude/skills/web-screenshot
chmod +x ~/.claude/skills/web-screenshot/lib/*.sh
```

然后跟 Claude Code 说"截个图..."就行。skill 会：
- 检测 Node（没装就 stderr 告诉用户怎么装）
- 自动 npm install puppeteer-core
- 自动下载 chrome-headless-shell
- 出图

整个过程对用户透明。第一次有 1-3 分钟下载，之后秒回。

## 重置 / 故障排查

skill 自管的所有缓存都在 `~/.cache/web-screenshot/`：

```
~/.cache/web-screenshot/
├── chrome/                 自动下载的 chrome-headless-shell（~80MB）
└── runtime/                npm install puppeteer-core 的目录
```

要彻底重置：`rm -rf ~/.cache/web-screenshot/`，下次跑 skill 会自动重建。

环境变量调试：
- `WEB_SCREENSHOT_NO_AUTO_INSTALL=1` 找不到 chrome 时不要自动下载，直接报错（适合 CI 或不想等）
- `CHROME=/path/to/chrome` 强制指定浏览器路径

## 不做的事

- 不能截要登录的页面（cookie 注入是另一码事，以后扩展）
- 不能截桌面应用 / 你本地打开的窗口（只能截 URL）
- 不管 README 里图片排版（出图是出图，排版是另一码事）
- 不做 visual regression diff（那是 percy/chromatic 的领地）

## 开发约定

- 默认 capture.mjs 跑完就扔（写到 `/tmp/`）
- 如果用户在某项目目录跑、并明说"留一份"，把 capture.mjs 复制到该项目的 `docs/screenshots/capture.mjs`
- 所有"避坑配置"（waitUntil、deviceScaleFactor、--hide-scrollbars 等）默认走 `lib/template.mjs`
- skill 自管缓存严格在 `~/.cache/web-screenshot/`，不污染别处
