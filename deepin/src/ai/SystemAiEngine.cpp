#include "SystemAiEngine.h"
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QVariantMap>

namespace {
// 报错原文（PLAN §5.3 逐字）——可插拔降级时全应用只有这一句话，不许改模糊。
const char kPresentNoCompletion[] =
    "系统级 AI（UOS AI）的 D-Bus 接口只提供唤起对话窗口（inputPrompt 无返回值），"
    "不能执行程序化生成。请在「设置 → AI」里选择 OpenAI 兼容或 Anthropic 渠道并填写 API Key。";

constexpr char kService[] = "com.deepin.copilot";
constexpr char kChatPath[] = "/org/deepin/copilot/chat";
constexpr char kChatIface[] = "org.deepin.copilot.chat";
} // namespace

SystemAiEngine::Cap SystemAiEngine::probe() const
{
    if (m_cap != Cap::Unknown)
        return m_cap;
    QDBusConnection bus = QDBusConnection::sessionBus();
    QDBusConnectionInterface *iface = bus.interface();
    if (!iface) {
        m_cap = Cap::Absent;
        return m_cap;
    }
    // 1) 运行中？（env.md §4：uos-ai-assistant 常驻，:1.161 挂三个名）
    QDBusReply<bool> registered = iface->isServiceRegistered(QLatin1String(kService));
    if (registered.isValid() && registered.value()) {
        m_cap = Cap::Present;
        return m_cap;
    }
    // 2) 可激活？（ListActivatableNames——D-Bus activation 能把它拉起来）
    QDBusReply<QStringList> activatable = iface->activatableServiceNames();
    if (activatable.isValid() && activatable.value().contains(QLatin1String(kService)))
        m_cap = Cap::Present;
    else
        m_cap = Cap::Absent;
    return m_cap;
}

bool SystemAiEngine::isConfigured(QString *whyNot) const
{
    if (probe() == Cap::Present)
        return true;
    if (whyNot)
        *whyNot = QStringLiteral(
            "系统级 AI 服务不可用（会话总线上没有 %1），也未配置显式渠道"
            "（provider / Base URL / API Key）。请在「设置 → AI」里选择 OpenAI 兼容或 "
            "Anthropic 渠道并填写 API Key。")
            .arg(QLatin1String(kService));
    return false;
}

GenerateResult SystemAiEngine::generate(const GenerateRequest &)
{
    // 【如实降级】找到了服务也只是「唤起对话窗口」，补全能力不存在——
    // 这里是全应用唯一诚实说明这件事的地方，不许静默假装成功。
    GenerateResult r;
    if (probe() == Cap::Absent) {
        QString why;
        isConfigured(&why);
        r.error = QStringLiteral("AI 未配置：%1").arg(why);
    } else {
        r.error = QString::fromUtf8(kPresentNoCompletion);
    }
    r.ok = false;
    return r;
}

bool SystemAiEngine::launchChat(const QString &question, const QVariantMap &params)
{
    if (probe() != Cap::Present)
        return false;
    QVariantMap p = params;
    if (!p.contains(QStringLiteral("source")))
        p.insert(QStringLiteral("source"), QStringLiteral("deepDolphin"));
    QDBusInterface chat(QLatin1String(kService), QLatin1String(kChatPath),
        QLatin1String(kChatIface), QDBusConnection::sessionBus());
    if (!chat.isValid())
        return false;
    // inputPrompt(s question, a{ss} params) 无返回值（fire-and-forget）；
    // params 语义未公开文档化，首版只带 source 标记来源（结论记进 README）。
    QDBusReply<void> reply = chat.call(QStringLiteral("inputPrompt"), question, p);
    return reply.isValid(); // 服务在但调用出错（对象没起等）也要如实说
}
