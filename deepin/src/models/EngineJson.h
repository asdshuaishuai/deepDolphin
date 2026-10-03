// EngineJson.h — 引擎 --json 输出的统一取键工具。
//
// 【边界】JSON 键名字符串只允许出现在各模型 fromJson 里（见 deepin/README.md
// 「分层纪律」）；本文件只提供取值与兜底口径：
//   · 「未知/读不到 = -1」（CONTRACT §6.2）→ intAt 默认兜底 -1
//   · 布尔披露键缺席 → boolAt 兜底 false（缺键 = 引擎版本过旧，由上层闸门判）
//   · 空串/空数组兜底，不抛异常
#pragma once
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QString>
#include <QStringList>

namespace EngineJson {

// 取键。缺键返回 QJsonValue::Undefined，由各 *_At 决定兜底值。
QJsonValue take(const QJsonObject &obj, const char *key);

// int：缺键/类型不符 → fallback（默认 -1 =「读不到」，不是 0）
int intAt(const QJsonObject &obj, const char *key, int fallback = -1);

// string：缺键/非字符串 → fallback（默认空串）
QString strAt(const QJsonObject &obj, const char *key, const QString &fallback = QString());

// bool：缺键/类型不符 → fallback（默认 false）
bool boolAt(const QJsonObject &obj, const char *key, bool fallback = false);

// double（毫秒时间戳等）：缺键/类型不符 → fallback
double msAt(const QJsonObject &obj, const char *key, double fallback = -1.0);

// 数组：缺键/非数组 → 空数组
QJsonArray arrAt(const QJsonObject &obj, const char *key);

// 字符串数组：缺键/条目非字符串 → 空列表
QStringList strArrAt(const QJsonObject &obj, const char *key);

// ── 顶层判定（CONTRACT §3.1 / §4.1 失败判定三则）──

// 有 `error` 键 → 状态采集失败桩（§4.1 形状③）
bool isErrorStub(const QJsonObject &obj);

// 有 `ok` 键 → 条目自带 ok（ok:false 只是「跑了但没写文档」，不算失败）
bool hasOpKey(const QJsonObject &obj);

// 引擎 hasErrorOrCode 同规则：有 ok 键 → 永远不算失败；否则有 code 或 error → 失败。
// （util/log.cj:159-164；客户端必须逐字对齐，不许写成 ok==true 才算成功）
bool hasCodeOrError(const QJsonObject &obj);

} // namespace EngineJson
