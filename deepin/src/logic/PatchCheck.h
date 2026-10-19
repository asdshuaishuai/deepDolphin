// PatchCheck.h — 补丁体检的判定层（纯函数，零 QWidget 头）。
//
// 【为什么单独一层】三层体检里最容易悄悄错的是三处：
//   ① `signals` 里的 null（分母为 0，算不出）被回落成 0 → 用户以为「得了 0 分」；
//   ② 低置信度实体的**排序与阈值**（mac 同款 <0.75 升序）算错 → 最不可信的那条
//      反而排在最后，用户先看到的正是最可信的；
//   ③ 裁决 id **原样回填** —— `uncertain.id` 与 `entity.id` 不是同一套 id 空间
//      （前者 `文件@行号:名字`，后者 `名字@文件:行号`），混用会让引擎认不出裁决。
// 三处都不该等到看界面才发现，故抽成纯函数直接判。
//
// 【三层流程】
//   解析 Layer1 → 人工裁决（默认 ambiguous/0.5）→ 生成 agent.json → 合并终稿。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include "../models/PatchReport.h"

namespace PatchCheck {

/// 低置信度阈值（mac 同款 0.75）。
constexpr double kLowConfidence = 0.75;

/// 裁决档位（与引擎 agent.json 的 `verdict` 同名同形）。
namespace Verdict {
inline constexpr char Resolved[] = "resolved";
inline constexpr char Unresolved[] = "unresolved";
inline constexpr char Ambiguous[] = "ambiguous";
} // namespace Verdict

/// 分数档位（0..1 → 三档），供界面着色。
enum class ScoreBand { high, mid, low };

/// 档位判定（mac 同款口径：≥0.8 高 / ≥0.5 中 / 其余低）。
ScoreBand bandOf(double score);

/// 解析 Layer 1 载荷。
/// 形状不对时 `ok=false` 且 `error` 说清是哪一种（缺 schema / 缺 signals / 不是对象）。
PatchLayer1 parseLayer1(const QJsonObject &o);

/// 解析 Layer 3（合并终稿）载荷。
PatchMerged parseMerged(const QJsonObject &o);

/// 低置信度实体：confidence < 阈值，**升序**（最不可信的排最前）。
/// 阈值缺键的实体不参与（置信度未知 ≠ 低置信度）。
QVector<PatchEntity> lowConfidenceEntities(const PatchLayer1 &l1,
    double threshold = kLowConfidence);

/// 默认裁决：每个 uncertain 项默认 `ambiguous` / 0.5（mac 同款）。
QVector<PatchVerdict> defaultVerdicts(const PatchLayer1 &l1);

/// 生成 agent.json 载荷（Layer 2 的裁决 → 引擎吃的形状）。
/// `id` 原样回填；`verdict` 越界值归一到 `ambiguous`（不猜）。
QJsonObject agentPayload(const QVector<PatchVerdict> &verdicts);

/// 从 unified diff 文本里抽出「某文件某行附近」的代码块（mac `CodeSnippet.fromDiff` 对位）。
/// 返回空列表 = 抽不到（行不在补丁里 / 文件不在补丁里）—— 调用方要如实说「读不到」。
///
/// @param file 仓库相对路径（如 "src/util.c"）
/// @param line **新文件**里的行号（补丁新增行的行号）
/// @param context 命中行上下各留几行
QStringList diffSnippet(const QString &diffText, const QString &file, int line, int context = 2);

/// 解析 `@@ -a,b +c,d @@` 头里的新起始行号（抽不到就是 0）。
int parseNewStart(const QString &hunkHeader);

} // namespace PatchCheck
