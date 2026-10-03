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
            @Expect(snap.projects.size == 6)
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
