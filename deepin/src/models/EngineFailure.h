// EngineFailure.h — 引擎失败载荷的解读。**纯函数，零 GUI 依赖**（CONTRACT §4.1）。
//
// 五种失败载荷（mac 实测，逐字保留）：
//   ① {code,message,details?}              —— update/deep 单项目 DOC_WRITE_FAILED 等
//   ② {error:true,code,message}            —— milestone 未找到等 errJson
//   ③ {results:[…],count,succeeded,failed} —— update/deep 全项目（成功/失败混製数组）
//   ④ {projects:[…],summary:{failedProjects:N}} —— status，失败项目自带 error
//   ⑤ {projects:{…,failed:N},…}            —— dashboard，只有个数没有原因
// 另有 usage 类失败：stdout 是**纯文本**真因 + stderr 一句汇总（EngineCli 拼）。
//
// isFailure 与引擎 hasErrorOrCode 同规则（有 ok 键 → 不算失败）——两份判定必须逐字一致。
#pragma once
#include <QJsonDocument>
#include <QString>
#include <QStringList>

namespace EngineFailure {

// 人类可读的失败原因，**永不为空**。fallback = 无载荷时的退路（stderr 或退出码文案）。
QString reason(const QJsonDocument &payload, const QString &fallback);

// 同上，fallback = 「引擎退出码 N」（PLAN §2.2 签名口径）。
QString reason(const QJsonDocument &payload, int exitCode);

// 批量载荷里逐项失败原因（给模型/逐条列给用户）。非批量形状 → 空数组。
QStringList batchReasons(const QJsonDocument &payload);

// 这一批失败了几条；载荷不是批量 → -1（不是 0）。
int batchFailedCount(const QJsonDocument &payload);

// 引擎 hasErrorOrCode 同规则：有 ok 键 → 不算失败；否则有 code 或 error → 失败。
bool isFailure(const class QJsonObject &entry);

} // namespace EngineFailure
