#include "EngineInstaller.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QTemporaryDir>
#include <QTimer>

namespace {
constexpr int kNetTimeoutMs = 30000;
constexpr int kProcTimeoutMs = 30000;
} // namespace

EngineInstaller::EngineInstaller(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
    qRegisterMetaType<EngineInstaller::Result>("EngineInstaller::Result");
}

void EngineInstaller::fail(EngineDownload::Stage stage, const QString &detail)
{
    // ⚠ **实测**原引擎有没有被动过 —— 不是承诺，是比对指纹。
    //   ⚠ 存在性证明不了「没被动过」（负控照出「文件还在、但被顶替成坏的」）。
    const bool preserved = m_hadExisting && !m_fingerprint.isEmpty()
        && m_fingerprint == EngineDownload::engineFingerprint(m_installDir);
    Result r;
    r.ok = false;
    r.stage = stage;
    r.message = EngineDownload::stageMessage(stage, detail)
        + EngineDownload::preserveNote(m_hadExisting, preserved);
    r.tag = m_release.tag;
    r.verified = m_verified;
    r.keptPrevious = preserved;
    done(r);
}

/// 失败收尾：清掉旁路目录，**不碰**目标目录。
///
/// ⚠ **这是本批的核心不变量**：安装失败 ⇒ 原来能用的引擎**原封不动**。
///   原来的实现是「先删旧 → 再解包 → 最后探活」⇒ 装到坏包时
///   **旧引擎被顶替成坏的**（实测 `old 0.9.9` → `boom`），且无法回滚。
void EngineInstaller::abortInstall(EngineDownload::Stage stage, const QString &detail)
{
    if (!m_stagingDir.isEmpty())
        QDir(m_stagingDir).removeRecursively();
    fail(stage, detail);
}

void EngineInstaller::done(const Result &r)
{
    if (m_reply) {
        m_reply->abort();
        m_reply->deleteLater();
        m_reply = nullptr;
    }
    if (m_proc) {
        m_proc->kill();
        m_proc->deleteLater();
        m_proc = nullptr;
    }
    emit finished(r);
}

void EngineInstaller::start(const QString &apiUrl, const QString &installDir)
{
    m_apiUrl = apiUrl;
    m_installDir = installDir.isEmpty() ? EngineDownload::installDir() : installDir;
    m_stagingDir = EngineDownload::stagingDir(m_installDir);
    m_backupDir = EngineDownload::backupDir(m_installDir);
    m_release = EngineDownload::Release();
    m_payload.clear();
    m_verified = false;
    m_newVersion.clear();
    m_installedVersion.clear();
    // ⚠ 目标目录里**原本**就有引擎吗？决定失败文案说「已保留原有引擎」还是
    //   「未安装任何引擎」—— 也决定要不要比版本（防降级）。
    m_hadExisting = EngineDownload::hasInstalledEngine(m_installDir);
    // ⚠ 记一份**指纹**（mtime + 大小）：失败时复查一遍 ⇒ 「原封未动」是实测的，
    //   不是承诺的（负控照出「文件还在、但内容已被顶替」这种情形）。
    m_fingerprint = EngineDownload::engineFingerprint(m_installDir);

    if (!m_tmp) {
        // ⚠ QTemporaryDir 的构造只认「模板路径」，不认 QObject parent ——
        //   自己管生命周期（析构时 autoRemove 会清目录）。
        m_tmp = new QTemporaryDir(QDir::tempPath() + QStringLiteral("/deepdolphin-engine-XXXXXX"));
        m_tmp->setAutoRemove(true);
    }
    if (!m_tmp->isValid()) {
        fail(EngineDownload::Stage::downloadFailed,
            QStringLiteral("临时目录不可用：%1").arg(m_tmp->path()));
        return;
    }

    m_apiAttempt = 0;
    m_assetAttempt = 0;
    emit progress(QStringLiteral("正在查询引擎发布信息…"));
    fetchRelease();
}

// 查询发布信息（**可重入**：重试时再调一次）。
void EngineInstaller::fetchRelease()
{
    ++m_apiAttempt;
    QNetworkRequest req(m_apiUrl);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("deepDolphin"));
    // GitHub 的 browser_download_url 是 302 直链 → 必须跟随重定向。
    // ⚠ setRedirectPolicy() 是 QNetworkAccessManager 的 6.6+ API；本机这版用请求属性。
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_nam->get(req);
    connect(m_reply, &QNetworkReply::finished, this, &EngineInstaller::onReleaseReady);
    QTimer::singleShot(kNetTimeoutMs, this, [this] {
        if (m_reply) {
            m_reply->abort();
        }
    });
}

void EngineInstaller::onReleaseReady()
{
    if (!m_reply)
        return;
    QNetworkReply *reply = m_reply;
    m_reply = nullptr;
    // ⚠ 先把错误**取出来**再 deleteLater —— 重试分支要用它们，
    //   而且 deleteLater 之后再碰 reply 是不该依赖的写法。
    const QNetworkReply::NetworkError err = reply->error();
    const QString errText = reply->errorString();
    const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    reply->deleteLater();

    if (err != QNetworkReply::NoError) {
        // ⚠ **瞬时故障先重试**（实测：GitHub 侧连接被关/超时是常态，见
        //   logic/EngineDownload.h 的「网络韧性」段）—— 永久故障（404/403 等）
        //   才直接报错，免得让用户干等三遍。
        if (EngineDownload::isRetryableNetworkError(err)
            && m_apiAttempt < EngineDownload::maxDownloadAttempts()) {
            emit progress(QStringLiteral("发布服务器没响应，正在重试（%1/%2）…")
                .arg(m_apiAttempt + 1).arg(EngineDownload::maxDownloadAttempts()));
            QTimer::singleShot(EngineDownload::retryDelayMs(m_apiAttempt), this,
                &EngineInstaller::fetchRelease);
            return;
        }
        // ⚠ 网络层错误**细分**：连不上主机 vs HTTP 错误码 —— 前者是「没网」，
        //   后者是「GitHub 说了什么」（404 / 限流 / 仓库不存在）。两者对用户是不同的话。
        if (err == QNetworkReply::HostNotFoundError
            || err == QNetworkReply::ConnectionRefusedError
            || err == QNetworkReply::TimeoutError
            || err == QNetworkReply::RemoteHostClosedError) {
            fail(EngineDownload::Stage::networkUnreachable, errText);
        } else {
            fail(EngineDownload::Stage::releaseUnreadable,
                QStringLiteral("HTTP %1（%2）").arg(code).arg(errText));
        }
        return;
    }

    const QByteArray json = reply->readAll();
    m_release = EngineDownload::parseRelease(json);
    if (!m_release.parsed) {
        fail(EngineDownload::Stage::releaseUnreadable,
            QStringLiteral("返回的不是预期的发布信息 JSON（%1 字节）").arg(json.size()));
        return;
    }
    if (!m_release.asset.present) {
        fail(EngineDownload::Stage::noPlatformAsset,
            QStringLiteral("版本 %1 的可用资产：%2")
                .arg(m_release.tag,
                    m_release.available.isEmpty()
                        ? QStringLiteral("（无）")
                        : m_release.available.join(QStringLiteral("、"))));
        return;
    }
    if (m_release.asset.url.isEmpty()) {
        fail(EngineDownload::Stage::releaseUnreadable,
            QStringLiteral("资产 %1 没有下载地址").arg(m_release.asset.name));
        return;
    }

    m_downloadUrl = m_release.asset.url;
    m_digest = m_release.asset.digest;
    m_assetAttempt = 0;
    emit progress(QStringLiteral("正在下载引擎 %1（%2）…")
                     .arg(m_release.asset.name,
                         m_release.asset.size > 0
                             ? QStringLiteral("%1 MB").arg(m_release.asset.size / 1024 / 1024)
                             : QStringLiteral("大小未知")));
    fetchAsset();
}

// 下载资产（**可重入**：重试时再调一次；复用 m_downloadUrl / m_digest）。
void EngineInstaller::fetchAsset()
{
    ++m_assetAttempt;
    QNetworkRequest req(m_downloadUrl);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("deepDolphin"));
    // GitHub 的 browser_download_url 是 302 直链 → 必须跟随重定向。
    // ⚠ setRedirectPolicy() 是 QNetworkAccessManager 的 6.6+ API；本机这版用请求属性。
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_nam->get(req);
    connect(m_reply, &QNetworkReply::finished, this, &EngineInstaller::onAssetReady);
    QTimer::singleShot(kNetTimeoutMs, this, [this] {
        if (m_reply)
            m_reply->abort();
    });
}

void EngineInstaller::onAssetReady()
{
    if (!m_reply)
        return;
    QNetworkReply *reply = m_reply;
    m_reply = nullptr;
    // ⚠ 先取错误再 deleteLater（重试分支要用；deleteLater 后再碰 reply 是坏写法）。
    const QNetworkReply::NetworkError err = reply->error();
    const QString errText = reply->errorString();
    reply->deleteLater();

    if (err != QNetworkReply::NoError) {
        // ⚠ **瞬时故障先重试**：实测（2026-10-20）本机第一次下载直接
        //   「下载中断：Connection closed」，稍后重试同一个 URL 1.17 秒就下完。
        //   ⇒ 一次抖动不该让用户手动再点一次。
        if (EngineDownload::isRetryableNetworkError(err)
            && m_assetAttempt < EngineDownload::maxDownloadAttempts()) {
            emit progress(QStringLiteral("下载中断，正在重试（%1/%2）…")
                .arg(m_assetAttempt + 1).arg(EngineDownload::maxDownloadAttempts()));
            QTimer::singleShot(EngineDownload::retryDelayMs(m_assetAttempt), this,
                &EngineInstaller::fetchAsset);
            return;
        }
        // ⚠ 重试到头仍失败 ⇒ 说清「已经试过几次」（用户不该只看到一句「下载失败」）。
        fail(EngineDownload::Stage::downloadFailed,
            m_assetAttempt > 1
                ? QStringLiteral("%1（已重试 %2 次仍失败）").arg(errText).arg(m_assetAttempt)
                : errText);
        return;
    }
    m_payload = reply->readAll();
    if (m_payload.isEmpty()) {
        fail(EngineDownload::Stage::downloadFailed, QStringLiteral("下载到的是空文件"));
        return;
    }

    // 校验和：发布方给了就必须对得上；没给 = 「未校验」（**不是**「校验通过」）。
    if (!m_digest.trimmed().isEmpty()) {
        if (!EngineDownload::digestMatches(m_digest, m_payload)) {
            const QString got = QString::fromLatin1(
                QCryptographicHash::hash(m_payload, QCryptographicHash::Sha256).toHex());
            fail(EngineDownload::Stage::digestMismatch,
                QStringLiteral("期望 %1，实得 %2").arg(m_digest, got));
            return;
        }
        m_verified = true;
    }

    const QString tarPath = m_tmp->path() + QStringLiteral("/engine.tar.gz");
    QFile tar(tarPath);
    if (!tar.open(QIODevice::WriteOnly)) {
        fail(EngineDownload::Stage::downloadFailed,
            QStringLiteral("临时文件写不了：%1").arg(tarPath));
        return;
    }
    tar.write(m_payload);
    tar.close();

    // ⚠⚠ **解到旁路目录，不是解到目标目录**。
    //   原来的实现是「解到目标目录 ⇒ 先删旧的 ⇒ 最后才探活」⇒
    //   装到跑不起来的包时，**原来能用的引擎被顶替成坏的**（实测 old 0.9.9 → boom）。
    //   现在：解到 staging → 探活 staging → **通过了才改名切过去**。
    //   ⇒ 失败路径压根不碰目标目录 ⇒ 旧引擎原封不动。
    QDir(m_stagingDir).removeRecursively(); // 清掉上次残留（进程被杀时可能留下）
    if (!QDir().mkpath(m_stagingDir)) {
        fail(EngineDownload::Stage::downloadFailed,
            QStringLiteral("临时安装目录建不了：%1").arg(m_stagingDir));
        return;
    }

    // 解压：系统 tar（deepin/UOS 都有）。⚠ 不用 waitForFinished —— 会卡 GUI 线程。
    m_proc = new QProcess(this);
    m_proc->setProgram(QStringLiteral("tar"));
    m_proc->setArguments({ QStringLiteral("xzf"), tarPath, QStringLiteral("-C"), m_stagingDir });
    connect(m_proc, &QProcess::finished, this, &EngineInstaller::onStaged);
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (m_proc)
            m_proc->kill();
    });
    m_proc->start();
    QTimer::singleShot(kProcTimeoutMs, this, [this] {
        if (m_proc)
            m_proc->kill();
    });
}

/// 包已解到旁路目录 ⇒ 检查内容、赋可执行位、**探活**。
void EngineInstaller::onStaged()
{
    if (!m_proc)
        return;
    QProcess *proc = m_proc;
    m_proc = nullptr;
    const int code = proc->exitCode();
    const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
    proc->deleteLater();

    const QString staged = m_stagingDir + QStringLiteral("/")
        + EngineDownload::packagedBinName();
    if (code != 0 || !QFileInfo::exists(staged)) {
        abortInstall(EngineDownload::Stage::extractFailed,
            err.isEmpty() ? QStringLiteral("tar 退出码 %1").arg(code) : err);
        return;
    }
    // 可执行位（tar 解出来的权限可能不带）
    QFile::setPermissions(staged,
        QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner | QFile::ReadGroup
            | QFile::ExeGroup | QFile::ReadOther | QFile::ExeOther);

    emit progress(QStringLiteral("正在校验引擎能否启动…"));
    m_proc = new QProcess(this);
    m_proc->setProgram(staged);
    m_proc->setArguments({ QStringLiteral("version") });
    connect(m_proc, &QProcess::finished, this, &EngineInstaller::onProbed);
    m_proc->start();
    QTimer::singleShot(kProcTimeoutMs, this, [this] {
        if (m_proc)
            m_proc->kill();
    });
}

/// 旁路里的引擎探活完了。
void EngineInstaller::onProbed()
{
    if (!m_proc)
        return;
    QProcess *proc = m_proc;
    m_proc = nullptr;
    const bool ok = proc->exitStatus() == QProcess::NormalExit && proc->exitCode() == 0;
    const int code = proc->exitCode();
    const QString out = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
    proc->deleteLater();

    if (!ok) {
        // ⚠ **探活失败 ⇒ 放弃安装**（不切目录）⇒ 旧引擎原封不动。
        abortInstall(EngineDownload::Stage::probeFailed,
            QStringLiteral("%1 version 退出码 %2").arg(m_stagingDir).arg(code));
        return;
    }
    m_newVersion = EngineDownload::parseEngineVersion(out);

    // ⚠ 升级场景：先看**已装**的版本是多少，再决定要不要换。
    //   没有已装引擎 ⇒ 直接切换（首装）。
    if (!m_hadExisting) {
        switchToStaging();
        return;
    }
    emit progress(QStringLiteral("正在核对已装版本…"));
    m_proc = new QProcess(this);
    m_proc->setProgram(m_installDir + QStringLiteral("/")
        + EngineDownload::packagedBinName());
    m_proc->setArguments({ QStringLiteral("version") });
    connect(m_proc, &QProcess::finished, this, &EngineInstaller::onExistingProbed);
    m_proc->start();
    QTimer::singleShot(kProcTimeoutMs, this, [this] {
        if (m_proc)
            m_proc->kill();
    });
}

/// 已装引擎探活完了 ⇒ 比版本。
void EngineInstaller::onExistingProbed()
{
    if (!m_proc)
        return;
    QProcess *proc = m_proc;
    m_proc = nullptr;
    const QString out = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
    proc->deleteLater();
    m_installedVersion = EngineDownload::parseEngineVersion(out);

    // ⚠ **拒绝降级**：下载到的比已装的旧 ⇒ 不换（换下去是把能用的换成不能用的）。
    //   ⚠ 版本**未知就不判**（解析失败不该挡掉一次合法升级）——
    //     判据在 logic/EngineDownload.h 的 isDowngrade()。
    if (EngineDownload::isDowngrade(m_installedVersion, m_newVersion)) {
        abortInstall(EngineDownload::Stage::versionDowngrade,
            QStringLiteral("已装 %1，下载到 %2")
                .arg(m_installedVersion.isEmpty() ? QStringLiteral("（版本未知）")
                                                   : m_installedVersion,
                    m_newVersion.isEmpty() ? QStringLiteral("（版本未知）") : m_newVersion));
        return;
    }
    switchToStaging();
}

/// 切换：旁路目录**改名**成目标目录。
///
/// ⚠ 用 rename（同一父目录 ⇒ 同一文件系统 ⇒ 原子）而不是「逐文件覆盖」——
///   逐文件覆盖中途失败会留半个引擎在目标目录。
///   顺序：旧的挪进 backup → 新的改名过来 → 确认成功才删 backup；
///   中途失败 ⇒ 从 backup 回滚。
void EngineInstaller::switchToStaging()
{
    QDir(m_backupDir).removeRecursively(); // 清掉上次残留
    const bool hadDir = QFileInfo::exists(m_installDir);
    if (hadDir) {
        if (!QDir().rename(m_installDir, m_backupDir)) {
            // 旧的挪不动 ⇒ 干脆不装（保留旧引擎）
            abortInstall(EngineDownload::Stage::extractFailed,
                QStringLiteral("旧引擎目录挪不开（%1）").arg(m_installDir));
            return;
        }
    }
    if (!QDir().rename(m_stagingDir, m_installDir)) {
        // ⚠ 回滚：把旧的挪回去，别让用户落到「没有引擎」的状态。
        if (hadDir)
            QDir().rename(m_backupDir, m_installDir);
        abortInstall(EngineDownload::Stage::extractFailed,
            QStringLiteral("切换安装目录失败（%1）").arg(m_installDir));
        return;
    }
    QDir(m_backupDir).removeRecursively(); // 切换成功 ⇒ 备份可丢

    Result r;
    r.ok = true;
    r.stage = EngineDownload::Stage::ok;
    r.bin = m_installDir + QStringLiteral("/") + EngineDownload::packagedBinName();
    r.tag = m_release.tag;
    r.verified = m_verified;
    r.installedVersion = m_newVersion;
    r.message = m_verified
        ? QStringLiteral("引擎 %1 已安装到 %2（校验和已核对）").arg(r.tag, r.bin)
        : QStringLiteral("引擎 %1 已安装到 %2（⚠ 该发布未提供校验和，未能核对）")
              .arg(r.tag, r.bin);
    if (!m_newVersion.isEmpty())
        r.message += QStringLiteral("；版本 %1").arg(m_newVersion);
    done(r);
}
