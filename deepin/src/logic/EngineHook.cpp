#include "EngineHook.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace EngineHook {

Status parseStatus(const QByteArray &json)
{
    Status out;
    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return out; // parsed=false：上层报「载荷读不懂」，不当成「没装」

    out.parsed = true;
    const QJsonObject root = doc.object();
    out.project = root.value(QStringLiteral("project")).toString();
    out.log = root.value(QStringLiteral("log")).toString();

    if (!root.contains(QStringLiteral("installed")))
        return out; // installedPresent=false —— 契约漂移，不是「没装」

    const QJsonValue v = root.value(QStringLiteral("installed"));
    if (!v.isArray())
        return out; // 形状变了（不是数组）—— 同样当漂移
    const QJsonArray arr = v.toArray();
    // ⚠ 位置约定：[0]=post-commit、[1]=post-merge（引擎不给键名）。
    //   数组不够长 = 契约漂移（installedPresent=false），不是「没装那一项」。
    if (arr.size() < 2)
        return out;
    out.installedPresent = true;
    out.postCommit = arr.at(0).toBool();
    out.postMerge = arr.at(1).toBool();
    return out;
}

int installedCount(const Status &s)
{
    return (s.postCommit ? 1 : 0) + (s.postMerge ? 1 : 0);
}

QString summary(const Status &s)
{
    if (!s.parsed)
        return QStringLiteral("钩子状态读不出来（引擎返回的不是预期载荷）");
    if (!s.installedPresent)
        return QStringLiteral("钩子状态读不出来（引擎载荷里没有可解读的 installed 字段）");
    const int n = installedCount(s);
    if (n == 2)
        return QStringLiteral("已安装（提交后与合并后都会自动记录进度）");
    if (n == 1)
        return QStringLiteral("只装了一半（%1）—— 建议重装一次让两者一致")
            .arg(s.postCommit ? QStringLiteral("只装了提交后")
                              : QStringLiteral("只装了合并后"));
    return QStringLiteral("未安装");
}

QString batchSummary(const QVector<Item> &items)
{
    int ok = 0;
    QStringList failed;
    for (const Item &it : items) {
        if (it.ok) {
            ++ok;
        } else {
            failed << QStringLiteral("%1（%2）").arg(it.project, it.detail);
        }
    }
    QString s = QStringLiteral("%1 个项目成功").arg(ok);
    if (!failed.isEmpty())
        s += QStringLiteral("，%1 个失败：%2").arg(failed.size()).arg(failed.join(QStringLiteral("；")));
    return s;
}

} // namespace EngineHook
