# ZCode Task Monitor

> 一个 macOS 菜单栏浮窗，实时显示所有 [ZCode](https://z.ai) 任务的状态。任务进入「等待输入 (HITL)」时弹出原生通知，点击任务可跳转到对应工作区。

**解决什么问题：** ZCode 并行跑多个任务时，某个任务卡在 HITL 等用户审批/回复，但任务列表只显示 `running`，跟正常跑的任务没区别——你不知道哪个在等你。这个插件把所有任务状态放进菜单栏，并在需要你介入时主动弹通知。

关键词：`zcode` · `z.ai` · `task monitor` · `hitl` · `menu bar` · `macos` · `agent observability`

---

## 截图 / 预览

<!-- TODO: 启动后补一张菜单栏浮窗截图到这里 -->

菜单栏图标在屏幕右上角。点击展开一个浮窗，按工作区分组列出所有任务：

- 🟢 **运行中** — 任务正在干活
- 🟡 **等待输入** — 任务卡住等用户（HITL），**首次进入此态会弹通知**
- 🔴 **出错** — 任务报错
- ⚪️ **已完成** — 任务结束

图标带未读角标（如 `⚡︎2`）表示有 2 个任务在等你。

---

## 功能

- ✅ **菜单栏浮窗**：随时查看所有工作区的全部任务状态，按工作区分组
- ✅ **HITL 通知**：任务从运行中变为「等待输入」时，弹原生 macOS 通知，点了直接跳到对应工作区
- ✅ **一键跳转**：点浮窗里任意任务，用 `zcode://workspace/open` deep-link 打开它的工作区并前置 ZCode
- ✅ **随 ZCode 启动**：通过 ZCode 的 `SessionStart` hook 拉起，同时装一个 LaunchAgent 做登录自启
- ✅ **零运行时依赖**：纯原生 Swift + SwiftUI，自带 libsqlite3，不依赖 Python/Node

---

## 系统要求

- macOS 13 (Ventura) 或更高
- 已安装并运行过 ZCode（用于生成 `~/.zcode` 数据目录）
- 安装脚本需要 `python3`（macOS 自带）

**已测试 ZCode 版本：** 3.1.3

---

## 安装

### 方式一：一键脚本（推荐）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/WcpDDD/zcode-task-monitor/main/scripts/install-from-release.sh)"
```

> 这会下载最新 Release 的预编译 `.app` + 插件，自动完成全部配置。

### 方式二：克隆仓库安装

```bash
git clone https://github.com/WcpDDD/zcode-task-monitor.git
cd zcode-task-monitor

# 1. 编译 .app（需要 Xcode / Swift 工具链）
./scripts/build-app.sh

# 2. 安装（复制 app + 插件，注册 marketplace，启用插件，装 LaunchAgent）
./scripts/install.sh
```

安装完成后：

1. 屏幕右上角会出现菜单栏图标。点击它查看任务。
2. 首次启动会请求**通知权限**——允许它才能收到 HITL 提醒。
3. **重启 ZCode**（或新建一个 session），`SessionStart` hook 会接管保活。

### 卸载

```bash
./scripts/uninstall.sh
```

---

## 工作原理

### 架构（两个松耦合组件）

```
zcode-task-monitor/
├── app/                         # 原生 Swift 菜单栏应用（真正的浮窗）
│   ├── Sources/ZCodeTaskMonitor/
│   │   ├── ZCodeTaskMonitorApp.swift   # MenuBarExtra + SwiftUI 浮窗 UI
│   │   ├── ZCodePoller.swift           # 每 5s 轮询两个 SQLite，join + 分类状态
│   │   ├── SQLiteReader.swift          # 只读、WAL 安全的 SQLite3 封装
│   │   ├── Notifier.swift              # 原生 macOS 通知（UNUserNotificationCenter）
│   │   ├── DeepLinker.swift            # 点击跳转：zcode://workspace/open
│   │   └── Models.swift                # TaskSnapshot / TaskStatus
│   └── Package.swift
├── plugin/                      # ZCode 插件壳（负责随 ZCode 启动）
│   ├── .zcode-plugin/plugin.json
│   ├── hooks/
│   │   ├── hooks.json           # SessionStart hook 定义
│   │   └── session-start        # 幂等拉起 .app 的 bash 启动器
│   └── dev.zcode.taskmonitor.plist   # LaunchAgent 模板
└── scripts/
    ├── build-app.sh             # swift build + 打包 .app + ad-hoc 签名
    ├── install.sh               # 一键安装
    ├── uninstall.sh             # 一键卸载
    └── install-from-release.sh  # 下载 Release 安装（curl|bash 用）
```

**为什么是两个组件？** ZCode 的 `SessionStart` hook 是一个短命同步进程——它输出 JSON 后就退出，不是常驻 daemon。所以 hook 的唯一职责是**幂等地拉起那个独立原生 .app**，真正的监控逻辑（轮询、状态分类、通知、UI）全在 Swift app 里。这样 hook 不会因超时被杀，用户也能手动双击 `.app` 启动。

### 数据来源（只读，绝不写入）

应用每 5 秒只读打开两个 ZCode SQLite 数据库：

| 数据库 | 作用 |
|---|---|
| `~/.zcode/v2/tasks-index.sqlite` | 任务列表（标题、工作区、分组） |
| `~/.zcode/cli/db/db.sqlite` | 实时状态（session / turn / tool / model usage）|

两库的 join key 是同一个 `sess_xxx` UUID（`tasks.task_id == session.id`）。连接以只读 + URI 模式打开，SQLite 自动读取 WAL，只看已提交 + 活动帧，**绝不写、不 checkpoint**，对 ZCode 运行零干扰。

### HITL（等待输入）是怎么判断的

> ⚠️ **重要限制：ZCode 数据库里没有显式的「等待用户输入」状态。** `tasks.task_status` 永远只有 `completed`；`turn_usage.status` 只有 `running`/`completed`/`error`/`cancelled`。

因此 HITL 是**推断**出来的：

1. **强信号**：某 session 的 `turn_usage.status = running`，且最近一个 tool 是 `AskUserQuestion` / `ExitPlanMode` 且其 `status = running` → 直接判为「等待输入」（无需等待）。
2. **推断信号**：`turn_usage.status = running`，且最近一次 tool/model 完成距今 **≥ 45 秒** → 判为「等待输入」。

> 45 秒阈值是为了避开「模型在长时间思考」的误报。可在源码 `ZCodePoller.swift` 顶部 `hitlInactivitySeconds` 调整。

### 点击跳转

ZCode 注册了 `zcode://` URL scheme，但**只支持 `zcode://workspace/open?path=<工作区>`，不支持「跳转到指定任务」**（已确认 ZCode 内部只有 `OpenWorkspacePath` IPC，没有 `OpenTask`）。所以点击任务 = 打开它的工作区 + 前置 ZCode，之后你在 ZCode 任务列表里点那个任务即可。

---

## 状态分类规则

| 显示状态 | 判定 |
|---|---|
| 🟢 运行中 | turn 正在跑，且近期有工具/模型活动 |
| 🟡 等待输入 | turn 在跑，但 45s 无活动 / 或命中 AskUserQuestion 等交互工具 |
| 🔴 出错 | turn status = error |
| ⚪️ 已完成 | turn status = completed / cancelled |

通知仅在状态**发生转换**时弹一次（如 running → waiting），不会每次轮询都打扰。任务离开等待态后，下次再进入会重新提醒。

---

## 局限与风险

- **HITL 是推断信号**：可能因模型长时间思考（>45s 无活动）短暂误报为「等待输入」。这是 ZCode 当前数据模型的上限，非精确信号。
- **deep-link 只到工作区**：跨工作区点击只能切到工作区，不能精确定位到某个任务 tab。
- **ZCode 升级风险**：若 ZCode 改了 DB schema 或 deep-link，本工具可能失效。会标注兼容的 ZCode 版本。
- **仅 macOS**：依赖 NSStatusItem / UNUserNotificationCenter，无 Windows/Linux 版本。

---

## 从源码构建

```bash
git clone https://github.com/WcpDDD/zcode-task-monitor.git
cd zcode-task-monitor
./scripts/build-app.sh     # 产出 dist/ZCodeTaskMonitor.app
```

需要 Swift 5.9+（Xcode 15+）。无第三方依赖，只链接系统 `libsqlite3`。

---

## 许可证

MIT

## 致谢

灵感来自 ZCode / Claude Code 的插件与 hook 系统。仅做只读监控，不对 ZCode 内部数据做任何修改。
