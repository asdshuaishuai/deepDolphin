// PatchReport.h — 补丁体检的数据模型（引擎 `graph patchconf` 的三层契约）。
//
// 【三层是什么】
//   Layer 1（算法）：`graph patchconf <项目> --patch <diff文件> --json`
//     → {schema, overall, signals{S1..S10}, entities[], uncertain[], diagnostics{}}
//   Layer 2（人工裁决）：对 uncertain 每一项给 verdict（resolved/unresolved/ambiguous）
//     + confidence，产出 agent.json。
//   Layer 3（合并）：`graph patchconf --merge <算法.json> <裁决.json> --json`
//     → {schema, overall, signals, entities[], alerts[], sources{}, diagnostics{}}
//
// 【null 与缺键必须可区分】
// `signals` 里的 **null** 是「分母为 0，词法层算不出」（引擎要求如实披露，
// 并在 `diagnostics.null_signals_note` 里说明）；缺键是「契约过旧」。
// 两者都回落成 0 的话，用户会以为「这个信号得了 0 分」而不是「这个信号算不出来」。
// 故每个信号带 `hasValue`，总分带 `overallPresent`。
//
// 【引擎实测口径（2026-10-19，真引擎 dev 分支）】
// · `schema`: "moongit-patch-confidence/1"（Layer1）/ "moongit-patch-confidence-merged/1"（Layer3）
// · `entity.id` 形如 `helper@src/util.c:5`（名字@文件:行号）
// · `uncertain.id` 形如 `src/util.c@6:mystery_call`（文件@行号:名字）—— **与 entity.id 不是同一套**，
//   故两者不可混用同一个 id 空间
// · `uncertain.context_ref` = {file, line}
// · 终稿的复核数在 `diagnostics.reviewed_by_agent`（**不在**顶层 `reviewed` 键上）
#pragma once
#include <QString>
#include <QStringList>
#include <QVector>

/// 一条补丁实体（补丁里被识别出的代码实体：函数/类/…）。
struct PatchEntity {
    QString id;
    QString kind;
    double confidence = 0;
    bool confidencePresent = false; ///< 缺键与「置信度 0」不可区分
    QString file;
    int line = 0;
};

/// 一条「拿不准」的项（算法层发现某个调用在仓库与补丁里都解析不出来）。
struct PatchUncertain {
    QString id;
    QString issue;
    QString detail;
    QStringList candidates;
    QString file; ///< context_ref.file
    int line = 0; ///< context_ref.line
    bool hasContext = false;
};

/// 一个信号（S1..S10）。null = 分母为 0（算不出），与「0 分」不是一回事。
struct PatchSignal {
    QString key;
    bool hasValue = false;
    double value = 0;
};

/// 算法层诊断（键缺失时 `present=false`，不当成「全 0」）。
struct PatchDiagnostics {
    bool present = false;
    int totalEntities = 0;
    int totalRelations = 0;
    int parseErrors = 0;
    int patchFiles = 0;
    int addedLines = 0;
    QStringList nullSignals;
    QString nullSignalsNote;
};

/// Layer 1（算法层）结果。
struct PatchLayer1 {
    bool ok = false;
    QString error; ///< ok==false 时说清是哪一种（契约过旧 / 形状不对）
    QString schema;
    double overall = 0;
    bool overallPresent = false;
    QVector<PatchSignal> signalList;
    QVector<PatchEntity> entities;
    QVector<PatchUncertain> uncertain;
    PatchDiagnostics diagnostics;
};

/// 人工裁决（一条 uncertain 对一条）。
struct PatchVerdict {
    QString id;      ///< uncertain.id（原样回填）
    QString verdict; ///< resolved | unresolved | ambiguous
    double confidence = 0.5;
    QString reason;
};

/// 终稿的一条告警。
struct PatchAlert {
    QString level; ///< high | medium | low
    QString type;
    QString detail;
};

/// Layer 3（合并终稿）结果。
struct PatchMerged {
    bool ok = false;
    QString error;
    QString schema;
    double overall = 0;
    bool overallPresent = false;
    QVector<PatchAlert> alerts;
    bool sourcesAlgorithm = false;
    bool sourcesAgent = false;
    bool diagnosticsPresent = false;
    int certainFromAlgorithm = 0;
    int reviewedByAgent = 0;
    int deferred = 0;
};
