// AIChannel.h — OpenAI 兼容 / Anthropic 共用的 HTTP 传输层（mac AISDK.swift §4.2 的对位）。
//
// 红线照抄：只放行 https 与 http://127.0.0.1/http://localhost（防投毒端点骗取 apiKey）；
// 错误脱敏（Bearer/sk-/x-api-key →「（响应含敏感字段，已隐藏）」，仅前 300 字）；
// stream:false；请求超时 120s（测试连接用短超时 20s）；
// 网络错误按 QNetworkReply::NetworkError 映射成「中文 + 下一步建议」的 13 支
//（mac AIErrorMessage.describe 的对位——实测配错的 baseURL 曾让用户看到纯英文原文）。
#pragma once
#include <QUrl>
#include <QString>
#include <QMap>

class QNetworkReply;

namespace AIChannel {

// 同步 POST 的结果。networkOk=false 时 errCode/errString 有值；HTTP 层错误走 status。
struct HttpResponse {
    bool networkOk = false;
    int status = 0;
    QByteArray body;
    int errCode = 0; // QNetworkReply::NetworkError
    QString errString;
};

// 同步 JSON POST（内部 QEventLoop；调用方自行放 worker 线程）。
HttpResponse post(const QUrl &url, const QByteArray &body,
    const QMap<QString, QString> &headers, int timeoutMs = 120'000);

// URL 安全判定：https://* 或 http://127.0.0.1* 或 http://localhost*。
bool urlAllowed(const QUrl &url);

// 错误体脱敏（响应含敏感字段时整体替换，仅前 300 字）。
QString redact(const QString &text);

// 网络错误码 → 「一句话 + 下一步建议」（AIErrorMessage.describe 13 支对位）。
QString describeNetworkError(int code, const QString &host);

// 只取 host:port 用于显示（key 放 URL userinfo/query 时不外泄；解析不出整个丢掉）。
QString hostOf(const QUrl &url);

} // namespace AIChannel
