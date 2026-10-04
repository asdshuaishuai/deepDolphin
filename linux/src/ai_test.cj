// deepDolphin Linux 客户端 —— AI 层判据。
//
// 同样不开窗口、不连引擎、不发网络请求。
// 唯一碰真实外部依赖的两条（provider 目录、引擎 tools 载荷）用的是
// **本机真实输出**截下来的夹具，不是编的形状 ——
// 编出来的夹具会犯本项目最典型的那个错：断言的东西压根不是引擎发的。
package deepdolphin_linux

import std.collection.*
import std.env.*
import std.fs.*
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

/// 一份**最小**项目夹具。只为界面判定用，不追求还原真实载荷 ——
/// 那件事由 model_test.cj 的 `realEngineFixturesParseIntoModels` 负责。
/// ⚠ 不复用 `model_test.cj` 里的 `SPAN_PROJECTS`：那是 `private`，
/// 跨文件拿不到。与其把它改成 public（两个文件的夹具混在一起，
/// 以后改一边会静默影响另一边），不如各自持有。
private let UI_PROJECTS = """
{"projects":[
 {"name":"fresh","path":"/tmp/f","commitCount":3},
 {"name":"old","path":"/tmp/o","commitCount":9}
],"summary":{"projectCount":2,"listedProjects":2}}
"""

private func uiSnapshot(): StatusSnapshot {
    return StatusSnapshot.from(Json.parse(UI_PROJECTS).getOrThrow())
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

@Test
func aiBodyDecodeReplacesGarbageInsteadOfThrowingMidStream(): Unit {
    // R4-02：严格 `String.fromUtf8` 对**任何一个**非 UTF-8 字节都抛
    // （实测本机：`Invalid utf8 byte sequence.`）。AI 响应体可能是
    // GBK 错误页、网关吐出的压缩体/二进制垃圾；抛点在「读响应」与
    // 「清临时文件」之间时，装 API Key 的临时文件永久残留，后台线程死亡。
    // 解码必须有损替换，绝不抛。
    // 合法内容原样（1/2/3/4 字节序列各验一种）
    @Expect(fromUtf8Lossy([0x41, 0xe4, 0xb8, 0xad, 0x42]), "A中B")
    @Expect(fromUtf8Lossy([0xf0, 0x9f, 0x8e, 0xaf]), "🎯")
    // 中部垃圾字节 → U+FFFD，不抛
    @Expect(fromUtf8Lossy([0x41, 0xff, 0x42]), "A\u{FFFD}B")
    // 尾部残缺（引擎输出被截断的那一族）。按 WHATWG 口径，残缺序列的
    // 每个滞留字节各出一个 U+FFFD（实测口径与此一致，判据钉住它）。
    @Expect(fromUtf8Lossy([0x41, 0xe4, 0xb8]), "A\u{FFFD}\u{FFFD}")
    // GBK「中文」的四个字节，按 WHATWG 口径逐字节换 U+FFFD
    @Expect(fromUtf8Lossy([0xd6, 0xd0, 0xce, 0xc4]), "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}")
    // 代理区（CESU-8）不合法
    @Expect(fromUtf8Lossy([0xed, 0xa0, 0x80]), "\u{FFFD}\u{FFFD}\u{FFFD}")
    // 超长编码不合法
    @Expect(fromUtf8Lossy([0xc0, 0xaf]), "\u{FFFD}\u{FFFD}")
    // U+10FFFF 之外不合法
    @Expect(fromUtf8Lossy([0xf4, 0x90, 0x80, 0x80]), "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}")
    // 空输入 → 空串
    @Expect(fromUtf8Lossy(Array<UInt8>()), "")
}

@Test
func utf8LossyNeverThrowsWhenTheStreamEndsOnALoneLeadByte(): Unit {
    // R4-01 的原始探针：流末尾**恰好**是一个多字节字符的首字节（0xE4）。
    // 引擎被超时 force-terminate、或 stdio 缓冲边界切断多字节字符时，
    // 已读尾字节正是这个形状；旧实现（e257732 之前的「末尾回退」版）在这里
    // 直接抛 IllegalArgumentException，并沿管道读线程穿透到发起调用的
    // 后台线程 —— busy 永不复位，界面永远停在「读取项目群…」。
    // 现实现的口径：末尾每个滞留字节各出一个 U+FFFD，绝不抛。
    @Expect(fromUtf8Lossy([0x41, 0xe4]), "A\u{FFFD}")
    @Expect(fromUtf8Lossy([0xe4]), "\u{FFFD}")
    // 首字节 + 部分续字节（截断在序列中间）同样是滞留字节逐个替换
    @Expect(fromUtf8Lossy([0x41, 0xe4, 0xb8]), "A\u{FFFD}\u{FFFD}")
    // 4 字节序列截断在每个位置
    @Expect(fromUtf8Lossy([0xf0, 0x9f]), "\u{FFFD}\u{FFFD}")
    @Expect(fromUtf8Lossy([0xf0, 0x9f, 0x8e]), "\u{FFFD}\u{FFFD}\u{FFFD}")
}

// ---------------------------------------------------------------------------
// 私有文件落盘（R1-05 / R1-04）
// ---------------------------------------------------------------------------

/// `stat -c %a` 的权限串。判据用；GNU stat 在标准环境里都有。
private func fileModeOf(path: String): String {
    let r = execCapture("/bin/stat", ["-c", "%a", path], 5000)
    return r.stdout.trimAscii()
}

@Test
func privateFilesAreWrittenAtomicallyAt600AndReplacedWhole(): Unit {
    // R1-05：旧实现 remove → writeTo → chmod，密钥先按 umask（常见 0644）
    // 落盘、之后才收紧 —— 存在全局可读窗口；且 remove 之后任何一步失败
    // = 旧密钥已丢。现在的写法：临时文件 → 建好立即 600 → rename 原子替换。
    // 用判据自己的沙盒目录，不碰真实 ~/.config/deepdolphin。
    let dir = "/tmp/dd-privwrite-${nowMillis()}"
    execCapture("/bin/mkdir", ["-p", dir], 5000)
    execCapture("/bin/chmod", ["700", dir], 5000)
    let path = "${dir}/api-key"

    // 第一次写：内容完整、权限 600
    @Expect(writePrivateFile(path, "sk-first", "密钥文件"), "")
    @Expect(String.fromUtf8(File.readFrom(Path(path))), "sk-first")
    @Expect(fileModeOf(path), "600")

    // 覆盖写：更长的内容不留尾巴（writeTo 不截断那一族），
    // 更短的内容也不缺尾巴；权限仍是 600
    @Expect(writePrivateFile(path, "sk-second-much-longer-key", "密钥文件"), "")
    @Expect(String.fromUtf8(File.readFrom(Path(path))), "sk-second-much-longer-key")
    @Expect(writePrivateFile(path, "sk-3", "密钥文件"), "")
    @Expect(String.fromUtf8(File.readFrom(Path(path))), "sk-3")
    @Expect(fileModeOf(path), "600")

    // 目录里不剩临时文件 —— .tmp-* 残留也是半截凭据
    let listing = execCapture("/bin/sh", ["-c", "ls -1 -- \"$1\"", "dd-test", dir], 5000)
    @Expect(listing.stdout.trimAscii(), "api-key")

    // 写不进去要沿返回值报原因，且旧内容原封不动（不再「先删后写」）
    execCapture("/bin/chmod", ["500", dir], 5000)
    let problem = writePrivateFile(path, "sk-never", "密钥文件")
    execCapture("/bin/chmod", ["700", dir], 5000)
    @Expect(!problem.isEmpty())
    @Expect(String.fromUtf8(File.readFrom(Path(path))), "sk-3")

    // 清场
    execCapture("/bin/sh", ["-c", "rm -rf -- \"$1\"", "dd-test", dir], 5000)
}

@Test
func configDocParseDisclosesABrokenFileInsteadOfSilentlyFallingBack(): Unit {
    // R1-04：设置文件坏了静默回落 deepseek，用户看到的配置和
    // 真正生效的配置是两份。解析不出来要沿返回值（loadProblem）说出来。
    let good = parseAIConfigDoc("{\"providerID\":\"openrouter\",\"model\":\"m\",\"baseURL\":\"https://x\"}", "/p/settings.json")
    @Expect(good.providerID, "openrouter")
    @Expect(good.model, "m")
    @Expect(good.loadProblem, "")
    // 坏文件：字段回落默认值，但必须给原因与文件路径
    let broken = parseAIConfigDoc("{not json", "/p/settings.json")
    @Expect(broken.providerID, "deepseek")
    @Expect(broken.loadProblem.contains("JSON"), true)
    @Expect(broken.loadProblem.contains("/p/settings.json"), true)
    // 空文件同样是「坏」，不是「没配置」
    let empty = parseAIConfigDoc("", "/p/settings.json")
    @Expect(!empty.loadProblem.isEmpty())
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

@Test
func catalogCandidatesListEnvThenCacheThenInstallInThatOrder(): Unit {
    // T2：候选构造抽成收三个环境串的纯函数后，顺序可以直接断言 ——
    // 显式注入（脚本给的仓内快照）→ 刷新缓存（$XDG_DATA_HOME/deepdolphin）
    // → 默认安装位（~/.local/share/deepdolphin）。**缓存必须先于安装位**：
    // 用户刷新过之后，下次启动要用上新的那份，而不是读回旧快照。
    let ps = catalogSearchPathCandidates("/repo/assets/models/models-dev.json", "/xdg/data", "/home/u")
    @Expect(ps.size, 3)
    @Expect(ps[0], "/repo/assets/models/models-dev.json")
    @Expect(ps[1], "/xdg/data/deepdolphin/models-dev.json")
    @Expect(ps[2], "/home/u/.local/share/deepdolphin/models-dev.json")
    // 空 / 纯空白 env 不产生空候选（空串候选永不存在，只会污染「找过」披露）
    @Expect(catalogSearchPathCandidates("", "/xdg", "/home/u").size, 2)
    @Expect(catalogSearchPathCandidates("   ", "/xdg", "/home/u").size, 2)
    // env 带首尾空白时进链的是干净值
    @Expect(catalogSearchPathCandidates(" /x.json ", "/xdg", "/home/u")[0], "/x.json")
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

// ---------------------------------------------------------------------------
// C10 系统集成
// ---------------------------------------------------------------------------

@Test
func launchRouteParserHandlesBothKeysAndIgnoresTheRest(): Unit {
    // 纯函数：判据直接喂 argv，不启窗口、不连引擎。
    let r = parseLaunchRoute(["deepdolphin_linux", "--section", "board", "--project", "moonGit", "--unknown"])
    @Expect(r.section, "board")
    @Expect(r.project, "moonGit")
    @Expect(!r.isEmpty())
    // 缺值不许把下一个参数当值吃掉
    @Expect(parseLaunchRoute(["--section"]).section, "")
    // 顺序无关
    @Expect(parseLaunchRoute(["--project", "x", "--section", "milestones"]).section, "milestones")
    // 什么都没有
    @Expect(parseLaunchRoute([]).isEmpty())
}

@Test
func unknownSectionIsNamedInsteadOfSilentlyIgnored(): Unit {
    // 「打错了一个字」与「这版还不支持」要给的提示不同 ——
    // 静默忽略会让用户以为点错了没反应。
    @Expect(sectionIndexOfName("board"), 1)
    @Expect(sectionIndexOfName("milestones"), 2)
    @Expect(sectionIndexOfName("dashboard"), 0)
    @Expect(sectionIndexOfName("Boad"), -1) // 拼错
    @Expect(sectionIndexOfName(""), -1)
}

@Test
func autostartEntryQuotesWholeArgsBecauseTheXdgParserSplitsOnUnquotedWhitespace(): Unit {
    // freedesktop Desktop Entry 规范：Exec= 按**未加引号的空白**切参数、
    // 引号定界参数。所以每个参数整段包进双引号 —— 包进之后，空格与
    // `&`、`|`、`;` 这类分隔符全是字面字符；引号内的 `"` 与 `\` 用 `\` 转义。
    // 旧写法的 `\s`（转义空格）现行规范里没有，会话解析时留成字面 `\ `，
    // 路径里有空格照样断开。
    @Expect(escapeDesktopExec("/home/kelthas/My Apps/main"), "\"/home/kelthas/My Apps/main\"")
    @Expect(escapeDesktopExec("/usr/bin/deepdolphin"), "\"/usr/bin/deepdolphin\"")
    // 引号内的反斜杠与双引号必须转义：否则引号提前闭合
    @Expect(escapeDesktopExec("a\\b\"c"), "\"a\\\\b\\\"c\"")
    // 分隔符与裸空白一并防住
    @Expect(escapeDesktopExec("/opt/a&b|c;d e"), "\"/opt/a&b|c;d e\"")
    let e = autostartEntry("/usr/bin/deepdolphin", "/usr/bin/moongit")
    @Expect(e.contains("[Desktop Entry]"))
    @Expect(e.contains("Type=Application"))
    @Expect(e.contains("Exec=\"/usr/bin/deepdolphin\" --engine \"/usr/bin/moongit\""))
    @Expect(e.contains("X-GNOME-Autostart-enabled=true"))
    // 引擎为空时不能留下一截「--engine 」
    @Expect(!autostartEntry("/usr/bin/deepdolphin", "").contains("--engine"))
}

@Test
func autostartFileLandsInTheXdgAutostartDirNotTheAppPrivateDir(): Unit {
    // R3-01：freedesktop Autostart 规范的用户级目录是 $XDG_CONFIG_HOME/autostart
    // （默认 ~/.config/autostart），会话登录**只扫那里**。第一版写到应用
    // 私有目录 ~/.config/deepdolphin/autostart/ —— 根本不会被扫到，
    // 开关显示「已开启」而实际永远不会自启。
    @Expect(xdgConfigBase("", "/home/u"), "/home/u/.config")
    @Expect(xdgConfigBase("relative/x", "/home/u"), "/home/u/.config") // 非绝对路径不认
    @Expect(xdgConfigBase("/custom/cfg", "/home/u"), "/custom/cfg")
    @Expect(xdgAutostartDir("", "/home/u"), "/home/u/.config/autostart")
    @Expect(xdgAutostartDir("/custom/cfg", "/home/u"), "/custom/cfg/autostart")
}

@Test
func autostartRefusesAnEmptyExecBecauseTheSessionWouldExecuteTheArgument(): Unit {
    // R3-02：调用方传空 execPath 时，写出的条目是「Exec= --engine <bin>」
    // —— 会话把 --engine 当程序名去执行，客户端永远不会被启动，
    // 而界面照样显示「已开启」。现在空 Exec 在写入前就被拒掉，并给下一步。
    let p = autostartEntryProblem("")
    @Expect(!p.isEmpty())
    @Expect(p.contains("Exec"))
    @Expect(!autostartEntryProblem("   ").isEmpty()) // 纯空白等同空
    @Expect(autostartEntryProblem("/opt/dd/scripts/run.sh"), "")
}

@Test
func autostartEntryFromArgvNeedsAnAbsolutePathFourLevelsAboveTheBinary(): Unit {
    // T2：argv[0] → run.sh 的四层上溯抽成纯函数。以 `/` 开头时
    // main → bin → release → target → <root>/linux，拼出 scripts/run.sh；
    // 相对 argv[0]（`exec ./…` 的产物、PATH 启动）算不出 → 空串 ——
    // R3-02 的拒写守卫**不松动**，空入口照样不许写条目。
    @Expect(autostartEntryFromArgv("/r/linux/target/release/bin/main"), "/r/linux/scripts/run.sh")
    @Expect(autostartEntryFromArgv("./target/release/bin/main"), "")
    @Expect(autostartEntryFromArgv("main"), "")
    @Expect(autostartEntryFromArgv(""), "")
    // 层数不够到不了仓库根（/usr/bin/main 只有两层）
    @Expect(autostartEntryFromArgv("/usr/bin/main"), "")
}

@Test
func autostartUnavailableHintNamesRunShNotTheBareBinary(): Unit {
    // T2：旧文案让用户「从 linux/target/release/bin/main 启动」—— 裸二进制
    // 是相对路径 argv[0]，永远满足不了守卫，等于教用户去做一件做不到的事。
    // 修好后的现实：从 scripts/run.sh 启动即可（脚本 exec 绝对路径）。
    let hint = autostartEntryUnavailableHint()
    @Expect(hint.contains("scripts/run.sh"))
    @Expect(!hint.contains("target/release/bin/main"))
    // 守卫文案同步：下一步也指向 run.sh，不再指向裸二进制
    @Expect(autostartEntryProblem("").contains("scripts/run.sh"))
}

@Test
func autostartWriteReadBackRemoveAndRefusalWorkInASandboxDir(): Unit {
    // T2：写盘动作此前零单测（README「已知代价」第 5 条如实记过）—— 碰真实
    // ~/.config/autostart 不宜在判据里写真文件。核心抽成收**目录**的
    // setAutostartIn 之后，/tmp 沙盒即可验「写 → 回读 → 删 → 幂等 →
    // 拒写 → 建目录」全链（先例：密钥落盘的沙盒判据）。
    let t = nowMillis()
    let dir = "/tmp/dd-autostart-${t}"
    let refused = "/tmp/dd-autostart-refused-${t}"
    let deep = "/tmp/dd-autostart-deep-${t}"
    let exec = "/home/u/deepDolphin/linux/scripts/run.sh"

    // ① 开：写 → 回读正文（[Desktop Entry] 与整引号 Exec=；bin 空则无 --engine）
    @Expect(setAutostartIn(dir, exec, "", true), "")
    let back = String.fromUtf8(File.readFrom(Path("${dir}/deepdolphin.desktop")))
    @Expect(back.contains("[Desktop Entry]"))
    @Expect(back.contains("Exec=${escapeDesktopExec(exec)}"))
    @Expect(!back.contains("--engine"))

    // ② 关：文件删掉；再关一次幂等（没有文件 = 成功，不报错）
    @Expect(setAutostartIn(dir, exec, "", false), "")
    @Expect(!exists(Path("${dir}/deepdolphin.desktop")))
    @Expect(setAutostartIn(dir, exec, "", false), "")

    // ③ 空 execPath 拒写：且拒写发生在建目录之前 —— 连目录都不该被建出来
    @Expect(!setAutostartIn(refused, "", "", true).isEmpty())
    @Expect(!setAutostartIn(refused, "   ", "", true).isEmpty())
    @Expect(!exists(Path(refused)))
    // 关闭方向不需要入口（拆条目用不到 Exec=）
    @Expect(setAutostartIn(refused, "", "", false), "")

    // ④ 自启目录整条不存在：mkdir -p 分支接住，写成功且回读得到
    @Expect(setAutostartIn(deep, exec, "", true), "")
    @Expect(String.fromUtf8(File.readFrom(Path("${deep}/deepdolphin.desktop"))).contains("[Desktop Entry]"))

    // 清场（目录经位置参数传给 sh，不拼进脚本串）
    execCapture("/bin/sh", ["-c", "rm -rf -- \"$1\" \"$2\" \"$3\"", "dd-test", dir, refused, deep], 5000)
}

@Test
func toolLookupWalksPathInOrderThenCallersFallBackToTheBuiltinPath(): Unit {
    // R3-06：curl / notify-send / secret-tool 原来钉死 /usr/bin ——
    // 工具装在 PATH 别处的机器上明明有也报「找不到」。解析规则：
    // 目录顺序 × 名字顺序，取第一个「存在」的命中（firstToolOnPath
    // 的纯函数核心）。用 /usr/bin/sh（每台机器都有）验，不依赖具体工具。
    @Expect(firstOnPathString("/usr/bin:/bin", ["sh"], { c => isRegularFile(c) }), "/usr/bin/sh")
    // 前面的目录没有 → 落到后面的
    @Expect(firstOnPathString("/nonexistent-dd:/bin", ["sh"], { c => isRegularFile(c) }), "/bin/sh")
    // 名字有先后：第一个名字在任何目录命中，都优先于第二个名字
    @Expect(firstOnPathString("/bin:/usr/bin", ["no-such-tool-dd", "sh"], { c => isRegularFile(c) }), "/bin/sh")
    // 都找不到 → 空串，调用方回退各自的绝对路径兜底
    @Expect(firstOnPathString("/nonexistent-dd", ["no-such-tool-dd"], { c => isRegularFile(c) }), "")
}

@Test
func longUpdateNoticeSaysWhatHappenedNotJustDone(): Unit {
    // 深更新要跑 5 分钟。通知里只写「完成」的话，
    // 用户在几十秒后已经忘了自己点了什么。
    @Expect(updateFinishedNotice("深更新", "", true, ""), "深更新完成：全部项目")
    @Expect(updateFinishedNotice("浅更新", "moonGit", true, ""), "浅更新完成：moonGit")
    // 失败要说清是哪个范围 + 原因
    @Expect(updateFinishedNotice("深更新", "moonGit", false, "（引擎退出码 1）"),
        "深更新失败：moonGit（引擎退出码 1）")
}

@Test
func startupSweepRemovesLeftoverAITempFiles(): Unit {
    // R4-02 的兜底：进程被 SIGKILL 时 ai_http 的 finally 清理跑不到，
    // 装着 API Key 的临时文件残留 —— 下一次启动必须补删。
    // 目录经**位置参数**传给 sh（不拼进脚本串），所以这里同时验了
    // 「目录名带空格也不会变成另一条命令」。
    let tmpRoot = (getVariable("TMPDIR") ?? "").trimAscii()
    let dir = if (tmpRoot.isEmpty() || !tmpRoot.startsWith("/")) { "/tmp" } else { tmpRoot }
    let leftover = "${dir}/deepdolphin-ai-head-${nowMillis()}"
    File.writeTo(leftover, "Authorization: Bearer sk-x\n".toArray())
    let problem = sweepAITempLeftovers()
    let gone = !exists(leftover)
    if (!gone) {
        removeQuiet(leftover) // 清理自己的测试残留，不让断言失败留垃圾
    }
    @Expect(problem, "")
    @Expect(gone, true)
}

// ---------------------------------------------------------------------------
// 界面层的纯判定
// ---------------------------------------------------------------------------

@Test
func aiScopeFollowsTheMainAreaSoTheQuestionMatchesWhatIsOnScreen(): Unit {
    // 问的是屏幕上正看着的那个项目，还是整个项目群，必须说得准 ——
    // 错了的后果是模型读了 A 的上下文、界面却是 B。
    let s = uiSnapshot()
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)

    // 默认：项目群
    @Expect(aiScopeLabel(model).contains("项目群"))
    match (aiTargetOf(model)) {
        case AgentTarget.Group => ()
        case AgentTarget.Project(_) => @Expect(false)
    }

    // 进到某个项目里
    openProject(model, "fresh")
    @Expect(aiScopeLabel(model).contains("fresh"))
    match (aiTargetOf(model)) {
        case AgentTarget.Project(n) => @Expect(n, "fresh")
        case AgentTarget.Group => @Expect(false)
    }
}

@Test
func aiPaneIsNotConfusedWithTheNormalRoute(): Unit {
    // AI 面板是主区里的另一个场景。开关它**不许**动侧栏高亮 ——
    // 动了两边就再也说不清「我现在在哪个项目」。
    let s = uiSnapshot()
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)
    openProject(model, "fresh")
    let beforeView = model.viewIndex.value
    let beforeSel = model.selected.value
    let beforeProject = model.selectedProject.value

    openAIPane(model, 1)
    @Expect(model.aiPane.value, 1)
    openAIPane(model, 2)
    @Expect(model.aiPane.value, 2)
    closeAIPane(model)
    @Expect(model.aiPane.value, 0)

    @Expect(model.viewIndex.value, beforeView)
    @Expect(model.selected.value, beforeSel)
    @Expect(model.selectedProject.value, beforeProject)
}

@Test
func toolResultsAreTruncatedInTheUiButNotInWhatTheModelSees(): Unit {
    // 整段工具结果可能几百 KB。铺到界面上只会让人找不到助手答了什么，
    // 但**给模型的必须完整** —— 截断的是显示，不是数据。
    var big = ""
    for (i in 0..5000) { big += "x" }
    let short = aiMessageText(ChatMessage.tool("c1", big))
    @Expect(short.size < big.size)
    @Expect(short.contains("已交给模型"))
    // 短的不该被截
    let small = aiMessageText(ChatMessage.tool("c1", "一行结果"))
    @Expect(small, "一行结果")
}

@Test
func assistantToolCallIsNamedSoTheUserCanSeeWhatItTriedToDo(): Unit {
    // 「模型做了什么都看不见」是 AI 助手最招人烦的一种体验。
    let calls = ArrayList<ToolCallRequest>()
    calls.add(ToolCallRequest("c1", "run_deep_update", "{}"))
    calls.add(ToolCallRequest("c2", "git_commit", "{}"))
    let text = aiMessageText(ChatMessage.assistant("我先看看", calls: calls))
    @Expect(text.contains("深更新"))
    @Expect(text.contains("提交"))
}

// ---------------------------------------------------------------------------
// 停止
// ---------------------------------------------------------------------------

@Test
func stopFlagIsCheckedBeforeEveryToolCallNotOnlyBetweenRounds(): Unit {
    // 一轮里模型可以返回**多个** tool_calls（实测会一次给几个）。
    // 只在轮次之间查停止的话，用户按下停止后剩下那几个照样会执行 ——
    // 其中可能有「深更新」或「提交」。这是不可接受的副作用。
    //
    // 这里验的是**检查点存在**：主循环源码里每个工具调用前都有一道
    // `if (aiShouldStop())`。做法是让停止标志为真、跑一轮，
    // 然后断言**一个工具都没执行**。
    @Expect(!shouldStopBeforeToolCall(0, false, -1))
    @Expect(shouldStopBeforeToolCall(0, true, -1)) // 用户按了 → 停
    @Expect(shouldStopBeforeToolCall(0, false, 0)) // 旋钮：第 0 个之前就停
    @Expect(shouldStopBeforeToolCall(2, false, 2))
    @Expect(!shouldStopBeforeToolCall(1, false, 2)) // 还没到
    // 用户标志优先于旋钮
    @Expect(shouldStopBeforeToolCall(0, true, 99))
}

@Test
func aLateWriteFromACancelledRoundIsRejectedInsteadOfOverwritingANewerOne(): Unit {
    // 「状态被迟到回写覆盖」是这一族里最招人烦的一种：
    // 用户「停止 → 立刻发新问题」，上一轮迟到的回写把新对话冲掉，
    // 用户的下一条提问凭空消失。
    aiRoundSeq = 5
    @Expect(aiRoundIsCurrent(5))
    aiRoundSeq = 6
    @Expect(!aiRoundIsCurrent(5)) // 旧代号被拒
    @Expect(aiRoundIsCurrent(6))
}

@Test
func stopVoidsTheRoundTokenSoALateWritebackCannotReopenTheActionGate(): Unit {
    // R4-04：停止后用户可以立刻发起深更新 / git 写。旧轮收尾的那次
    // app.post 若还能通过 `aiRoundIsCurrent`，就会再执行一次 endAction，
    // 把**正在跑的那个写动作**的 actionBusy 闸门提前放开 ——
    // 两个引擎写进程抢锁，恰是闸门注释里说要防的局面。
    // 所以 stopAI 必须同时推进代号，让被放弃轮次的一切迟到回写失效。
    let model = AppModel(EngineLocation("", "", ""))
    let savedSeq = aiRoundSeq
    let savedStop = aiStopRequested
    aiRoundSeq = 7
    let abandoned = aiRoundSeq
    model.aiRunning.value = true
    stopAI(model)
    // 旧轮（包括「以 Stopped 收尾」的那次回写）必须过不了守卫
    let guardRejectsAbandoned = !aiRoundIsCurrent(abandoned)
    let uiUnlocked = !model.aiRunning.value
    // 代号与停止标志是包级可变全局，先恢复干净值再断言
    aiRoundSeq = savedSeq
    aiStopRequested = savedStop
    @Expect(guardRejectsAbandoned, true)
    @Expect(uiUnlocked, true)
    @Expect(model.aiStatus.value.contains("已停止"), true)
}

@Test
func stopHappensAtRoundLimitTooAndStillDeliversWhatWasWritten(): Unit {
    // 停掉的这一轮**已经写出来的内容要交出去**。
    // 丢掉它 = 用户按下停止后什么都没留下，比不停还糟
    // （macOS 端 P0-4 是同一族：到上限直接抛错，把答案扔了）。
    @Expect(agentOutcomeLabel(AgentOutcomeKind.Stopped), "已停止")
    @Expect(agentOutcomeWasStopped(AgentOutcome(AgentOutcomeKind.Stopped, "已写出", ArrayList<String>(), "已停止")))
    @Expect(!agentOutcomeWasStopped(AgentOutcome(AgentOutcomeKind.Finished, "答完了", ArrayList<String>(), "")))
}

@Test
func closingWhileARoundIsRunningIsRefusedWithTheNextStepNotJustDenied(): Unit {
    // 正在跑时关面板 → 那一轮还会往回写，而 aiPane 已经回到 0：
    // 用户看着仪表盘，对话在背后自己变。
    // 提示必须给**下一步**（先按停止），不是一句「无法关闭」。
    let s = uiSnapshot()
    let model = AppModel(EngineLocation("", "", ""))
    model.snapshot.value = Some(s)
    openAIPane(model, 1)
    model.aiRunning.value = true
    closeAIWithCheck(model)
    @Expect(model.aiPane.value, 1) // 没关
    @Expect(model.routeNotice.value.contains("停止"))
    // 停下来之后就能关了
    model.aiRunning.value = false
    closeAIWithCheck(model)
    @Expect(model.aiPane.value, 0)
}

@Skip // 端到端：需要 scripts/ai-e2e.sh 起假 provider 与真引擎
@Test
func TEMP_stoppingBeforeToolCallsExecutesNoneOfThem(): Unit {
    // 假 provider 一次要 **3 个** 工具（见 tests/mock_agent.py 的 multi 模式）。
    // 在调用前把停止标志置真，断言：
    //   · 一个工具都没执行（`executed` 为空）
    //   · 收尾状态是「已停止」而不是「失败」
    //   · 对话流里**没有** tool 消息
    //
    // 为什么必须真跑：判据只能验「停止标志被检查了」，
    // 验不了「检查点插在了每个工具调用之前」——
    // 后者要一个真的返回多 tool_calls 的 provider 才触发得到。
    let port = e2ePort("DD_E2E_MULTI_PORT")
    let bin = (getVariable("DD_E2E_BIN") ?? "").trimAscii()
    let cfg = AIConfig(providerID: "deepseek", model: "m", baseURL: "http://127.0.0.1:${port}", apiKey: "sk-x")
    // 用**旋钮**而不是全局标志：标志一置真，轮次顶部就先返回了，
    // 压根走不到「逐个工具调用前检查」那个点 —— 那样这条判据是自欺的。
    aiStopAfterTools = 0
    let r = runAgent(cfg, bin, AgentTarget.Group, "看看三处", ArrayList<ChatMessage>(),
        maxRounds: 4, timeoutMs: 30000)
    aiStopAfterTools = -1
    println("E2E-STOP ${agentOutcomeLabel(r.outcome.kind)} executed=${r.outcome.executed.size}")
    @Expect(agentOutcomeLabel(r.outcome.kind), "已停止")
    @Expect(r.outcome.executed.size, 0)
    var toolMsgs: Int64 = 0
    for (m in r.transcript) {
        if (chatRoleIs(m.role, ChatRole.Tool)) { toolMsgs += 1 }
    }
    @Expect(toolMsgs, 0)
}
