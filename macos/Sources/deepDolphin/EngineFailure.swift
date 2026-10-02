import Foundation

/// 引擎失败载荷的解码。**纯函数，零依赖**。
///
/// 为什么要有它（缺陷 #193）：`EngineCLI.run` 早就知道该怎么处理
/// 「非 0 退出 + stdout 是合法 JSON」——它抛 `EngineError.failedWithPayload`，
/// 把 stdout 原样挂在错误上，注释里原话是
/// 「丢掉 payload 就只剩一句无信息量的『引擎退出码 1』」。
///
/// 可是 `EngineError.jsonPayload` **全仓库零个消费方**。
/// 于是那句注释描述的灾难照旧发生：引擎在 stdout 里把原因写得清清楚楚，
/// 客户端把它整个扔掉，用户和模型只拿到「引擎退出码 1」。
///
/// 实测五种失败载荷（`deepgit <cmd> --json`，非 0 退出）：
///
///   ① `{code,message,details?}` —— update/deep 单项目的 `DOC_WRITE_FAILED`
///      `message` 是「proj 更新失败：进度已记录到 p_xxx，但以下文档未能更新
///      （它们的内容仍是上一轮的）：\n  - README.md：Permission denied」
///   ② `{error:true,code,message}` —— milestone done/drop 找不到时的 `errJson`
///   ③ `{results:[…],count,succeeded,failed}` —— update/deep 全项目
///      （成功的项是 `{ok:true,…}`，失败的项是 ① 的形状，**混在同一个数组里**）
///   ④ `{projects:[…],summary:{failedProjects:N}}` —— status，失败项目自带 `error`
///   ⑤ `{projects:{…,failed:N},…}` —— dashboard，**只有个数没有原因**
///
/// 只有「stdout 空、原因在 stderr」那一种（项目不存在）是好的，
/// 而那一种恰好是唯一不需要本函数就能工作的形状 —— 也就是说
/// 引擎为了迁就客户端，**把重要的失败都写成了「stdout 是 JSON」那种**。
///
/// 另一条独立的洞：usage 类失败（如 `git commit` 缺 `--message`）把原因写在
/// **stdout 的纯文本**里，stderr 另有一句 `✗ proj：commit 失败`。
/// `run` 只把 stdout 当 JSON 试，失败就整份丢 —— 真因掉地上，
/// 用户只看到那句更没信息量的 `✗ proj：commit 失败`。在 EngineCLI 侧修。
enum EngineFailure {

    /// 人类可读的失败原因。**永不为空**。
    ///
    /// `fallback` 是没有载荷时的退路（通常就是 stderr 或退出码文案）。
    /// 载荷里能挖到原因就**必须**用挖到的 —— 这是本函数存在的全部理由。
    static func reason(payload: Data?, fallback: String) -> String {
        guard let payload, !payload.isEmpty else { return nonEmpty(fallback) }
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            // 载荷不是 JSON 对象。**不猜**：交回退路，另加一句「载荷长这样」，
            // 免得下次又是一句无信息量的话。
            let raw = String(data: payload, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty { return nonEmpty(fallback) }
            return "\(nonEmpty(fallback))（引擎输出：\(clip(raw)))"
        }

        // ③④ 批量形状：先处理，因为它的顶层是「成功/失败混合」，
        // 顶层没有 message，只看顶层会把成功的批说成失败。
        if let batch = batchOutcome(obj) { return batch }

        if let msg = nonemptyString(obj["message"]) {
            return decorate(code: obj["code"], message: msg)
        }
        if let msg = nonemptyString(obj["error"]), !(obj["error"] is Bool) {
            return decorate(code: obj["code"], message: msg)
        }
        return nonEmpty(fallback)
    }

    /// 批量载荷里逐项的失败原因（`["ok2 更新失败：…", …]`）。
    ///
    /// 给「要给模型 / 要逐条列给用户」的场合用；只想说一句话用 `reason`。
    /// 形状不是批量的返回空数组 —— 空数组表示「这里没有逐条原因」，
    /// 不是「没有失败」。
    static func batchReasons(_ payload: Data?) -> [String] {
        guard let payload,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let arr = obj["results"] as? [Any] else { return [] }
        return arr.compactMap { item -> String? in
            guard let d = item as? [String: Any] else { return nil }
            guard isFailure(d) else { return nil }
            guard let msg = nonemptyString(d["message"]) else { return nil }
            return decorate(code: d["code"], message: msg)
        }
    }

    /// 这一批里失败了几条。`nil` 表示载荷不是批量的（不是「零失败」）。
    static func batchFailedCount(_ payload: Data?) -> Int? {
        guard let payload,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              obj["results"] is [Any] else { return nil }
        return batchReasons(payload).count
    }

    // MARK: - 内部

    /// 「这个 batch 结果项是不是失败」——**必须与引擎的 `hasErrorOrCode` 同规则**。
    ///
    /// 引擎那一份（`src/util/log.cj`）的判据是：
    ///   有 `ok` 键 ⇒ 不是失败；否则有 `code` 或 `error` ⇒ 失败。
    /// 它的 `failed` 字段就是按这条数出来的，注释原话：
    /// 「失败数必须写出来，不能只靠调用方逐条 isErrorResult 扫 ——
    ///   那是消费方必须重复实现的同一份判定，漏一处就静默把失败读成成功。」
    ///
    /// ⚠️ 所以这里**不许**写成 `ok == true 才算成功`：
    /// 那样客户端会数出比引擎 `failed` 更多的失败项，
    /// 用户看到的「N 个项目失败」和载荷里写的 `failed: M` 对不上 ——
    /// 两个数都在屏幕上，一个来自引擎一个来自客户端，而没人知道该信哪个。
    /// 判据有两份就必然漂移（#192 的教训：清单有几份副本就钉几对）。
    private static func isFailure(_ d: [String: Any]) -> Bool {
        if d.keys.contains("ok") { return false }
        return d.keys.contains("code") || d.keys.contains("error")
    }

    /// ③④⑤ 的摘要。返回 nil 表示「这不是批量形状，也不是采集失败形状」。
    private static func batchOutcome(_ obj: [String: Any]) -> String? {
        // ③ update/deep 全项目：{results, count, succeeded, failed}
        if let arr = obj["results"] as? [Any] {
            let reasons = arr.compactMap { item -> String? in
                guard let d = item as? [String: Any] else { return nil }
                guard isFailure(d) else { return nil }
                guard let msg = nonemptyString(d["message"]) else { return nil }
                return decorate(code: d["code"], message: msg)
            }
            // 个数优先取引擎自己写的 `failed`，不要用 reasons.count ——
            // 后者只是「我们能说清原因的失败数」，引擎明确交代过的那条
            // 没带 message 的失败会被它悄悄漏掉，那才是谎报。
            let failed = intOf(obj["failed"]) ?? reasons.count
            if failed <= 0 {
                // results 全成功却非 0 退出 ⇒ 引擎没给出任何原因。
                // 说「不知道」，别把成功项当失败项报出去。
                return "引擎以非 0 退出但未在载荷里给出失败项"
            }
            return summarize("\(failed) 个项目更新失败", reasons)
        }

        // ④ status：{projects:[…], summary:{failedProjects:N}}，
        //    失败项目自带 error（实测「路径不存在或卷未挂载：…」）。
        if let arr = obj["projects"] as? [Any],
           let summary = obj["summary"] as? [String: Any],
           let n = intOf(summary["failedProjects"]), n > 0 {
            let reasons = arr.compactMap { item -> String? in
                guard let d = item as? [String: Any] else { return nil }
                return nonemptyString(d["error"])
            }
            if reasons.isEmpty {
                return "\(n) 个项目采集失败（引擎未给出逐条原因）"
            }
            return summarize("\(n) 个项目采集失败", reasons)
        }

        // ⑤ dashboard：projects 是**计数对象**不是数组，只有 failed 一个数。
        if let projs = obj["projects"] as? [String: Any],
           let n = intOf(projs["failed"]), n > 0 {
            return "\(n) 个项目采集失败（引擎在此只给了个数，未给逐条原因）"
        }
        return nil
    }

    /// 「N 个项目失败：a；b；c」——超过 4 条就说还剩几条。
    /// 不截断成静默的省略：剩下的条数必须自己说出来。
    private static func summarize(_ head: String, _ reasons: [String]) -> String {
        let show = reasons.prefix(4).map { clip($0) }
        var s = "\(head)：" + show.joined(separator: "；")
        if reasons.count > show.count {
            s += "；…另有 \(reasons.count - show.count) 个失败"
        }
        return s
    }

    private static func decorate(code: Any?, message: String) -> String {
        if let c = nonemptyString(code) { return clip("\(c)：\(message)") }
        return clip(message)
    }

    private static func nonemptyString(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func intOf(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    /// 引擎的单条消息可能带换行（DOC_WRITE_FAILED 就是多行的）。
    /// 通知栏一行放不下，但也不能把中间截成看不出所以然 —— 换行换成「 / 」。
    private static func clip(_ s: String) -> String {
        let flat = s
            .replacingOccurrences(of: "\n", with: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= 300 ? flat : String(flat.prefix(300)) + "…"
    }

    private static func nonEmpty(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "引擎失败（无详细信息）" : clip(t)
    }
}
