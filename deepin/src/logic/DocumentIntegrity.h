// DocumentIntegrity.h — 文档完整性判定的纯函数层（引擎 verify 的唯一收口）。
//
// 【红线】
// · 零 QWidget 头：只依赖 models/VerifyEnvelope.h + QtCore（可被无头单测直接编）。
// · 只做**判定的翻译**，不重算引擎的判据：failures/undetermined/missing
//   三个计数从哪来就是引擎说了算，客户端只决定它**显示成哪一句话**。
// · 「无法判定」与「通过」是两件事：undetermined 永远不并进 verified，
//   也不许用中性色装成「没事」（SPEC §3.5 三态纪律）。
// · 颜色不归本层：本层只给 State 档，色由视图层映射 DS::SemColor。
#pragma once
#include <QString>
#include <QStringList>
#include "../models/VerifyEnvelope.h"

namespace DocumentIntegrity {

// 四档 + 一档「无从校验」。顺序即严重度（missing > failed > undetermined > none）。
enum class State {
    verified,     // 逐字节一致
    failed,       // 明确不一致（有答案的坏）
    undetermined, // 无法判定（没答案，≠ 通过）
    missing,      // 文档缺失（备份仍在，可恢复）
    none,         // 没有可校验的文档
};

/// 判定档。优先级：missing > failed > undetermined > none > verified。
/// 引擎没说通过、也没给任何计数 → 落 undetermined（不落 verified）。
State stateOf(const VerifyEnvelope &e);

/// 一句话主判据。
QString headline(State s, const VerifyEnvelope &e);

/// 副说明：计数 + 引擎给的原因（引擎的 note 原样转述，不改写语义）。
QString detail(const VerifyEnvelope &e);

/// 单份文档的一行（文件名 + 引擎的 note）。
QString documentLine(const VerifyDocument &d);

} // namespace DocumentIntegrity
