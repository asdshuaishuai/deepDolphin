// L10n.swift — 多语言本地化系统（zh-CN / en / zh-TW / ja）
//
// 设计：
// - 语言切换存 UserDefaults，启动时恢复；不依赖系统语言
// - 字符串表用 [String: String] 字典（编译期不查漏，但 miss 时回退 en→zh-CN→key）
// - 视图中用 `L10n.t("key")` 或 `L10n.shared.str.keyName` 访问
// - 固定长文（About/Help/OpenSource/Changelog）走 `L10n.shared.doc(.about)` 等
import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhCN = "zh-CN"
    case en    = "en"
    case zhTW  = "zh-TW"
    case ja    = "ja"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .zhCN: return "简体中文"
        case .en:   return "English"
        case .zhTW: return "繁體中文"
        case .ja:   return "日本語"
        }
    }
}

// MARK: - 字符串表（每语言一个字典）

typealias L10nTable = [String: String]

let L10n_zhCN: L10nTable = [
    "settings.general": "通用",
    "settings.ai": "AI 配置",
    "settings.automation": "自动化",
    "settings.about": "关于",
    "settings.help": "帮助",
    "settings.openSource": "开源感谢",
    "settings.changelog": "更新日志",
    "settings.language": "语言",
    "settings.autostart": "登录时自动启动",
    "settings.autostartToggle": "登录时自动启动 deepDolphin",
    // 导航
    "nav.dashboard": "仪表盘",
    "nav.board": "看板",
    "nav.agent": "AI 助手",
    "nav.milestones": "里程碑",
    "nav.addScan": "添加 / 扫描项目",
    "nav.projects": "项目",
    "nav.overview": "总览",
    "nav.repos": "仓库",

    // 仪表盘
    "dash.title": "项目群脉搏",
    "dash.projectBrief": "项目群说明",
    "dash.projectCount": "项目总数",
    "dash.activeCount": "近 7 天活跃",
    "dash.pendingCount": "待处理",
    "dash.branches": "分支",
    "dash.pendingMerge": "待合入分支",
    "dash.untracked": "未跟踪文件",
    "dash.stash": "stash",
    "dash.dirtyCount": "有未提交改动",
    "dash.milestoneRate": "里程碑完成率",
    "dash.langDist": "语言分布（跟踪文件数）",
    "dash.activeProjects": "活跃项目",
    "dash.allProjects": "全部项目",

    // 看板
    "board.title": "看板",
    "board.active": "活跃中",
    "board.attention": "待处理",
    "board.stale": "停滞",
    "board.other": "其他",
    "board.empty": "空",

    // 里程碑
    "ms.title": "里程碑",
    "ms.total": "全部里程碑",
    "ms.add": "新建里程碑",
    "ms.done": "已达成",
    "ms.open": "进行中",
    "ms.dropped": "已放弃",
    "ms.overdue": "已逾期",
    "ms.markDone": "标记达成",
    "ms.reopen": "重新打开",
    "ms.drop": "放弃",
    "ms.delete": "删除",
    "ms.openProject": "打开项目",
    "ms.name": "名称",
    "ms.tag": "绑定 tag",
    "ms.date": "目标日期",
    "ms.desc": "描述",
    "ms.empty": "暂无里程碑",
    "ms.emptyHint": "里程碑绑定 git tag 后，tag 出现即自动判定达成",
    "ms.create": "创建",

    // 项目详情
    "detail.pulse": "工程脉搏",
    "detail.commitMix": "提交构成（近期）",
    "detail.branches": "分支进度",
    "detail.gitOps": "Git 操作",
    "detail.journal": "进度日志",
    "detail.shallowUpdate": "浅更新",
    "detail.deepUpdate": "深度更新",
    "detail.projectBrief": "项目说明",
    "detail.commit": "提交",
    "detail.commitMsg": "提交信息（提交全部改动）",
    "detail.pull": "拉取",
    "detail.push": "推送",
    "detail.fetch": "抓取",
    "detail.stash": "暂存",
    "detail.unstash": "恢复",
    "detail.inFinder": "在 Finder 中显示",
    "detail.inTerminal": "在终端中打开",
    "detail.openRemote": "打开远端仓库",
    "detail.current": "当前",
    "detail.default": "默认",
    "detail.ahead": "领先默认分支",
    "detail.docs": "文档",

    // 通用
    "common.refresh": "刷新",
    "common.loading": "加载中…",
    "common.cancel": "取消",
    "common.save": "保存",
    "common.close": "关闭",
    "common.confirm": "确认",
    "common.copy": "复制",
    "common.retry": "重试",
    "common.settings": "设置…",
    "common.quit": "退出 deepDolphin",
    "common.about": "关于 deepDolphin",
    "common.search": "搜索",
    "common.projects": "个项目",
    "common.enterManage": "进入管控",

    // 错误 / 状态
    "err.engineTimeout": "引擎响应超时 — 如果项目在外置卷上，请在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中允许 deepDolphin",
    "err.engineNotFound": "找不到引擎。请安装 moongit 或设置 DEEPGIT_BIN",
    "err.fdaRequired": "无法访问项目目录 — 请在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中允许 deepDolphin",
    "err.pathNotFound": "路径不存在或卷未挂载",
    "err.loadingProjects": "读取项目群…",
    "err.noProjects": "尚未注册任何项目",

    // 更新
    "update.shallowAll": "浅更新 · 全部",
    "update.deepAll": "深更新 · 全部",
    "update.allShallow": "全部浅更新",
    "update.aiDigest": "AI 摘要",
    "update.complete": "全部进度已记录",
    "update.failed": "批量更新失败",
]

let L10n_en: L10nTable = [
    "settings.general": "General",
    "settings.ai": "AI Configuration",
    "settings.automation": "Automation",
    "settings.about": "About",
    "settings.help": "Help",
    "settings.openSource": "Open Source",
    "settings.changelog": "Changelog",
    "settings.language": "Language",
    "settings.autostart": "Launch at Login",
    "settings.autostartToggle": "Launch deepDolphin at login",
    "nav.dashboard": "Dashboard",
    "nav.board": "Board",
    "nav.agent": "AI Assistant",
    "nav.milestones": "Milestones",
    "nav.addScan": "Add / Scan Projects",
    "nav.projects": "Projects",
    "nav.overview": "Overview",
    "nav.repos": "Repositories",

    "dash.title": "Project Group Pulse",
    "dash.projectBrief": "Group Brief",
    "dash.projectCount": "Total Projects",
    "dash.activeCount": "Active (7d)",
    "dash.pendingCount": "Pending",
    "dash.branches": "Branches",
    "dash.pendingMerge": "Merge Candidates",
    "dash.untracked": "Untracked Files",
    "dash.stash": "Stash",
    "dash.dirtyCount": "With Uncommitted Changes",
    "dash.milestoneRate": "Milestone Completion",
    "dash.langDist": "Language Distribution (tracked files)",
    "dash.activeProjects": "Active Projects",
    "dash.allProjects": "All Projects",

    "board.title": "Board",
    "board.active": "Active",
    "board.attention": "Needs Attention",
    "board.stale": "Stale",
    "board.other": "Other",
    "board.empty": "Empty",

    "ms.title": "Milestones",
    "ms.total": "All Milestones",
    "ms.add": "New Milestone",
    "ms.done": "Completed",
    "ms.open": "In Progress",
    "ms.dropped": "Dropped",
    "ms.overdue": "Overdue",
    "ms.markDone": "Mark Done",
    "ms.reopen": "Reopen",
    "ms.drop": "Drop",
    "ms.delete": "Delete",
    "ms.openProject": "Open Project",
    "ms.name": "Name",
    "ms.tag": "Bind Tag",
    "ms.date": "Target Date",
    "ms.desc": "Description",
    "ms.empty": "No Milestones",
    "ms.emptyHint": "Bind a git tag; milestone auto-completes when tag appears",
    "ms.create": "Create",

    "detail.pulse": "Engineering Pulse",
    "detail.commitMix": "Commit Mix (recent)",
    "detail.branches": "Branch Progress",
    "detail.gitOps": "Git Operations",
    "detail.journal": "Progress Log",
    "detail.shallowUpdate": "Shallow Update",
    "detail.deepUpdate": "Deep Update",
    "detail.projectBrief": "Project Brief",
    "detail.commit": "Commit",
    "detail.commitMsg": "Commit message (all changes)",
    "detail.pull": "Pull",
    "detail.push": "Push",
    "detail.fetch": "Fetch",
    "detail.stash": "Stash",
    "detail.unstash": "Unstash",
    "detail.inFinder": "Reveal in Finder",
    "detail.inTerminal": "Open in Terminal",
    "detail.openRemote": "Open Remote",
    "detail.current": "Current",
    "detail.default": "Default",
    "detail.ahead": "Ahead of default",
    "detail.docs": "Docs",

    "common.refresh": "Refresh",
    "common.loading": "Loading…",
    "common.cancel": "Cancel",
    "common.save": "Save",
    "common.close": "Close",
    "common.confirm": "Confirm",
    "common.copy": "Copy",
    "common.retry": "Retry",
    "common.settings": "Settings…",
    "common.quit": "Quit deepDolphin",
    "common.about": "About deepDolphin",
    "common.search": "Search",
    "common.projects": " projects",
    "common.enterManage": "Manage",

    "err.engineTimeout": "Engine timed out — if projects are on an external volume, grant deepDolphin Full Disk Access in System Settings",
    "err.engineNotFound": "Engine not found. Install moongit or set DEEPGIT_BIN",
    "err.fdaRequired": "Cannot access project directory — grant deepDolphin Full Disk Access in System Settings",
    "err.pathNotFound": "Path not found or volume not mounted",
    "err.loadingProjects": "Loading projects…",
    "err.noProjects": "No projects registered",

    "update.shallowAll": "Shallow · All",
    "update.deepAll": "Deep · All",
    "update.allShallow": "Shallow Update All",
    "update.aiDigest": "AI Digest",
    "update.complete": "All progress recorded",
    "update.failed": "Batch update failed",
]

let L10n_zhTW: L10nTable = [
    "settings.general": "一般",
    "settings.ai": "AI 配置",
    "settings.automation": "自動化",
    "settings.about": "關於",
    "settings.help": "說明",
    "settings.openSource": "開源感謝",
    "settings.changelog": "更新日誌",
    "settings.language": "語言",
    "settings.autostart": "登入時自動啟動",
    "settings.autostartToggle": "登入時自動啟動 deepDolphin",
    "nav.dashboard": "儀表板",
    "nav.board": "看板",
    "nav.agent": "AI 助手",
    "nav.milestones": "里程碑",
    "nav.addScan": "添加 / 掃描專案",
    "nav.projects": "專案",
    "nav.overview": "總覽",
    "nav.repos": "倉庫",

    "dash.title": "專案群脈搏",
    "dash.projectBrief": "專案群說明",
    "dash.projectCount": "專案總數",
    "dash.activeCount": "近 7 天活躍",
    "dash.pendingCount": "待處理",
    "dash.branches": "分支",
    "dash.pendingMerge": "待合入分支",
    "dash.untracked": "未追蹤檔案",
    "dash.stash": "stash",
    "dash.dirtyCount": "有未提交變更",
    "dash.milestoneRate": "里程碑完成率",
    "dash.langDist": "語言分佈（追蹤檔案數）",
    "dash.activeProjects": "活躍專案",
    "dash.allProjects": "全部專案",

    "board.title": "看板",
    "board.active": "活躍中",
    "board.attention": "待處理",
    "board.stale": "停滯",
    "board.other": "其他",
    "board.empty": "空",

    "ms.title": "里程碑",
    "ms.total": "全部里程碑",
    "ms.add": "新建里程碑",
    "ms.done": "已達成",
    "ms.open": "進行中",
    "ms.dropped": "已放棄",
    "ms.overdue": "已逾期",
    "ms.markDone": "標記達成",
    "ms.reopen": "重新打開",
    "ms.drop": "放棄",
    "ms.delete": "刪除",
    "ms.openProject": "打開專案",
    "ms.name": "名稱",
    "ms.tag": "綁定 tag",
    "ms.date": "目標日期",
    "ms.desc": "描述",
    "ms.empty": "暫無里程碑",
    "ms.emptyHint": "里程碑綁定 git tag 後，tag 出現即自動判定達成",
    "ms.create": "建立",

    "detail.pulse": "工程脈搏",
    "detail.commitMix": "提交構成（近期）",
    "detail.branches": "分支進度",
    "detail.gitOps": "Git 操作",
    "detail.journal": "進度日誌",
    "detail.shallowUpdate": "淺更新",
    "detail.deepUpdate": "深度更新",
    "detail.projectBrief": "專案說明",
    "detail.commit": "提交",
    "detail.commitMsg": "提交訊息（提交全部變更）",
    "detail.pull": "拉取",
    "detail.push": "推送",
    "detail.fetch": "抓取",
    "detail.stash": "暫存",
    "detail.unstash": "恢復",
    "detail.inFinder": "在 Finder 中顯示",
    "detail.inTerminal": "在終端機中打開",
    "detail.openRemote": "打開遠端倉庫",
    "detail.current": "目前",
    "detail.default": "預設",
    "detail.ahead": "領先預設分支",
    "detail.docs": "文件",

    "common.refresh": "重新整理",
    "common.loading": "載入中…",
    "common.cancel": "取消",
    "common.save": "儲存",
    "common.close": "關閉",
    "common.confirm": "確認",
    "common.copy": "複製",
    "common.retry": "重試",
    "common.settings": "設定…",
    "common.quit": "退出 deepDolphin",
    "common.about": "關於 deepDolphin",
    "common.search": "搜尋",
    "common.projects": "個專案",
    "common.enterManage": "進入管控",

    "err.engineTimeout": "引擎回應逾時 — 如果專案在外部磁碟上，請在 系統設定 → 隱私權與安全性 → 完整磁碟存取權限 中允許 deepDolphin",
    "err.engineNotFound": "找不到引擎。請安裝 moongit 或設定 DEEPGIT_BIN",
    "err.fdaRequired": "無法存取專案目錄 — 請在 系統設定 → 隱私權與安全性 → 完整磁碟存取權限 中允許 deepDolphin",
    "err.pathNotFound": "路徑不存在或卷未掛載",
    "err.loadingProjects": "讀取專案群…",
    "err.noProjects": "尚未註冊任何專案",

    "update.shallowAll": "淺更新 · 全部",
    "update.deepAll": "深更新 · 全部",
    "update.allShallow": "全部淺更新",
    "update.aiDigest": "AI 摘要",
    "update.complete": "全部進度已記錄",
    "update.failed": "批次更新失敗",
]

let L10n_ja: L10nTable = [
    "settings.general": "一般",
    "settings.ai": "AI 設定",
    "settings.automation": "自動化",
    "settings.about": "情報",
    "settings.help": "ヘルプ",
    "settings.openSource": "オープンソース",
    "settings.changelog": "変更履歴",
    "settings.language": "言語",
    "settings.autostart": "ログイン時に起動",
    "settings.autostartToggle": "ログイン時に deepDolphin を起動",
    "nav.dashboard": "ダッシュボード",
    "nav.board": "ボード",
    "nav.agent": "AI アシスタント",
    "nav.milestones": "マイルストーン",
    "nav.addScan": "プロジェクト追加 / スキャン",
    "nav.projects": "プロジェクト",
    "nav.overview": "概要",
    "nav.repos": "リポジトリ",

    "dash.title": "プロジェクト群ステータス",
    "dash.projectBrief": "グループ概要",
    "dash.projectCount": "プロジェクト总数",
    "dash.activeCount": "直近 7 日間アクティブ",
    "dash.pendingCount": "要対応",
    "dash.branches": "ブランチ",
    "dash.pendingMerge": "マージ候補",
    "dash.untracked": "未追跡ファイル",
    "dash.stash": "スタッシュ",
    "dash.dirtyCount": "未コミット変更あり",
    "dash.milestoneRate": "マイルストーン達成率",
    "dash.langDist": "言語分布（追跡ファイル数）",
    "dash.activeProjects": "アクティブなプロジェクト",
    "dash.allProjects": "すべてのプロジェクト",

    "board.title": "ボード",
    "board.active": "アクティブ",
    "board.attention": "要対応",
    "board.stale": "停滞中",
    "board.other": "その他",
    "board.empty": "空",

    "ms.title": "マイルストーン",
    "ms.total": "すべてのマイルストーン",
    "ms.add": "マイルストーン追加",
    "ms.done": "達成済み",
    "ms.open": "進行中",
    "ms.dropped": "中止",
    "ms.overdue": "期限超過",
    "ms.markDone": "達成としてマーク",
    "ms.reopen": "再オープン",
    "ms.drop": "中止",
    "ms.delete": "削除",
    "ms.openProject": "プロジェクトを開く",
    "ms.name": "名前",
    "ms.tag": "タグBind",
    "ms.date": "目標日",
    "ms.desc": "説明",
    "ms.empty": "マイルストーンなし",
    "ms.emptyHint": "git タグをバインドすると、タグの出現で自動達成",
    "ms.create": "作成",

    "detail.pulse": "エンジニアリングパルス",
    "detail.commitMix": "コミット構成（直近）",
    "detail.branches": "ブランチ進捗",
    "detail.gitOps": "Git 操作",
    "detail.journal": "進捗ログ",
    "detail.shallowUpdate": "浅い更新",
    "detail.deepUpdate": "深い更新",
    "detail.projectBrief": "プロジェクト概要",
    "detail.commit": "コミット",
    "detail.commitMsg": "コミットメッセージ（全変更）",
    "detail.pull": "プル",
    "detail.push": "プッシュ",
    "detail.fetch": "フェッチ",
    "detail.stash": "スタッシュ",
    "detail.unstash": "スタッシュ解除",
    "detail.inFinder": "Finder で表示",
    "detail.inTerminal": "ターミナルで開く",
    "detail.openRemote": "リモートを開く",
    "detail.current": "現在",
    "detail.default": "デフォルト",
    "detail.ahead": "デフォルトより先行",
    "detail.docs": "ドキュメント",

    "common.refresh": "更新",
    "common.loading": "読み込み中…",
    "common.cancel": "キャンセル",
    "common.save": "保存",
    "common.close": "閉じる",
    "common.confirm": "確認",
    "common.copy": "コピー",
    "common.retry": "再試行",
    "common.settings": "設定…",
    "common.quit": "deepDolphin を終了",
    "common.about": "deepDolphin について",
    "common.search": "検索",
    "common.projects": "プロジェクト",
    "common.enterManage": "管理",

    "err.engineTimeout": "エンジンがタイムアウト — プロジェクトが外部ボリューム上にある場合、システム設定 → プライバシーとセキュリティ → フルディスクアクセス で deepDolphin を許可してください",
    "err.engineNotFound": "エンジンが見つかりません。moongit をインストールするか DEEPGIT_BIN を設定してください",
    "err.fdaRequired": "プロジェクトディレクトリにアクセスできません — システム設定 → プライバシーとセキュリティ → フルディスクアクセス で deepDolphin を許可してください",
    "err.pathNotFound": "パスが存在しないかボリュームがマウントされていません",
    "err.loadingProjects": "プロジェクトを読み込み中…",
    "err.noProjects": "プロジェクトが登録されていません",

    "update.shallowAll": "浅い更新 · 全体",
    "update.deepAll": "深い更新 · 全体",
    "update.allShallow": "一括更新",
    "update.aiDigest": "AI 要約",
    "update.complete": "全進捗を記録しました",
    "update.failed": "一括更新失敗",
]

// MARK: - L10n 管理器

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "app.language")
            _strings = L10n.table(for: language)
        }
    }

    private var _strings: L10nTable

    var strings: L10nTable { _strings }
    var tabGeneral: String { _strings["settings.general"] ?? "General" }
    var tabAI: String { _strings["settings.ai"] ?? "AI" }
    var tabAutomation: String { _strings["settings.automation"] ?? "Automation" }
    var tabAbout: String { _strings["settings.about"] ?? "About" }
    var tabHelp: String { _strings["settings.help"] ?? "Help" }
    var tabOpenSource: String { _strings["settings.openSource"] ?? "Open Source" }
    var tabChangelog: String { _strings["settings.changelog"] ?? "Changelog" }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "app.language")
            ?? Bundle.main.preferredLocalizations.first
            ?? "zh-CN"
        let lang = AppLanguage(rawValue: saved) ?? .zhCN
        // init 期间不触发 didSet，直接赋值 _strings
        self._strings = L10n.table(for: lang)
        self.language = lang
    }

    /// 翻译入口：`L10n.t("nav.dashboard")`
    static func t(_ key: String) -> String {
        shared._strings[key]
            ?? L10n_en[key]
            ?? key
    }

    /// 便捷：`L10n.str.dashboard`
    var str: L10nTable { _strings }

    /// 固定长文获取
    func doc(_ kind: DocPageKind) -> String {
        DocPages.content(for: kind, language: language)
    }

    nonisolated static func table(for lang: AppLanguage) -> L10nTable {
        switch lang {
        case .zhCN: return L10n_zhCN
        case .en:   return L10n_en
        case .zhTW: return L10n_zhTW
        case .ja:   return L10n_ja
        }
    }
}

// MARK: - 固定文档页类型

enum DocPageKind: String, CaseIterable, Identifiable {
    case about      = "about"
    case help       = "help"
    case openSource = "openSource"
    case changelog  = "changelog"

    var id: String { rawValue }
}
