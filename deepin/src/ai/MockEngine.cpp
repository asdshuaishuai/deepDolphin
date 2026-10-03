#include "MockEngine.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>

namespace {
// 无片段时的默认编排：挑第一个**无必填参数**的工具（最安全——get_milestones 无参），
// 避免默认脚本就触发「改写文档」这类有副作用的调用。
QString defaultToolName(const QList<ToolDef> &tools)
{
    for (const ToolDef &t : tools) {
        if (t.requiredParams.isEmpty())
            return t.name;
    }
    return tools.isEmpty() ? QString() : tools.first().name;
}
} // namespace

bool MockEngine::isConfigured(QString *) const
{
    return true; // mock 恒可用（本地自测通道）
}

GenerateResult MockEngine::fromScript(const QString &baseURL, const GenerateRequest &req)
{
    GenerateResult out;
    QUrl url(baseURL);
    const QString frag = url.fragment(QUrl::FullyDecoded);

    // #fail[=原因]
    if (frag.startsWith(QLatin1String("fail"))) {
        const QString why = frag.mid(4);
        out.ok = false;
        out.error = why.isEmpty() ? QStringLiteral("（mock）按脚本返回失败") : why.mid(1);
        return out;
    }
    // #final[=文本]
    if (frag.startsWith(QLatin1String("final"))) {
        const QString tail = frag.mid(5);
        out.ok = true;
        out.text = tail.startsWith(QLatin1Char('='))
            ? tail.mid(1)
            : QStringLiteral("（mock）最终回答：脚本模式 final。");
        return out;
    }
    // #tool=<名>[;args=<json>]
    if (frag.startsWith(QLatin1String("tool="))) {
        const QString spec = frag.mid(5);
        const int semi = spec.indexOf(QLatin1Char(';'));
        ToolCall call;
        call.id = QStringLiteral("mock_call_script");
        call.name = semi < 0 ? spec : spec.left(semi);
        call.argsJson = "{}";
        if (semi >= 0 && spec.mid(semi + 1).startsWith(QLatin1String("args="))) {
            const QJsonDocument argsDoc = QJsonDocument::fromJson(
                spec.mid(semi + 6).toUtf8());
            if (argsDoc.isObject())
                call.argsJson = argsDoc.toJson(QJsonDocument::Compact);
        }
        out.ok = true;
        out.toolCalls.append(call);
        return out;
    }

    // ── 无片段：按会话状态自动编排 ──
    bool hasToolResult = false;
    QStringList executedTools;
    for (const ChatMessage &m : req.messages) {
        if (m.role == ChatMessage::Role::tool)
            hasToolResult = true;
        for (const ToolCall &tc : m.toolCalls)
            executedTools << tc.name;
    }
    if (hasToolResult) {
        out.ok = true;
        out.text = QStringLiteral("（mock）工具已执行（%1），这是回喂后的最终中文回答。")
                       .arg(executedTools.join(QStringLiteral("、")));
        return out;
    }
    if (!req.tools.isEmpty()) {
        ToolCall call;
        call.id = QStringLiteral("mock_call_auto");
        call.name = defaultToolName(req.tools);
        call.argsJson = "{}";
        out.ok = true;
        out.toolCalls.append(call);
        return out;
    }
    // 无工具（如连通性测试）
    out.ok = true;
    out.text = QStringLiteral("OK（mock）");
    return out;
}

GenerateResult MockEngine::generate(const GenerateRequest &req)
{
    // mock 的 Base URL 只当脚本载体；为空也能跑（自动编排）
    return fromScript(m_baseURL, req);
}
