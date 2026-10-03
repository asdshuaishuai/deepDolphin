// UpdateResult.h — `update`/`deep`/`track` 的结果载荷（CONTRACT §3.1/§3.2/§3.3）。
//
// 【红线】
// · shallow 出口（updateResultToJson）恰有 branchCount/repoBranchCount/branchCountTruncated/
//   commitCount 四键；**deep 出口没有这四键**，deep 另有 highlights[]。
//   解码按 mode 分派，不得跨型取键 —— deep 载荷喂进 ShallowUpdateResult 必须被拒。
// · ok=false **不是失败**：语义是「跑了但没写文档」（hasErrorOrCode 看键不看值）。
// · DocChange.backup 恒发：空串 = 新建/无变化/dry-run，不是「不知道」。
// · 多项目 envelope：恰好 1 项目时引擎给**裸结果对象**，两种形态都要能解（§3.1）。
#pragma once
#include "StatusTypes.h"
#include <QJsonDocument>
#include <QString>
#include <optional>
#include <variant>
#include <vector>

struct DocChange {
    QString file;
    bool changed = false;
    bool created = false;
    std::optional<QString> preview; // 仅 --dry-run 非空时出现
    QString backup;                 // 恒发；空串 ≠ 不知道

    static DocChange fromJson(const class QJsonObject &o);
};

// shallow/deep 共同基座（9 键，cli.cj:2092-2167 逐行核对）
struct UpdateResultBase {
    bool ok = false;              // false ≠ 失败
    QString mode;                 // "shallow"|"deep"
    QString projectId;
    QString project;
    QString provider;
    QString providerLabel;
    std::vector<DocChange> docs;
    std::optional<JournalEntry> journalEntry;
    QString at;
};

struct ShallowUpdateResult : UpdateResultBase {
    int branchCount = 0;           // 本轮建立基线的分支数（受 maxShallowBranches 限，≠仓库分支数）
    int repoBranchCount = -1;      // None → -1
    bool branchCountTruncated = false;
    int commitCount = 0;
};

struct DeepUpdateResult : UpdateResultBase {
    QStringList highlights;
};

// 条目失败的原文（有 code/error 且无 mode；§4.1 形状①②）
struct UpdateFailureEntry {
    QString message;   // EngineFailure 装饰后的单条原因
};

using UpdateResultAny = std::variant<ShallowUpdateResult, DeepUpdateResult, UpdateFailureEntry>;

// `update/deep` 的多项目 envelope {results[], count, failed, succeeded}；
// 恰好 1 项目时引擎给裸结果对象 —— decode() 归一。
struct UpdateAllEnvelope {
    std::vector<UpdateResultAny> results;
    int count = 0;
    int failed = 0;
    int succeeded = 0;

    // envelope 或裸对象 → 逐条按 mode 归一；裸对象返回单元素向量。
    static UpdateAllEnvelope decode(const QJsonDocument &doc);
};

// 单条解析：按 mode 分派；缺 mode / 键集不对 → UpdateFailureEntry（不伪造成功型）。
UpdateResultAny decodeUpdateResultEntry(const class QJsonObject &o);
