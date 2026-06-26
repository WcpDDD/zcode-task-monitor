# ZCode Task Monitor

> 一个 macOS **始终置顶的半透明浮窗**,实时显示所有 [ZCode](https://z.ai) **进行中任务**的状态、运行时长;任务疑似卡住/等待输入时给出阻塞警告;状态变化时弹原生通知。

**解决什么问题:** ZCode 并行跑多个任务时,某个任务卡住等用户输入,任务列表里却看不出来。这个工具把所有进行中的任务放进一个永远浮在右上角的浮窗,并在需要你介入时主动弹通知。

关键词:`zcode` · `z.ai` · `task monitor` · `hitl` · `floating window` · `menu bar` · `macos` · `agent observability`

---

## 功能

- 🪟 **始终置顶的半透明浮窗**:浮在所有窗口(包括 ZCode)之上,不抢焦点
- 📋 **只显示进行中的任务**:已完成的不占位;按工作区分组,从顶部往下排列
- ⏱️ **运行时长**:每行显示该任务已运行多久(`<1m` / `3m` / `1h20m`)
- ⚠️ **阻塞警告**:任务进入「等待输入(HITL)」或长时间无活动时,标记 `⚠ 可能阻塞`
- 🔔 **状态通知**:任务从运行中变为等待输入/出错时,弹原生 macOS 通知(点通知可跳到对应工作区)
- 👆 **一键跳转**:点浮窗里任意任务 → 用 `zcode://workspace/open` 打开它的工作区并前置 ZCode
- 🪶 **纯原生**:Swift + AppKit,零运行时依赖,只链接系统 libsqlite3

---

## ⚠️ 重要的安装限制(必读)

**这个浮窗无法在 ZCode 会话内部启动。** 原因:ZCode 的 host 进程会对它派生的子进程施加 sandbox,导致任何从 ZCode 会话里(包括 SessionStart hook)拉起的 GUI 子进程**都无法向 WindowServer 注册窗口**——进程会跑起来,但浮窗永远是隐形的。

因此:

- ✅ **可以**在 ZCode 会话里运行安装脚本(`install.sh`)——它会编译、复制文件、注册插件和 LaunchAgent。
- ❌ **不能**在 ZCode 会话里启动浮窗本身——必须从 ZCode 之外的环境启动。

**首次/日常启动浮窗,用以下任一方式**(它们的父进程是 launchd 或 loginwindow,不经过 ZCode):

```bash
# 方式一(推荐):系统终端 App(不是 ZCode 里的)运行
open /Applications/ZCodeTaskMonitor.app
```
- 方式二:Finder 里双击 `/Applications/ZCodeTaskMonitor`
- 方式三:注销重登 —— 已注册的 LaunchAgent 会在登录时自动启动(此后每次登录都自启)

> 一旦从上述路径启动过一次,浮窗就会正常渲染。后续想关掉再开,用菜单栏图标或重登即可。

---

## 系统要求

- macOS 13(Ventura)或更高
- 已安装并运行过 ZCode(用于生成 `~/.zcode` 数据目录)
- 从源码安装需要 Swift 5.9+ / Xcode 命令行工具

**已测试:** ZCode 3.1.3 / macOS 26.5

---

## 安装

### 方式一:克隆仓库安装(从源码编译)

```bash
git clone https://github.com/WcpDDD/zcode-task-monitor.git
cd zcode-task-monitor
./scripts/install.sh
```

`install.sh` 会自动完成:
1. 若没有预编译 `.app`,则用 `swift build` 从源码编译(需要 Xcode)
2. 把 `.app` 复制到 `/Applications`
3. 把插件复制到 `~/.zcode/cli/plugins/cache/...`,在 `marketplace.json` 注册,在 `config.json` 启用
4. 安装 LaunchAgent(登录自启)

> ⚠️ 如果你在 ZCode 会话里跑 `install.sh`,脚本会检测到并提示你「最后一步启动浮窗需从 ZCode 之外做」。

### 方式二:下载 Release(预编译)

到 [Releases](https://github.com/WcpDDD/zcode-task-monitor/releases) 下载 `zcode-task-monitor-*.zip`,解压后运行里面的 `./scripts/install.sh`。

### 卸载

```bash
./scripts/uninstall.sh
```

---

## 工作原理

### 架构(两个松耦合组件)

```
zcode-task-monitor/
├── app/                         # 原生 Swift 浮窗应用
│   ├── Sources/ZCodeTaskMonitor/
│   │   ├── ZCodeTaskMonitorApp.swift   # NSApplication 启动入口
│   │   ├── AppDelegate.swift           # 浮窗 + 菜单栏图标
│   │   ├── FloatingPanel.swift         # 置顶半透明 NSPanel
│   │   ├── PanelContentView.swift      # AppKit 任务列表视图
│   │   ├── TaskStore.swift             # 轮询调度 + 状态 diff + 通知触发
│   │   ├── ZCodePoller.swift           # 每 5s 读两个 SQLite,join + 分类
│   │   ├── SQLiteReader.swift          # 只读、WAL 安全的 SQLite3 封装
│   │   ├── Notifier.swift              # 原生通知(UNUserNotificationCenter)
│   │   ├── DeepLinker.swift            # 点击跳转 zcode://workspace/open
│   │   └── Models.swift                # TaskSnapshot / TaskStatus / 阻塞判定
│   └── Package.swift
├── plugin/                      # ZCode 插件壳(随 ZCode 启动保活)
│   ├── .zcode-plugin/plugin.json
│   ├── hooks/{hooks.json,session-start}
│   └── dev.zcode.taskmonitor.plist     # LaunchAgent 模板
└── scripts/{build-app,install,uninstall,install-from-release}.sh
```

### 数据来源(只读,绝不写入)

每 5 秒只读打开两个 ZCode SQLite 数据库:

| 数据库 | 作用 |
|---|---|
| `~/.zcode/v2/tasks-index.sqlite` | 任务列表(标题、工作区、`task_status`) |
| `~/.zcode/cli/db/db.sqlite` | 实时状态(session / turn / tool / model usage) |

连接以只读 + URI 模式打开,SQLite 自动读 WAL,**绝不写、不 checkpoint**,对 ZCode 零干扰。

### 状态判定

- **进行中显示**:`tasks-index.task_status = 'running'` 的任务才进入浮窗(已完成的隐藏)。
- **状态分类**:以 `task_status` 为准;turn 级别数据只在 running 时用来细分 `running` vs `waiting`(HITL)。
- **阻塞警告 `⚠ 可能阻塞`**:`waiting` 状态,或 running 但最近一次 tool/model 活动距今 ≥ 45 秒(阈值在 `ZCodePoller.swift` 的 `hitlInactivitySeconds` 可调)。
- **运行时长**:基于 `tasks.updated_at` 距今的时间。

> ⚠️ ZCode 数据库里**没有显式的「等待用户输入」状态**,HITL 是基于「turn 卡在 running + 无活动」**推断**的,非精确信号,长模型思考可能短暂误报。

### 点击跳转

ZCode 注册了 `zcode://` scheme,但**只支持 `zcode://workspace/open?path=<工作区>`,不支持跳转到指定任务**(已确认 ZCode 内部只有 `OpenWorkspacePath` IPC)。所以点击任务 = 打开它的工作区 + 前置 ZCode。

---

## 局限与风险

- **ZCode 子进程 sandbox**:浮窗不能从 ZCode 会话内启动(见上方「重要的安装限制」)。
- **HITL 是推断信号**:可能因模型长时间思考(>45s 无活动)短暂误报。
- **deep-link 只到工作区**:跨工作区点击只能切到工作区,不能精确定位任务 tab。
- **仅 macOS**:依赖 NSPanel / NSVisualEffectView / UNUserNotificationCenter。

---

## 从源码构建

```bash
git clone https://github.com/WcpDDD/zcode-task-monitor.git
cd zcode-task-monitor
./scripts/build-app.sh     # 产出 dist/ZCodeTaskMonitor.app
```

需要 Swift 5.9+(Xcode 15+)。无第三方依赖,只链接系统 `libsqlite3`。

---

## 许可证

MIT
