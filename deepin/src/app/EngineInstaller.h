// EngineInstaller.h — 引擎获取（GitHub Releases 下载安装）的**执行层**。
//
// 【为什么客户端可以写盘】⚠ 「客户端零业务数据写入，一切经引擎子进程」说的是
//   **业务数据**（项目状态 / 里程碑 / 文档 / 日志）。引擎二进制是**程序自身的依赖**，
//   不是业务数据 —— 不装它客户端根本跑不起来（mac 侧同样有这条下载链）。
//   落盘位置限**用户目录**（~/.local/libexec/deepdolphin），不碰系统目录、不要 sudo。
//
// 【全异步】网络与解压都不在 GUI 线程上阻塞：QNetworkReply 天然异步，
//   解压/探活用 QProcess 的异步接口（waitForFinished 一律不用）。
#pragma once
#include <QObject>
#include <QString>
#include "../logic/EngineDownload.h"

class QNetworkAccessManager;
class QNetworkReply;
class QProcess;
class QTemporaryDir;

class EngineInstaller : public QObject {
    Q_OBJECT
public:
    struct Result {
        bool ok = false;
        EngineDownload::Stage stage = EngineDownload::Stage::ok;
        QString message;       ///< 面向用户的说明（失败时说清是哪一种）
        QString bin;           ///< 成功后引擎路径
        QString tag;           ///< 引擎版本（tag_name）
        bool verified = false; ///< 是否真的做了校验和校验（false = 发布方没给校验和）
        QString installedVersion; ///< 实际装上的引擎版本（探活输出里解析的；空 = 未知）
        bool keptPrevious = false; ///< 失败时**原有引擎是否被保留**（true = 原封未动）
    };

    explicit EngineInstaller(QObject *parent = nullptr);

    /// 异步下载安装。apiUrl / installDir 可注入（无头契约门用 file:// 打桩）。
    void start(const QString &apiUrl, const QString &installDir);

signals:
    void progress(const QString &text);
    void finished(const EngineInstaller::Result &r);

private:
    /// 查发布信息（**可重入**：网络瞬断时重试）。
    void fetchRelease();
    /// 下载资产（**可重入**：网络瞬断时重试）。
    void fetchAsset();
    void onReleaseReady();
    void onAssetReady();
    /// 包已解到**旁路目录**（staging）⇒ 检查内容、探活。
    void onStaged();
    /// 旁路目录里的引擎探活完了 ⇒ 判断要不要比版本。
    void onProbed();
    /// 已装引擎探活完了 ⇒ 比版本（拒绝降级）。
    void onExistingProbed();
    /// 切换：把旁路目录**改名**成目标目录（原子），旧的挪进备份再删。
    void switchToStaging();
    /// 失败收尾：清掉旁路目录（**不碰**目标目录 ⇒ 旧引擎原封不动）。
    void abortInstall(EngineDownload::Stage stage, const QString &detail);
    void fail(EngineDownload::Stage stage, const QString &detail);
    void done(const Result &r);

    QNetworkAccessManager *m_nam = nullptr;
    QNetworkReply *m_reply = nullptr;
    QProcess *m_proc = nullptr;
    QTemporaryDir *m_tmp = nullptr;

    EngineDownload::Release m_release;
    QByteArray m_payload;
    QString m_apiUrl;
    QString m_installDir;
    QString m_stagingDir;  ///< 旁路构建目录（解包 + 探活都在这儿做）
    QString m_backupDir;   ///< 切换时的旧引擎暂存
    QString m_downloadUrl;
    QString m_digest;
    bool m_verified = false;
    /// 目标目录里**原本**就有引擎吗（= 这次是升级；失败文案要说「已保留原有引擎」）。
    bool m_hadExisting = false;
    /// 安装开始时目标引擎的**指纹**（mtime + 大小）—— 失败时复查 ⇒ 「原封未动」是实测的。
    QString m_fingerprint;
    /// 旁路里新包的版本 / 已装引擎的版本（空 = 未知）。
    QString m_newVersion;
    QString m_installedVersion;
    /// 已尝试次数（**分阶段各计**：查询与下载各一轮重试）。
    /// ⚠ 判据在 logic/EngineDownload.h：可重试的错误类型、最多几次、退避多久。
    int m_apiAttempt = 0;
    int m_assetAttempt = 0;
};

Q_DECLARE_METATYPE(EngineInstaller::Result)
