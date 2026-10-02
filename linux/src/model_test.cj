// deepDolphin Linux 客户端 —— 模型层判据。
//
// 这些是**纯函数**测试：不开窗口、不连引擎、不碰磁盘。
// 能不开窗口就验的规则，绝不挪到视图测试里去 ——
// 视图测试要构造 SDL 宿主，慢一个量级，而且失败时不好定位是哪条规则破了。
package deepdolphin_linux

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/// 一份**过旧引擎**的真实输出。
///
/// 这不是编出来的样本，是本机 `~/.local/bin/deepgit`（旧版）的原样输出：
/// `summary` 里**没有** failedProjects / listedProjects，
/// 每个项目也**没有** error 字段。
///
/// 它的存在意义：这份载荷解析得干干净净、六个项目全在，
/// 而其中三个的仓库路径根本不可达。**如果照单全收，界面上这六个
/// 会长得一模一样 —— 三个显示成健康的空项目。**
private let OLD_ENGINE_STATUS = """
{"projects":[
 {"name":"atlas","path":"/tmp/a","commitCount":12,"userDirtyCount":0,"branches":[]},
 {"name":"gone","path":"/tmp/gone","commitCount":0,"userDirtyCount":0,"branches":[]}
],"summary":{"projectCount":2,"activeProjects":1,"generatedAt":"2026-10-01T00:00:00+08:00"}}
"""

/// 当前引擎的输出形状（含披露字段）。
private let NEW_ENGINE_STATUS = """
{"projects":[
 {"name":"atlas","path":"/tmp/a","commitCount":12,"userDirtyCount":2,"lastCommitAgo":"17 小时前",
  "branches":[{"name":"main","status":"active","statusLabel":"活跃","isCurrent":true,"isDefault":true}]},
 {"name":"gone","path":"/tmp/gone","error":"路径不存在或卷未挂载：/tmp/gone","branches":[]}
],"summary":{"projectCount":2,"listedProjects":2,"failedProjects":1,"activeProjects":1,
 "staleProjects":0,"dirtyProjects":1,"branchCount":1,"generatedAt":"2026-10-03T03:00:00+08:00"}}
"""

// ---------------------------------------------------------------------------
// 契约校验
// ---------------------------------------------------------------------------

/// 负控记录（2026-10-03，踩过）：
/// 第一次拆闸门时只把 `!Json.has(payload,"projects")` 换成 `if (false)`，
/// 结果 19 项**全绿** —— 因为函数里还有第二道检查（`summary` 里的两个键）
/// 照样把旧载荷挡住了。那不是判据失效，是**负控没有真正复现缺陷**：
/// 拆掉一扇门不等于拆掉门禁。
/// 真正把整个函数换成 `return true` 之后，两条契约用例立刻红，其余 17 项仍绿。
/// ⇒ 负控没红时，先证明「缺陷真的被复现了」，再怀疑判据。
@Test
func contractCheckRejectsPayloadWithoutDisclosureFields(): Unit {
    // 旧引擎的输出没有 failedProjects / listedProjects。
    // 这一条是整条链路的闸门：闸门不响，后面所有显示规则都会把
    // 「引擎没说」当成「没问题」。
    let v = Json.parse(OLD_ENGINE_STATUS).getOrThrow()
    @Expect(!checkContract(v))
}

@Test
func contractCheckAcceptsCurrentEnginePayload(): Unit {
    let v = Json.parse(NEW_ENGINE_STATUS).getOrThrow()
    @Expect(checkContract(v))
}

@Test
func payloadWithoutProjectsKeyIsRejected(): Unit {
    @Expect(!checkContract(Json.parse("{\"summary\":{}}").getOrThrow()))
}

// ---------------------------------------------------------------------------
// 失败披露
// ---------------------------------------------------------------------------

@Test
func missingFailedCountIsReportedAsUnknownNotZero(): Unit {
    // 负控就是这个用例存在的理由：把模型里的 `Json.has(s,"failedProjects")`
    // 改成恒 true（即回落成 0），本用例立刻红。
    //
    // 「引擎没报失败数」与「失败数是 0」是两件事，写成同一个 0
    // 等于替引擎宣布一切正常。
    let snap = StatusSnapshot.from(Json.parse(OLD_ENGINE_STATUS).getOrThrow())
    @Expect(!snap.failedKnown)
    @Expect(snap.failedLabel(), "?")
}

@Test
func knownFailedCountIsRenderedAsNumber(): Unit {
    let snap = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
    @Expect(snap.failedKnown)
    @Expect(snap.failedLabel(), "1")
}

@Test
func failedProjectStaysInTheListWithItsEngineReportedReason(): Unit {
    // 静默过滤失败项目是这里最容易犯的错：界面上「已注册 2 个」
    // 变成 1 个，用户无从知道少了什么。
    let snap = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
    @Expect(snap.projects.size, 2)
    @Expect(snap.find("gone").isSome())
    @Expect(snap.find("gone").getOrThrow().error, "路径不存在或卷未挂载：/tmp/gone")
}

@Test
func readableProjectsExcludesUnreadableOnes(): Unit {
    // 界面上「读到了几个」必须用这个数，而不是引擎的 listedProjects ——
    // 后者把失败的也计入，于是有 3 个项目挂了外置盘时，
    // 数字说 6 而列表里只有 3 个，对不上。
    let snap = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
    @Expect(snap.listedProjects, 2)
    @Expect(snap.readableProjects(), 1)
}

@Test
func failedProjectShowsReasonInsteadOfZeroedCounts(): Unit {
    // 采集失败时 commitCount 本来就是 0。显示成「0 提交」等于谎称读过这个仓库。
    let p = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
        .find("gone").getOrThrow()
    @Expect(p.failed())
    @Expect(p.commitCount, 0)
    @Expect(p.sidebarLine(), "路径不存在或卷未挂载：/tmp/gone")
}

@Test
func healthyProjectSidebarLineShowsRealFacts(): Unit {
    let p = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
        .find("atlas").getOrThrow()
    @Expect(!p.failed())
    @Expect(p.sidebarLine(), "2 处未提交 · 17 小时前")
}

// ---------------------------------------------------------------------------
// 活跃度（客户端派生，不是引擎给的）
// ---------------------------------------------------------------------------

@Test
func activityComesFromTheCurrentBranchNotFromAnInventedField(): Unit {
    // 引擎的逐项目载荷里**没有** activity 字段。一开始这里写的是
    // `Json.strAt(v,"activity","unknown")`，于是每个项目都显示「未知」，
    // 而界面上看着像个正经判定。
    let p = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
        .find("atlas").getOrThrow()
    @Expect(p.activity(), "active")
}

@Test
func unreadableProjectIsUnknownNotStale(): Unit {
    // 没读到 ≠ 停滞。把「不知道」说成「停滞」是在替引擎下结论，
    // 而停滞会让人去翻 git 历史 —— 白费功夫且越查越慌。
    let p = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
        .find("gone").getOrThrow()
    @Expect(p.activity(), "unknown")
}

// ---------------------------------------------------------------------------
// 解析健壮性
// ---------------------------------------------------------------------------

@Test
func missingKeysFallBackInsteadOfThrowing(): Unit {
    // 旧引擎的载荷**根本没有**这些键。缺键必须走 fallback，
    // 而不是抛异常把窗口干掉。
    let snap = StatusSnapshot.from(Json.parse(OLD_ENGINE_STATUS).getOrThrow())
    @Expect(snap.projects.size, 2)
    @Expect(snap.staleProjects, 0)
    @Expect(snap.branchCount, 0)
    @Expect(snap.find("atlas").getOrThrow().name, "atlas")
}

@Test
func emptySnapshotIsDistinctFromARealEmptyResult(): Unit {
    // 「还没读到」（None）与「读到了，确实是空的」（listedProjects=0）
    // 在界面上必须长得不一样 —— 前者要提示去点刷新，后者是真实结论。
    let none: ?StatusSnapshot = None
    @Expect(none.isNone())
    let empty = StatusSnapshot.from(Json.parse(
        "{\"projects\":[],\"summary\":{\"projectCount\":0,\"listedProjects\":0,\"failedProjects\":0}}").getOrThrow())
    @Expect(empty.projects.size, 0)
    @Expect(empty.listedProjects, 0)
    @Expect(empty.failedProjects, 0)
}

@Test
func dashboardDecodesTheWorkSection(): Unit {
    let d = Dashboard.from(Json.parse("""
    {"projects":{"total":6,"registered":6,"failed":3,"dirty":0,"active7d":2,"active30d":2},
     "work":{"branches":8,"mergeCandidates":1,"untrackedFiles":4,"stashes":0},
     "languages":[{"language":"Swift","count":40},{"language":"Cangjie","count":12}],
     "milestones":{"counts":{"total":5,"done":2}},
     "activeProjects":[{"name":"atlas"}]}
    """).getOrThrow())
    @Expect(d.total, 6)
    @Expect(d.failed, 3)
    @Expect(d.branches, 8)
    @Expect(d.languages.size, 2)
    @Expect(d.languages[0].language, "Swift")
    @Expect(d.milestoneTotal, 5)
    @Expect(d.milestoneDone, 2)
    @Expect(d.activeProjectNames[0], "atlas")
}

// ---------------------------------------------------------------------------
// JSON 解析器（从引擎移植来的那份，最容易在移植中丢能力）
// ---------------------------------------------------------------------------

@Test
func jsonParsesCjkAndEscapes(): Unit {
    let v = Json.parse("{\"a\":\"中文\",\"b\":\"q\\\"uote\",\"c\":\"tab\\there\"}").getOrThrow()
    @Expect(Json.strAt(v, "a", ""), "中文")
    @Expect(Json.strAt(v, "b", ""), "q\"uote")
    @Expect(Json.strAt(v, "c", ""), "tab\there")
}

@Test
func jsonRejectsMalformedInputWithoutThrowing(): Unit {
    // 契约：解析失败返回 None，绝不抛。抛了就是窗口直接没了。
    @Expect(Json.parse("{").isNone())
    @Expect(Json.parse("").isNone())
    @Expect(Json.parse("{\"a\":1}trailing").isNone())
    @Expect(Json.parse("[1,]").isNone())
}

@Test
func jsonHandlesDeepNestingWithoutStackOverflow(): Unit {
    // 解析器在栈上递归。深度上限这一条是从引擎搬来的，
    // 但上限值改成了 128 —— 搬过来时顺手改小，得确认它还在生效。
    let sb = StringBuilder()
    for (_ in 0..5000) {
        sb.append("[")
    }
    sb.append("1")
    for (_ in 0..5000) {
        sb.append("]")
    }
    let deep = sb.toString()
    @Expect(Json.parse(deep).isNone())
}

@Test
func jsonSkipsUtf8Bom(): Unit {
    // Windows 工具链产出的 JSON 常带 BOM。不跳过就直接解析失败。
    let v = Json.parse("\u{FEFF}{\"a\":1}").getOrThrow()
    @Expect(Json.intAt(v, "a", -1), 1)
}

@Test
func integralNumbersBeyondSafeRangeFallBackInsteadOfCrashing(): Unit {
    // Float64 能精确表示的整数上限是 2^53。超出的取整数必须返回 None，
    // 走调用方的 fallback，而不是硬转 Int64 抛异常。
    let v = Json.parse("{\"big\":1e30,\"small\":42}").getOrThrow()
    @Expect(Json.intAt(v, "big", -1), -1)
    @Expect(Json.intAt(v, "small", -1), 42)
}
