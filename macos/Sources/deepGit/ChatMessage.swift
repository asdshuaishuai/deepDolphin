// ChatMessage.swift — AI 通道的纯数据形状（零依赖）。
//
// 为什么从 AISDK.swift 里拆出来：AgentConversation（对话判定）要用 ChatMessage，
// 而 AISDK.swift 带着 Keychain（Security 框架）和 LanguageModel（网络通道）——
// 不拆的话，agent-check 就得把整个通道拖进来编译，判定也就没法单独测。
// 与 AgentOutcome / ClientDecisions / PathInput 同一路子：**判定层零依赖**。
//
// 这几个类型是**协议形状**，不是业务逻辑：一个字段都不许在别处重新造一份。
// MARK: - 消息与工具

struct ChatMessage: Equatable {
    var role: String           // system | user | assistant | tool
    var text: String
    /// assistant 原生工具调用（OpenAI 形状，Anthropic 侧转换）
    var toolCalls: [ToolCallRequest]?
    /// tool 角色消息的调用 id（OpenAI tool_call_id / Anthropic tool_use_id）
    var toolCallID: String?
    /// **只给界面用**，不发给模型（通道只序列化 role/text/tool_calls/tool_call_id）。
    ///
    /// ⚠️ 原来 `transcript` 靠 `m.text.contains("执行失败")` 判断该不该显示这条 tool 消息。
    /// 那是**字面量匹配**，两处会漂：写文案的人不知道这个隐藏约定，
    /// 改个措辞（「已拒绝执行」「未执行」）界面就静默什么都不显示 ——
    /// 工具明明没跑、用户却什么都不知道。
    /// 修 NC31 加「拒绝畸形参数」那条路径时就是这么丢的。
    /// 谁执行了、失败了没有，只有发起方知道，所以标记得由发起方打，
    /// 界面只读标记，不去猜文案。
    var isError: Bool = false

    static func system(_ t: String) -> ChatMessage { ChatMessage(role: "system", text: t, toolCalls: nil, toolCallID: nil) }
    static func user(_ t: String) -> ChatMessage { ChatMessage(role: "user", text: t, toolCalls: nil, toolCallID: nil) }
    static func assistant(_ t: String) -> ChatMessage { ChatMessage(role: "assistant", text: t, toolCalls: nil, toolCallID: nil) }

    /// 一条 tool 消息。`isError` 只影响界面显不显示，不影响发给模型的内容。
    static func tool(_ text: String, callID: String?, isError: Bool = false) -> ChatMessage {
        ChatMessage(role: "tool", text: text, toolCalls: nil, toolCallID: callID, isError: isError)
    }
}

struct ToolCallRequest: Equatable {
    let id: String
    let name: String
    /// JSON 对象字符串
    let argumentsJSON: String
}

struct ToolCallResponse: Equatable {
    let id: String
    let name: String
    /// 已执行的结果文本
    let content: String
    let isError: Bool
}

struct ToolDefinition {
    let name: String
    let description: String
    /// JSON Schema 对象（字符串键）
    let parametersJSON: [String: Any]
}

struct GenerateTextResult {
    let text: String
    let toolCalls: [ToolCallRequest]
}
