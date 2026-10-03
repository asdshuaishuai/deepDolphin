// MilestonesPage.h — 里程碑页（mac MilestonesView 对位，PLAN §4.4）。
//
// 判定顺序（刻意）：先 failed → loading → 搜索空 → 列表（「读取失败」与「还没有」长得不同）。
// 仓库筛选条在**内容区顶部**不在标题栏；筛选状态是页面自己的（默认 nil=全部，
// 不从 selection 推导）。统计按明细 tally + 当前范围；明细 ≠ readCount → 披露「下界」。
#pragma once
#include "../../logic/DashFilter.h"
#include "../../models/LoadState.h"
#include "../../models/Milestone.h"
#include <QWidget>

class QComboBox;
class QLabel;
class QVBoxLayout;
class QLineEdit;
class QTreeWidget;

class MilestonesPage : public QWidget {
    Q_OBJECT
public:
    explicit MilestonesPage(QWidget *parent = nullptr);

    void setEnvelope(const std::optional<MilestonesEnvelope> &envelope, const LoadStateBox &state);
    void setProjectNames(const QStringList &names); // 供「新建里程碑」对话框的项目候选

signals:
    void createRequested(const QString &project);
    // action ∈ done|reopen|drop（UI 词 "open" 已转 CLI "reopen"）
    void statusAction(const QString &project, const QString &name, const QString &action);
    void removeRequested(const QString &project, const QString &name);
    void goProject(const QString &project);

private:
    void rebuild();

    std::optional<MilestonesEnvelope> m_envelope;
    LoadStateBox m_state;
    QString m_query;           // 搜索里程碑名称
    QString m_projectFilter;   // 页面自有状态；空 = 全部
    QStringList m_projectNames;
    QComboBox *m_projectBox = nullptr;
    QLabel *m_filterCount = nullptr;
    QTreeWidget *m_tree = nullptr;
    QWidget *m_body = nullptr;
    QVBoxLayout *m_bodyLayout = nullptr;
};
