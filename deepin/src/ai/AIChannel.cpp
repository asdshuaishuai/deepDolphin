#include "AIChannel.h"
#include <DLog>
#include <QEventLoop>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrl>

DCORE_USE_NAMESPACE

namespace AIChannel {

bool urlAllowed(const QUrl &url)
{
    // 只放行 https 与 http://127.0.0.1/http://localhost（防投毒端点骗取 apiKey）。
    if (url.scheme() == QLatin1String("https"))
        return true;
    if (url.scheme() != QLatin1String("http"))
        return false;
    const QString host = url.host();
    return host == QLatin1String("127.0.0.1") || host == QLatin1String("localhost");
}

QString redact(const QString &text)
{
    if (text.contains(QLatin1String("Bearer")) || text.contains(QLatin1String("sk-"))
        || text.contains(QLatin1String("x-api-key"))) {
        return QStringLiteral("（响应含敏感字段，已隐藏）");
    }
    return text.left(300);
}

QString hostOf(const QUrl &url)
{
    if (!url.isValid() || url.host().isEmpty())
        return QString(); // 解析不出来就整个丢掉：宁可少说，也不能把可能含 key 的原文打出去
    const QString host = url.host();
    if (url.port() > 0)
        return host + QStringLiteral(":%1").arg(url.port());
    return host;
}

QString describeNetworkError(int code, const QString &host)
{
    const QString at = host.isEmpty() ? QString() : QStringLiteral("（%1）").arg(host);
    // QNetworkReply::NetworkError 与 mac URLError 的等价映射（SPEC §4.2 的 13 支）
    switch (code) {
    case QNetworkReply::ConnectionRefusedError: // cannotConnectToHost
        return QStringLiteral("连不上 AI 服务%1。检查 AI 设置里的 baseURL 是否写对（要含 /v1 之类的路径），"
                              "以及本机网络是否可用。")
            .arg(at);
    case QNetworkReply::HostNotFoundError: // cannotFindHost
        return QStringLiteral("AI 服务域名解析不了%1。baseURL 里的域名可能有拼写错误，或本机 DNS 不可用。")
            .arg(at);
    case QNetworkReply::TimeoutError:
    case QNetworkReply::OperationCanceledError: // 超时路径的取消
        return QStringLiteral("AI 请求超时（120 秒无响应）。可能是模型太大或网络太慢；"
                              "换一个小一点的模型，或稍后重试。");
    case QNetworkReply::UnknownNetworkError: // notConnectedToInternet 等底层网络不可用
        return QStringLiteral("设备没有网络连接。接上网络后再试。");
    case QNetworkReply::RemoteHostClosedError: // networkConnectionLost
        return QStringLiteral("AI 连接中途断开%1。网络不稳定；重试一次，或换一个 provider。").arg(at);
    case QNetworkReply::SslHandshakeFailedError: // secureConnectionFailed
        return QStringLiteral("HTTPS 连接建立失败%1。该地址的证书无法校验；"
                              "若是你自建的服务，检查证书链是否完整。")
            .arg(at);
    case QNetworkReply::AuthenticationRequiredError: // userAuthenticationRequired
        return QStringLiteral("AI 服务要求身份验证。检查 AI 设置里的 API Key 是否填写。");
    case QNetworkReply::BackgroundRequestNotAllowedError: // dataNotAllowed 同族
        return QStringLiteral("系统不允许这次请求。检查网络/防火墙是否拦了该应用。");
    default:
        break;
    }
    return QStringLiteral("AI 调用失败%1。可在 AI 设置里换一个 provider 或模型后重试。").arg(at);
}

HttpResponse post(const QUrl &url, const QByteArray &body,
    const QMap<QString, QString> &headers, int timeoutMs)
{
    HttpResponse r;
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(timeoutMs);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) {
        if (!it.value().isEmpty())
            req.setRawHeader(it.key().toUtf8(), it.value().toUtf8());
    }

    QNetworkAccessManager nam;
    QNetworkReply *reply = nam.post(req, body);
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QTimer::singleShot(timeoutMs + 1000, &loop, &QEventLoop::quit);
    loop.exec();

    r.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    r.body = reply->readAll();
    if (reply->error() != QNetworkReply::NoError) {
        r.networkOk = false;
        r.errCode = reply->error();
        r.errString = reply->errorString();
        // 真机排障要能回答"连的是谁、为什么失败"（M0-9）：host + 状态码 + 脱敏摘要。
        dWarning() << "AI 渠道调用失败 host=" << hostOf(url) << "status=" << r.status
                   << "netErr=" << r.errCode << redact(r.errString);
    } else {
        r.networkOk = true;
    }
    reply->deleteLater();
    return r;
}

} // namespace AIChannel
