#include "EngineDownload.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace EngineDownload {

QString platformSuffix()
{
    // deepin = linux x86_64。⚠ 这不是「运行时探测」—— 客户端只发 linux x64 构建，
    //   架构差异由 release 资产名表达（引擎的 workflow 也只出 linux-x64）。
    return QStringLiteral("linux-x64");
}

QString releaseApiUrl(const QString &repo)
{
    return QStringLiteral("https://api.github.com/repos/%1/releases/latest").arg(repo);
}

bool assetMatches(const QString &assetName, const QString &suffix)
{
    if (assetName.isEmpty() || suffix.isEmpty())
        return false;
    if (!assetName.endsWith(QStringLiteral(".tar.gz")))
        return false;
    return assetName.contains(suffix);
}

Release parseRelease(const QByteArray &json)
{
    Release out;
    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return out; // parsed=false：上层报「载荷读不懂」，不当成「没有资产」

    out.parsed = true;
    const QJsonObject root = doc.object();
    out.tag = root.value(QStringLiteral("tag_name")).toString();

    const QJsonArray assets = root.value(QStringLiteral("assets")).toArray();
    const QString suffix = platformSuffix();
    for (const QJsonValue &v : assets) {
        const QJsonObject a = v.toObject();
        const QString name = a.value(QStringLiteral("name")).toString();
        if (!name.isEmpty())
            out.available << name;
        if (out.asset.present)
            continue;
        if (!assetMatches(name, suffix))
            continue;
        out.asset.name = name;
        out.asset.url = a.value(QStringLiteral("browser_download_url")).toString();
        out.asset.digest = a.value(QStringLiteral("digest")).toString();
        if (a.contains(QStringLiteral("size")))
            out.asset.size = static_cast<qint64>(a.value(QStringLiteral("size")).toDouble());
        out.asset.present = true;
    }
    return out;
}

bool digestMatches(const QString &expected, const QByteArray &data)
{
    if (expected.trimmed().isEmpty())
        return true; // ⚠ 无校验和可比 —— 上层必须说「未校验」，不能冒充「已校验」
    QString hex = expected.trimmed();
    if (hex.startsWith(QStringLiteral("sha256:"), Qt::CaseInsensitive))
        hex = hex.mid(7);
    hex = hex.trimmed().toLower();
    if (hex.size() != 64)
        return false; // 长度不对 = 校验和本身不可信
    const QByteArray actual =
        QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex();
    return actual == hex.toLatin1();
}

QString installDir()
{
    // 用户目录，**不碰系统目录**。与「改名字不改身份」的纪律一致：
    // 引擎的正式名是 moongit，落在用户自己的 libexec 下。
    return QDir::homePath() + QStringLiteral("/.local/libexec/deepdolphin");
}

QString installedBin()
{
    return installDir() + QStringLiteral("/moongit");
}

QString packagedBinName()
{
    // ⚠ 发布包**根部**的可执行文件是**启动器** `moongit`（引擎自己的打包脚本
    //   `scripts/package-release.sh` 产出的），不是裸二进制：
    //   真二进制在 `bin/moongit-cli`、仓颉运行库在 `runtime/lib/`，
    //   启动器按**自身所在目录**去找这两样 ⇒ 三样必须**一起**落盘。
    //   （原实现按「包根只有一个 moongit-cli」设计 —— 那是**虚构的布局**：
    //    真实资产根本找不到那个文件，装下来也跑不起来。）
    return QStringLiteral("moongit");
}

QStringList packagedDirs()
{
    // 与启动器一起落盘的目录（相对发布包根）。
    // ⚠ 少落一个 = 装下来的引擎跑不起来（runtime 缺了就是 Library not loaded）。
    return { QStringLiteral("bin"), QStringLiteral("runtime") };
}

QString stageMessage(Stage s, const QString &detail)
{
    switch (s) {
    case Stage::ok:
        return detail.isEmpty() ? QStringLiteral("完成") : detail;
    case Stage::networkUnreachable:
        return QStringLiteral("连不上 GitHub（网络不可达）：%1").arg(detail);
    case Stage::releaseUnreadable:
        return QStringLiteral("读不懂引擎发布信息（接口返回的不是预期 JSON）：%1").arg(detail);
    case Stage::noPlatformAsset:
        return QStringLiteral("该版本没有 Linux x64 安装包：%1").arg(detail);
    case Stage::downloadFailed:
        return QStringLiteral("下载中断：%1").arg(detail);
    case Stage::digestMismatch:
        return QStringLiteral("校验和不匹配（下载到的文件与发布方声明的不一致，已拒绝安装）：%1")
            .arg(detail);
    case Stage::extractFailed:
        return QStringLiteral("解压失败：%1").arg(detail);
    case Stage::probeFailed:
        return QStringLiteral("安装后的引擎跑不起来（`version` 探活失败）：%1").arg(detail);
    }
    return detail;
}

QString stageName(Stage s)
{
    switch (s) {
    case Stage::ok:
        return QStringLiteral("ok");
    case Stage::networkUnreachable:
        return QStringLiteral("networkUnreachable");
    case Stage::releaseUnreadable:
        return QStringLiteral("releaseUnreadable");
    case Stage::noPlatformAsset:
        return QStringLiteral("noPlatformAsset");
    case Stage::downloadFailed:
        return QStringLiteral("downloadFailed");
    case Stage::digestMismatch:
        return QStringLiteral("digestMismatch");
    case Stage::extractFailed:
        return QStringLiteral("extractFailed");
    case Stage::probeFailed:
        return QStringLiteral("probeFailed");
    }
    return QStringLiteral("unknown");
}

} // namespace EngineDownload
