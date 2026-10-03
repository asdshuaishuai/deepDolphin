// ProjectDetailPage.h — 项目详情页（mac ProjectDetailView 对位，PLAN §2.6 / §4.5）。
//
// 三态：有 project → 内容；projectLoadErrors → EmptyState「读不出来：<名>」+ 原因；
// 否则 → ProgressView（列表没加载完时短暂存在）。
// 页头 Git 操作 + 提交卡（gitOpButtons **唯一构造点**）；分支进度/里程碑/进度日志/托管文档卡。
#pragma once
#include "../../logic/DashFilter.h"
#include "../../models/DocsEnvelope.h"
#include "../../models/GitOpResponse.h"
#include "../../models/LoadState.h"
#include "../../models/Milestone.h"
#include "../../models/ProjectStatus.h"
#include "../common/Card.h"
#include <QScrollArea>
#include <QWidget>

class QLabel;
class QLineEdit;
class QPlainTextEdit;
class QPushButton;
class QComboBox;
class QVBoxLayout;
class SegmentedBar;
class LegendRow;
class MilestoneRowWidget;
class MarkdownView;
class AppModel;

class ProjectDetailPage : public QWidget {
    Q_OBJECT
public:
    explicit ProjectDetailPage(QWidget *parent = nullptr);

    void setProject(const QString &name, const std::optional<ProjectStatus> &p,
        const QString &loadError);
    void setDocs(const QString &name, const std::optional<DocsEnvelope> &docs,
        const LoadStateBox &state);
    void setMilestones(const QVector<Milestone> &items); // 详情页里程碑卡（该项目范围）
    void setGitOutput(const QString &name, const GitOpResponse &resp);
    void setBusy(bool busy);

signals:
    void gitOpRequested(const QString &op, const QString &project, const QString &message);
    void updateMenuRequested();
    void briefRequested(const QString &project);
    void retryRequested();          // 「读不出来」空态的重试（→ loadProject）
    // 里程碑行内动作（详情页里程碑卡；UI 词已转 CLI 词）
    void milestoneDone(const QString &project, const QString &name);
    void milestoneReopen(const QString &project, const QString &name);
    void milestoneDrop(const QString &project, const QString &name);
    void milestoneRemove(const QString &project, const QString &name);

private:
    void rebuild();
    QWidget *buildHeader(const ProjectStatus &p);
    QWidget *buildCommitCard();
    QWidget *buildPulseCard(const ProjectStatus &p);
    QWidget *buildCommitCompositionCard(const ProjectStatus &p);
    QWidget *buildBranchesCard(const ProjectStatus &p);
    QWidget *buildMilestoneCard();
    QWidget *buildJournalCard(const ProjectStatus &p);
    QWidget *buildDocsArea();

    QString m_name;
    std::optional<ProjectStatus> m_project;
    QString m_loadError;
    std::optional<DocsEnvelope> m_docs;
    LoadStateBox m_docsState;
    QVector<Milestone> m_milestones;
    GitOpResponse m_gitOutput;
    bool m_hasGitOutput = false;
    bool m_busy = false;

    QScrollArea *m_scroll = nullptr;
    QWidget *m_content = nullptr;
    QVBoxLayout *m_contentLayout = nullptr;
    QLineEdit *m_commitInput = nullptr;
    QPushButton *m_commitBtn = nullptr;
    QWidget *m_gitOutputHost = nullptr;
    QWidget *m_headerHost = nullptr;
};
