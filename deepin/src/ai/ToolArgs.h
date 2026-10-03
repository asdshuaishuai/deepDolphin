// ToolArgs.h — 工具入参的解析与必填校验（纯函数，无业务依赖；mac ToolArgs.swift 对位）。
//
// ⚠️ 缺陷 NC31 的收口：畸形 JSON 曾被静默吞成「没有参数」，而引擎把**空项目名**
// 理解成「整个项目群」——一次畸形的模型响应 = 静默改写所有项目。所以：
//   · 空串 ≠ 空对象 {}（前者是模型根本没给出参数结构，执行之前必须拦下）；
//   · 必填校验放在**执行点内部**，清单只从「已发给模型的那份」取（单一来源）；
//   · 空白值等同缺（{"name":"  "} 与没给一样危险）。
#pragma once
#include <QByteArray>
#include <QJsonObject>
#include <QMap>
#include <QString>
#include <QStringList>

namespace ToolArgs {

struct Decoded {
    enum class K { object, malformed } k = K::malformed;
    QJsonObject obj;  // k==object 时有效
    QString raw;      // k==malformed 时给人/模型看的前 200 字
};

// 解析模型给的 argumentsJson。畸形/空串/顶层非对象 → malformed（执行之前拦）。
Decoded decode(const QByteArray &argsJson);

// 必填参数里缺了哪些（缺失或空白都算缺）。
QStringList missing(const QJsonObject &params, const QStringList &required);

// 回报给模型的文案：说清缺什么、以及为什么不能自己猜（模型会顺手编项目名）。
QString missingMessage(const QString &tool, const QStringList &missingList);

// 解析畸形入参时的文案（回报给模型，让它能重试而不是放弃）。
QString malformedMessage(const QString &tool, const QString &raw);

// 从「已经发给模型的那份工具定义」（name → parametersJSON 字符串）里取必填参数。
// 抄两份必然漂移——执行端照模型看到过的契约执行，不另抄一份。
QStringList required(const QMap<QString, QString> &parametersJSONByName, const QString &tool);

} // namespace ToolArgs
