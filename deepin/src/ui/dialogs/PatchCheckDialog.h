// PatchCheckDialog.h — 补丁体检窗（mac `PatchCheckPage` 对位，批 F）。
//
// 【页面形状】一个独立 `DDialog`（不是面板第 N 段）：
//   mac 把补丁体检挂在面板级页（`PanelView` 的 `.patchCheck`），deepin 的面板
//   是全局语境（仪表盘/看板/里程碑），而补丁体检天然是**单项目**语境
//   （对某个仓库工作区未提交改动的体检）—— 故按 deepin 既有纪律从详情页入口
//   进、项目名在入口锁定（同架构图窗 / 代码图谱窗）。
//
// 【三层流程（与 mac 一致）】
//   Layer 1 算法：引擎 `graph patchconf <项目> --patch <diff>` → 总分 / S1..S10 信号 /
//                  实体 / 拿不准的项。
//   Layer 2 人工：对每个「拿不准的项」给裁决（已确认 / 未确认 / 存疑）。
//   Layer 3 合并：引擎 `graph patchconf --merge` → 终稿总分 + 告警。
//
// 【披露纪律】
// · `signals` 里的 **null** 是「分母为 0，算不出」，显示「—」而不是 0；
// · 低置信度实体**默认收起**（只告知位置与分数），点开才给 diff 实码 ——
//   「低置信度」不能只给一句元数据，用户得看到代码本身才能判断该不该信。
#pragma once
#include <DDialog>
#include <QHash>
#include <QPointer>
#include <QString>
#include <QStringList>

DWIDGET_USE_NAMESPACE

class QLabel;
class QPlainTextEdit;
class QTextBrowser;
class QComboBox;
class FlatButton;
class QTreeWidget;
class QTreeWidgetItem;
class AppModel;

class PatchCheckDialog : public DDialog {
    Q_OBJECT
public:
    PatchCheckDialog(const QString &projectName, AppModel *model, QWidget *parent = nullptr);

signals:
    /// 请求打开一个导出文件（HTML 绝对路径）。
    void openExportedFile(const QString &path);

private:
    void reload();
    void refreshView();
    void rebuildLayer1();
    void rebuildUncertain();
    void rebuildLowEntities();
    void rebuildMerged();
    void showError(const QString &text);
    void setVerdict(const QString &id, int choice);
    void onMerged(const QString &name);
    void onSkill(const QString &name, const QString &text);
    QString diffText();

    QString m_project;
    AppModel *m_model = nullptr;
    QString m_diff; ///< 工作区 diff（抽实码用；一次体检内不变）
    bool m_diffLoaded = false;

    QLabel *m_score = nullptr;
    QLabel *m_errorBar = nullptr;
    FlatButton *m_run = nullptr;
    FlatButton *m_merge = nullptr;
    FlatButton *m_skill = nullptr;
    QTextBrowser *m_mergedBox = nullptr;
    QTreeWidget *m_signals = nullptr;
    QTreeWidget *m_uncertain = nullptr;
    QTreeWidget *m_entities = nullptr;
    QPlainTextEdit *m_skillBox = nullptr;

    /// uncertain.id → 裁决档位（0=已确认 / 1=未确认 / 2=存疑）。
    QHash<QString, int> m_verdicts;
    /// uncertain.id → 裁决控件（点选后回写 m_verdicts）。
    QHash<QString, QComboBox *> m_verdictBoxes;
};
