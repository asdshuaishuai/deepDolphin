// Derived.h — 项目级派生判定的**唯一出处**（mac Models.swift:516-618 对位，纯函数层）。
//
// 【红线】判定顺序就是正确性（SPEC §3.7）：
//   error→unreadable；kind≠git→notGit；needsAction→needsAction（**必须在 engineStale 前**
//   ——旧顺序曾造成侧栏「看板 1」vs 仪表盘「待处理 3」）；primaryBranch status=="stale"
//   →engineStale；daysSinceLastCommit==nil→unknown；age≤30→recent else quiet。
// · isMergeCandidate 逐字对齐引擎 `ahead>0 && !isDefault && !merged`，**禁用 pendingCommits**。
// · 客户端不许拿 staleDays 自推 3/14 天档位线（那两根线归引擎）。
// · `.quiet` 措辞是「N 天没更新」，**不说「停滞」**（停滞是引擎 14 天档位的词）。
// · 未知状态字符串一律落 unknown，**不许默认绿**。
#pragma once
#include "../logic/Liveness.h"
#include "../models/DashboardData.h"
#include "../models/Milestone.h"
#include "../models/StatusTypes.h"
#include <QColor>
#include <QString>
#include <QStringList>
#include <optional>
#include <vector>

class ProjectStatus;

namespace Derived {

// 「这条项目该显示哪个分支」：标记为当前的那个，没有就退回第一条。
// 唯一出处（不叫 currentBranch——那名字被引擎的分支名字符串占了）。
const BranchStatus *primaryBranch(const ProjectStatus &p);

// 距最后一次提交多少天（毫秒差整除 86400000，对齐引擎 active7d/30d 桶的整数除法）。
// nullopt = 读不出来（非 git / 时间解析不了 / 引擎没给键）。
std::optional<int> daysSinceLastCommit(const ProjectStatus &p);

// 引擎修好的判据：`aheadOfDefault>0 && !isDefault && !merged`。禁用 pendingCommits。
bool isMergeCandidate(const BranchStatus &b);

// 待处理信号：有未提交 / 未跟踪 / stash / 待合入分支 / 合入建议（merge|fast-forward）。
bool needsAction(const ProjectStatus &p);

// 还在不在动（顺序即正确性，见文件头）。
Liveness liveness(const ProjectStatus &p);

struct StateWord {
    QString text;   // 「读不出来 / 非 git 目录 / 有未提交改动 / 停滞 / N 天没更新 / 正常 / 状态读不出来」
    Liveness tone;
};
StateWord stateWord(const ProjectStatus &p);

// ── 看板四列（只读 liveness，不许自己判）──
enum class BoardColumn { attention, active, stale, other };
BoardColumn boardColumn(const ProjectStatus &p);
QString boardColumnTitle(BoardColumn c);
// 空列显示的判定依据原文（mac BoardView.swift:59-66 逐字）。
QString boardColumnBasis(BoardColumn c);

// 看板「待处理」列 / 侧栏徽标 / KPI 待处理 同一谓词的计数。
int attentionCount(const std::vector<ProjectStatus> &projects);

// 侧栏里程碑行徽标：open + done（**不含 unknown**）。调用方在数据缺席时传 nullopt 不显示。
int milestoneBadge(const MilestoneCounts &counts);

// 分支 KPI：Σ max(repoBranchCount,0)（真实分支数；不是 work.branches 追踪数组长度和）。
int branchKpi(const std::vector<ProjectStatus> &projects);

// 合入提示一行文案（kind=="merged" 时返回空串——已合入不再提示；rebase/no-default 不当合入提示）。
QString mergeHintKindLine(const MergeHint &hint);

// 「工程脉搏」行：未提交 N · 未跟踪 N · stash N · 工作区 ×N；空串 = 没有值得说的。
// 采集失败 ⇒「仓库读不出来（<原因>）」——-1 不许当 0。
QString pulseLine(const ProjectStatus &p);

// 「N 个已跟踪分支」＋「仓库共 M 个」披露；M 读不出来时只报追踪数并说明。
QString branchScopeLine(const ProjectStatus &p);

// 分支「多久没更新」：颜色跟引擎 status，不自推档位。
// -1→「多久没更新：读不出来」；0→「今天更新过」；否则「N 天没更新」。
QString staleText(const BranchStatus &b);

// ── 里程碑行派生（mac MilestoneItem 对位）──
bool milestoneUnknown(const Milestone &m);   // status=="unknown" || !gitReadable
QString milestoneStatusLabel(const Milestone &m); // 无法核验/已达成/已放弃/已逾期/进行中
QString milestoneDueText(const Milestone &m);     // 还剩 N 天 / 逾期 N 天 / 空串
QString milestoneCommitsText(const Milestone &m); // 创建以来 N 提交 / 提交数读不出来
QString milestoneUnverifiedNote(const Milestone &m);

// liveness 的状态点颜色（红橙绿灰黄；unknown 灰——不许默认绿）。
QColor livenessColor(Liveness l);

// 引擎分支状态字符串 → 状态色（active绿/idle黄/stale红/merged紫/未知灰，不自推档位）。
QColor branchStatusColor(const QString &status);

// 数值量级分档色（DSStat）：0→中性文字；1–2→黄；3–9→橙；≥10 与**负数（读不出来）**→红。
QColor statTint(int n);

} // namespace Derived
