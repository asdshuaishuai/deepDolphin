#include "PathInput.h"
#include <QFileInfo>

namespace PathInput {

PathKind classify(const QString &path)
{
    const QFileInfo info(path);
    if (info.isDir())
        return PathKind::directory;
    if (info.exists())
        return PathKind::file;
    return PathKind::missing;
}

Verdict prepare(const QString &raw)
{
    const QString s = raw.trimmed();
    if (s.isEmpty())
        return { QString(), QStringLiteral("路径为空"), false };

    // 相对路径：引擎会拿子进程 CWD 当基准，那个目录用户看不见——拒绝并说明。
    if (!s.startsWith(QLatin1Char('/')) && !s.startsWith(QLatin1Char('~'))) {
        return { QString(),
            QStringLiteral("「%1」是相对路径。请填绝对路径（以 / 开头），或用「选择…」按钮直接挑一个文件夹。")
                .arg(s),
            false };
    }

    // 纯 `~`：是家目录本身，得让用户知道。`~/x` 交给引擎（它自己会展开）。
    if (s == QLatin1String("~") || s == QLatin1String("~/"))
        return { QString(), QStringLiteral("「~」是家目录本身，请选一个具体的文件夹"), false };

    // 尾斜杠引擎会消解，这里顺手收掉（`~/` 已经在上面拦截）。
    QString out = s;
    while (out.size() > 1 && out.endsWith(QLatin1Char('/')))
        out.chop(1);
    return { out, QString(), true };
}

Verdict validateScanRoot(const QString &raw)
{
    const Verdict p = prepare(raw);
    if (!p.acceptable)
        return p;
    switch (classify(p.path)) {
    case PathKind::directory:
        return p;
    case PathKind::file:
        return { QString(), QStringLiteral("「%1」是个文件。扫描需要一个文件夹作为根。").arg(p.path),
            false };
    case PathKind::missing:
        break;
    }
    return { QString(),
        QStringLiteral("「%1」不存在。用「选择…」按钮挑一个真实存在的文件夹。").arg(p.path), false };
}

Verdict pickDirectory(const QStringList &candidates)
{
    for (const QString &c : candidates) {
        if (classify(c) == PathKind::directory)
            return prepare(c);
    }
    if (candidates.isEmpty())
        return { QString(), QStringLiteral("没收到任何路径"), false };
    int missing = 0;
    for (const QString &c : candidates) {
        if (classify(c) == PathKind::missing)
            ++missing;
    }
    const QString reason = missing == 0
        ? QStringLiteral("拖进来的不是文件夹")
        : QStringLiteral("拖进来的 %1 个里没有文件夹（%2 个路径不存在）").arg(candidates.size()).arg(missing);
    return { QString(),
        QStringLiteral("%1。要添加单个项目，请拖一个文件夹进来。").arg(reason), false };
}

} // namespace PathInput
