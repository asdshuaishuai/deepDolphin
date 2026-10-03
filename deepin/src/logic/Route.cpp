#include "Route.h"
#include <QFileInfo>
#include <QSet>

namespace Route {

LaunchRoute parseArgs(const QStringList &args)
{
    LaunchRoute r;
    for (const QString &a : args) {
        if (a == QLatin1String("--open-panel"))
            r.openPanel = true;
        else if (a == QLatin1String("--open-settings"))
            r.openSettings = true;
        else if (a == QLatin1String("--scan"))
            r.openScan = true; // desktop Action「扫描项目」（M2-2）
        else if (a == QLatin1String("--agent-selftest"))
            r.agentSelftest = true;
    }

    // 位置参数：第一个裸参数（desktop 项 `%f` 传入的目录）。args[0] 是程序自身路径，跳过；
    // 只认本地已存在的目录（本应用不吃普通文件名）。已知 flag（含带值的）先跳过，
    // 免得把 `--project foo` 里的 foo 当成路径。
    if (!r.path.has_value()) {
        static const QSet<QString> kValueFlags = {
            QStringLiteral("--project"), QStringLiteral("--section"),
            QStringLiteral("--snapshot"),
        };
        for (int i = 1; i < args.size(); ++i) {
            const QString a = args.at(i);
            if (a.startsWith(QLatin1String("--"))) {
                if (kValueFlags.contains(a))
                    ++i; // 跳过该 flag 的值
                continue;
            }
            const QFileInfo info(a);
            if (info.isDir())
                r.path = info.absoluteFilePath();
            break; // 第一个裸参数就定性，不继续猜
        }
    }

    // --project 与 --section 同现以 project 为准（PLAN §2.4）
    if (auto project = flagValue(QStringLiteral("--project"), args)) {
        r.project = *project;
    } else if (auto section = flagValue(QStringLiteral("--section"), args)) {
        r.section = resolveSection(*section); // 认不出来的名字落 dashboard，不是静默丢弃
    }

    // 问句可省，但**必须有值**：--agent-selftest 后面直接跟 flag 时，
    // 那个 flag 不能被当成问句吃掉。
    for (int i = 0; i < args.size(); ++i) {
        if (args.at(i) != QLatin1String("--agent-selftest"))
            continue;
        const QString next = i + 1 < args.size() ? args.at(i + 1) : QString();
        if (!next.isEmpty() && !next.startsWith(QLatin1String("--")))
            r.selftestQuestion = next;
        else
            r.selftestQuestion = defaultSelfTestQuestion();
        break;
    }
    return r;
}

QString resolveSection(const QString &raw)
{
    if (raw == QLatin1String("milestones"))
        return QStringLiteral("milestones");
    if (raw == QLatin1String("board"))
        return QStringLiteral("board");
    return QStringLiteral("dashboard"); // dashboard 与一切认不出的名字
}

QString defaultSelfTestQuestion()
{
    return QStringLiteral("总结一下项目群现状");
}

std::optional<QString> flagValue(const QString &flag, const QStringList &args)
{
    const int i = args.indexOf(flag);
    if (i < 0 || i + 1 >= args.size())
        return std::nullopt;
    const QString v = args.at(i + 1);
    if (v.isEmpty() || v.startsWith(QLatin1String("--")))
        return std::nullopt;
    return v;
}

} // namespace Route
