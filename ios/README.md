# PencilTripPlanner — Phase 2: SwiftUI 原生骨架

iOS 17+ / Swift 5.9 / SwiftUI + SwiftData。视觉与交互 1:1 对照仓库根目录的
`index.html`（v13，已定稿的 HTML 高保真原型）。

> ⚠️ 这份代码是在没有 Xcode 的环境下手写的，**没有编译验证过**。
> 请在 Mac 上用 Xcode 打开后 Build，有报错贴回来修。

## 打开运行

1. 把整个仓库 clone / pull 到 Mac：
   `git clone https://github.com/xueluren/pencil-trip-planner.git`
2. 双击打开 `ios/PencilTripPlanner.xcodeproj`
3. 顶部 target 选 **PencilTripPlanner**，destination 选一台 iPhone 模拟器
   （iOS 17.0+，如 iPhone 15）
4. **Signing & Capabilities**：Team 选你自己的 Apple ID / 开发团队；
   Bundle Identifier 默认是 `com.example.penciltripplanner`，可改成你自己的
   （如 `studio.lululand.penciltripplanner`）
5. ⌘R 运行。首次启动会自动种入 Tahiti 14 天示例行程（和 HTML 原型同一份数据）。

## 文件结构

```
ios/PencilTripPlanner/
  PencilTripPlannerApp.swift   @main 入口，建 ModelContainer，首次启动种示例数据
  Models.swift                 @Model: Trip → TripDay → Activity（cascade 删除）
  PlannerStore.swift           @Observable：选中状态、CRUD、示例数据
  Theme.swift                  设计 token：铅笔风颜色 / 字号字重 / 手绘 Shape
                               （WavyLine、SketchCircle、PaperPlane、SketchButtonStyle）
  OverviewViews.swift          HeaderView / WeekdayRow / OverviewView /
                               DayCardView（7列 LazyVGrid、时间比例 emoji + clamp 防出框）
  DetailViews.swift            DetailView / DayStripView / TimelineView /
                               EventBlock（24h 时间轴，64pt/小时）
  ChromeViews.swift            ContentView / SidebarView / EmptyStateView
  EditorViews.swift            EventEditorView / EmojiPickerView / TripEditorView
```

## 功能对照（Phase 2 范围）

- ✅ 总览：7 列日历、行等分撑满屏幕、emoji 按时间定位且不出框、
      关键节点（✈️/🏨 In/Out）手绘圈、浅灰日期头、底部波浪完结线
- ✅ 详情：日期横条（选中黑色）、拖拽条关闭、24h 时间轴、事件块按时长拉伸、
      点空白小时新建、点事件编辑
- ✅ 侧边栏行程列表 + ＋New Trip；首次空白页纸飞机涂鸦 + ＋New Trip
- ✅ 新事件弹窗（标题/图标选择器/起止时间/地点/备注/删除）、编辑行程弹窗
- ✅ SwiftData 本地持久化，离线 CRUD
- ⬜ EventKit 双向同步 → Phase 3
- ⬜ Share Extension 一键解析确认单 → Phase 4

## 已知简化（相对 HTML 原型）

- 时间轴点空白新建：HTML 按点击纵坐标精确到 15 分钟对齐；
  原生版点整小时行即以该整点为开始时间（手势与滚动冲突，取保守实现）。
- header 的 menu / 编辑图标用 SF Symbols（line.horizontal.3 / square.and.pencil）
  近似 HTML 的手绘 SVG。
- 按钮的手绘抖动边框用圆角矩形 + 偏移阴影近似。
