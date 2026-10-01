import Foundation

/// journal 条目里那个 `+N` 的**口径**。**纯函数，零依赖**。
///
/// 为什么单独成文件：判定内联在视图里时，运行时根本抓不到它，
/// 而「同名不同义」恰恰是那种只能靠断言钉住的问题。
///
/// 引擎侧缺陷 #188：`commitCount` 这个键在两条路径上装的是不同的东西 ——
///   · 浅更新 = 本轮真正新记录的提交数（`commitCountScope: "new"`）
///   · 深更新 = 仓库提交总数（`commitCountScope: "repoTotal"`，无上限）
/// 引擎的注释写明「靠 mode 字段去猜口径不行：那是约定不是契约」，
/// 并为此专门恒发了 `commitCountScope`。
///
/// 客户端原来既不解它也不显示它，日志里一个「本轮新增 6」和一个
/// 「仓库一共 6 个」渲染成两个一模一样的绿色 `+6`。
/// 读者会得出「深更新也新增了 6 个提交」—— 而这个数会随仓库一直涨。
///
/// 三种状态必须分开：口径（scope）、是否样本（truncated）、读不出来（nil/-1）。
/// 合并任何两个都会撒谎。
enum CommitCountScope: Equatable {
    /// 本轮新增
    case newCommits
    /// 仓库提交总数
    case repoTotal
    /// 口径未知 —— **不能**默认成上面任何一个
    case unknown
    /// 读不出来（-1）
    case unreadable

    init(raw: String?, commitCount: Int) {
        if commitCount < 0 {
            self = .unreadable
            return
        }
        switch raw {
        case "new": self = .newCommits
        case "repoTotal": self = .repoTotal
        default: self = .unknown
        }
    }

    /// 徽章后缀。空串表示不写任何限定词（那正是 #188 的病症）。
    var suffix: String {
        switch self {
        case .newCommits: return "新增"
        case .repoTotal: return "累计"
        case .unknown: return "口径未知"
        case .unreadable: return "读不出来"
        }
    }

    /// 口径不是「本轮新增」时，徽章不能继续用绿色 ——
    /// 绿色 + 无限定词 = 「这次变好了这么多」，那是把累计量说成增量。
    var isIncremental: Bool { self == .newCommits }
}

/// `+N` 该显示成什么。**纯函数**。
struct CommitCountBadge: Equatable {
    /// nil = 不显示徽章（0 个新增不是一条值得占位的信息）
    let text: String?
    let scope: CommitCountScope
    let truncated: Bool
    /// 必须写进界面的补充说明；nil = 无。
    let note: String?
}

func commitCountBadge(
    commitCount: Int,
    scope: String?,
    truncated: Bool?
) -> CommitCountBadge {
    let s = CommitCountScope(raw: scope, commitCount: commitCount)

    // 读不出来：绝不能显示成 0。-1 是「整个数字没意义」，不是「没提交」。
    if s == .unreadable {
        return CommitCountBadge(text: "提交数读不出来", scope: s, truncated: false,
                               note: "不是「这轮没有提交」")
    }
    // 0 与 -1 都不是徽章要表达的事。
    if commitCount == 0 {
        return CommitCountBadge(text: nil, scope: s, truncated: false, note: nil)
    }

    var notes: [String] = []
    if s == .unknown {
        notes.append("这条的提交数口径没标出来（旧引擎），无法判断是本轮新增还是仓库累计")
    }
    if truncated == true {
        notes.append("这是采样值，不是全量")
    }
    return CommitCountBadge(
        text: "+\(commitCount) \(s.suffix)",
        scope: s,
        truncated: truncated == true,
        note: notes.isEmpty ? nil : notes.joined(separator: "；")
    )
}
