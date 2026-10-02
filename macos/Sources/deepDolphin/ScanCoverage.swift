import Foundation

/// 扫描结果的覆盖度披露。**纯函数，零依赖**。
///
/// 为什么单独成文件（引擎侧对应缺陷 #197 的第二个出口）：
/// `ScanSheet` 原来只读 `added` / `existing` / `found` 三个数，
/// 于是 `found == 0` 一律渲染成「—— 该目录树里没有 git 仓库」。
/// 而「没看完」有三种成因，引擎全都发了出来，客户端**一个都没读**：
///   · `truncated`    —— 撞到目录上限
///   · `unreadable`   —— 有目录读不出来（引擎侧 #179）
///   · `depthCapped`  —— 撞到 `--depth` 上限且下面还有目录没看（#197）
///
/// 实测（`ScanSheet` 的默认深度就是 **2**）：
///     扫描一棵仓库在第 4 层的目录树 → found=0、depthCapped=true
///     界面显示「新增 0 个 / 共发现 0 个 —— 该目录树里没有 git 仓库」
/// 仓库就在那儿。这与引擎侧 #197 是**同一个谎**，只是换了个出口说。
///
/// 顺带一提：客户端的深度 Stepper 范围是 `1...6`，所以**不会**触发
/// 引擎新增的「`--depth < 1` 报错」守卫 —— 那边是给 CLI 用的。
///
/// 三种「没看完」必须分开说，因为**处置方式不同**：
///   · 撞到深度上限   → 加深度
///   · 撞到目录上限   → 分根扫描
///   · 目录读不出来   → 查权限
/// 合并成一句「没扫完」等于让用户自己猜。
enum ScanCoverage {
    /// 一次扫描的覆盖情况。`nil` 表示「这个键没有」——
    /// 与「明确说是 false」是两件事，不得合并。
    struct Input {
        let found: Int
        let truncated: Bool?
        let depthCapped: Bool?
        let unreadable: Int?
    }

    /// 从引擎 `scan --json` 的响应里读出覆盖情况。读不到的键一律 nil。
    static func input(from obj: [String: Any]) -> Input {
        Input(
            found: (obj["found"] as? Int) ?? 0,
            truncated: obj["truncated"] as? Bool,
            depthCapped: obj["depthCapped"] as? Bool,
            unreadable: (obj["unreadable"] as? [Any])?.count
        )
    }

    /// 该在界面上附加的那句披露。没有要说的事返回 nil（**不返回空串** ——
    /// 空串会被拼成「…… 」这种看起来像残缺的话）。
    static func note(_ i: Input) -> String? {
        var why: [String] = []
        if i.depthCapped == true {
            why.append("撞到扫描深度上限，下面还有目录没看")
        }
        if i.truncated == true {
            why.append("撞到目录数量上限")
        }
        if let n = i.unreadable, n > 0 {
            why.append("\(n) 个目录读不出来（无权限或 I/O 错误）")
        }
        if why.isEmpty { return nil }

        // 「没看完」和「没有」是两个结论，必须在**同一句**里说清。
        // 原来只说「该目录树里没有 git 仓库」，等于替用户断言了一个
        // 引擎没有验证过的结论。
        if i.found == 0 {
            return "本次**未**扫完（" + why.joined(separator: "，") +
                "）—— 上面「共发现 0 个」只代表已访问的那部分里没有，**不是**这棵树里没有"
        }
        return "本次**未**扫完（" + why.joined(separator: "，") + "）—— 上面列出的不是全部"
    }
}
