#include "EngineDownload.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

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

QString installHint()
{
    // ⚠ **旧文案是过时的**：原来让用户「运行 moonGit/scripts/install.sh」——
    //   那是**仓库里**的脚本，拿到 deb 的普通用户**根本没有那个仓库**
    //   ⇒ 指了一条走不通的路。而客户端**自己就有下载链**
    //   （设置·通用页的「下载并安装引擎」⇒ 判定层 logic/EngineDownload 这条链）。
    // ⇒ 先说「应用内就能装」，再给两条备选（离线/内网场景）。
    // ⚠ 措辞保持**中性**（不提「上面/下面」）：判定层不知道界面长什么样。
    return QStringLiteral(
        "可以从 GitHub Releases 下载并安装引擎（装到用户目录，不需要 sudo）；"
        "也可以自己装：把环境变量 DEEPGIT_BIN 指向引擎二进制，或把 moongit 放进 ~/.local/bin。");
}

QString downloadActionLabel()
{
    return QStringLiteral("下载并安装引擎");
}

QString downloadActionTooltip()
{
    // ⚠ 首屏与设置页**逐字抄过同一句**（各写一遍）⇒ 改一处漏一处。
    //   现在只有这里一份，两处都从判定层取。
    return QStringLiteral("从 GitHub Releases 下载并安装引擎（moongit）到用户目录");
}

QString downloadBusyLabel()
{
    return QStringLiteral("正在下载…");
}

QString downloadStatusText(bool found, bool pending, bool downloading)
{
    // ⚠ **下载中优先于「没找到」**：下载期间引擎确实还不在，
    //   但说「没找到」会让用户以为按钮没生效 ⇒ 先说在下载。
    if (downloading)
        return QStringLiteral("正在下载并安装引擎，请稍候…");
    if (found)
        return QStringLiteral("已找到引擎，可正常使用。");
    if (pending)
        return QStringLiteral("正在查找引擎…");
    return QStringLiteral("没有找到引擎。点右侧按钮可从 GitHub Releases 下载并安装"
                          "（装到用户目录，不需要管理员权限）。");
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

QString stagingDir(const QString &installDir)
{
    // ⚠ **与目标目录同级**（不是它的子目录）—— 同级才能用「改名」做**原子切换**
    //   （同一父目录 ⇒ 同一文件系统 ⇒ rename 是原子的）。
    //   放成子目录的话切换就变成「逐文件覆盖」，中途失败会留半个引擎。
    return installDir + QStringLiteral(".staging");
}

QString backupDir(const QString &installDir)
{
    // 切换时的暂存：旧的挪到这儿，切换确认成功才删；失败时用它回滚。
    return installDir + QStringLiteral(".backup");
}

bool hasInstalledEngine(const QString &installDir)
{
    if (installDir.isEmpty())
        return false;
    const QFileInfo bin(installDir + QStringLiteral("/") + packagedBinName());
    // ⚠ 「可执行」才算「有引擎」：只剩半个文件（上次装崩了）不算，
    //   否则会把「首次安装」误判成「升级」，失败文案就会说错。
    return bin.exists() && bin.isExecutable();
}

QString parseEngineVersion(const QString &text)
{
    if (text.isEmpty())
        return QString();
    // ⚠ **锚定 "Engine"**：探活输出是
    //   `moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)`
    //   —— 括号里还有一个 1.0.5（那是**仓颉 SDK** 的版本，不是引擎的）。
    //   ⚠ **文本里有 "Engine" 时就只认它后面的版本，认不到就返回空**（不知道），
    //   **不许**再退回「全文第一个 x.y」—— 那会把 SDK 版本当成引擎版本。
    //   （负控照出来的：不许 fallback 蒙对 ⇒ 判据必须与错误实现分叉。）
    const bool hasEngineWord = text.contains(QStringLiteral("engine"), Qt::CaseInsensitive);
    // ⚠⚠ 中间只许**非字母非数字**（空格/括号/破折号），**不许跨过别的单词** ——
    //   `engine[^0-9]*` 会跨过 " (Cangjie " 抓到 SDK 的 1.0.5（负控照出来的真 bug）。
    static const QRegularExpression anchored(
        QStringLiteral("engine[^0-9a-zA-Z]*([0-9]+(?:\\.[0-9]+)*)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m = anchored.match(text);
    if (m.hasMatch())
        return m.captured(1);
    if (hasEngineWord)
        return QString(); // ⚠ 说「Engine」却给不出版本 ⇒ 不知道，不猜

    // 全文里**没有** "engine" 字样（老引擎 / 契约门夹具输出 `moongit 0.0.0-contract`）
    //   ⇒ 退回「第一个 x.y 形态的数字串」。
    static const QRegularExpression loose(
        QStringLiteral("([0-9]+\\.[0-9]+(?:\\.[0-9]+)*)"));
    const QRegularExpressionMatch m2 = loose.match(text);
    if (m2.hasMatch())
        return m2.captured(1);
    return QString(); // ⚠ 解析不出来就是「不知道」—— 不猜
}

namespace {
/// 把版本串拆成数字段：`v0.2.1-beta` → ["0","2","1"]（前导 v 与后缀不算）。
QStringList versionParts(const QString &v)
{
    static const QRegularExpression num(QStringLiteral("[0-9]+"));
    QStringList out;
    QRegularExpressionMatchIterator it = num.globalMatch(v);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        out << m.captured(0);
    }
    return out;
}
} // namespace

int compareVersions(const QString &a, const QString &b)
{
    const QStringList as = versionParts(a);
    const QStringList bs = versionParts(b);
    const int n = qMax(as.size(), bs.size());
    for (int i = 0; i < n; ++i) {
        // ⚠ 缺失的段当 0 ⇒ `0.2` 与 `0.2.0` 相等。
        const int x = i < as.size() ? as.at(i).toInt() : 0;
        const int y = i < bs.size() ? bs.at(i).toInt() : 0;
        if (x != y)
            return x < y ? -1 : 1;
    }
    return 0;
}

bool isDowngrade(const QString &installed, const QString &candidate)
{
    // ⚠ **版本未知就不判降级**：宁可让用户装上一个「看起来旧」的引擎，
    //   也不要因为解析失败把一次合法升级挡在门外（挡错的代价更大）。
    if (installed.trimmed().isEmpty() || candidate.trimmed().isEmpty())
        return false;
    return compareVersions(candidate, installed) < 0;
}

QString engineFingerprint(const QString &installDir)
{
    if (installDir.isEmpty())
        return QString();
    const QFileInfo bin(installDir + QStringLiteral("/") + packagedBinName());
    if (!bin.exists() || !bin.isExecutable())
        return QString();
    return QStringLiteral("%1:%2")
        .arg(bin.lastModified().toMSecsSinceEpoch())
        .arg(bin.size());
}

QString preserveNote(bool hadExisting, bool preserved)
{
    if (!hadExisting)
        return QStringLiteral("（未安装任何引擎）");
    if (preserved)
        return QStringLiteral("（已保留原有引擎，未做任何改动）");
    // ⚠ 「本来有引擎」但指纹变了 ⇒ 老实说「状态已变」，别装作没事。
    return QStringLiteral("（⚠ 原有引擎的状态已改变，请重新检查）");
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
    case Stage::versionDowngrade:
        return QStringLiteral("拒绝降级安装（下载到的版本比已装的旧）：%1").arg(detail);
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
    case Stage::versionDowngrade:
        return QStringLiteral("versionDowngrade");
    }
    return QStringLiteral("unknown");
}

bool isRetryableNetworkError(QNetworkReply::NetworkError err)
{
    // ⚠ **白名单**（不是黑名单）：Qt 将来新增的错误码默认**不**重试 ⇒ 保守。
    //   「漏重试」只是慢一点；「乱重试」是把 404 / 403 重试三遍让用户干等。
    switch (err) {
    case QNetworkReply::RemoteHostClosedError: // 服务器提前断开（实测的 Connection closed）
    case QNetworkReply::TimeoutError:          // 超时（慢网络 / 被卡住）
    case QNetworkReply::UnknownNetworkError:   // 连接被重置 / HTTP2 stream 中断
    case QNetworkReply::UnknownServerError:    // 服务端 5xx ⇒ 瞬时故障，可再试
        return true;
    default:
        return false;
    }
}

int maxDownloadAttempts()
{
    // ⚠ 3 次（不是无限）：够穿过一次实测的瞬断，又不至于让用户干等太久。
    return 3;
}

int retryDelayMs(int failedAttempts)
{
    // 指数退避：1s → 3s → 9s。
    // ⚠ 「已经失败几次」从 1 起算；失败次数 ≤ 0 或 > 上限时都按第一档给（防御性）。
    if (failedAttempts < 1)
        failedAttempts = 1;
    if (failedAttempts > 3)
        failedAttempts = 3;
    static const int kDelays[3] = { 1000, 3000, 9000 };
    return kDelays[failedAttempts - 1];
}

} // namespace EngineDownload
