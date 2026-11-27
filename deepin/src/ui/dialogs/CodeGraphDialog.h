// CodeGraphDialog.h — 代码图谱窗（mac CodeGraphPage 对位，批 E2）。
//
// 【页面形状】两栏（mac 同款，不是三栏）：
//   左栏 = 搜索框 + 列表树（mac 的「符号索引热力图」是左栏的**另一种模式**，
//         批 E3 做；本批先交列表树，模式位留着）。
//   右栏 = 详情头 + 三页签（源码 / 置信度 / 关系）+ 详情体。
// 顶栏 = 项目名 + 刷新 / 生成 / 导出 + 置信度总分。
//
// 【单仓库锁定】项目名在入口（详情页）锁定，窗内没有切仓库的选择器 ——
// 与架构图窗、mac 同款纪律：仓库选择是「面板入口」的事。
//
// 【数据来源】引擎三源（graph tree / confidence / functions）→ 合成规则在
// `logic/CodeGraphBuild`（纯函数层）。本窗只做展示与交互。
#pragma once
#include <DDialog>
#include <QPointer>
#include <QString>
#include <QStringList>

DWIDGET_USE_NAMESPACE

class QLabel;
class QLineEdit;
class QTreeWidget;
class QTreeWidgetItem;
class QTextEdit;
class QPlainTextEdit;
class CodeHighlighter;
class QStackedWidget;
class FlatButton;
class SegmentedButton;
class HeatmapWidget;
class AppModel;

class CodeGraphDialog : public DDialog {
    Q_OBJECT
public:
    CodeGraphDialog(const QString &projectName, AppModel *model, QWidget *parent = nullptr);

signals:
    /// 请求打开一个导出文件（HTML 绝对路径）。
    void openExportedFile(const QString &path);

private:
    enum class DetailTab { source, confidence, relation };

    void reload();
    void refreshData();
    void rebuildTree();
    void applyVisibility();
    void onItemActivated(QTreeWidgetItem *item, int column);
    void onSearchChanged(const QString &text);
    void onModeChanged(int id);
    void onHeatNodeSelected(int nodeIdx);
    void onHeatDrillChanged(int nodeIdx);
    void onOverviewChanged(const QString &name);
    void onSymbolDetail(const QString &name, const QString &symbolName);
    void onImpact(const QString &name, const QString &symbolName);
    void showImpact();
    void updateHeatBreadcrumb();
    void showDetail();
    void showSource();
    void showConfidence();
    void showRelation();
    void showError(const QString &text);
    void showReceipt(const QString &text);
    void updateScore();
    /// 索引状态行（持久化索引的代数/节点数/探针时间）。
    /// ⚠ 与页头概览**不是一回事**：概览读的是实时扫描（graph overview），
    ///   这里读的是**持久化索引**（index overview）—— 代码图谱页的「生成」
    ///   写的就是后者，不显示它的话点完「生成」看不到任何变化。
    void updateIndexStatus();

    int nodeIndexOf(QTreeWidgetItem *item) const;
    QTreeWidgetItem *itemFor(int nodeIdx) const;

    QString m_project;
    AppModel *m_model = nullptr;

    QLabel *m_score = nullptr;
    QLabel *m_errorBar = nullptr;
    QLabel *m_receipt = nullptr;
    FlatButton *m_openExport = nullptr;
    QLineEdit *m_search = nullptr;
    QTreeWidget *m_tree = nullptr;
    QStackedWidget *m_leftStack = nullptr;
    SegmentedButton *m_mode = nullptr;
    HeatmapWidget *m_heat = nullptr;
    QLabel *m_heatCrumb = nullptr;
    FlatButton *m_heatBack = nullptr;
    QLabel *m_detailTitle = nullptr;
    QPlainTextEdit *m_source = nullptr;
    /// 源码页签的语法高亮（判定在 logic/SyntaxHighlight，涂色在 ui/CodeHighlighter）
    CodeHighlighter *m_highlighter = nullptr;
    QTreeWidget *m_findings = nullptr;
    QTreeWidget *m_relations = nullptr;
    /// 关系页签的另外两段：引用来源（graph symbol）与影响面（graph impact）
    QTreeWidget *m_refs = nullptr;
    QTreeWidget *m_impact = nullptr;
    QLabel *m_impactNote = nullptr;
    QLabel *m_overview = nullptr;
    QLabel *m_indexStatus = nullptr; ///< 持久化索引的状态行
    FlatButton *m_indexUpdate = nullptr; ///< 「增量更新」钮（引擎 index update）
    FlatButton *m_tabSource = nullptr;
    FlatButton *m_tabConfidence = nullptr;
    FlatButton *m_tabRelation = nullptr;

    QStringList m_expanded; ///< 展开的节点 id（单一真相源）
    QString m_query;
    int m_selected = -1;   ///< 选中的节点（arena 索引）
    DetailTab m_tab = DetailTab::source;
    QString m_exportedPath;
};
