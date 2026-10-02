// PathInput.swift — 用户给的路径，在发给引擎之前该先过一遍什么。
//
// 为什么不直接 `TextField` 里取字符串就 `add`：
//
// **引擎做什么、不做什么（2026-10-01 对 moonGit/target/release/bin/main 实测）**
//
//   输入                       引擎行为
//   ─────────────────────────────────────────────────────────────
//   /abs/path                  ✓ 规范化（/tmp → /private/tmp）
//   /abs/path/                 ✓ 消解尾斜杠
//   ~/sub                      ✓ **自己展开 ~**
//   "  /abs/path  "（首尾空格）  ✗ 直接失败
//   rel/path（相对）            ✗ 相对**引擎进程的 CWD** 解析
//
// 所以客户端真正要负责的只有两件：**去掉首尾空白**、**拒绝相对路径**。
// `~` 和尾斜杠刻意**不**在客户端展开 —— 重复实现一遍只会引入第二套
// 可能与引擎不一致的规则（这正是「三处手写拷贝」那族缺陷）。
//
// 最后一条最阴险：相对路径的解析基准是子进程的 CWD，
// 那个目录用户根本看不见也改不了。实测 `add "work/myproj"` 会去
// `/private/tmp/.../myproj/work/myproj` 找 —— 报错信息里两个路径拼在一起，
// 完全指不出错在哪。与其猜一个基准目录，不如**明确拒绝并说清楚**。
//
// 无 SwiftUI 依赖，因此可以被检查程序直接编译来测。
import Foundation

/// 一条路径能不能直接发给引擎，以及不能的话为什么。
struct PreparedPath: Equatable {
    /// 可以直接发给引擎的路径；不可用时为空串。
    let path: String
    /// 不可用的原因；可用时为 nil。**必须说清楚**，不能只显示"无效路径"——
    /// 用户改哪个字段、改成什么样，全靠这句话。
    let problem: String?

    var isUsable: Bool { path.isEmpty == false }
}

/// 路径在磁盘上是什么。
///
/// 为什么是三态而不是 Bool（`isDirectory: (String) -> Bool`）：
/// 有了 Bool 就分不出「不存在」和「存在但是个文件」，于是两种完全不同的
/// 错误被压成同一句「不是文件夹」。用户拿着「不是文件夹」去检查，
/// 而真相是「那个路径压根不存在」—— 又是**误导性诊断**。
/// 「我们不知道」≠「不是」，这条在引擎侧已经栽了 16 次，这里不能再来一次。
enum PathKind: Equatable {
    case missing
    case file
    case directory
}

enum PathInput {

    /// 把用户输入（文本框 / 拖放）整理成能发给引擎的路径。
    ///
    /// 纯函数：不碰文件系统、不碰全局状态、不读环境变量。
    /// `home` 只在需要判断 `~` 是否**独自出现**时用得上（那是要提示的情况）。
    static func prepare(_ raw: String) -> PreparedPath {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            return PreparedPath(path: "", problem: "路径为空")
        }

        // 相对路径：引擎会拿子进程 CWD 当基准，而那个目录用户看不见。
        // 与其替用户猜一个基准，不如拒绝并说明。
        if !s.hasPrefix("/") && !s.hasPrefix("~") {
            return PreparedPath(
                path: "",
                problem: "「\(s)」是相对路径。请填绝对路径（以 / 开头），"
                       + "或用「选择…」按钮直接挑一个文件夹。"
            )
        }

        // 纯 `~`：展开不了，得让用户知道。`~/x` 交给引擎（它自己会展开）。
        if s == "~" || s == "~/" {
            return PreparedPath(path: "", problem: "「~」是家目录本身，请选一个具体的文件夹")
        }

        // 尾斜杠引擎会消解，但这里顺手收掉，免得日志里出现 `//`。
        var out = s
        while out.count > 1 && out.hasSuffix("/") { out.removeLast() }

        return PreparedPath(path: out, problem: nil)
    }

    /// 从一次拖放给出的候选里挑出**第一个文件夹**。
    ///
    /// 为什么要挑而不是全要：
    ///   · 「添加单个项目」一次只能加一个，多选时静默丢掉其余 = 用户以为都加上了
    ///   · 拖进来的常常混着文件和文件夹（从下载目录拖、从桌面拖）
    ///   · 批量扫描本来就该用「扫描根目录」那个模式
    /// 所以取第一个文件夹，并把**为什么不是别的**说清楚。
    ///
    /// `classify` 由调用方注入 —— 这样本函数不碰文件系统，可测。
    static func pickDirectory(
        among candidates: [String],
        classify: (String) -> PathKind
    ) -> PreparedPath {
        if let first = candidates.first(where: { classify($0) == .directory }) {
            return prepare(first)
        }
        if candidates.isEmpty {
            return PreparedPath(path: "", problem: "没收到任何路径")
        }
        // 候选都在，但没有一个是文件夹。这和"什么都没拖"是两件事，别混成一句话。
        let missing = candidates.filter { classify($0) == .missing }
        let reason = missing.isEmpty
            ? "拖进来的不是文件夹"
            : "拖进来的 \(candidates.count) 个里没有文件夹（\(missing.count) 个路径不存在）"
        return PreparedPath(
            path: "",
            problem: "\(reason)。要添加单个项目，请拖一个文件夹进来。"
        )
    }

    /// 扫描模式下要求路径是一个**已存在的文件夹**。
    ///
    /// 引擎的 scan 收的是根目录；给它一个文件会得到 `dirsVisited: 0` 与
    /// `found: 0` 的"正常"结果 —— 看起来像"这个目录里没有 git 仓库"，
    /// 而真相是"你给的根本不是目录"。先在这里拦下来。
    static func validateScanRoot(_ raw: String, classify: (String) -> PathKind) -> PreparedPath {
        let p = prepare(raw)
        guard p.isUsable else { return p }
        switch classify(p.path) {
        case .directory:
            return p
        case .file:
            return PreparedPath(
                path: "",
                problem: "「\(p.path)」是个文件。扫描需要一个文件夹作为根。"
            )
        case .missing:
            // 单独说一句，因为这是最常见的一种（路径敲错、目录被删、没选全）。
            return PreparedPath(
                path: "",
                problem: "「\(p.path)」不存在。用「选择…」按钮挑一个真实存在的文件夹。"
            )
        }
    }
}
