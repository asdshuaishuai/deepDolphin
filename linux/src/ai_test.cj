// deepDolphin Linux 客户端 —— AI 层判据。
//
// 同样不开窗口、不连引擎、不发网络请求。
// 唯一碰真实外部依赖的两条（provider 目录、引擎 tools 载荷）用的是
// **本机真实输出**截下来的夹具，不是编的形状 ——
// 编出来的夹具会犯本项目最典型的那个错：断言的东西压根不是引擎发的。
package deepdolphin_linux

import std.collection.*
import std.env.*
import std.unittest.*
import std.unittest.testmacro.*

/// 引擎 `tools --json` 的**真实输出**（本机 `moongit tools --json`，原样截取）。
///
/// 这份夹具存在的全部理由是 `params` 那个字段：
/// 它是**逗号分隔的声明串**，不是 JSON Schema，而且带枚举注解
/// ——`"name,op(pull|push)"`。照着「params 是一段 JSON」去写的解析器
/// 会安静地返回空对象，然后模型每次调 `git_pull_push` 都失败。
private let REAL_TOOLS_PAYLOAD = """
{"tools":[
 {"name":"get_group_context","description":"获取整个项目群的总览上下文（活跃度/改动/分支/待合入）","params":""},
 {"name":"get_project_context","description":"获取单个项目的深度上下文（分支进度/脉搏/日志/里程碑）。params: name","params":"name"},
 {"name":"get_project_docs","description":"读取项目内 README/AGENTS/CLAUDE 原文。params: name","params":"name"},
 {"name":"get_journal","description":"读取项目的进度日志。params: name","params":"name"},
 {"name":"get_milestones","description":"列出全部里程碑及其 git 感知进度","params":""},
 {"name":"run_shallow_update","description":"对项目执行浅更新：记录各分支进度并刷新文档托管区域。params: name","params":"name"},
 {"name":"run_deep_update","description":"对项目执行深度更新：重写 overview/architecture/commands/history。params: name","params":"name"},
 {"name":"git_commit","description":"提交项目的全部未提交改动。params: name, message","params":"name,message"},
 {"name":"git_pull_push","description":"对项目执行 git pull（--ff-only）或 push。params: name, op(pull|push)","params":"name,op(pull|push)"},
 {"name":"milestone_done","description":"把里程碑标记为达成。params: project, name","params":"project,name"}
],"note":"引擎为 AI 无关内核；以上工具只声明能力与参数，怎么调用由调用方决定。"}
"""

/// 引擎 `docs --json` 的**真实键名**（实测：`docs` 而非 `files`，元素字段 `file` 而非 `path`）。
private let REAL_DOCS_PAYLOAD = """
{"project":"deepGit","docs":[{"file":"README.md","content":"# 项目说明","project":"deepGit"}],"unreadable":[]}
"""

private func realToolsPayload(): Payload {
    return Payload(Json.parse(REAL_TOOLS_PAYLOAD).getOrThrow(), "", false, 0, "", staleContract: false)
}

private func realDocsPayload(): Payload {
    return Payload(Json.parse(REAL_DOCS_PAYLOAD).getOrThrow(), "", false, 0, "", staleContract: false)
}

// ---------------------------------------------------------------------------
// JSON 写侧
// ---------------------------------------------------------------------------

@Test
func jsonWriterEscapesTheThingsThatWouldOtherwiseBreakTheRequest(): Unit {
    // 请求体里装着**用户自己打的字**和**模型返回的原文**。
    // 不转义的症状不是「报错」而是「偶发地 400」—— 极难定位。
    @Expect(jsonWrite(jstr("plain")), "\"plain\"")
    @Expect(jsonWrite(jstr("say \"hi\"")), "\"say \\\"hi\\\"\"")
    @Expect(jsonWrite(jstr("a\\b")), "\"a\\\\b\"")
    @Expect(jsonWrite(jstr("line1\nline2")), "\"line1\\nline2\"")
    @Expect(jsonWrite(jstr("tab\there")), "\"tab\\there\"")
    // 控制字符走 \u00XX
    @Expect(jsonWrite(jstr("\u{1}")), "\"\\u0001\"")
    // 中文与 emoji **原样输出**（逐字符转 \u 既慢又更容易写错）
    @Expect(jsonWrite(jstr("中文 🎯")), "\"中文 🎯\"")
}

@Test
func jsonWriterEmitsIntegersAsIntegersNotAsFixedPointNoise(): Unit {
    // `Float64.toString()` 在本工具链上是 `4000.000000`。
    // 那是合法 JSON，但 max_tokens 写成这样会被部分 provider 的参数校验挑刺。
    @Expect(jsonWrite(jnum(4000.0)), "4000")
    @Expect(jsonWrite(jnum(0.0)), "0")
    @Expect(jsonWrite(jnum(-1.0)), "-1")
    @Expect(jsonWrite(jnum(1.5)), "1.500000")
}

@Test
func jsonWriterRoundTripsThroughTheRealParser(): Unit {
    // 写完必须能被**本仓自己的解析器**读回来 —— 写侧和读侧是同一个契约。
    let original = "引号\" 反斜杠\\ 换行\n 尖括号<>& 制表\t 中文 🎯"
    let text = jsonWrite(jobjWith(original))
    let back = Json.strAt(Json.parse(text).getOrThrow(), "v", "")
    @Expect(back, original)
}

private func jobjWith(v: String): JsonValue {
    let p = ArrayList<(String, JsonValue)>()
    jobjAdd(p, "v", jstr(v))
    return jobj(p)
}

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

@Test
func onlyHttpsAndLocalhostHttpAreAllowedAsEndpoints(): Unit {
    // 这是一条**安全**规则：目录数据来自网络，攻击者改掉一个 api 字段
    // 就能让本客户端把 API Key 连同每次对话 POST 到他的服务器，
    // 而用户界面上看不出任何异常。
    @Expect(sanitizeBaseURL("https://api.deepseek.com"), "https://api.deepseek.com")
    @Expect(sanitizeBaseURL("HTTPS://api.deepseek.com"), "HTTPS://api.deepseek.com")
    @Expect(sanitizeBaseURL("http://localhost:11434"), "http://localhost:11434")
    @Expect(sanitizeBaseURL("http://127.0.0.1:1234/v1"), "http://127.0.0.1:1234/v1")
    // 下面这些一律拒绝
    @Expect(sanitizeBaseURL("http://api.deepseek.com"), "")
    @Expect(sanitizeBaseURL("ftp://x"), "")
    @Expect(sanitizeBaseURL(""), "")
    @Expect(sanitizeBaseURL("javascript:alert(1)"), "")
    // 带用户名的同形域名：前缀检查只认 scheme，https 之后什么都放行，
    // 这与 macOS 端一致 —— 真正的信任边界是「用户自己填的 URL」，
    // 而目录来源不可信才需要这条规则
    @Expect(sanitizeBaseURL("https://evil.example/x"), "https://evil.example/x")
}

@Test
func isConfiguredRefusesToPretendAnUnsetKeyIsConfigured(): Unit {
    // ollama 免 key —— 但**它不在 models.dev 目录里**（实测快照 225 家里没有它，
    // 因为它是本地运行时不是 provider）。所以 `effectiveBaseURL` 拿不到端点，
    // 用户必须手填 `http://localhost:11434/v1`。
    // 这条一开始被我写成「ollama 免 key 就该直接可用」，是判据写错了，不是代码错 ——
    // 而它错在**想当然**：以为 ollama 会像 openai 那样有目录端点。
    @Expect(!AIConfig(providerID: "ollama", model: "qwen", apiKey: "").isConfigured())
    // 手填本地端点后：免 key 也算配好（这才是「ollama 免 key」的真实含义）
    @Expect(AIConfig(providerID: "ollama", model: "qwen", baseURL: "http://localhost:11434/v1", apiKey: "").isConfigured())
    // 有端点但没 key → 没配好。
    // ⚠ 端点一律**显式给出**：不写 baseURL 时 `effectiveBaseURL` 要去查目录快照，
    // 而判据跑在「本机有没有装过快照」这个不确定的前提上 ——
    // 同一份判据在开发机（快照在）与 CI（快照不在）会给出相反结论。
    @Expect(!AIConfig(providerID: "deepseek", model: "x", baseURL: "https://api.deepseek.com", apiKey: "").isConfigured())
    // 目录里没有端点、用户也没填 → 没配好（openai 实测 api 就是 null）
    @Expect(!AIConfig(providerID: "openai", model: "gpt-4o", apiKey: "sk-x").isConfigured())
    // 用户手填端点后立刻可用
    @Expect(AIConfig(providerID: "openai", model: "gpt-4o", baseURL: "https://api.openai.com/v1", apiKey: "sk-x").isConfigured())
    // anthropic 有内置兜底端点
    @Expect(AIConfig(providerID: "anthropic", model: "claude", apiKey: "k").isConfigured())
    // 用户填了一个会被拒的端点 → 不因为「填了」就算配好
    @Expect(!AIConfig(providerID: "openai", model: "m", baseURL: "http://evil.example", apiKey: "k").isConfigured())
}

@Test
func aiErrorTextNeverEchoesCredentialsBack(): Unit {
    // 恶意/故障的服务器可以回显任何东西。局部替换漏一个变体就把密钥漏出去，
    // 所以命中模式就**整体**隐藏。
    @Expect(redactAI("Bearer sk-abc123"), "（响应含敏感字段，已隐藏）")
    @Expect(redactAI("your key sk-abc is bad"), "（响应含敏感字段，已隐藏）")
    @Expect(redactAI("x-api-key: whatever"), "（响应含敏感字段，已隐藏）")
    @Expect(redactAI("sk-ant-api03-xxxx"), "（响应含敏感字段，已隐藏）")
    // 普通内容原样保留 —— 一刀切隐藏等于把排查路径也砍了
    @Expect(redactAI("HTTP 429 rate limit"), "HTTP 429 rate limit")
}

// ---------------------------------------------------------------------------
// 引擎工具清单 → JSON Schema
// ---------------------------------------------------------------------------

@Test
func engineParamStringBecomesAJsonSchemaInsteadOfAnEmptyObject(): Unit {
    // 真实取值见 REAL_TOOLS_PAYLOAD。四种形状都要对。
    @Expect(engineParamsToSchema(""),
        "{\"type\":\"object\",\"properties\":{},\"required\":[]}")
    @Expect(engineParamsToSchema("name"),
        "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}")
    @Expect(engineParamsToSchema("name,message"),
        "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"message\":{\"type\":\"string\"}}," +
        "\"required\":[\"name\",\"message\"]}")
}

@Test
func engineParamEnumAnnotationBecomesAnEnumNotAParameterNamedOpPullPush(): Unit {
    // 真实取值 `"name,op(pull|push)"`。
    // 不解析那段括号的话，声明出来的参数名会是 `op(pull|push)`，
    // 症状是「模型永远填不出合法的 op」——看起来像模型能力问题。
    let schema = engineParamsToSchema("name,op(pull|push)")
    @Expect(schema.contains("\"op\":{\"type\":\"string\",\"enum\":[\"pull\",\"push\"]}"))
    @Expect(schema.contains("\"name\":{\"type\":\"string\"}"))
    @Expect(!schema.contains("op(pull"))
    // 两个参数都必填：漏标 required 的后果是模型少传、引擎报「未找到项目」，
    // 而模型侧完全无法自愈
    @Expect(schema.contains("\"required\":[\"name\",\"op\"]"))
}

@Test
func everyToolTheEngineDeclaresIsActuallyExecutableOnThisClient(): Unit {
    // 少映射一个工具，模型调用它时只会得到「客户端不认识这个工具」，
    // 用户看到的是「AI 助手不好用」，真因却是客户端的映射表少了一项。
    // 所以这张表必须与引擎 `tools --json` **逐个相等**。
    let declared = engineToolNames(realToolsPayload())
    let mapped = mappedToolNames()
    @Expect(declared.size, mapped.size)
    for (name in declared) {
        @Expect(mapped.contains(name))
    }
    for (name in mapped) {
        @Expect(declared.contains(name))
    }
}

@Test
func clientRequiredParamsMatchWhatTheEngineActuallyDeclares(): Unit {
    // 第二张对拍：参数。引擎说 `name,op(pull|push)`，客户端就得校验 name 与 op；
    // 少校验一个 = 一次能打中**别的**项目的调用。
    let p = realToolsPayload()
    for (t in Json.arrAt(p.value(), "tools")) {
        let name = Json.strAt(t, "name", "")
        let fromEngine = engineParamsToSchema(Json.strAt(t, "params", ""))
        let required = Json.strListAt(Json.parse(fromEngine).getOrThrow(), "required")
        let mine = toolRequiredParams(name)
        @Expect(required.size, mine.size)
        for (r in required) {
            @Expect(mine.contains(r))
        }
    }
}

@Test
func toolDefinitionsCarryTheEnginesOwnDescriptionNotAnInventedOne(): Unit {
    // 描述直接来自引擎清单。客户端自己编描述 = 两边说法不一致，
    // 而模型只看得见客户端给的那一份。
    let defs = engineToolDefinitions(realToolsPayload())
    @Expect(defs.size, 10)
    for (d in defs) {
        @Expect(!d.description.isEmpty())
        @Expect(!d.parametersJSON.isEmpty())
    }
}

// ---------------------------------------------------------------------------
// 工具执行
// ---------------------------------------------------------------------------

@Test
func missingParamsAreNamedInsteadOfJustSayingInvalidArguments(): Unit {
    // 工具结果会**原样进对话**，所以「参数错误」这四个字对模型毫无用处。
    let msg = missingMessage("git_commit", ["message"])
    @Expect(msg.contains("git_commit"))
    @Expect(msg.contains("message"))
    @Expect(!msg.contains("name"))
}

@Test
func docsPayloadUsesTheKeysTheEngineReallySends(): Unit {
    // 实测键名是 `docs` / 元素 `file`。写成 `files` / `path` 会拿到空数组，
    // 然后把一段空文本当**成功结果**喂回模型 —— 比报错更难发现。
    @Expect(Json.strListAt(realDocsPayload().value(), "docs").size, 0) // docs 是对象数组，strListAt 拿不到 —— 见下一条
    let files = Json.arrAt(realDocsPayload().value(), "docs")
    @Expect(files.size, 1)
    @Expect(Json.strAt(files[0], "file", ""), "README.md")
    @Expect(Json.strAt(files[0], "content", ""), "# 项目说明")
    // 反证：那个不存在的键真的读不到
    @Expect(Json.arrAt(realDocsPayload().value(), "files").size, 0)
}

// ---------------------------------------------------------------------------
// 提示词与循环
// ---------------------------------------------------------------------------

@Test
func systemPromptCarriesTheEngineFactsAndTheNoAssertionWithoutToolsRule(): Unit {
    let s = agentSystemPrompt("## 总览\n- 项目 3 个", ["get_group_context", "get_journal"], AgentTarget.Group)
    // 纪律必须在：模型是这里唯一会「把不知道说成知道」的那一环
    @Expect(s.contains("没有工具结果就不要断言"))
    @Expect(s.contains("读不出来"))
    // 引擎事实必须真的进去
    @Expect(s.contains("项目 3 个"))
    // 工具名要列全
    @Expect(s.contains("get_group_context"))
    @Expect(s.contains("get_journal"))
    // 作用域要说清楚
    @Expect(s.contains("项目群"))
}

@Test
func conversationHistoryIsTrimmedButTheNewQuestionAlwaysLandsLast(): Unit {
    // 提问必须是最后一条：历史裁剪写错顺序，模型就会去回答上一轮的问题。
    let h = ArrayList<ChatMessage>()
    for (i in 0..20) {
        h.add(ChatMessage.user("旧问题 ${i}"))
    }
    let seeded = seedConversation(h, "本轮问题", keep: 12)
    @Expect(seeded.size, 13)
    @Expect(seeded[12].text, "本轮问题")
    // 裁掉的是**最早**的
    @Expect(seeded[0].text, "旧问题 8")
}

@Test
func toolShortLabelsAreHumanWordsNotIdentifierNames(): Unit {
    // 这句话会出现在「这一轮做了什么」里给用户看。
    @Expect(toolShortLabel("run_shallow_update"), "浅更新")
    @Expect(toolShortLabel("git_commit"), "提交")
    @Expect(toolShortLabel("milestone_done"), "标记里程碑达成")
    // 未知工具不许静默显示原始标识符
    @Expect(toolShortLabel("brand_new_tool"), "brand_new_tool")
}

// ---------------------------------------------------------------------------
// provider 目录
// ---------------------------------------------------------------------------

@Test
func providerPickerNeverClaimsItListedEverythingItCounted(): Unit {
    // 缺陷 #209：目录 225 家、199 家有端点，列表只列 40 家，
    // 而标题写「目录 · 225 家」—— 一个声称完整的数字配一个被砍过的列表。
    let s = providerPickerSlice(225, 199)
    @Expect(s.shown, 40)
    @Expect(s.cut)
    // 披露必须给**两个**口径
    @Expect(s.note.contains("199"))
    @Expect(s.note.contains("225"))
    // 必须给可执行的下一步，不是「其余略」
    @Expect(s.note.contains("Base URL"))
    // 没被砍就不造披露
    @Expect(!providerPickerSlice(30, 20).cut)
    @Expect(providerPickerSlice(30, 20).note.isEmpty())
    // 端点家数 = 总家数时不该提「目录共 N 家」（两个数一样，说两遍只是噪音）
    @Expect(!providerPickerSlice(10, 40).note.contains("目录共"))
}

@Test
func providerPickerRefusesToSayItListedTheFirstZeroProviders(): Unit {
    // cap 传 0 而披露说「只列前 0 家」是自相矛盾的话。
    let s = providerPickerSlice(100, 100, limit: 0)
    @Expect(s.shown, 1)
    @Expect(!s.note.contains("前 0 家"))
}

// ---------------------------------------------------------------------------
// 端到端（真 curl + 真引擎 + 假 provider）
//
// ⚠ 这两条**只在 scripts/ai-e2e.sh 里跑**。它们需要两个本地 HTTP 服务，
// 所以绝不能混进日常 `cjpm test` —— 那会让没装 python3 的机器直接红。
//
// 它们的判据不是「curl 返回了 200」，而是**假 provider 逐项校验请求体**：
// 中文有没有被转义坏、`stream` 是不是 false、`max_tokens` 是不是整数、
// 工具的 JSON Schema 对不对。见 scripts/ai-e2e.sh 顶部那两条实测教训。
// ---------------------------------------------------------------------------

/// 端到端环境变量。**没起假 provider 就明确失败** ——
/// 静默跳过等于「检查通过」，而实际上一条都没验。
private func e2ePort(name: String): Int64 {
    let v = (getVariable(name) ?? "").trimAscii()
    if (v.isEmpty()) {
        @Expect(false)  // 端到端判据在缺环境下必须**红**，不是安静地过
    }
    // 端口号按字节逐个转 —— 与 ai_http.cj 里解 HTTP 状态码同一套做法
    // （`Int64(string)` 在本工具链上不是合法转换）。
    var n: Int64 = 0
    for (b in v.toArray()) {
        if (b >= 0x30u8 && b <= 0x39u8) {
            n = n * 10 + Int64(b - 0x30u8)
        }
    }
    return n
}

// @Skip 的理由写在这里而不是参数里：仓颉的 @Skip **不接受参数**
// （传字符串会在宏展开期报 "expected declaration, found ''"）。
// scripts/ai-e2e.sh 按下面这行注释的固定文本删掉 @Skip，删不掉就报错退出。
@Skip // 端到端：需要 scripts/ai-e2e.sh 起假 provider
@Test
func TEMP_e2eRequestBodySurvivesTheRealCurlRoundTrip(): Unit {
    let port = e2ePort("DD_E2E_PLAIN_PORT")
    let cfg = AIConfig(
        providerID: "deepseek",
        model: "test-model",
        baseURL: "http://127.0.0.1:${port}",
        apiKey: "sk-e2e-secret"
    )
    let msgs = ArrayList<ChatMessage>()
    msgs.add(ChatMessage.user("中文提问：项目群现在怎么样？带 \"引号\" 和换行\n"))
    let r = generateText(cfg, "你是助手", msgs, ArrayList<ToolDefinition>(), maxTokens: 100, timeoutMs: 20000)
    // 假 provider 只有在**逐字段校验通过**时才回 E2E-OK。
    // 请求体里有半个错（中文被转义坏、max_tokens 写成 4000.000000、
    // stream 漏了）它都会回 E2E-WRONG。
    @Expect(r.problem.isEmpty())
    @Expect(r.result.text, "E2E-OK")
}

@Skip // 端到端：需要 scripts/ai-e2e.sh 起假 provider 与真引擎
@Test
func TEMP_agentLoopCallsTheRealEngineAndConverges(): Unit {
    let port = e2ePort("DD_E2E_AGENT_PORT")
    let bin = (getVariable("DD_E2E_BIN") ?? "").trimAscii()
    let cfg = AIConfig(providerID: "deepseek", model: "m", baseURL: "http://127.0.0.1:${port}", apiKey: "sk-x")
    let r = runAgent(cfg, bin, AgentTarget.Group, "现在有多少未达成里程碑？", ArrayList<ChatMessage>(),
        maxRounds: 4, timeoutMs: 30000)
    println("E2E-AGENT ${agentOutcomeLabel(r.outcome.kind)} executed=${r.outcome.executed.size} " +
        "transcript=${r.transcript.size} problem=[${r.outcome.problem}]")
    @Expect(r.outcome.problem.isEmpty())
    // 第一轮模型要 get_milestones，客户端真调了一次引擎
    @Expect(r.outcome.executed.size, 1)
    // system + user + assistant(含 tool_calls) + tool + assistant(收尾)
    @Expect(r.transcript.size >= 4)
    // 收尾答案必须带着工具结果的内容，而不是模型凭空编的
    @Expect(r.outcome.text.contains("收尾答案"))
    // 收尾状态必须是「已收尾」而不是「已达上限」——
    // 两轮就该结束，跑满 4 轮说明收敛判定坏了
    @Expect(agentOutcomeLabel(r.outcome.kind), "已收尾")
}
