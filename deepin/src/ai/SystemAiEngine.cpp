#include "SystemAiEngine.h"
#include <DLog>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QMutexLocker>
#include <QRegularExpression>
#include <QVariantMap>

DCORE_USE_NAMESPACE

namespace {
// 报错原文（PLAN §5.3 逐字）——可插拔降级时全应用只有这一句话，不许改模糊。
const char kPresentNoCompletion[] =
    "系统级 AI（UOS AI）的 D-Bus 接口只提供唤起对话窗口（inputPrompt 无返回值），"
    "不能执行程序化生成。请在「设置 → AI」里选择 OpenAI 兼容或 Anthropic 渠道并填写 API Key。";

constexpr char kService[] = "com.deepin.copilot";
constexpr char kMainPath[] = "/com/deepin/copilot";
constexpr char kChatPath[] = "/org/deepin/copilot/chat";
constexpr char kChatIface[] = "org.deepin.copilot.chat";

// 首次探测的接口 dump（M1-6）：把一个对象上可 Introspect 到的接口名记进日志——
// 未来 UOS AI 若冒出程序化补全出口，日志里第一时间可见。只记接口名，不含业务数据。
void dumpInterfaces(const QDBusConnection &bus, const char *path)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QLatin1String(kService),
        QLatin1String(path), QStringLiteral("org.freedesktop.DBus.Introspectable"),
        QStringLiteral("Introspect"));
    QDBusReply<QString> xml = bus.call(msg);
    if (!xml.isValid()) {
        dWarning() << "UOS AI 探测:" << path << "Introspect 失败:" << xml.error().name();
        return;
    }
    static const QRegularExpression kIfaceName(
        QStringLiteral("<interface name=\"([^\"]+)\""));
    QStringList names;
    QRegularExpressionMatchIterator it = kIfaceName.globalMatch(xml.value());
    while (it.hasNext())
        names << it.next().captured(1);
    names.sort(); // 排序保证日志稳定可比对
    dInfo() << "UOS AI 探测:" << path << "可见接口:" << names.join(QLatin1Char(','));
}
} // namespace

SystemAiEngine::Cap SystemAiEngine::probe() const
{
    // 锁住「查缓存 → 探测 → dump」整段（M1-6）：AgentCore/AiDigests 在 worker、
    // AgentDialog 在 GUI，同一实例并发探测时第二次只等第一次落缓存，不重复打总线。
    QMutexLocker lock(&m_probeMutex);
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
        // 只对「正在运行」的服务 introspect：仅可激活的服务一调就会被总线拉起，
        // 探测不该有唤醒副作用（dump 是观察，不是触碰）。
        dumpInterfaces(bus, kChatPath);
        dumpInterfaces(bus, kMainPath);
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
    QDBusMessage msg = QDBusMessage::createMethodCall(QLatin1String(kService),
        QLatin1String(kChatPath), QLatin1String(kChatIface),
        QStringLiteral("inputPrompt"));
    msg << question << p;
    // inputPrompt(s question, a{ss} params) 无返回值（fire-and-forget）；
    // params 语义未公开文档化，首版只带 source 标记来源（结论记进 README）。
    // 异步化（M1-6）：原 QDBusInterface::call() 同步等回包，GUI 线程被总线往返卡住
    // （构造 QDBusInterface 还隐含一次同步 Introspect）。改 asyncCall 后返回值
    // 语义收窄为「请求已交给会话总线」；「服务在但回包报错」由 watcher 如实记
    // dWarning——降级诚实性保住，只是从同步返回值挪进日志。
    QDBusPendingCall pending = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pending);
    // 引擎本体常是调用方栈上的临时对象（AgentDialog lambda），watcher 不得挂 this：
    // 以自身为收件人，回调只捕获 watcher（不捕获 this），回包落地即 deleteLater 自清理。
    // finished 在 watcher 的所属线程（= 发起线程，即调用方 GUI 线程）派发。
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, watcher,
        [watcher] {
            if (watcher->isError()) {
                const QDBusError e = watcher->error();
                dWarning() << "UOS AI inputPrompt 回包错误:" << e.name() << e.message();
            } else {
                dInfo() << "UOS AI inputPrompt 已送达（对话窗口唤起请求完成）";
            }
            watcher->deleteLater();
        });
    return true;
}
