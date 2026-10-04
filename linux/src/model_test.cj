// deepDolphin Linux 客户端 —— 模型层判据。
//
// 这些是**纯函数**测试：不开窗口、不连引擎、不碰磁盘。
// 能不开窗口就验的规则，绝不挪到视图测试里去 ——
// 视图测试要构造 SDL 宿主，慢一个量级，而且失败时不好定位是哪条规则破了。
// （例外：T1 确认 Modal 的两条「镜头」判据用框架的 `WidgetTestHost` ——
// 它是无头事务宿主，不开真窗，成本与普通判据同量级。）
package deepdolphin_linux

import std.collection.*
import std.math.*
import std.unittest.*
import std.unittest.testmacro.*
import cui.testing.WidgetTestHost
import sdl.{Key, Rect, UiEvent}

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
     "milestones":{"counts":{"open":3,"done":2,"readCount":5,"storeHealth":"ok","degraded":false}},
     "activeProjects":[{"name":"atlas"}]}
    """).getOrThrow())
    @Expect(d.total, 6)
    @Expect(d.failed, 3)
    @Expect(d.branches, 8)
    @Expect(d.languages.size, 2)
    @Expect(d.languages[0].language, "Swift")
    // ⚠ 引擎**不发** counts.total。原来这条判据写的是 @Expect(d.milestoneTotal, 5)，
    // 而夹具里正好编了那个不存在的键 —— 于是模型恒读成 0，判据却一直绿。
    @Expect(d.milestoneCounts.readCount, 5)
    @Expect(d.milestoneCounts.done, 2)
    @Expect(d.milestoneCounts.decided(), 5)
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

// ---------------------------------------------------------------------------
// 字体选择
// ---------------------------------------------------------------------------

@Test
func fontPickerTakesTheFirstPresentCandidateInPreferenceOrder(): Unit {
    // 候选表已按偏好排序，所以要的是**第一个**存在的，
    // 不是最后一个、更不是任意一个 —— 取后者等于把顺序写反，
    // 装了什么字体就取决于文件系统的枚举顺序。
    let cands = ["/a.ttf", "/b.ttf", "/c.ttf"]
    @Expect(pickFontFile(cands, {p => p == "/b.ttf"}).getOrThrow(), "/b.ttf")
    @Expect(pickFontFile(cands, {p => p == "/a.ttf"}).getOrThrow(), "/a.ttf")
    @Expect(pickFontFile(cands, {p => p == "/c.ttf"}).getOrThrow(), "/c.ttf")
}

@Test
func fontPickerReturnsNoneWhenNoCandidateExists(): Unit {
    // 负控：把这个改成 `return Some(candidates[0])`（即「反正挑一个」），
    // `installAppFonts` 就会注册一个不存在的字体，
    // 而失败点在 FreeType 里，表现为「什么都没发生」——
    // 界面照常开着，只是中文全是豆腐块。
    @Expect(pickFontFile(["/a.ttf", "/b.ttf"], {p => false}).isNone())
    @Expect(pickFontFile(Array<String>(), {p => true}).isNone())
}

@Test
func cjkCandidateListCarriesFilesForAllThreePlatforms(): Unit {
    // 判据钉的是「三个平台各至少有一个候选」，不是具体路径 ——
    // 路径会随发行版变，规则不该因此变红。
    let all = cjkFontCandidates()
    @Expect(all.contains("/System/Library/Fonts/Hiragino Sans GB.ttc"))
    @Expect(all.contains("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"))
    @Expect(all.contains("C:/Windows/Fonts/msyh.ttc"))
}

// ---------------------------------------------------------------------------
// 设计令牌：与 macOS 端逐值对齐
// ---------------------------------------------------------------------------

/// 判据钉的是**取值本身**，不是「有没有这些常量」。
///
/// 为什么这条必须存在：两端各有一份色板（`DesignTokens.swift` / `tokens.cj`），
/// 而它们之间**没有任何编译期或运行期的联系**。改了 macOS 端、
/// Linux 端不会红；改了 Linux 端、macOS 端不会红。
/// 后果是同一个「活跃」在两端是两个绿 —— 用户以为是两件事。
///
/// 负控：把 `C_SHALLOW` 改成 `0x22C55E`（另一个绿），
/// 本条立刻红；而其它 20 条全绿 —— 因为没有别的判据看这个值。
@Test
func sequenceAndAccentColorsMatchMacOSTokens(): Unit {
    // DSPalette.accent / shallow / deep / ai
    @Expect(C_ACCENT == 0x3B82F6)
    @Expect(C_SHALLOW == 0x10B981)
    @Expect(C_DEEP == 0x8B5CF6)
    @Expect(C_AI == 0x06B6D4)
}

/// 两套色板的表面色。两端各四个，一个都不能错。
@Test
func surfacePaletteMatchesMacOSTokens(): Unit {
    @Expect(BG_DARK == 0x0F172A)
    @Expect(CARD_DARK == 0x1E293B)
    @Expect(SIDEBAR_DARK == 0x0B0F19)
    @Expect(BORDER_DARK == 0x334155)
    @Expect(BG_LIGHT == 0xF8FAFC)
    @Expect(CARD_LIGHT == 0xFFFFFF)
    @Expect(SIDEBAR_LIGHT == 0xF1F5F9)
    @Expect(BORDER_LIGHT == 0xE2E8F0)
}

/// 间距刻度。**刻度必须只有 4/8/12/16/20/24**，
/// 出现第 7 个散值就说明有人开始随手写字面量了。
@Test
func spacingScaleIsTheSixDesignValues(): Unit {
    @Expect(SP_XS == 4.0)
    @Expect(SP_SM == 8.0)
    @Expect(SP_MD == 12.0)
    @Expect(SP_LG == 16.0)
    @Expect(SP_XL == 20.0)
    @Expect(SP_XXL == 24.0)
}

@Test
func radiusScaleIsTheThreeDesignValues(): Unit {
    @Expect(R_CHIP == 3.0)
    @Expect(R_CONTROL == 6.0)
    @Expect(R_CARD == 10.0)
}

/// 状态映射：五个已知档各自落对，未知一律 Unknown。
///
/// 这条钉的是**关系**（哪个状态落哪档），不是字面量 ——
/// 换一套颜色只要关系不变就不该红。
@Test
func statusMappingCoversKnownValuesAndRefusesToGuess(): Unit {
    @Expect(dsStatusIs(dsStatusFrom("active"), DsStatus.Active))
    @Expect(dsStatusIs(dsStatusFrom("idle"), DsStatus.Idle))
    @Expect(dsStatusIs(dsStatusFrom("stale"), DsStatus.Stale))
    @Expect(dsStatusIs(dsStatusFrom("merged"), DsStatus.Merged))
    @Expect(dsStatusIs(dsStatusFrom("dirty"), DsStatus.Dirty))
    // 没读懂的字符串不许落进「活跃」
    @Expect(dsStatusIs(dsStatusFrom("weird"), DsStatus.Unknown))
    @Expect(dsStatusIs(dsStatusFrom(""), DsStatus.Unknown))
}

/// 量级分档，**含负数**。
///
/// 负数不是 0 —— 负数意味着数据本身有问题，
/// 落进「干净」档是最坏的一种说谎。
@Test
func statSeverityGradesByMagnitudeAndTreatsNegativeAsWorst(): Unit {
    @Expect(dsStatIs(dsStatFrom(0), DsStat.Clean))
    @Expect(dsStatIs(dsStatFrom(1), DsStat.Low))
    @Expect(dsStatIs(dsStatFrom(2), DsStat.Low))
    @Expect(dsStatIs(dsStatFrom(3), DsStat.Medium))
    @Expect(dsStatIs(dsStatFrom(9), DsStat.Medium))
    @Expect(dsStatIs(dsStatFrom(10), DsStat.High))
    @Expect(dsStatIs(dsStatFrom(10000), DsStat.High))
    @Expect(dsStatIs(dsStatFrom(-1), DsStat.High))
    @Expect(dsStatIs(dsStatFrom(-999), DsStat.High))
}

/// 序列色 12 档**两两不同**。
///
/// ⚠ 这条是为了钉住一个已经犯过的错：第 4 档与第 9 档都填了紫、
/// 第 5 档与第 11 档都填了青。后果不是「不够好看」，是同一根分段条上
/// 两段同色、图例里两行同色圆点，读者根本分不出那是两类。
///
/// 负控：把第 9 档改回 `C_DEEP`，本条立刻红。
@Test
func sequencePaletteHasNoDuplicateColors(): Unit {
    let pal = dsSequencePalette()
    @Expect(pal.size == 12)
    @Expect(DS_SEQUENCE_SLOTS == 12)
    for (i in 0..pal.size) {
        for (j in (i + 1)..pal.size) {
            @Expect(pal[i] != pal[j])
        }
    }
}

/// 取模回绕：序号超出色板长度时回到 0，而不是越界。
@Test
func sequenceColorWrapsInsteadOfGoingOutOfRange(): Unit {
    @Expect(dsSequenceColor(0) == dsSequenceColor(12))
    @Expect(dsSequenceColor(0) == dsSequenceColor(24))
    @Expect(dsSequenceColor(-1) == C_GRAY)
}

/// 提交构成的**两条**截断披露都要说。
///
/// 只披露一条就是撒谎：引擎给全量而界面藏起一半，
/// 读者会把看到的 8 种当成这个项目的全部提交类型。
/// 一份**真的会触发两条截断**的载荷：引擎采样窗口截断，
/// 而且引擎给了 11 种类型（超过界面 8 档的上限）。
private let TRUNCATED_COMMIT_TYPES = """
{"projects":[
 {"name":"wide","path":"/tmp/wide","commitCount":240,"commitTypesTruncated":true,
  "commitTypes":[
   {"type":"feat","count":9},{"type":"fix","count":12},{"type":"docs","count":7},
   {"type":"refactor","count":5},{"type":"perf","count":3},{"type":"test","count":6},
   {"type":"chore","count":4},{"type":"build","count":3},{"type":"ci","count":2},
   {"type":"style","count":1},{"type":"revert","count":1}
  ],"branches":[]}
],
"summary":{"projectCount":1,"listedProjects":1,"failedProjects":0,"activeProjects":1,
 "staleProjects":0,"dirtyProjects":0,"branchCount":0,"generatedAt":"2026-10-03T03:00:00+08:00"}}
"""

/// 提交构成的**两条**截断披露都要说。
///
/// 引擎的采样窗口（`commitTypesTruncated`）与界面的显示上限（只列前 8 种）
/// 是两条**独立**的轴，少披露一条就是撒谎：读者会把看到的 8 种
/// 当成这个项目的全部提交类型。
///
/// ⚠ 负控记录：这条判据的**第一版**用的是 `NEW_ENGINE_STATUS` ——
/// 那份夹具里根本没有 `commitTypes` 字段，于是 `notes` 恒为空、
/// 判据红了。查下来是**负控/夹具没复现场景**，不是代码错。
/// 换成 `TRUNCATED_COMMIT_TYPES`（真带 11 种 + 采样截断）才测得到东西。
@Test
func commitTypeDisclosureCoversBothTruncationAxes(): Unit {
    let snap = StatusSnapshot.from(Json.parse(TRUNCATED_COMMIT_TYPES).getOrThrow())
    let p = snap.projects[0]

    // 界面只列前 8 种（显示上限）
    @Expect(commitTypeParts(p).size == 8)
    // 引擎一共给了 11 种（采样上限）
    @Expect(p.commitTypes.size == 11)

    let notes = commitTypeNotes(p, commitTypeParts(p).size)
    // 两条轴 → 至少两条披露
    @Expect(notes.size == 2)
    // 第一条说采样窗口，并写出分母
    @Expect(notes[0].contains("采样"))
    @Expect(notes[0].contains("/240"))
    // 第二条说界面自己砍了几种
    @Expect(notes[1].contains("8"))
    @Expect(notes[1].contains("11"))
}

/// 引擎没截断、类型也没超上限时**不该**有披露。
/// 多余的披露和缺失的披露一样是噪声：每张卡都挂一句「本卡只列前 8 种」
/// 而实际只列了 3 种，用户会以为还有 5 种被藏起来了。
@Test
func commitTypeDisclosureStaysSilentWhenNothingIsCut(): Unit {
    let s = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
    let p = s.projects[0]
    // 这份夹具没有 commitTypes，引擎也没报截断
    @Expect(p.commitTypes.size == 0)
    @Expect(!p.commitTypesTruncated)
    @Expect(commitTypeNotes(p, 0).size == 0)
}

/// 非 git 项目。真实引擎对它给的是 `summary` 空串 + 一条 note，
/// 而这条 note 是**唯一**说明「为什么提交数是 0」的地方。
private let NON_GIT_OVERALL = """
{"name":"plainly","path":"/tmp/dg-src/plainly","kind":"dir","storeHealth":"ok",
 "userDirtyCount":1,"stashCount":0,"commitCount":0,"branches":[],
 "overall":{"summary":"","notes":["非 git 仓库：进度基于文件活动时间，不含提交历史"]}}
"""

/// 真实引擎逐字截取的一个项目（`d2note`），
/// 保留 `overall` 的两个键与 `commitTypes` 的形状。
private let REAL_OVERALL_PROJECT = """
{"storeHealth":"ok","name":"d2note","path":"/tmp/d2note","kind":"git",
 "remote":"https://github.com/asdshuaishuai/d2note.git","tags":[],"headline":"main: 闲置 · 1 处未提交",
 "currentBranch":"main","defaultBranch":"main","userDirtyCount":1,"stashCount":0,"commitCount":6,
 "lastCommitAt":"2026-09-25T00:58:31+08:00","lastCommitAgo":"8 天前",
 "commitTypes":[{"type":"feat","count":1},{"type":"fix","count":2},{"type":"docs","count":1},{"type":"other","count":2}],
 "commitTypesTruncated":false,"repoBranchCount":1,
 "overall":{"summary":"最近 6 个提交：修复×2、更新×1、新增×1","notes":["工作区有 1 处未提交改动"]},
 "branches":[]}
"""

/// 采集失败时引擎把 `overall` 发成**空对象 `{}`**，不是缺这个键。
/// 这一条盯的是它与「非 git 项目」的区别：
/// 两者在 `summary` 上都是空串，**只有 notes 能分开** ——
/// 分不开的话，「读不出来」和「确实没有提交历史」在界面上长得一模一样。
private let EMPTY_OVERALL_PROJECT = """
{"storeHealth":"ok","name":"gone","path":"/tmp/gone","kind":"dir",
 "error":"路径不存在或卷未挂载：/tmp/gone","userDirtyCount":-1,"stashCount":-1,"commitCount":-1,
 "branches":[],"overall":{}}
"""

// ---------------------------------------------------------------------------
// overall.notes —— 引擎算了、界面不说的那批事实
// ---------------------------------------------------------------------------

@Test
func engineNotesReachTheModelBecauseTheyCarryFactsNothingElseSays(): Unit {
    // 实测的两种文案：未提交计数、stash 清理提醒。
    // 后者尤其要紧：界面上有 stash 的**数字**，但「注意清理」这半句
    // 只存在于引擎的 note 里 —— 引擎算了、模型收了、界面不说 ⇒ 等于没算。
    let p = Project.from(Json.parse(REAL_OVERALL_PROJECT).getOrThrow())
    @Expect(p.overallNotes.size == 1)
    @Expect(p.overallNotes[0].contains("未提交"))
    @Expect(p.overallSummary.contains("最近 6 个提交"))
}

@Test
func anEmptyOverallObjectIsNotTheSameAsANonGitProject(): Unit {
    // ⚠ 这两个在 `summary` 上都是空串。唯一能分开它们的是 notes。
    let unreadable = Project.from(Json.parse(EMPTY_OVERALL_PROJECT).getOrThrow())
    let nonGit = Project.from(Json.parse(NON_GIT_OVERALL).getOrThrow())
    @Expect(unreadable.overallSummary.isEmpty())
    @Expect(nonGit.overallSummary.isEmpty())
    // 读不出来 → 没有任何 note
    @Expect(unreadable.overallNotes.isEmpty())
    // 非 git → 有一条**解释性** note
    @Expect(nonGit.overallNotes.size == 1)
    @Expect(nonGit.overallNotes[0].contains("非 git 仓库"))
}

// ---------------------------------------------------------------------------
// overall.summary 的补位规则（macOS 端 DetailViews.swift:293）
// ---------------------------------------------------------------------------

@Test
func theEngineSummaryOnlyFillsInWhenTheCommitChartHasNotSaidItYet(): Unit {
    // 真实数据核对：本机 15 个项目里，`summary` 非空的有 11 个，
    // **全部**同时有 `commitTypes`；反之 `summary` 非空而 `commitTypes` 为空的有 **0 个**。
    // 所以这条规则的实际效果是：绝大多数情况下都不显示引擎那句。
    //
    // 不套规则的症状不是「啰嗦」，是**同一屏两套词表**：
    // 引擎摘要写「最近 25 个提交：文档×7、修复×6」，紧挨着的图例写
    // `feat / fix / docs / chore`。读者会当成两个统计口径。
    let withTypes = Project.from(Json.parse(REAL_OVERALL_PROJECT).getOrThrow())
    @Expect(withTypes.commitTypes.size > 0)
    @Expect(!withTypes.overallSummary.isEmpty())
    // 有提交类型 → 下面的图表已经说过 → 引擎那句不补位
    @Expect(!overallSummaryShows(withTypes))

    // 没有提交类型但引擎仍给了摘要 → 这时才轮到它补位
    let fallback = Project.from(Json.parse(
        """
        {"name":"x","path":"/tmp/x","branches":[],"commitTypes":[],
         "overall":{"summary":"最近 4 个提交：更新×2","notes":[]}}
        """).getOrThrow())
    @Expect(overallSummaryShows(fallback))

    // 两者都没有 → 没有东西可显示
    let neither = Project.from(Json.parse(
        """
        {"name":"y","path":"/tmp/y","branches":[],"commitTypes":[],"overall":{}}
        """).getOrThrow())
    @Expect(!overallSummaryShows(neither))
}

@Test
func theOnDiskFixtureActuallyExercisesTheNotesPath(): Unit {
    // ⚠ 这条是给**夹具自己**设的门槛。
    // 原来的 `tests/fixtures/status.json` 六个项目里三个是「读不出来」
    // （`overall` 为空对象），**没有一个非 git 项目** —— 于是
    // 「非 git」这条最该显示的 note 在任何快照里都不会被触发，
    // 而布局自查恰恰是靠快照做的：通路写了、快照里永远不出现，
    // 等于没有证据说它工作过。
    match (readTextFileOf("tests/fixtures/status.json")) {
        case Some(text) =>
            let snap = StatusSnapshot.from(Json.parse(text).getOrThrow())
            var nonGit: Int64 = 0
            var withNotes: Int64 = 0
            var unreadable: Int64 = 0
            for (p in snap.projects) {
                if (!p.overallNotes.isEmpty()) {
                    withNotes += 1
                }
                // 非 git = 读得出、但一个提交类型都没有、也没有采集错误
                if (p.error.isEmpty() && p.commitCount == 0 && p.commitTypes.isEmpty()) {
                    nonGit += 1
                }
                if (!p.error.isEmpty()) {
                    unreadable += 1
                }
            }
            @Expect(withNotes >= 2)
            @Expect(nonGit >= 1)
            // 「读不出来」的覆盖不能因为补了非 git 就丢掉
            @Expect(unreadable >= 3)
        case None => @Expect(false)
    }
}

// ---------------------------------------------------------------------------
// mergeHint / dirty / manifests —— 三个真实存在、而本端一度当它们不存在的键
// ---------------------------------------------------------------------------

/// 真实载荷逐字截取（`moonpainter`）。关键形状：
/// **一个可合并分支都没有**，工作区干净、没有 stash ——
/// 只看分支与脏度的判据会把它显示成「一切正常」，
/// 而它其实欠着一次 154 个提交的 fast-forward。
private let REAL_MERGE_HINT_PROJECT = """
{"storeHealth":"ok","name":"moonpainter","path":"/tmp/moonpainter","kind":"git",
 "userDirtyCount":0,"untrackedCount":0,"stashCount":0,"worktreeCount":1,"commitCount":155,
 "tags":[],"manifests":["package.json"],
 "mergeHint":{"kind":"fast-forward","ahead":154,"behind":0,"defaultBranch":"main",
   "target":"dev","description":"main 可直接 fast-forward 到 dev（154 个新提交）"},
 "dirty":{"clean":false,"ok":true,"staged":0,"modified":2,"untracked":1,"conflicts":3,
   "total":6,"files":["agent/index.js","docs/plan.md","package.json"]},
 "branches":[{"name":"main","status":"idle","statusLabel":"闲置","isCurrent":true,"isDefault":true,
   "aheadOfDefault":0,"merged":false}],"overall":{}}
"""

@Test
func aFastForwardableBranchIsAnActionEvenWithNoMergeCandidateBranch(): Unit {
    // 这条是 `mergeHint` 存在的全部理由。原来的注释断言这个键不存在，
    // 理由是「实测 33 个键」—— 量的是**载荷夹具**，不是真实输出。
    // 真实输出里本机 15 个项目有 3 个带它。
    let p = Project.from(Json.parse(REAL_MERGE_HINT_PROJECT).getOrThrow())
    // 前置事实：这个项目确实「没有别的信号」
    @Expect(p.userDirtyCount == 0)
    @Expect(p.untrackedCount == 0)
    @Expect(p.stashCount == 0)
    var candidates: Int64 = 0
    for (b in p.branches) {
        if (b.isMergeCandidate()) { candidates += 1 }
    }
    @Expect(candidates == 0)
    // 但它欠着一次合并 —— 少了这条判据它显示成「一切正常」
    @Expect(projectNeedsAction(p))
    match (p.mergeHint) {
        case Some(h) =>
            @Expect(h.kind == "fast-forward")
            @Expect(h.ahead == 154)
            @Expect(h.behind == 0)
            @Expect(h.target == "dev")
            @Expect(h.description.contains("154"))
        case None => @Expect(false)
    }
    // `merged` 是「已经合过了」，不是待办
    @Expect(!MergeHint.from(Json.parse(
        """
        {"kind":"merged","ahead":0,"behind":0}
        """).getOrThrow()).actionable())
    // 没有 mergeHint 时判据不受影响
    let bare = Project.from(Json.parse(
        """
        {"name":"b","path":"/tmp/b","userDirtyCount":0,"untrackedCount":0,"stashCount":0,"branches":[]}
        """).getOrThrow())
    @Expect(!projectNeedsAction(bare))
}

@Test
func dirtyDisclosurePutsConflictsFirstAndNeverReportsZeroWhenUnreadable(): Unit {
    let p = Project.from(Json.parse(REAL_MERGE_HINT_PROJECT).getOrThrow())
    match (p.dirtyInfo) {
        case Some(d) =>
            @Expect(d.readable())
            @Expect(d.conflicts == 3)
            // 冲突（会丢代码的那种）必须压在最前面，混进「N 处未提交」
            // 会被当成一条普通改动
            let line = dirtyLine(d)
            @Expect(line.startsWith("6 处未提交"))
            @Expect(line.contains("⚠ 冲突 3"))
            // 仓颉的 `indexOf` 返回 `Option<Int64>`，不能直接比大小 ——
            // 先确认两段都在（都在才谈得上谁在前），再解包比下标。
            @Expect(line.contains("已修改"))
            @Expect(line.contains("未跟踪"))
            let iConflict = line.indexOf("冲突").getOrThrow()
            let iModified = line.indexOf("已修改").getOrThrow()
            @Expect(iConflict < iModified)
            // 「哪几个文件」也要能拿到，且截断自报
            @Expect(dirtyFilesLine(d).contains("agent/index.js"))
        case None => @Expect(false)
    }
    // ⚠ 下面是**防御性**断言，不是实测形状：本机 13 个 `dirty` 对象
    // **全是 `ok=true`**，引擎没发过 `ok=false`。但字段在代码里存在、
    // 读不出来时又必须与「干净」分开，所以这条留着。
    // （别把 `ok=false` 写进夹具去「演示」它 —— 夹具里没有的形状
    // 就是没有，本轮 mergeHint 那条注释就是这么错的。）
    let blind = DirtyInfo(false, 0, 0, 0, 0, 0, ArrayList<String>())
    @Expect(dirtyLine(blind).contains("读不出来"))
    @Expect(dirtyFilesLine(blind).isEmpty())
    // 真的干净就说干净
    let clean = DirtyInfo(true, 0, 0, 0, 0, 0, ArrayList<String>())
    @Expect(dirtyLine(clean), "工作区干净")
}

@Test
func readOnlyFactsDoNotOccupySpaceWhenTheyAreEmptyAndSayHowManyTheyHid(): Unit {
    // 空数组**不占位**：画一个空的「标签」行只会让人以为这里本来该有东西而没采到。
    @Expect(projectFactsLine("标签", ArrayList<String>()).isEmpty())
    @Expect(projectFactsLine("依赖清单", ArrayList<String>()).isEmpty())

    let two = ArrayList<String>()
    two.add("package.json")
    two.add("Cargo.toml")
    @Expect(projectFactsLine("依赖清单", two), "依赖清单：package.json、Cargo.toml")

    // 静默截会让人以为标签只有前几个 —— 必须自报
    let many = ArrayList<String>()
    for (i in 0..10) {
        many.add("t${i}")
    }
    let line = projectFactsLine("标签", many)
    @Expect(line.startsWith("标签：t0、t1"))
    @Expect(line.contains("还有 2 个"))
}

@Test
func theFixtureCarriesMergeHintAndDirtySoThosePathsAreActuallyDrawn(): Unit {
    // 与 `theOnDiskFixtureActuallyExercisesTheNotesPath` 同一条道理：
    // 布局自查靠快照，通路写了而夹具里没有这个形状，就永远没有证据说它工作过。
    match (readTextFileOf("tests/fixtures/status.json")) {
        case Some(text) =>
            let snap = StatusSnapshot.from(Json.parse(text).getOrThrow())
            var hints: Int64 = 0
            var dirties: Int64 = 0
            var manifests: Int64 = 0
            for (p in snap.projects) {
                match (p.mergeHint) {
                    case Some(h) => if (h.actionable()) { hints += 1 }
                    case None => ()
                }
                match (p.dirtyInfo) {
                    case Some(d) => if (d.readable()) { dirties += 1 }
                    case None => ()
                }
                if (!p.manifests.isEmpty()) { manifests += 1 }
            }
            @Expect(hints >= 1)
            @Expect(dirties >= 1)
            @Expect(manifests >= 1)
            // 还要保证夹具里**至少有一个项目只靠 mergeHint 一个信号**。
            // 否则「未跟踪 1」会先把 needsAction 置真，截图看上去
            // 待处理徽标亮着，而它其实与 mergeHint 无关 ——
            // 夹具会替这段代码说它工作过，而它没被验证过。
            var onlySignal: Int64 = 0
            for (p in snap.projects) {
                match (p.mergeHint) {
                    case Some(h) =>
                        if (!h.actionable()) { continue }
                        if (p.userDirtyCount != 0 || p.untrackedCount != 0 || p.stashCount != 0) {
                            continue
                        }
                        var cands: Int64 = 0
                        for (b in p.branches) {
                            if (b.isMergeCandidate()) { cands += 1 }
                        }
                        if (cands == 0) { onlySignal += 1 }
                    case None => ()
                }
            }
            @Expect(onlySignal >= 1)
        case None => @Expect(false)
    }
}

/// 日志的两条披露是**两件事**，合并成一句就会把「后面还有」与
/// 「中间有你看漏的」糊在一起 —— 用户会把那条分界线当成历史的终点。
///
/// 与 macOS 端 `DetailViews.swift:717` 同一条规则与同一句措辞。
/// ⚠ 这是**防御性**通路：本机 `journal --json` 实测 `unparsableLines: 0`。
/// 留着是因为字段在契约里，引擎换日志格式那天它就会变成非 0。
@Test
func journalTruncationAndUnparsableLinesAreTwoDifferentDisclosures(): Unit {
    let cut = Journal.from(Json.parse(
        """
        {"entries":[],"limit":20,"windowExhausted":true,"unparsableLines":0}
        """).getOrThrow())
    @Expect(cut.truncatedNote().contains("已截断"))
    @Expect(cut.truncatedNote().contains("20"))
    @Expect(cut.unparsableNote().isEmpty())

    let blind = Journal.from(Json.parse(
        """
        {"entries":[],"limit":20,"windowExhausted":false,"unparsableLines":3}
        """).getOrThrow())
    @Expect(blind.truncatedNote().isEmpty())
    let note = blind.unparsableNote()
    @Expect(note.contains("3 行"))
    // 措辞不许含糊：必须明确说「不是日志到此为止」
    @Expect(note.contains("不是「日志到此为止」"))

    // 两个同时发生时两句都在，谁也不许吞掉谁
    let both = Journal.from(Json.parse(
        """
        {"entries":[],"limit":8,"windowExhausted":true,"unparsableLines":1}
        """).getOrThrow())
    @Expect(!both.truncatedNote().isEmpty())
    @Expect(!both.unparsableNote().isEmpty())
    // 都正常时一句都不说 —— 多余的披露和缺失的一样是噪声
    let fine = Journal.from(Json.parse(
        """
        {"entries":[],"limit":20,"windowExhausted":false,"unparsableLines":0}
        """).getOrThrow())
    @Expect(fine.truncatedNote().isEmpty())
    @Expect(fine.unparsableNote().isEmpty())
}

/// 语言分布的**四轴披露**，一条都不能少。
///
/// ⚠ 这条盯的是 macOS 缺陷 #205 的本端复现：`dashboard --json` 实测给
/// **12 种**语言，而界面只画前 8 条，且 `languagesTruncated` 与
/// `languagesTopCut` **都是 false** —— 于是连原有的「已截断」标记都不亮，
/// 读者看到的是一条看起来完整的分段条。
/// 实测被藏起来的是 C/C++ 34、Shell 16、Python 13、Rust 11。
@Test
func theLanguageCardSaysWhenItsOwnEightRowCapHidSomething(): Unit {
    // 逐字取自本机 `dashboard --json` 的前 8 条 + 后 4 条
    let d = Dashboard.from(Json.parse(
        """
        {"projects":{"total":1},"work":{"branches":1,"mergeCandidates":0,"untrackedFiles":0,"stashes":0},
         "languages":[
           {"language":"TypeScript","count":777},{"language":"MoonBit","count":356},
           {"language":"其他","count":210},{"language":"JavaScript","count":85},
           {"language":"配置","count":78},{"language":"HTML","count":65},
           {"language":"Swift","count":56},{"language":"CSS","count":45},
           {"language":"C/C++","count":34},{"language":"Shell","count":16},
           {"language":"Python","count":13},{"language":"Rust","count":11}],
         "languagesTruncated":false,"languagesTopCut":false,
         "languagesFailed":0,"languagesFailedReasons":[],
         "fetchedAt":"x"}
        """).getOrThrow())

    let parts = languageParts(d)
    @Expect(parts.size, 8)
    // 引擎两条轴都是 false —— 所以**只有**界面自己那条会响。
    // 这正是它原先一个字都不说的原因。
    @Expect(!d.languagesTruncated)
    @Expect(!d.languagesTopCut)

    let cov = languageCoverage(d, parts.size)
    @Expect(cov.notes.size, 1)
    // 披露里的数必须与**实际画出来的条数**和**引擎给的条数**都对得上
    @Expect(cov.notes[0].contains("前 8 种"))
    @Expect(cov.notes[0].contains("共 12 种"))
    // 披露用的上限与切片用的上限必须是同一个常量
    @Expect(LANGUAGE_CARD_MAX, 8)

    // 引擎那两条轴各自独立：响了就是它自己那一句，不许互相顶替
    let cut = Dashboard.from(Json.parse(
        """
        {"projects":{"total":1},"work":{"branches":1,"mergeCandidates":0,"untrackedFiles":0,"stashes":0},
         "languages":[{"language":"Swift","count":56},{"language":"Rust","count":11}],
         "languagesTruncated":true,"languagesTopCut":true,
         "languagesFailed":2,"languagesFailedReasons":["listFiles 失败：/tmp/x"],
         "fetchedAt":"x"}
        """).getOrThrow())
    let c2 = languageCoverage(cut, languageParts(cut).size)
    @Expect(c2.notes.size, 3)
    @Expect(c2.notes[0].contains("跟踪文件上限"))
    @Expect(c2.notes[1].contains("引擎上限"))
    @Expect(c2.notes[2].contains("2 个项目语言采集失败"))
    @Expect(c2.notes[2].contains("listFiles 失败"))

    // 采集失败 + 没有语言 → 空态标题必须说「未采集到」而不是「暂无数据」。
    // 「暂无数据」会被读成「这个项目群真的没有这些语言」。
    let blind = Dashboard.from(Json.parse(
        """
        {"projects":{"total":1},"work":{"branches":1,"mergeCandidates":0,"untrackedFiles":0,"stashes":0},
         "languages":[],"languagesTruncated":false,"languagesTopCut":false,
         "languagesFailed":3,"languagesFailedReasons":[],"fetchedAt":"x"}
        """).getOrThrow())
    @Expect(languageCoverage(blind, 0).emptyTitle, "未采集到语言数据")
    @Expect(languageCoverage(d, parts.size).emptyTitle, "暂无数据")

    // 什么都没发生时一句话都不说 —— 多余的披露和缺失的一样是噪声
    let small = Dashboard.from(Json.parse(
        """
        {"projects":{"total":1},"work":{"branches":1,"mergeCandidates":0,"untrackedFiles":0,"stashes":0},
         "languages":[{"language":"Swift","count":56}],
         "languagesTruncated":false,"languagesTopCut":false,
         "languagesFailed":0,"languagesFailedReasons":[],"fetchedAt":"x"}
        """).getOrThrow())
    @Expect(languageCoverage(small, 1).notes.size, 0)
}

@Test
func theOnDiskFixtureHasMoreLanguagesThanTheCardCanShow(): Unit {
    // 夹具原来只有 1 种语言 —— 于是这个缺陷在**任何快照里都不会出现**。
    // 布局自查靠快照，夹具里没有的形状就等于没验证过。
    // 这条是给夹具自己设的门槛。
    match (readTextFileOf("tests/fixtures/dashboard.json")) {
        case Some(text) =>
            let d = Dashboard.from(Json.parse(text).getOrThrow())
            @Expect(d.languages.size > LANGUAGE_CARD_MAX)
            // 引擎那两条轴都是 false：唯一会响的必须是界面自己那条
            @Expect(!d.languagesTruncated)
            @Expect(!d.languagesTopCut)
            let parts = languageParts(d)
            @Expect(parts.size, LANGUAGE_CARD_MAX)
            @Expect(languageCoverage(d, parts.size).notes.size, 1)
        case None => @Expect(false)
    }
}

/// journal 里那个 `+N` 的口径（引擎侧缺陷 #188）。
///
/// 原实现是 `${n} 个提交`，而实测本机 `journal --json` 的 57 条 entry
/// **根本没有 `commitCountScope` 键** —— 于是每一行都渲染成裸数字，
/// 浅更新的「本轮新增 6」和深更新的「仓库一共 6 个」长得一模一样，
/// 读者会得出「深更新也新增了 6 个」，而那个数会随仓库一直涨。
///
/// 注释里写的词汇表（`all` / `branch`）也是凭想象的：真实取值按
/// macOS 端 `CommitCountScope.swift` 是 `new` / `repoTotal`。
@Test
func aCommitCountWithoutAScopeSaysItsScopeIsUnknown(): Unit {
    // 口径认得出
    @Expect(commitCountBadge(6, "new", false).text, "+6 新增")
    @Expect(commitCountBadge(1397, "repoTotal", false).text, "+1397 累计")
    // 只有「本轮新增」才配得上增量绿 —— 绿 + 无限定词 = 把累计量说成增量
    @Expect(commitScopeIsIncremental(commitScopeOf("new", 6)))
    @Expect(!commitScopeIsIncremental(commitScopeOf("repoTotal", 6)))
    @Expect(!commitScopeIsIncremental(commitScopeOf("", 6)))

    // 引擎没给口径（本机真实形状）→ 认不出就是认不出，不许默认
    let unknown = commitCountBadge(6, "", false)
    @Expect(unknown.text, "+6 口径未知")
    @Expect(unknown.note.contains("无法判断是本轮新增还是仓库累计"))
    // 也不能当成新增
    @Expect(!commitScopeIsIncremental(unknown.scope))

    // 读不出来绝不能显示成 0
    let blind = commitCountBadge(-1, "", false)
    @Expect(blind.text, "提交数读不出来")
    @Expect(blind.note.contains("不是「这轮没有提交」"))
    // 有 scope 也一样：-1 优先
    @Expect(commitCountBadge(-1, "new", false).text, "提交数读不出来")

    // 0 不是徽章要表达的事，不占位
    @Expect(commitCountBadge(0, "new", false).text.isEmpty())
    @Expect(commitCountBadge(0, "", false).note.isEmpty())

    // 采样值是**另一条**轴，两条一起发生时都要说
    let both = commitCountBadge(15, "new", true)
    @Expect(both.text, "+15 新增")
    @Expect(both.note.contains("采样值"))
}

/// 夹具必须能撑起日志卡与文档卡，否则这两块布局**永远没有证据**。
///
/// 它们走的是 `loadProjectDetail` 里的真实子进程调用，而夹具模式不起引擎
/// —— 加载器原先只认 status/dashboard/milestones，于是任何快照里
/// 「进度日志」和「托管文档」都是空态。空态证明不了任何排版。
@Test
func theOnDiskFixtureCoversJournalAndDocsToo(): Unit {
    match (readTextFileOf("tests/fixtures/journal.json")) {
        case Some(text) =>
            let j = Journal.from(Json.parse(text).getOrThrow())
            @Expect(j.entries.size >= 3)
            // 三种口径状态都要在，披露的每一条分支才有东西可验
            var unknown = 0
            var repoTotal = 0
            var unreadable = 0
            for (e in j.entries) {
                if (!e.commitText().isEmpty()) {
                    if (e.commitText().contains("口径未知")) { unknown += 1 }
                    if (e.commitText().contains("累计")) { repoTotal += 1 }
                }
                if (e.commitText() == "提交数读不出来") { unreadable += 1 }
            }
            @Expect(unknown >= 1)
            @Expect(repoTotal >= 1)
            @Expect(unreadable >= 1)
            // 「口径未知」这一条必须**带着说明**，否则又是一个裸数字
            for (e in j.entries) {
                if (e.commitText().contains("口径未知")) {
                    @Expect(e.commitNote().contains("无法判断"))
                }
            }
        case None => @Expect(false)
    }
    match (readTextFileOf("tests/fixtures/docs.json")) {
        case Some(text) =>
            let d = DocBundle.from(Json.parse(text).getOrThrow())
            @Expect(d.docs.size >= 1)
            // 「读不出来」也要有一份，否则那条披露在快照里不出现
            @Expect(d.unreadable.size >= 1)
        case None => @Expect(false)
    }
}

/// 空路径**不许**把进程带崩。
///
/// `Path("")` 在仓颉里抛 `IllegalArgumentException`。而 `locateEngine`
/// 的候选表天然会出现空串（`DEEPGIT_BIN` 未设、仓内上溯失败、PATH 没找到）。
///
/// ⚠ 这条判据是为了钉一次**真实崩机**：没有装引擎的机器上
/// 应用一启动就抛异常退出，界面上那句
/// 「请运行 moonGit/scripts/install.sh 安装，或设置 DEEPGIT_BIN」
/// 永远显示不出来 —— 披露做得再全，崩在披露之前就等于没有。
///
/// 负控：把 `isRegularFile` 开头的空串守卫删掉，本条立刻红。
@Test
func emptyPathIsRejectedInsteadOfThrowing(): Unit {
    // 旧实现在这一行直接抛异常，测试会以 ERROR 而不是 FAILED 结束 ——
    // 效果一样是红，但看不出是被哪条判据抓住的，所以写成「不抛且为 false」。
    @Expect(!isRegularFile(""))
    @Expect(!isRegularFile("/definitely/not/here/moonGit"))
    @Expect(!isRegularFile("relative/nope"))
}

/// 真实引擎载荷能被解析成完整模型。
///
/// 【为什么要这条】`tests/fixtures/*.json` 是 `moongit --json` 的**真实输出**
/// （含 6 个项目、失败路径、41 KB）。单元测试此前只用过几百字节的手写夹具，
/// 于是**从没在真实体量的载荷上跑过解析**。
/// 症状是：`--snapshot` 自查时进程挂在 `loadFromFixtureDir` 里出不来
/// （`sample` 抓到的栈停在 `checkContractOf`），而界面自查恰恰要靠它。
///
/// 负控：把 `loadFromFixtureDir` 的 `checkContractOf` 换成 `return true`，
/// 本条会因契约不符而红。
@Test
func realEngineFixturesParseIntoModels(): Unit {
    let dir = "tests/fixtures"

    // status
    match (readTextFileOf("${dir}/status.json")) {
        case Some(text) =>
            let v = Json.parse(text).getOrThrow()
            let snap = StatusSnapshot.from(v)
            // 7 个：atlas/beacon/legacy（可读 git）、plainly（可读但非 git）、
            // gone/newbie/fresh（读不出来）。
            // ⚠ 别把 7 改回 6 来「修」这条判据 —— `theOnDiskFixtureActuallyExercisesTheNotesPath`
            // 要求里面**必须**有一个非 git 项目，否则 note 通路在快照里永远不出现。
            @Expect(snap.projects.size == 7)
            @Expect(snap.failedKnown)
            @Expect(snap.failedProjects == 3)
            // 契约闸门必须过
            @Assert(checkContractOf(v, PayloadShape.Status))
            // 每个项目都要拿到真实字段
            for (p in snap.projects) {
                @Expect(!p.name.isEmpty())
                @Expect(p.lastCommitAt.isEmpty() || p.lastCommitAgo.isEmpty() == false)
            }
        case None => @Expect(false)
    }

    // dashboard
    match (readTextFileOf("${dir}/dashboard.json")) {
        case Some(text) =>
            let v = Json.parse(text).getOrThrow()
            @Assert(checkContractOf(v, PayloadShape.Dashboard))
            let d = Dashboard.from(v)
            @Expect(d.total == 3)
            @Expect(d.registered == 6)
            @Expect(d.failed == 3)
            @Expect(d.branches == 8)
            @Expect(d.mergeCandidates == 5)
        case None => @Expect(false)
    }

    // milestones
    match (readTextFileOf("${dir}/milestones.json")) {
        case Some(text) =>
            let v = Json.parse(text).getOrThrow()
            @Assert(checkContractOf(v, PayloadShape.Milestones))
        case None => @Expect(false)
    }
}

/// 契约闸门**按形状族**分别判定 —— 这条钉的是那次真事故。
///
/// ⚠ 事故：闸门只认 `summary.failedProjects` / `summary.listedProjects`，
/// 而 `dashboard` / `milestone list` / `docs` / `journal` 的载荷里
/// **根本没有 `summary` 键**（实测三份真实载荷的键见上）。
/// 于是四路读全被判成「契约过旧」，界面回落到全 0 **且一句解释都没有**。
/// 用户看到「语言分布：没有采集到」，真相是「载荷被闸门丢了」。
///
/// 负控：把 `checkContractOf` 退回成只查 `summary`，本条立刻红。
@Test
func contractGateIsPerShapeFamilyNotOneGlobalRule(): Unit {
    let dash = Json.parse(
        "{\"projects\":{\"total\":1},\"work\":{\"branches\":2},\"languages\":[],\"fetchedAt\":\"x\"}"
    ).getOrThrow()
    let ms = Json.parse("{\"milestones\":[],\"storeHealth\":\"ok\",\"readCount\":0}").getOrThrow()
    let docs = Json.parse("{\"docs\":[],\"project\":\"a\",\"unreadable\":[]}").getOrThrow()
    let journal = Json.parse("{\"entries\":[],\"limit\":8,\"branches\":1,\"projects\":1}").getOrThrow()

    // 四族都必须通过（都不含 summary）
    @Expect(checkContractOf(dash, PayloadShape.Dashboard))
    @Expect(checkContractOf(ms, PayloadShape.Milestones))
    @Expect(checkContractOf(docs, PayloadShape.Docs))
    @Expect(checkContractOf(journal, PayloadShape.Journal))
    // 但它们**不能**冒充 status 通过
    @Expect(!checkContractOf(dash, PayloadShape.Status))
    // 缺披露键的仍然要拒
    @Expect(!checkContractOf(Json.parse("{\"projects\":{},\"work\":{}}").getOrThrow(), PayloadShape.Dashboard))
    @Expect(!checkContractOf(Json.parse("{\"milestones\":[]}").getOrThrow(), PayloadShape.Milestones))
}

// ---------------------------------------------------------------------------
// 仪表盘 KPI 口径 —— 与 macOS 端 `DashKPIBuilder` 逐条对应
// ---------------------------------------------------------------------------

/// 这份夹具的 counts 键**照抄引擎真实输出**（实测 `moongit dashboard --json`：
/// `{"open","done","dropped","unknown","other","storeHealth","degraded",
///   "readCount","excludedDisabled","orphaned"}`）。
///
/// ⚠ 原来这里写的是 `{"counts":{"total":5,"done":2}}` —— 那个 `total` 键
/// **引擎根本不发**（真实键是 `readCount`）。于是模型读出来恒为 0，
/// 而判据因为夹具里正好编了这个键，一直是绿的。
/// 教训：判据夹具的键必须来自真实载荷，不能照着字段名想象着写。
private let REAL_DASHBOARD = """
{"projects":{"total":6,"listed":6,"registered":6,"excludedDisabled":1,"failed":3,
 "dirty":2,"active7d":1,"active30d":2},
 "work":{"branches":8,"mergeCandidates":5,"untrackedFiles":2,"stashes":0},
 "languages":[{"language":"Swift","count":40}],
 "languagesTruncated":false,"languagesTopCut":false,"languagesFailed":0,"languagesFailedReasons":[],
 "milestones":{"counts":{"open":3,"done":1,"dropped":0,"unknown":2,"other":0,
   "storeHealth":"ok","degraded":false,"readCount":6,"excludedDisabled":0,"orphaned":1},"items":[]},
 "activeProjects":[{"name":"atlas"}],"fetchedAt":"x"}
"""

private func realDashboard(): Dashboard {
    return Dashboard.from(Json.parse(REAL_DASHBOARD).getOrThrow())
}

private func realProjects(): ArrayList<Project> {
    let s = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
    return s.projects
}

@Test
func dashboardReadsOnlyTheMilestoneCountKeysEngineActuallySends(): Unit {
    let d = realDashboard()
    let c = d.milestoneCounts
    // 这五个键在真实载荷里逐个对上
    @Expect(c.open, 3)
    @Expect(c.done, 1)
    @Expect(c.unknown, 2)
    @Expect(c.orphaned, 1)
    @Expect(c.readCount, 6)
    @Expect(c.storeHealth, "ok")
    @Expect(!c.degraded)
    // ⚠ 负控：引擎**不发** counts.total。真实载荷里塞一个 total 也不该被当成
    // 「总数」—— 那是「读到多少条」的 readCount，两者混同会凭空多出一批里程碑。
    let withFake = MilestoneCounts.from(
        Json.parse("{\"total\":99,\"readCount\":4,\"done\":1,\"open\":1}").getOrThrow())
    @Expect(withFake.readCount, 4)
    @Expect(withFake.decided(), 2)
}

@Test
func milestoneUnknownStaysOutOfTheCompletionDenominator(): Unit {
    let c = realDashboard().milestoneCounts
    // unknown=2 是「读不出来」，不是「没达成」。塞进分母等于假装它是目标。
    // 正确分母 = done + open = 1 + 3 = 4 ⇒ 25%
    @Expect(c.decided(), 4)
    let kpis = buildDashKpis(realDashboard(), realProjects())
    @Expect(kpiValueOf(kpis, DashKpiKind.Milestones), 25)
}

@Test
func projectTotalKpiUsesListedNotTotal(): Unit {
    let kpis = buildDashKpis(realDashboard(), realProjects())
    // listed=6（注册表条数）/ total=6（采集成功）。夹具里两者都是 6 时看不出差别，
    // 所以再加一份 failed 存在的：标题绝不能写「项目总数 3」而侧栏写 6。
    let d2 = Dashboard.from(Json.parse("""
    {"projects":{"total":3,"listed":6,"registered":6,"failed":3,"dirty":0,"active7d":1,"active30d":2},
     "work":{"branches":0,"mergeCandidates":0,"untrackedFiles":0,"stashes":0},
     "languages":[],"milestones":{"counts":{"open":0,"done":0,"readCount":0,"storeHealth":"ok","degraded":false}}}
    """).getOrThrow())
    let k2 = buildDashKpis(d2, ArrayList<Project>())
    @Expect(kpiValueOf(k2, DashKpiKind.Projects), 6)
}

@Test
func everyKpiCarriesACaptionThatExplainsTheNumber(): Unit {
    let kpis = buildDashKpis(realDashboard(), realProjects())
    // 「没有副说明的数字只是数字」（macOS 端 KPIWideCard 的原话）。
    for (k in kpis) {
        @Expect(!k.caption.isEmpty())
    }
    // 四张卡的副说明必须真的在解释各自那个数
    @Expect(kpis[0].caption.contains("可读取"))
    @Expect(kpis[1].caption.contains("进行中"))
    @Expect(kpis[2].caption.contains("未跟踪文件"))
    @Expect(kpis[3].caption.contains("stash"))
    // 第 4 张的副说明要披露「有项目的分支数读不出来」而不是静默少算
    @Expect(kpis[3].caption.contains("已跟踪明细"))
}

@Test
func summaryLineReadsFromKpisInsteadOfRecomputing(): Unit {
    // 同一件事被算两次就会出现「页头 6 · KPI 5」这种同屏矛盾。
    let kpis = buildDashKpis(realDashboard(), realProjects())
    let line = dashSummaryLine(kpis)
    @Expect(line.contains("${kpiValueOf(kpis, DashKpiKind.Projects)}"))
    @Expect(line.contains("${kpiValueOf(kpis, DashKpiKind.Attention)}"))
    // 待处理为 0 时不该出现「0 个项目待处理」这种别扭句子
    let calm = buildDashKpis(
        Dashboard.from(Json.parse("""
        {"projects":{"total":1,"listed":1,"failed":0},"work":{"branches":0,"mergeCandidates":0,
         "untrackedFiles":0,"stashes":0},"languages":[],
         "milestones":{"counts":{"open":0,"done":0,"readCount":0,"storeHealth":"ok","degraded":false}}}
        """).getOrThrow()), ArrayList<Project>())
    @Expect(dashSummaryLine(calm), "共 1 个项目")
}

@Test
func branchScopeLineCountsTrackedBranchesItselfNotFromAMissingKey(): Unit {
    let s = StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow())
    let p = s.find("atlas").getOrThrow()
    // 引擎项目对象**不发** branchCount（实测键表），所以「追踪到」只能是自己数。
    let line = branchScopeLine(p)
    @Expect(line.contains("引擎追踪到 1"))
    // ⚠ 负控：塞一个 branchCount 也不该被采信 —— 那不是引擎发的键
    let p2 = Project.from(Json.parse(
        "{\"name\":\"x\",\"branchCount\":99,\"branches\":[{\"name\":\"main\"}]}").getOrThrow())
    @Expect(branchScopeLine(p2).contains("引擎追踪到 1"))
}

@Test
func engineLabelDoesNotLeakEnvironmentVariableNamesOrPaths(): Unit {
    // 顶栏那格是整屏最贵的一行，放开发细节等于浪费。
    // 用户看到 DEEPGIT_BIN 这个环境变量名，既不知道它指什么也不知道该做什么。
    let via = "DEEPGIT_BIN"
    let path = "/Volumes/data/dev/moonGit/target/release/bin/main"
    @Expect(engineLabelFor(via, path), "引擎已就绪")
    // ⚠ 负控：字符串里不许出现环境变量名，也不许出现路径的任何片段
    let label = engineLabelFor(via, path)
    @Expect(!label.contains(via))
    @Expect(!label.contains("main"))
    @Expect(!label.contains("/"))
    // 引擎找不到时要说人话
    @Expect(engineLabelFor("", ""), "未找到引擎")
    @Expect(engineLabelFor(via, ""), "引擎未就绪")
}

@Test
func milestoneItemStatusLabelsKeepUnknownApartFromDropped(): Unit {
    // 「系统读不出来」和「明确放弃」是相反的两件事，混同会让故障被读成进度清零。
    let unknown = MilestoneItem.from(Json.parse(
        "{\"projectName\":\"a\",\"name\":\"v2\",\"status\":\"unknown\",\"targetDate\":\"\",\"daysToTarget\":-1}").getOrThrow())
    let dropped = MilestoneItem.from(Json.parse(
        "{\"projectName\":\"a\",\"name\":\"v2\",\"status\":\"dropped\"}").getOrThrow())
    let done = MilestoneItem.from(Json.parse(
        "{\"projectName\":\"a\",\"name\":\"v2\",\"status\":\"done\"}").getOrThrow())
    @Expect(unknown.statusLabel().contains("无法核验"))
    @Expect(dropped.statusLabel(), "已放弃")
    @Expect(done.statusLabel(), "已达成")
    @Expect(unknown.statusLabel() != dropped.statusLabel())
    // daysToTarget = -1 是「未设置或日期无效」，绝不能变成「逾期 1 天」
    @Expect(milestoneDueText(unknown), "")
    let bad = MilestoneItem.from(Json.parse(
        "{\"projectName\":\"a\",\"name\":\"v2\",\"status\":\"open\",\"targetDate\":\"2026-02-31\",\"daysToTarget\":-1}").getOrThrow())
    @Expect(milestoneDueText(bad).contains("日期无效"))
    @Expect(!milestoneDueText(bad).contains("逾期 1 天"))
    // R2-08 回归：判定条件曾是 `< 0` 就报「日期无效」—— 契约里**其余负数**
    // 是真实的「已逾期 N 天」，一并吞掉后「逾期」分支成了静态不可达的死代码。
    let overdue = MilestoneItem.from(Json.parse(
        "{\"projectName\":\"a\",\"name\":\"v2\",\"status\":\"open\",\"targetDate\":\"2026-01-10\",\"daysToTarget\":-5}").getOrThrow())
    @Expect(milestoneDueText(overdue).contains("逾期 5 天"))
    @Expect(!milestoneDueText(overdue).contains("日期无效"))
}

// ---------------------------------------------------------------------------
// 仪表盘筛选行 —— 判定「它真的有效果」
// ---------------------------------------------------------------------------

/// 三个项目：一个 7 天前动过、一个 61 天前、一个**读不出更新时间**。
/// 第三个是这份夹具存在的全部理由。
private let SPAN_PROJECTS = """
{"projects":[
 {"name":"fresh","path":"/tmp/f","lastCommitAt":"2025-12-25T00:00:00+08:00","commitTypes":[
   {"type":"feat","count":3},{"type":"fix","count":5}]},
 {"name":"old","path":"/tmp/o","lastCommitAt":"2025-11-01T00:00:00+08:00","commitTypes":[
   {"type":"fix","count":9}]},
 {"name":"noread","path":"/tmp/n","commitTypes":[{"type":"chore","count":1}]}
],"summary":{"listedProjects":3,"projectCount":3}}
"""

private func spanProjects(): ArrayList<Project> {
    return StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow()).projects
}

private func spanNow(): Int64 {
    return parseIso8601Ms("2026-01-01T00:00:00+08:00").getOrThrow()
}

@Test
func dashSpanActuallyFiltersProjectsInsteadOfJustLookingLikeItDoes(): Unit {
    // 筛选控件最常见的失败不是「不好看」，是摆在那里不起作用。
    // 换一档结果必须真的变 —— 这是它成立的前提，不是锦上添花。
    let all = spanProjects()
    let now = spanNow()
    @Expect(filteredProjects(DashFilter(DashSpan.All, DashCommitFilter.AllCommits), all, now).size, 3)
    @Expect(filteredProjects(DashFilter(DashSpan.D30, DashCommitFilter.AllCommits), all, now).size, 2)
    // D7 = fresh + noread = 2 而不是 1：读不出更新时间的项目**一律保留**
    // （见下一条判据）。这条判据最初写成 1，与那条自相矛盾 ——
    // 两处都得对，缺一处就说明规则没想清楚。
    @Expect(filteredProjects(DashFilter(DashSpan.D7, DashCommitFilter.AllCommits), all, now).size, 2)
    // 档位必须**从宽到严**递增，否则「近 7 天」比「全量」还宽就是反的
    @Expect(spanMaxDays(DashSpan.D7).getOrThrow() < spanMaxDays(DashSpan.D30).getOrThrow())
    @Expect(spanMaxDays(DashSpan.All).isNone())
    // 切档循环要回到起点
    var s = DashSpan.All
    s = spanNext(s)
    s = spanNext(s)
    s = spanNext(s)
    @Expect(spanIs(s, DashSpan.All))
}

@Test
func projectsWithUnreadableLastCommitAreNeverFilteredOut(): Unit {
    // 「读不出更新时间」的真实状态是**不知道**，不是「不在范围内」。
    // 筛掉它等于把「我们没读到」说成「这项目很久没动了」——
    // 本项目最高发的那族缺陷就是这句。
    let now = spanNow()
    let keep = filteredProjects(DashFilter(DashSpan.D7, DashCommitFilter.AllCommits),
        spanProjects(), now)
    var hasNoread = false
    for (p in keep) {
        if (p.name == "noread") {
            hasNoread = true
        }
    }
    @Expect(hasNoread)
    // 而 fresh 确实留下了（7 天档含 7 天）
    @Expect(keepsProject(DashFilter(DashSpan.D7, DashCommitFilter.AllCommits),
        spanProjects()[0], now))
    // old 61 天前，两档都该被筛掉
    @Expect(!keepsProject(DashFilter(DashSpan.D30, DashCommitFilter.AllCommits),
        spanProjects()[1], now))
}

@Test
func commitFilterOnlyChangesCompositionNotTheKpis(): Unit {
    // `commitTypes` 是引擎给的**最近 N 条样本**（`commitTypesTruncated` 恒发），
    // 拿样本去重算「全局提交总数」是拿小样本充总量。
    // 所以这个筛选只能作用在结构条上，绝不能接到 KPI。
    let ps = spanProjects()
    let onlyFix = DashFilter(DashSpan.All, DashCommitFilter.Only("fix"))
    @Expect(keptCommitTypes(onlyFix, ps[0]).size, 1)
    @Expect(keptCommitTypes(onlyFix, ps[0])[0][0], "fix")
    @Expect(keptCommitTypes(DashFilter.none(), ps[0]).size, 2)
    // KPI 走的是另一套数据（dashboard 的 languages + projects），与本筛选无关
    @Expect(commitAllowed(onlyFix.commits, "feat"), false)
    @Expect(commitAllowed(onlyFix.commits, "fix"), true)
}

@Test
func commitSlotMatchesPositionSoBarLegendAndColorAgree(): Unit {
    // 堆叠条的段顺序、图例的行顺序、颜色号必须**三者自洽**。
    // 曾经试过按「跨项目全局累计名次」取色，于是名次第 1 的段排在第 2 位 ——
    // 读者在堆叠条里看到第 1 段是紫色、在图例里第 1 行却是蓝色。
    // macOS 端就是按引擎给的顺序取序号，这里与它一致。
    let ps = spanProjects()
    let all = keptCommitParts(DashFilter.none(), ps[0])
    @Expect(all[0].label, "feat")
    @Expect(all[0].slot, 0)
    @Expect(all[1].label, "fix")
    @Expect(all[1].slot, 1)

    // 筛选只改变**看得见多少**，不重排：留下的是第 2 项，slot 仍是它自己的名次，
    // 不会因为前面那项被筛掉就顶上来变成第 1 名。
    let onlyFix = keptCommitParts(DashFilter(DashSpan.All, DashCommitFilter.Only("fix")), ps[0])
    @Expect(onlyFix.size, 1)
    @Expect(onlyFix[0].label, "fix")

    // 筛选行的选项列表按累计条数降序（fix=14 > feat=3 > chore=1）
    let kinds = allCommitTypes(ps)
    @Expect(kinds[0].name, "fix")
    @Expect(kinds[1].name, "feat")
    @Expect(kinds[2].name, "chore")
    @Expect(kinds[0].total, 14)
}

@Test
func gridTitleSaysHowManyWereFilteredOut(): Unit {
    // 标题写「（12）」而下面画 3 张卡，正是本项目栽过多次的那族缺陷。
    let f = DashFilter(DashSpan.D7, DashCommitFilter.AllCommits)
    @Expect(gridCountLine(3, 3, DashFilter.none()), "共 3 个项目")
    @Expect(gridCountLine(1, 3, f), "1/3 个项目（最近更新在 近 7 天）")
    // 筛选生效时标题必须跟着变，且带上档位名 —— 让人知道被什么筛了
    @Expect(!gridCountLine(1, 3, f).contains("共 3"))
}

// ---------------------------------------------------------------------------
// 范围选择器
// ---------------------------------------------------------------------------

@Test
func scopeOptionsAlwaysLeadWithTheGroupAndOnlyListRealProjects(): Unit {
    // 下拉第 0 项必须是「全局」，下标 1..N 才是项目 ——
    // 于是「下标 ↔ 范围」的映射只有一个真相，不会两处各数一次。
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)
    let labels = scopeLabels(model, 3)
    @Expect(labels.size, 4)
    @Expect(labels[0].contains("全局"))
    @Expect(labels[0].contains("3"))
    @Expect(labels[1], "fresh")
    @Expect(labels[3], "noread")
    // 项目列表为空时也不该出现一个假的项目项
    let empty = AppModel(EngineLocation("", "", ""))
    @Expect(scopeLabels(empty, 0).size, 1)
}

@Test
func applyScopeIsTheOnlyWriterAndItSetsAllThreeFieldsTogether(): Unit {
    // 原来三处各写一遍 scope / selectedProject / root，漏写一处就会
    // 「标题说单仓库、内容是全局」—— 范围错了主区内容就全错。
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)

    applyScope(model, 0)
    @Expect(scopeIs(model.scope.value, ScopeChoice.Group))
    @Expect(rootSectionIs(model.root.value, RootSection.Dashboard))
    @Expect(scopeIndexOf(model), 0)

    // 下标 1 = 第 1 个项目（fresh）
    applyScope(model, 1)
    @Expect(scopeIs(model.scope.value, ScopeChoice.One))
    @Expect(model.selectedProject.value, "fresh")
    @Expect(rootSectionIs(model.root.value, RootSection.Project))
    @Expect(scopeIndexOf(model), 1)

    // 下标 → 范围 → 下标 往返要闭合，否则下拉会显示错的项
    applyScope(model, 3)
    @Expect(model.selectedProject.value, "noread")
    @Expect(scopeIndexOf(model), 3)

    // 越界不许把范围写成垃圾值
    applyScope(model, 99)
    @Expect(scopeIs(model.scope.value, ScopeChoice.One))
    @Expect(model.selectedProject.value, "noread")
}

// ---------------------------------------------------------------------------
// 写操作契约：批量更新信封 / 里程碑动作判定（R1-01 / R1-02）
// ---------------------------------------------------------------------------

/// 引擎 `update --json` 在 **2 个项目**上的真实返回（/tmp 沙箱、DEEPGIT_HOME
/// 隔离实测，2026-10-04）：顶层键是 results / count / failed / succeeded，
/// **没有** `projects` 键；成功项带 project + ok；失败项是 DgError 桩
/// `{code,message}` —— 没有 ok、没有 error，项目名在 message 里。
private let BULK_UPDATE_ENVELOPE = """
{"results":[
 {"ok":true,"mode":"shallow","project":"atlas","commitCount":3,"docs":[
   {"file":"README.md","changed":true,"created":false,"backup":"/tmp/bak"}]},
 {"code":"UPDATE_FAILED","message":"gone 更新失败：路径不存在或卷未挂载"}
],"count":2,"failed":1,"succeeded":1}
"""

/// 里程碑动作失败时的真实载荷（实机探针：
/// `moongit milestone done <项目> nosuch --json` → exit 1）。
private let MILESTONE_ERROR_STUB = """
{"error":true,"code":"MILESTONE_NOT_FOUND","message":"未找到里程碑：nosuch"}
"""

@Test
func bulkUpdateReadsTheRealAggregateEnvelopeNotProjects(): Unit {
    // 负控（R1-01）：旧实现读 `projects`，这份**真实形状**的载荷会被报成
    // 「引擎没有返回逐项目结果」—— 引擎明明把成败名单给了，界面却说没给，
    // 哪个项目失败永远显示不出来。
    let v = Json.parse(BULK_UPDATE_ENVELOPE).getOrThrow()
    let line = describeBulkResult(v)
    @Expect(line.contains("成功 1"))
    @Expect(line.contains("失败 1"))
    @Expect(line.contains("gone"))
    @Expect(line.contains("路径不存在或卷未挂载"))
    @Expect(!line.contains("没有返回逐项目结果"))
}

@Test
func bulkUpdateAcceptsTheSingleProjectBareResultToo(): Unit {
    // 单项目时引擎不包信封、直返逐仓结果
    // （contract-check.sh:74：两种形状都合法，两种都要认）。
    let v = Json.parse(
        "{\"ok\":true,\"project\":\"atlas\",\"commitCount\":1,\"docs\":[]}").getOrThrow()
    let line = describeBulkResult(v)
    @Expect(line.contains("atlas"))
    @Expect(!line.contains("没有返回逐项目结果"))
}

@Test
func bulkUpdateSingleProjectErrorStubIsAFailureNotAMystery(): Unit {
    // 单项目失败时引擎直返**裸**错误桩 {code,message}
    // （multiProjectJson 对单元素原样打印）—— 没有 ok 键。
    // 它必须渲染成 ✗ 与原因，不能落进「没给结果」那句兜底话里。
    let v = Json.parse(
        "{\"code\":\"UPDATE_FAILED\",\"message\":\"atlas 更新失败：权限不足\"}").getOrThrow()
    let line = describeBulkResult(v)
    @Expect(line.startsWith("✗"))
    @Expect(line.contains("atlas 更新失败：权限不足"))
}

@Test
func milestoneFailurePayloadWithoutResultKeyRendersAsFailure(): Unit {
    // 负控（R1-02）：旧代码 `boolAt(v,"applied",true)` 把这个桩渲染成
    // 「✓ …标记达成」，与详情页的「未完成」红 pill 并排自相矛盾。
    let v = Json.parse(MILESTONE_ERROR_STUB).getOrThrow()
    let (line, ok) = milestoneResultOf("里程碑「nosuch」标记达成", v,
        "未找到里程碑：nosuch（MILESTONE_NOT_FOUND）")
    @Expect(line.startsWith("✗"))
    @Expect(line.contains("未找到里程碑：nosuch"))
    @Expect(!ok)
}

@Test
func milestoneAppliedFalseWithCleanExitIsStillAFailure(): Unit {
    // 引擎明说：同名 tag 规则会把写入压回（requested done、生效 open）。
    // 退出码 0 不代表生效 —— 结果行与红 pill 必须说同一句话。
    let v = Json.parse(
        "{\"project\":\"atlas\",\"milestone\":\"v1\",\"requested\":\"done\",\"status\":\"open\",\"applied\":false}").getOrThrow()
    let (line, ok) = milestoneResultOf("里程碑「v1」标记达成", v, "")
    @Expect(line.startsWith("✗"))
    @Expect(line.contains("open"))
    @Expect(!ok)
}

@Test
func milestoneSuccessPayloadKeepsTheCheckmarkAndStatus(): Unit {
    let v = Json.parse(
        "{\"project\":\"atlas\",\"milestone\":\"v1\",\"requested\":\"done\",\"status\":\"done\",\"applied\":true}").getOrThrow()
    let (line, ok) = milestoneResultOf("里程碑「v1」标记达成", v, "")
    @Expect(line.startsWith("✓"))
    @Expect(line.contains("done"))
    @Expect(ok)
}

@Test
func milestoneRemoveSuccessIsNotMistakenForAFailure(): Unit {
    // remove 的成功载荷恒发 removed、**没有 applied/ok**（引擎 cli.cj 出口）。
    // 「结果键一个都没有才算失败」的口径必须容得下它，否则删除恒报 ✗。
    let v = Json.parse(
        "{\"project\":\"atlas\",\"milestone\":\"v1\",\"removed\":true}").getOrThrow()
    let (line, ok) = milestoneResultOf("里程碑「v1」删除", v, "")
    @Expect(line.startsWith("✓"))
    @Expect(ok)
}

@Test
func milestoneNonStringStatusDoesNotThrow(): Unit {
    // R4-05：status 不是字符串时，旧代码 `asStr(s).getOrThrow()` 在
    // app.post 里抛穿到 main，未捕获会杀死应用。现在按「没有 status」处理。
    let v = Json.parse(
        "{\"applied\":true,\"status\":42}").getOrThrow()
    let (line, ok) = milestoneResultOf("里程碑「v1」标记达成", v, "")
    @Expect(line.startsWith("✓"))
    @Expect(!line.contains("42"))
    @Expect(ok)
}

@Test
func engineFailureDescriptionReadsTheBoolErrorShape(): Unit {
    // R1-02：写失败桩的 error 是**布尔**不是字符串。只当字符串读的话，
    // 引擎给的原因会被丢成「引擎退出码 1（未给出原因）」。
    let res = ExecResult(1, MILESTONE_ERROR_STUB, "", false)
    let why = describeEngineFailure(res)
    @Expect(why.contains("未找到里程碑：nosuch"))
    @Expect(why.contains("MILESTONE_NOT_FOUND"))
    @Expect(!why.contains("未给出原因"))
}

// ---------------------------------------------------------------------------
// ISO 8601 解析：紧凑偏移与小数秒（R1-07）
// ---------------------------------------------------------------------------

@Test
func isoCompactOffsetsParseToTheSameInstantAsColonForm(): Unit {
    // 紧凑形 `±HHMM`：符号在 b[19]、oh 在 20、om 在 22。旧代码把 om 取在
    // 23（那是 `:MM` 的位置），紧凑形读出界，`+0800` 永远解析失败。
    let colon = parseIso8601Ms("2026-01-01T08:00:00+08:00").getOrThrow()
    @Expect(parseIso8601Ms("2026-01-01T08:00:00+0800").getOrThrow(), colon)
    let minusColon = parseIso8601Ms("2026-01-01T00:00:00-08:00").getOrThrow()
    @Expect(parseIso8601Ms("2026-01-01T00:00:00-0800").getOrThrow(), minusColon)
    // 西经负偏移把 UTC 时刻推后 8 小时（00:00-08:00 = 08:00Z）
    @Expect(minusColon - colon, 8 * 3600 * 1000)
}

@Test
func isoFractionalSecondsAreAcceptedWithMillisecondPrecision(): Unit {
    // 引擎 journal 的 `at` 实测带 9 位小数（…T09:36:32.800460121+08:00），
    // 旧实现整条拒绝 → 这类项目「多久没动」读不出来。
    let base = parseIso8601Ms("2026-01-01T00:00:00Z").getOrThrow()
    @Expect(parseIso8601Ms("2026-01-01T00:00:00.5Z").getOrThrow(), base + 500)
    @Expect(parseIso8601Ms("2026-01-01T00:00:00.25+08:00").getOrThrow(), base + 250 - 8 * 3600 * 1000)
    // 超过毫秒的位截断、不进位（0.9999 秒不能进成下一秒）
    @Expect(parseIso8601Ms("2026-01-01T00:00:00.9999Z").getOrThrow(), base + 999)
    @Expect(parseIso8601Ms("2026-01-01T00:00:00.800460121+08:00").getOrThrow(), base + 800 - 8 * 3600 * 1000)
    // `.` 后没有数字仍是形状不认识
    @Expect(parseIso8601Ms("2026-01-01T00:00:00.Z").isNone())
}

// ---------------------------------------------------------------------------
// 侧栏选中态：必须跨帧存活
// ---------------------------------------------------------------------------

@Test
func sidebarSelectionSurvivesARebuildInsteadOfBeingRebornEachFrame(): Unit {
    // CUI 的 `ListView` 点击**直接写**传入的 `selected`
    // （`selection_widgets.cj` 的 handle），它自己的滚动状态特意用
    // `localState(key)` 持久化，注释写着「a fresh State each frame would reset」——
    // 选中没做同样保护，因为设计上假定外部传进来的是**持久实例**。
    //
    // 原来侧栏传的是 `State<Int64>(0)`：每次重建都造一个新实例，
    // 点击写进那个临时实例，下一帧就没了 —— **侧栏点了不换页**。
    // 旁证：`goView` / `goProject` 两个写入口当时已写好，却从未被任何地方调用。
    let model = AppModel(EngineLocation("", "", ""))

    // 模拟「用户点了第 2 行（看板）」→ 控件写入选中态
    model.viewIndex.value = 1
    model.selected.value = 2

    // 下一帧重建：视图重新从模型取选中态
    let viewSel = viewSelection(model)
    let projSel = projectSelection(model)

    // 重建后选中态必须还在。全新的 State 会把它们抹回初值。
    @Expect(viewSel.value, 1)
    @Expect(projSel.value, 2)
}

@Test
func goViewAndGoProjectAreActuallyReachableFromTheSidebar(): Unit {
    // 「写入口存在但没人调用」是接线漏掉的那一步，光看函数定义看不出来 ——
    // 判据必须从**用户动作**出发，走完整条路。
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)

    // 视图组：写入选中态 → goView → 路由真的变了
    model.viewIndex.value = 1
    goView(model, model.viewIndex.value)
    @Expect(rootSectionIs(model.root.value, RootSection.Board))

    // 越界/未选中的哑操作不许把路由写成垃圾
    model.viewIndex.value = 9
    goView(model, model.viewIndex.value)
    @Expect(rootSectionIs(model.root.value, RootSection.Board))

    // 仓库组：写入选中态 → goProject → 选中项目 + 进详情
    model.selected.value = 0
    goProject(model, model.selected.value)
    @Expect(model.selectedProject.value, "fresh")
    @Expect(rootSectionIs(model.root.value, RootSection.Project))
    // 进详情时视图组撤掉高亮；这一步不能回环（goView(-1) 必须是哑操作）
    @Expect(model.viewIndex.value, -1)
    goView(model, model.viewIndex.value)
    @Expect(rootSectionIs(model.root.value, RootSection.Project))
}

@Test
func everyWayIntoAProjectAlsoMovesTheSidebarHighlightWithIt(): Unit {
    // 侧栏高亮改成**持久 State** 之后，它不再每帧从 `selectedProject` 现算，
    // 于是「碰巧对」的那个巧合没了：谁切了主区，谁就得负责把高亮跟上。
    // 不跟上的症状不是抽象的 —— 主区已经是 B，侧栏还亮着 A。
    //
    // 这里是三条**互不相同**的入口，漏掉任何一条都会留下高亮错位：
    // 侧栏点（`goProject`）、范围下拉（`applyScope`）、看板卡「打开」（`openProject`）。
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())

    // 路径 1：范围下拉选第 3 个项目（noread）
    let a = AppModel(EngineLocation("", "", ""))
    a.snapshot.value = Some(s)
    applyScope(a, 3)
    @Expect(a.selectedProject.value, "noread")
    @Expect(a.selected.value, 2) // 侧栏仓库组亮第 3 行
    @Expect(a.viewIndex.value, -1) // 视图组不亮：详情不属于那三个视图

    // 路径 2：看板卡「打开」第 2 个项目（old）
    let b = AppModel(EngineLocation("", "", ""))
    b.snapshot.value = Some(s)
    openProject(b, "old")
    @Expect(b.selected.value, 1)
    @Expect(b.viewIndex.value, -1)

    // 路径 3：从全局回退到「仪表盘」→ 视图组必须亮回第 0 行，仓库组撤掉。
    // 漏这一步的症状是：主区是仪表盘，侧栏的「看板」还亮着。
    applyScope(a, 0)
    @Expect(a.viewIndex.value, 0)
    @Expect(a.selected.value, -1)
}

@Test
func aProjectHiddenByTheSearchBoxGetsNoHighlightInsteadOfRowZero(): Unit {
    // 「这一行看不见」与「这一行是第 0 行」是两件事。
    // 搜索把目标项目滤掉时若回落成 0，侧栏就会高亮一个**不相干的仓库** ——
    // 比不高亮更糟，因为用户会以为点错了。
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)
    model.query.value = "noread" // 只剩第 1 个项目显示

    @Expect(sidebarProjectIndex(model, "noread"), 0)
    @Expect(sidebarProjectIndex(model, "fresh"), -1) // 看不见 → -1，不是 0
}

@Test
func openProjectIsIdempotentInsteadOfRecursingThroughItsOwnObserver(): Unit {
    // `openProject` 写 `model.selected`，那会触发 `selected` 的观察者
    // `goProject`，而 `goProject` 又调回 `openProject`。
    // 普通 `State` 的 `value = x` 在**值没变时照样通知**（`state.cj` 的 setter
    // 不比较旧值），所以这里必须幂等 —— 否则是无条件写 → 通知 → 再写 → 再通知，
    // 直接爆栈。
    //
    // ⚠ 这条判据**必须真的注册观察者**，否则测的是另一回事：
    // 没人监听时，写多少遍都不会递归，判据恒绿。
    // 所以这里手动装上 `sidebar.cj` 里那两个观察者（`observeSidebarSelection`
    // 要 `mountEffect`，判据不开窗）。
    // 不装 `selectedProject` 的那个 —— 它会真去拉引擎起子进程。
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)
    model.selected.observe({_, v => goProject(model, v)})
    model.viewIndex.observe({_, v => goView(model, v)})

    openProject(model, "noread")
    @Expect(model.selected.value, 2)
    @Expect(model.viewIndex.value, -1)
    @Expect(model.selectedProject.value, "noread")

    // 再调两次同样的话：所有字段都不该变，而且**不许爆栈** ——
    // 爆栈会让整条判据红，这就是它的判据。
    openProject(model, "noread")
    openProject(model, "noread")
    @Expect(model.selectedProject.value, "noread")
    @Expect(model.selected.value, 2)
    @Expect(model.viewIndex.value, -1)
    @Expect(rootSectionIs(model.root.value, RootSection.Project))

    // 换个项目再回来：高亮必须跟着换，不能卡在上一行
    openProject(model, "old")
    @Expect(model.selected.value, 1)
    openProject(model, "noread")
    @Expect(model.selected.value, 2)
}

/// 夹具加载器必须真的把日志与文档**灌进 model**。
///
/// 【为什么单独一条】`theOnDiskFixtureCoversJournalAndDocsToo` 只读文件，
/// 验的是「夹具内容够不够」。可它**绕过了加载器** —— 于是把
/// `loadFromFixtureDir` 里 journal/docs 那两段 `match` 整段删掉，
/// 那条判据照样绿，而每一张快照里的「进度日志」「托管文档」会退回空态。
/// 空态不报错、不留痕，正是自查最怕的那种静默失效。
///
/// 加载器不依赖 UI：`EngineLocation` 是纯数据构造，`syncLabels` 只改 State，
/// 整条路径不碰引擎子进程、也不读写用户注册表。
///
/// 负控：删掉 `loadFromFixtureDir` 里的 journal 或 docs 分支，
/// 本条的 `entries` / `docs` 断言与 `n == 5` 会同时红。
@Test
func theFixtureLoaderActuallyPutsJournalAndDocsIntoTheModel(): Unit {
    let model = AppModel(EngineLocation("", "", ""))
    let n = loadFromFixtureDir(model, "tests/fixtures")

    // 5 份：status / dashboard / milestones / journal / docs。
    // 少任何一份都会在这里露出来，而不是等到看快照时才发现卡片是空的。
    @Expect(n, 5)

    // 日志：三种口径状态都得进得来，口径披露那一行才有东西可排版
    match (model.journal.value) {
        case Some(j) =>
            @Expect(j.entries.size >= 3)
            var unknown = 0
            var repoTotal = 0
            var blind = 0
            for (e in j.entries) {
                if (e.commitText().contains("口径未知")) { unknown += 1 }
                if (e.commitText().contains("累计")) { repoTotal += 1 }
                if (e.commitText() == "提交数读不出来") { blind += 1 }
            }
            @Expect(unknown >= 1)
            @Expect(repoTotal >= 1)
            @Expect(blind >= 1)
        case None => @Expect(false)
    }
    // 契约闸门过了才会是 Some，所以 Problem 必须是空的
    @Expect(model.journalProblem.value.isEmpty())

    // 文档：两份可读 + 一份读不出来，那条披露才有素材
    match (model.docs.value) {
        case Some(d) =>
            @Expect(d.docs.size >= 2)
            @Expect(d.unreadable.size >= 1)
        case None => @Expect(false)
    }
    @Expect(model.docsProblem.value.isEmpty())

    // 走完这一轮，状态栏不许说「尚未读取」—— 它读到了
    match (model.snapshot.value) {
        case Some(_) => @Expect(true)
        case None => @Expect(false)
    }
    @Expect(!model.dashboardProblem.value.isEmpty() == false)
}

/// 侧栏**点击**必须真的换页（ListView → State → 路由 这条反向链路）。
///
/// ⚠ 此前 118 条判据里没有一条覆盖它，原因是接线整段塞在 `mountEffect`
/// 的闭包里 —— 闭包要活动的 StateStore 才能执行，判据不开窗就跑不了。
/// 于是「把 `sidebar()` 里那行调用删掉」是完全静默的：
/// 侧栏从此点了不换页，而所有判据照绿。
///
/// 已有判据验的是**正方向**（`applyScope` / `openProject` / 回退
/// 三个入口把高亮写对，见 `everyWayIntoAProjectAlsoMovesTheSidebarHighlightWithIt`），
/// 唯独少了这一条：UI 上**写** `selected` 之后有没有人接。
///
/// 顺带验一件容易踩空的事：`observe` 返回的 `StateObservation` 是
/// `Resource`，而 `installSidebarSelectionObservers` 把它**丢掉了**。
/// 若丢弃等于注销，观察者等于没装 —— 本条会红。
@Test
func clickingTheSidebarActuallyRoutesBecauseSomebodyIsListening(): Unit {
    let s = StatusSnapshot.from(Json.parse(SPAN_PROJECTS).getOrThrow())
    let model = AppModel(EngineLocation("", "", ""))

    // 不装观察者时，写 `selected` 什么都不会发生 —— 这就是「接线被删」的症状。
    // 先记下这个「坏掉的基线」，免得后面的绿没有参照。
    model.snapshot.value = Some(s)
    model.selected.value = 1
    @Expect(model.selectedProject.value.isEmpty())

    // 装上侧栏接线（`sidebar()` 里走 mountEffect 的那条）。
    // ⚠ 必须把返回值绑住：`StateObservation` 是 Resource，析构即 close()，
    // 不绑住等于装上又立刻取消 —— 那正是本条要防的「静默失效」的另一种形状。
    let obs = installSidebarSelectionObservers(model)

    // 点「视图」组第 1 行（看板）→ 主区必须是看板，且仓库组撤掉高亮
    model.viewIndex.value = 1
    @Expect(rootSectionIs(model.root.value, RootSection.Board))
    @Expect(model.selectedProject.value.isEmpty())
    @Expect(model.selected.value, -1)

    // 点「仓库」组第 2 个项目 → 主区必须是它的详情
    model.selected.value = 1
    @Expect(model.selectedProject.value, "old")
    @Expect(rootSectionIs(model.root.value, RootSection.Project))
    @Expect(model.viewIndex.value, -1)

    // goView(-1) 必须是哑操作，否则「进详情时撤掉视图组高亮」会自触发回环
    model.viewIndex.value = -1
    @Expect(model.selectedProject.value, "old")

    // 收尾：显式 close 之后，观察者必须**真的不再被叫**。
    // 这一条同时验住了上面那个「析构即取消」的判断 ——
    // 若 close 形同虚设，close 之后再写 `selected` 仍会换页，本条红。
    obs.close()
    let before = model.selectedProject.value
    model.selected.value = 2
    @Expect(model.selectedProject.value, before)
}

// ---------------------------------------------------------------------------
// CUI 美学批次（R2-01 / R2-02 / R2-03 / R2-04 / R2-05 / R2-07）
//
// 这一族的共同点：**病在视图，判据却验不了视图** —— .enabled 的方向写反
// 不点真按钮看不出来，「整层零消费」纯函数全绿。所以除了能抽成纯函数的，
// 还配了**源码扫描**：cjpm test 从包根跑，`src/...` 可读（与夹具判据同约定）。
// 源码扫描验的是「这行代码还在不在」，语义由各自的纯函数判据兜住。
// ---------------------------------------------------------------------------

/// 读一份 src 源码文本。读不到 = 判据环境不对（文件被挪走），
/// 按 `@Expect(false)` 红，不静默放过。
private func readSrcText(name: String): Option<String> {
    return readTextFileOf("src/${name}")
}

@Test
func primaryActionButtonsEnableWhenIdleNotWhenBusy(): Unit {
    // R2-01 回归：`.enabled(busy)` 方向写反 —— enabled(false)=禁用（框架
    // widget.cj 的语义，且禁用会打灰罩、吞事件），于是空闲时灰死、忙碌时
    // 可点却被 beginAction 的闸门拒绝，稳态永远点不动。
    // 同库里 `.enabled(!busy)`（AI 说明 / 重新索引 / 保存并测试）都是对的方向，
    // 可见是笔误不是约定 —— 扫源码钉死这两个文件不许再出现反写的形态。
    for (name in ["views.cj", "detail.cj"]) {
        match (readSrcText(name)) {
            case Some(text) => @Expect(!text.contains(".enabled(busy)"))
            case None => @Expect(false)
        }
    }
}

@Test
func sidebarAddHintNamesTheRealCommandInsteadOfLookingClickable(): Unit {
    // R2-02 回归：「＋ 添加 / 扫描项目」曾是一个强调色 Label —— 长得能点、
    // 点不动（CUI 没有目录选择器，客户端起不了「挑目录扫描」）。
    // 降级成说明文字后，它必须把**真实可执行**的命令写给用户：
    // 命令名与参数占位符少一个，这句话就退化成了一句空提示。
    let hint = sidebarAddHint()
    @Expect(hint.contains("moongit scan"))
    @Expect(hint.contains("<目录>"))
}

@Test
func appearanceChoicesRoundTripThroughDropdownIndices(): Unit {
    // R2-03：三档外观曾整层零 UI 消费。下拉按下标工作，映射必须可逆 ——
    // 三档往返后还是同一档；越界下标回落「跟随系统」，
    // 与 dsAppearanceFrom 对未知字符串的口径一致（不猜）。
    for (a in [DsAppearance.System, DsAppearance.Light, DsAppearance.Dark]) {
        @Expect(appearanceIs(a, appearanceAt(appearanceIndex(a))))
        @Expect(appearanceChoices()[appearanceIndex(a)], dsAppearanceLabel(a))
    }
    @Expect(appearanceIs(appearanceAt(-1), DsAppearance.System))
    @Expect(appearanceIs(appearanceAt(99), DsAppearance.System))
}

@Test
func appearanceApplyNoteSaysRestartOnSuccessAndPassesTheWriteProblemThrough(): Unit {
    // R2-03：CUI 的 Theme 不可变、没有 setTheme —— 切换只落盘、重启生效。
    // 成功文案**必须**写明「重启后生效」，否则用户点了暗色看着界面没变，
    // 会以为按钮是坏的；失败时原样透传落盘原因（写不进去要说为什么）。
    let (okNote, ok) = appearanceApplyNote(DsAppearance.Dark, "")
    @Expect(ok)
    @Expect(okNote.contains("暗色"))
    @Expect(okNote.contains("重启"))
    let (badNote, bad) = appearanceApplyNote(DsAppearance.Dark, "外观设置没能写入 /x/settings.conf")
    @Expect(!bad)
    @Expect(badNote, "外观设置没能写入 /x/settings.conf")
}

@Test
func appearanceChoiceObserverSavesAndDisclosesWithoutTouchingDisk(): Unit {
    // R2-03 的接线本体：下拉下标 → 记档 + 落盘 + 披露。落盘动作由参数注入
    //（假写，不碰真实 ~/.config），close 之后观察者必须真的不再被叫。
    let model = AppModel(EngineLocation("", "", ""))
    let wrote = ArrayList<String>()
    let obs = model.appearanceIndex.observe({_, v =>
        applyAppearanceChoiceBy(model, v, write: {a =>
            wrote.add(dsAppearanceKey(a))
            ""
        })
    })
    model.appearanceIndex.value = 2
    @Expect(appearanceIs(model.appearance.value, DsAppearance.Dark))
    @Expect(wrote.size, 1)
    @Expect(wrote[0], "dark")
    @Expect(model.appearanceNoteOk.value)
    @Expect(model.appearanceNote.value.contains("重启"))
    obs.close()
    model.appearanceIndex.value = 1
    // close 之后：档位不动、落盘不再发生
    @Expect(appearanceIs(model.appearance.value, DsAppearance.Dark))
    @Expect(wrote.size, 1)
}

@Test
func appearanceSettingsPaneActuallyConsumesTheAppearanceLayer(): Unit {
    // R2-03 的病根是「能存、能读、没人消费」：saveAppearance / appearance /
    // appearanceUnknown 在 appearance.cj 之外零引用，判据个个全绿，
    // 用户却换不了主题。纯函数测不出「没人消费」，扫设置页源码：
    // 下拉接线、未知披露两样都必须真的被视图引用。
    match (readSrcText("ai_view.cj")) {
        case Some(text) =>
            @Expect(text.contains("installAppearanceChoiceObserver"))
            @Expect(text.contains("appearanceChoices("))
            @Expect(text.contains("model.appearanceUnknown.value"))
        case None => @Expect(false)
    }
}

// ---------------------------------------------------------------------------
// R2-04：状态色文字的对比度
// ---------------------------------------------------------------------------

/// sRGB 单通道 → 线性值（WCAG 2.x 公式）。
private func linearChannel(v: Int64): Float64 {
    let c = Float64(v) / 255.0
    return (if (c <= 0.04045) { c / 12.92 } else { pow((c + 0.055) / 1.055, 2.4) })
}

private func relLum(hex: Int64): Float64 {
    return 0.2126 * linearChannel((hex >> 16) & 0xFF) + 0.7152 * linearChannel((hex >> 8) & 0xFF)
        + 0.0722 * linearChannel(hex & 0xFF)
}

/// WCAG 相对对比度。
private func contrastRatio(a: Int64, b: Int64): Float64 {
    let la = relLum(a)
    let lb = relLum(b)
    let hi = (if (la > lb) { la } else { lb })
    let lo = (if (la > lb) { lb } else { la })
    return (hi + 0.05) / (lo + 0.05)
}

/// 胶囊底色的合成结果：原色按 alpha 铺在底色上（与 dsPillBg 同一算式）。
/// 判据要用它算「文字压在自己颜色的胶囊底上」的真实对比度。
private func alphaOver(fg: Int64, alpha: Int64, bg: Int64): Int64 {
    let a = Float64(alpha) / 255.0
    func ch(f: Int64, g: Int64): Int64 {
        return Int64(Float64(f) * a + Float64(g) * (1.0 - a))
    }
    return (ch((fg >> 16) & 0xFF, (bg >> 16) & 0xFF) << 16)
        | (ch((fg >> 8) & 0xFF, (bg >> 8) & 0xFF) << 8)
        | ch(fg & 0xFF, bg & 0xFF)
}

@Test
func statusTextVariantsMeetContrastOnLightSurfacesWhileDarkKeepsTheBrightOnes(): Unit {
    // R2-04：#EAB308 直接当文字压在白卡上只有 1.92:1、#F97316 只有 2.8:1
    //（WCAG 正文 4.5:1）。亮色主题必须走深变体，且在它的两个真实落点
    //（白卡 / 自己颜色的胶囊底）都达标；暗色主题亮色本来就是对的，保持原值。
    @Expect(dsTextColor(C_YELLOW, true), C_YELLOW)
    @Expect(dsTextColor(C_ORANGE, true), C_ORANGE)
    // 没配变体的色原样透传 —— 变体表只收真正读不清的那几档
    @Expect(dsTextColor(C_RED, false), C_RED)
    @Expect(dsTextColor(C_ACCENT, false), C_ACCENT)
    for (c in [C_YELLOW, C_ORANGE]) {
        let t = dsTextColor(c, false)
        @Expect(contrastRatio(t, CARD_LIGHT) >= 4.5)
        @Expect(contrastRatio(t, alphaOver(c, 30, CARD_LIGHT)) >= 4.5)
        // 变体必须真的比原色可读，否则「换档」就是换了个说法
        @Expect(contrastRatio(t, CARD_LIGHT) > contrastRatio(c, CARD_LIGHT))
    }
}

// ---------------------------------------------------------------------------
// R2-05：字号只许有一套刻度
// ---------------------------------------------------------------------------

@Test
func fontScaleIsTheSevenStepsAndTokensFileCarriesNoSecondScale(): Unit {
    // R2-05：字号曾有两套表并存（tokens.cj 的 FS_* 与 components.cj 的 fs*），
    // FS_* 全仓零引用已删。这里钉住唯一一套的七个取值；
    // tokens.cj 里不许再长出第二张字号表。
    @Expect(fsMicro(), 10.0)
    @Expect(fsLabel(), 11.0)
    @Expect(fsBody(), 12.0)
    @Expect(fsCard(), 13.0)
    @Expect(fsSection(), 15.0)
    @Expect(fsTitle(), 17.0)
    @Expect(fsDisplay(), 22.0)
    match (readSrcText("tokens.cj")) {
        case Some(text) => @Expect(!text.contains("public let FS_"))
        case None => @Expect(false)
    }
}

/// `text` 里有没有「fontSize( 后面不是 fs*/mdHeadingSize」的调用。
/// 逐字节扫：fontSize( 之后只允许 `f`（fs* 刻度）或 `m`
///（markdown 渲染器照抄 macOS 端的 mdHeadingSize 独立映射）。
private func hasBareFontSizeCall(text: String): Bool {
    let bytes = text.toArray()
    let needle: Array<UInt8> = "fontSize(".toArray()
    let n = Int64(needle.size)
    var i: Int64 = 0
    while (i + n < Int64(bytes.size)) {
        var hit = true
        for (j in 0..Int64(needle.size)) {
            if (bytes[i + j] != needle[j]) {
                hit = false
                break
            }
        }
        if (hit) {
            let next = bytes[i + n]
            if (next != 0x66u8 && next != 0x6Du8) { // 'f' / 'm'
                return true
            }
        }
        i += 1
    }
    return false
}

@Test
func viewSourcesCarryNoBareFontSizeLiterals(): Unit {
    // R2-05：185+ 处裸 `.fontSize(12.0)` 一类散值已收进刻度。
    // 扫源码防回添：`fontSize(` 后面只许是 fs*() 或 mdHeadingSize()。
    // 逐文件红，坏的哪个看得见。
    for (name in ["views.cj", "detail.cj", "sidebar.cj", "components.cj", "ai_view.cj", "markdown_view.cj"]) {
        match (readSrcText(name)) {
            case Some(text) => @Expect(!hasBareFontSizeCall(text))
            case None => @Expect(false)
        }
    }
}

// ---------------------------------------------------------------------------
// R2-07：筛选 chip 换框架 Chip 后的双向绑定
// ---------------------------------------------------------------------------

@Test
func commitFilterChipLensTogglesOnlyAndFallsBackToAll(): Unit {
    // R2-07：dsFilterChip 曾用 Button + 自绘 style（整体覆盖交互表面，
    // 无 hover/按下反馈），换框架 Chip 后选中态经 State.project 镜头
    // 双向绑到筛选值上 —— 判据直接驱动镜头，验三条语义：
    // ①选中态从筛选值推导（chip 自己不另存一份）；
    // ②点亮 = Only(类型)，再点一下（熄灭）= 回「所有」；
    // ③「所有提交类型」是重置位，没有「熄灭」态。
    let model = AppModel(EngineLocation("", "", ""))
    let feat = commitFilterLens(model, DashCommitFilter.Only("feat"))
    @Expect(!feat.value)
    feat.value = true
    @Expect(commitFilterEquals(model.dashCommits.value, DashCommitFilter.Only("feat")))
    @Expect(feat.value)
    feat.value = false
    @Expect(commitFilterIsAll(model.dashCommits.value))
    // 换一颗 chip：点亮新的，旧的自动回到未选（单一筛选源，不是多选）
    feat.value = true
    let fix = commitFilterLens(model, DashCommitFilter.Only("fix"))
    @Expect(!fix.value)
    fix.value = true
    @Expect(!feat.value)
    @Expect(commitFilterEquals(model.dashCommits.value, DashCommitFilter.Only("fix")))
    let all = commitFilterLens(model, DashCommitFilter.AllCommits)
    @Expect(!all.value) // 此刻筛选在 Only("fix")，「所有」那颗是熄灭的
    all.value = true
    @Expect(commitFilterIsAll(model.dashCommits.value))
    @Expect(!fix.value)
    // 重置位没有「熄灭」态：再点一下它，筛选仍是「所有」
    all.value = false
    @Expect(commitFilterIsAll(model.dashCommits.value))
}

// ---------------------------------------------------------------------------
// T1：破坏性操作确认（mac 端 `DestructiveGuard.swift` 的移植）
//
// 病在视图、判据却开不了窗 —— 与 .enabled 反写那一族同款：
// 除了能抽成纯函数的判定与文案，还配了源码扫描钉
// 「四个按钮回调必须经确认状态机」，并跑过负控验红。
// ---------------------------------------------------------------------------

@Test
func needsConfirmationCoversExactlyTheFourDestructiveKinds(): Unit {
    @Expect(needsConfirmation(DestructiveAction.RemoveMilestone))
    @Expect(needsConfirmation(DestructiveAction.DropMilestone))
    // 「深/浅更新全部」= BulkUpdate —— 引擎会逐项目改写托管文档
    @Expect(needsConfirmation(DestructiveAction.BulkUpdate))
    // 引擎的 commit 走 git add -A，提交的是**整个工作区**
    @Expect(needsConfirmation(DestructiveAction.CommitAll))
    // 负控（防确认范围扩散）：达成/重开是可逆的状态切换，**故意**不在集合里。
    // 把它挪进来本条立刻红 —— 那是在教用户「确认疲劳」，
    // 比不确认更糟：真正的破坏性操作也会一起被忽略。
    @Expect(!needsConfirmation(DestructiveAction.SetMilestoneStatus))
}

@Test
func milestoneVerbMapsToExactlyTheGuardKinds(): Unit {
    // 引擎动词 → 守卫档。认不出的动词必须落「免确认」档：
    // 档位判错的方向只能是「少弹框」，不能是「把未知动词当成删除」。
    @Expect(destructiveActionIs(milestoneActionKind("remove"), DestructiveAction.RemoveMilestone))
    @Expect(destructiveActionIs(milestoneActionKind("drop"), DestructiveAction.DropMilestone))
    @Expect(destructiveActionIs(milestoneActionKind("done"), DestructiveAction.SetMilestoneStatus))
    @Expect(destructiveActionIs(milestoneActionKind("open"), DestructiveAction.SetMilestoneStatus))
    @Expect(destructiveActionIs(milestoneActionKind(""), DestructiveAction.SetMilestoneStatus))
}

@Test
func guardTextNamesTheSubjectAndStatesTheCost(): Unit {
    // 标题必须点名**具体对象**，不能只说「确认吗」——
    // 用户要知道自己确认的是哪一个。
    @Expect(guardTitle(DestructiveAction.RemoveMilestone, "接入统一登录"), "删除里程碑「接入统一登录」？")
    @Expect(guardTitle(DestructiveAction.DropMilestone, "接入统一登录"), "放弃里程碑「接入统一登录」？")
    // 正文必须说清代价：引擎不留备份、没有回收站、无法恢复。
    // 「删除」而不说「不可恢复」，等于让用户以为还能撤销。
    let m = guardMessage(DestructiveAction.RemoveMilestone, "接入统一登录")
    @Expect(m.contains("接入统一登录"))
    @Expect(m.contains("不留备份"))
    @Expect(m.contains("无法恢复"))
    // drop 与 remove 代价不同（可重开 vs 不可逆），不许共用一句话
    let d = guardMessage(DestructiveAction.DropMilestone, "接入统一登录")
    @Expect(d.contains("已放弃"))
    @Expect(d != m)
    // 确认按钮要说**会发生什么**，不是「确定」——
    // 「确定/取消」挨着放时，用户得靠位置猜「确定」是确定什么。
    @Expect(guardConfirmLabel(DestructiveAction.RemoveMilestone), "删除")
    @Expect(guardConfirmLabel(DestructiveAction.DropMilestone), "放弃")
    @Expect(guardConfirmLabel(DestructiveAction.BulkUpdate), "全部更新")
    @Expect(guardConfirmLabel(DestructiveAction.CommitAll), "全部提交")
    // 染色：不可逆三类染危险色；批量更新有备份、可回滚，不染 ——
    // 满屏红会稀释「红=危险」这个信号。
    @Expect(guardIsDestructiveRole(DestructiveAction.RemoveMilestone))
    @Expect(guardIsDestructiveRole(DestructiveAction.DropMilestone))
    @Expect(guardIsDestructiveRole(DestructiveAction.CommitAll))
    @Expect(!guardIsDestructiveRole(DestructiveAction.BulkUpdate))
    @Expect(!guardIsDestructiveRole(DestructiveAction.SetMilestoneStatus))
}

@Test
func safeSubjectFallsBackToUnnamedForBlankInput(): Unit {
    @Expect(safeSubject("接入统一登录"), "接入统一登录")
    @Expect(safeSubject("   "), "未命名")
    @Expect(safeSubject(""), "未命名")
    // 空名不许渲染成「删除里程碑「」？」—— 用户不知道自己在删什么
    @Expect(guardTitle(DestructiveAction.RemoveMilestone, safeSubject("")), "删除里程碑「未命名」？")
    @Expect(commitTitle("atlas"), "在「atlas」里提交全部改动？")
    @Expect(commitTitle("  "), "在「未命名」里提交全部改动？")
}

@Test
func commitScopeTextStaysDistinguishableAcrossTheThreeStates(): Unit {
    // 三态必须**可区分**，不能塌成一句「若干改动」：
    // 0 个 ⇒ 不该走到确认（没有可提交的东西）
    let zero = CommitAllScope(0, 0, 0)
    @Expect(zero.willCommit(), 0)
    @Expect(commitScopeText(zero), "当前没有待提交的内容")
    // 含未跟踪 ⇒ 单独点名密钥风险 —— 这是最容易出事的一种（误提交 .env/密钥）
    let mixed = CommitAllScope(2, 3, 0)
    @Expect(mixed.willCommit(), 5)
    let mixedLine = commitScopeText(mixed)
    @Expect(mixedLine.contains("5 个文件"))
    @Expect(mixedLine.contains("2 个已改动"))
    @Expect(mixedLine.contains("3 个未跟踪"))
    @Expect(mixedLine.contains("密钥"))
    // 只有已改动 ⇒ 报数量，且不出现密钥那句（没有未跟踪就没有这个风险）
    let trackedOnly = CommitAllScope(4, 0, 0)
    @Expect(trackedOnly.willCommit(), 4)
    let trackedLine = commitScopeText(trackedOnly)
    @Expect(trackedLine.contains("4 个文件"))
    @Expect(trackedLine.contains("4 个已改动"))
    @Expect(!trackedLine.contains("密钥"))
    // 暂存数大于「已改动+未跟踪」时取大者（保守上界，mac 端同一条算式）
    @Expect(CommitAllScope(1, 2, 9).willCommit(), 9)
}

@Test
func commitScopeReadsOnlyTheCountersTheEngineSends(): Unit {
    // mac 端 DetailViews.commitScope 同款：引擎只有 userDirtyCount /
    // untrackedCount 两个口径，「已暂存」恒 0 —— **不编造**。
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow()))
    // atlas 实测 userDirtyCount=2、载荷里没有 untrackedCount → 上界 2
    let s = commitAllScopeOf(model, "atlas")
    @Expect(s.trackedModified, 2)
    @Expect(s.untracked, 0)
    @Expect(s.staged, 0)
    @Expect(s.willCommit(), 2)
    // 读不出来的 -1 不许参与计数 —— 负数上界比 0 更谎
    @Expect(commitAllScopeOf(model, "gone").willCommit(), 0)
    // 不在列表里的项目 → 空范围，正文落「当前没有待提交的内容」
    @Expect(commitScopeText(commitAllScopeOf(model, "nosuch")), "当前没有待提交的内容")
}

@Test
func bulkUpdateMessageReportsScopeAndBackupNotFalseAlarm(): Unit {
    // 0 个 ⇒ 明说不会做任何事，不是「将对 0 个项目执行」
    @Expect(bulkUpdateMessage(0, false), "当前没有已注册的项目，不会做任何事。")
    let shallow = bulkUpdateMessage(15, false)
    @Expect(shallow.contains("15 个项目"))
    @Expect(shallow.contains("浅更新"))
    // 只**报范围**不报「不可逆」：每个被改写的文件都先留备份、可回滚，
    // 弹「你确定要删东西吗」式红字会把真正的不可逆操作稀释掉。
    @Expect(shallow.contains("留备份"))
    @Expect(!shallow.contains("无法恢复"))
    // 深更新那一轨要说清多了什么（AI 重新生成），且数字跟着项目数走
    let deep = bulkUpdateMessage(1, true)
    @Expect(deep.contains("1 个项目"))
    @Expect(deep.contains("AI"))
    @Expect(!deep.contains("15"))
}

@Test
func pendConfirmSuspendsDestructiveActionsAndRefusesTheReversibleOnes(): Unit {
    let model = AppModel(EngineLocation("", "", ""))
    @Expect(!model.confirmOpen.value)
    @Expect(model.pendingConfirm.isNone())

    // 破坏性动作：挂起 + 开框，而不是当场执行
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.RemoveMilestone,
        project: "atlas", name: "v1", op: "remove")))
    @Expect(model.confirmOpen.value)
    match (model.pendingConfirm) {
        case Some(p) =>
            @Expect(destructiveActionIs(p.action, DestructiveAction.RemoveMilestone))
            @Expect(p.project, "atlas")
            @Expect(p.name, "v1")
            @Expect(p.op, "remove")
        case None => @Expect(false)
    }

    // 取消：框与挂起动作**一起**清 —— 只关框不清挂起态的话，
    // 下次确认按钮会替用户执行上一个动作。
    cancelConfirm(model)
    @Expect(!model.confirmOpen.value)
    @Expect(model.pendingConfirm.isNone())

    // 负控（防确认范围扩散）：免确认档必须被拒 —— 框不开、状态不挂。
    @Expect(!pendConfirm(model, PendingConfirm(DestructiveAction.SetMilestoneStatus,
        project: "atlas", name: "v1", op: "done")))
    @Expect(!model.confirmOpen.value)
    @Expect(model.pendingConfirm.isNone())
}

@Test
func confirmDialogTextPerKindNamesItsObjectAndStatesTheCost(): Unit {
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(StatusSnapshot.from(Json.parse(NEW_ENGINE_STATUS).getOrThrow()))

    // 里程碑删除：点名对象 + 代价句
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.RemoveMilestone,
        project: "atlas", name: "接入统一登录", op: "remove")))
    @Expect(confirmHeadingOf(model), "删除里程碑「接入统一登录」？")
    @Expect(confirmBodyOf(model).contains("不留备份"))
    @Expect(confirmBodyOf(model).contains("无法恢复"))
    @Expect(confirmButtonLabelOf(model), "删除")

    // 提交：标题带仓库名、正文报**真实数量**（atlas 实测 2 处未提交）
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.CommitAll,
        project: "atlas", op: "commit", message: "feat: x")))
    @Expect(confirmHeadingOf(model), "在「atlas」里提交全部改动？")
    @Expect(confirmBodyOf(model).contains("2 个文件"))
    @Expect(confirmButtonLabelOf(model), "全部提交")

    // 批量更新：标题带轨道、正文报项目数（夹具 2 个项目）与 AI 轨差分
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.BulkUpdate, deep: true)))
    @Expect(confirmHeadingOf(model), "全部深更新？")
    @Expect(confirmBodyOf(model).contains("2 个项目"))
    @Expect(confirmBodyOf(model).contains("AI"))
    @Expect(confirmButtonLabelOf(model), "全部更新")

    // 放弃：与删除的代价句不同（可重开 vs 不可逆）
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.DropMilestone,
        project: "atlas", name: "v1", op: "drop")))
    @Expect(confirmHeadingOf(model), "放弃里程碑「v1」？")
    @Expect(confirmBodyOf(model).contains("已放弃"))
    @Expect(confirmBodyOf(model) != guardMessage(DestructiveAction.RemoveMilestone, "v1"))
    cancelConfirm(model)
    @Expect(confirmHeadingOf(model), "")
}

@Test
func destructiveButtonCallbacksGoThroughTheConfirmationGate(): Unit {
    // T1 回归（两路调查独立命中同一缺口）：里程碑「放弃/删除」直连
    // actMilestone(…"drop"/"remove")、「提交」直连 actGit(…"commit")、
    // 全局双轨/重新索引直连 actUpdate —— 全仓确认逻辑零命中。
    // 四个回调必须经确认状态机（requestMilestoneAction / requestCommit /
    // requestUpdate），直连形态一律不许再出现在视图源码里。
    //
    // ⚠ 负控已验：把「删除」改回直连 actMilestone(…"remove")，本条立刻红。
    match (readSrcText("detail.cj")) {
        case Some(text) =>
            // 里程碑四个动作全部经状态机（达成/重开走它的免确认直通档）
            @Expect(!text.contains("actMilestone("))
            @Expect(text.contains("requestMilestoneAction(app, model, m.projectName, m.name, \"drop\")"))
            @Expect(text.contains("requestMilestoneAction(app, model, m.projectName, m.name, \"remove\")"))
            // commit 不许以直连形态出现（含白名单排里的第二个「提交」）
            @Expect(!text.contains("actGit(app, model, p.name, \"commit\""))
            @Expect(text.contains("requestCommit(app, model, p.name, msg.value)"))
            // 按钮行必须用「去了 commit 的切片」——
            //（gitRowOps 自己的实现体也迭代白名单，所以这里只钉正形态：
            // 行循环一旦退回 gitWhitelist()，上面这条 contains 立刻红；
            // 行内成分由 gitRowOpsKeepsCommitOutOfTheQuickRow 纯函数钉住。）
            @Expect(text.contains("for (op in gitRowOps())"))
            // 详情页头的单项目更新**有意**保持直连（mac 端 .project 分支同口径）
            @Expect(text.contains("actUpdate(app, model, p.name, false)"))
        case None => @Expect(false)
    }
    match (readSrcText("views.cj")) {
        case Some(text) =>
            @Expect(!text.contains("actUpdate("))
            @Expect(text.contains("requestUpdate(app, model, updateTargetOf(model)"))
            @Expect(text.contains("requestUpdate(app, model, \"\", false)"))
            // Modal 必须真的挂在根视图上（此前全应用零使用）——
            // 守卫层写得再对，框没人挂就等于没做（教训与 R2-03 同族）
            @Expect(text.contains("Modal(model.confirmOpen"))
            @Expect(text.contains("runPendingConfirm(app, model)"))
        case None => @Expect(false)
    }
}

@Test
func gitRowOpsKeepsCommitOutOfTheQuickRow(): Unit {
    // 引擎白名单里有 commit（AI 工具校验要用它），但**按钮行**不许渲染它：
    // 它有专属按钮 + 确认框 —— 留在行里就是一个绕过确认、
    // 用空提交信息直连的第二个「提交」。
    let row = gitRowOps()
    @Expect(!row.contains("commit"))
    @Expect(row.contains("pull"))
    @Expect(row.contains("push"))
    @Expect(row.contains("stash"))
    // 白名单本身不动 —— 它镜像引擎契约，AI 工具校验还要用
    @Expect(gitWhitelist().contains("commit"))
}

// ---------------------------------------------------------------------------
// T1：确认 Modal 的无头镜头（框架 `WidgetTestHost`，不开真窗）
//
// 守卫层的纯函数判据验「判定与文案」，这两条验**呈现与接线**：
// 框只在挂起后在场上、内容点名挂起的动作、两颗按钮各自接对、Esc 走取消。
// 与 DD_SNAP_CONFIRM 快照互为补充 —— 快照机链不出来时（SDL 3.4 缺口），
// 这里就是确认框在场的证据。
// ---------------------------------------------------------------------------

@Test
func confirmModalLensPresentsThePendingActionAndWiresBothButtons(): Unit {
    let host = WidgetTestHost()
    let model = AppModel(EngineLocation("", "", ""))
    // 闭包不能捕获可变变量：用引用类型记录确认按钮是否被按下（appearance 判据同款）。
    let fired = ArrayList<String>()
    let view: () -> Unit = {=>
        destructiveConfirmModalBody(model, {=>
            // runPendingConfirm 的**状态一半**：取走挂起动作并收框
            // （拆出 takePendingConfirm 就是为了让镜头驱动得了这一半）。
            // 执行一半（runDestructive → actMilestone/actUpdate/actGit）要真引擎
            // 与 DesktopApp，镜头里以记录代替；它在真挂载里的接线由
            // destructiveButtonCallbacksGoThroughTheConfirmationGate 的扫描钉住。
            match (takePendingConfirm(model)) {
                case Some(p) => fired.add(confirmHeading(p))
                case None => ()
            }
        })
        ()
    }
    let vp = Rect(0.0, 0.0, 500.0, 400.0)

    // 框关着：不注册浮层 —— 隐藏的对话框零成本（框架契约）。
    let closed = host.frame(vp, body: view)
    @Expect(closed.metrics.overlayCount, 0)

    // 挂起「删除里程碑」：下一帧框在场，标题点名具体对象。
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.RemoveMilestone,
        project: "atlas", name: "接入统一登录", op: "remove")))
    let open = host.frame(vp, body: view)
    @Expect(open.metrics.overlayCount, 1)
    @Expect(confirmHeadingOf(model), "删除里程碑「接入统一登录」？")
    @Expect(confirmBodyOf(model).contains("无法恢复"))
    @Expect(confirmButtonLabelOf(model), "删除")

    // 确认路径：聚焦「删除」按回车 → onConfirm 恰好一次、框收起、挂起态清空。
    host.context.focus("dd-confirm-ok", viaKeyboard: true)
    let _ = host.frame(vp, events: [UiEvent.KeyDown(Key.Enter, false)], body: view)
    @Expect(fired.size, 1)
    @Expect(fired[0], "删除里程碑「接入统一登录」？")
    @Expect(!model.confirmOpen.value)
    @Expect(model.pendingConfirm.isNone())
    let after = host.frame(vp, body: view)
    @Expect(after.metrics.overlayCount, 0)

    // 取消路径：再挂起一次，聚焦「取消」按回车 → 什么都不执行，框与挂起态一起清。
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.DropMilestone,
        project: "atlas", name: "v1", op: "drop")))
    let open2 = host.frame(vp, body: view)
    @Expect(open2.metrics.overlayCount, 1)
    host.context.focus("dd-confirm-cancel", viaKeyboard: true)
    let _ = host.frame(vp, events: [UiEvent.KeyDown(Key.Enter, false)], body: view)
    @Expect(fired.size, 1) // 取消不触发确认
    @Expect(!model.confirmOpen.value)
    @Expect(model.pendingConfirm.isNone())
    host.reset()
}

@Test
func confirmModalLensEscapeDismissesWithoutRunning(): Unit {
    let host = WidgetTestHost()
    let model = AppModel(EngineLocation("", "", ""))
    let fired = ArrayList<String>()
    let view: () -> Unit = {=>
        destructiveConfirmModalBody(model, {=> fired.add("ran") })
        ()
    }
    let vp = Rect(0.0, 0.0, 500.0, 400.0)
    // Esc = 取消（框架 Modal 的 dismissOnEscape）→ onDismiss → cancelConfirm：
    // 框收起、挂起动作清空。这条钉的是「Esc 不会把挂起动作留在场上」——
    // 留下的旧挂起态会让下一次确认框执行上一个动作。
    @Expect(pendConfirm(model, PendingConfirm(DestructiveAction.CommitAll,
        project: "atlas", op: "commit", message: "x")))
    let _ = host.frame(vp, body: view)
    let _ = host.frame(vp, events: [UiEvent.KeyDown(Key.Escape, false)], body: view)
    @Expect(!model.confirmOpen.value)
    @Expect(model.pendingConfirm.isNone())
    @Expect(fired.size, 0)
    let after = host.frame(vp, body: view)
    @Expect(after.metrics.overlayCount, 0)
    host.reset()
}
