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
    };

    explicit EngineInstaller(QObject *parent = nullptr);

    /// 异步下载安装。apiUrl / installDir 可注入（无头契约门用 file:// 打桩）。
    void start(const QString &apiUrl, const QString &installDir);

signals:
    void progress(const QString &text);
    void finished(const EngineInstaller::Result &r);

private:
    void onReleaseReady();
    void onAssetReady();
    void onExtracted();
    void onProbed();
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
    QString m_downloadUrl;
    QString m_digest;
    bool m_verified = false;
};

Q_DECLARE_METATYPE(EngineInstaller::Result)
