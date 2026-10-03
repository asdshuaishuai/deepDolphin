#include "ScanDialog.h"
#include "../../logic/PathInput.h"
#include "../DesignTokens.h"
#include <DFileDialog>
#include <DTabBar>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMimeData>
#include <QPushButton>
#include <QSpinBox>
#include <QStackedWidget>
#include <QUrl>
#include <QVBoxLayout>

using namespace PathInput;

namespace {
// 路径输入框 + 拖放（setAcceptDrops；取第一个**文件夹**）
class PathDropEdit : public QLineEdit {
public:
    explicit PathDropEdit(QWidget *parent = nullptr)
        : QLineEdit(parent)
    {
        setAcceptDrops(true);
    }

protected:
    void dragEnterEvent(QDragEnterEvent *e) override
    {
        if (e->mimeData()->hasUrls())
            e->acceptProposedAction();
    }

    void dropEvent(QDropEvent *e) override
    {
        QStringList candidates;
        for (const QUrl &u : e->mimeData()->urls())
            candidates << u.toLocalFile();
        const Verdict v = pickDirectory(candidates);
        if (v.acceptable)
            setText(v.path);
        else
            setToolTip(v.problem); // 「为什么不是别的」说清楚
    }
};
} // namespace

ScanDialog::ScanDialog(QWidget *parent)
    : DDialog(parent)
{
    setWindowTitle(QStringLiteral("添加 / 扫描项目"));
    resize(480, 440);
    setMinimumSize(480, 440);
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::md);

    // 顶部分段：添加单个项目 / 批量扫描目录
    m_tabs = new DTabBar(content);
    m_tabs->addTab(QStringLiteral("添加单个项目"));
    m_tabs->addTab(QStringLiteral("批量扫描目录"));
    v->addWidget(m_tabs);

    m_stack = new QStackedWidget(content);

    // 模式一：路径 + 项目名（可选）
    auto *addPage = new QWidget(m_stack);
    auto *av = new QVBoxLayout(addPage);
    av->setSpacing(DS::Spacing::sm);
    av->addWidget(new QLabel(QStringLiteral("项目路径（绝对路径；~/x 与尾斜杠原样交给引擎）"), addPage));
    m_addPath = new PathDropEdit(addPage);
    m_addPath->setPlaceholderText(QStringLiteral("/home/me/work/my-project"));
    av->addWidget(m_addPath);
    av->addWidget(new QLabel(QStringLiteral("项目名（可选；缺省用目录名）"), addPage));
    m_addName = new DLineEdit(addPage);
    m_addName->setPlaceholderText(QStringLiteral("my-project"));
    av->addWidget(m_addName);
    av->addStretch(1);
    m_stack->addWidget(addPage);

    // 模式二：根目录 + 深度 1..6（默认 2）
    auto *scanPage = new QWidget(m_stack);
    auto *sv = new QVBoxLayout(scanPage);
    sv->setSpacing(DS::Spacing::sm);
    sv->addWidget(new QLabel(QStringLiteral("扫描根目录（必须是一个已存在的文件夹）"), scanPage));
    m_scanRoot = new PathDropEdit(scanPage);
    m_scanRoot->setPlaceholderText(QStringLiteral("/home/me/work"));
    sv->addWidget(m_scanRoot);
    auto *depthRow = new QHBoxLayout;
    depthRow->addWidget(new QLabel(QStringLiteral("扫描深度"), scanPage));
    m_depth = new DSpinBox(scanPage);
    m_depth->setRange(1, 6);
    m_depth->setValue(2);
    depthRow->addWidget(m_depth);
    depthRow->addStretch(1);
    sv->addLayout(depthRow);
    sv->addStretch(1);
    m_stack->addWidget(scanPage);

    v->addWidget(m_stack, 1);

    // 判定提示（橙 Label）+ 结果行
    m_verdict = new QLabel(content);
    m_verdict->setFont(DS::font(DS::FontT::label));
    m_verdict->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
    m_verdict->setWordWrap(true);
    m_verdict->hide();
    v->addWidget(m_verdict);
    m_result = new QLabel(content);
    m_result->setWordWrap(true);
    m_result->hide();
    v->addWidget(m_result);

    addContent(content);
    addButton(QStringLiteral("取消"), false);
    addButton(QStringLiteral("提交"), true, DDialog::ButtonRecommend);
    setOnButtonClickedClose(false);

    auto *choose = new QPushButton(QStringLiteral("选择…"), content);
    connect(choose, &QPushButton::clicked, this, [this] { pickPath(); });
    // 放进两页共用的路径行（同一个焦点绑定，切模式重送焦点）
    qobject_cast<QVBoxLayout *>(m_stack->widget(0)->layout())->insertWidget(1, choose);
    auto *choose2 = new QPushButton(QStringLiteral("选择…"), content);
    connect(choose2, &QPushButton::clicked, this, [this] { pickPath(); });
    qobject_cast<QVBoxLayout *>(m_stack->widget(1)->layout())->insertWidget(1, choose2);

    const auto revalidate = [this] {
        const Verdict v = m_addMode ? prepare(m_addPath->text())
                                    : validateScanRoot(m_scanRoot->text());
        m_verdict->setText(v.acceptable ? QString() : v.problem);
        m_verdict->setVisible(!v.acceptable);
    };
    connect(m_addPath, &QLineEdit::textChanged, this, revalidate);
    connect(m_scanRoot, &QLineEdit::textChanged, this, revalidate);
    connect(m_tabs, &DTabBar::currentChanged, this, [this, revalidate](int index) {
        switchMode(index);
        revalidate();
    });

    connect(this, &DDialog::buttonClicked, this, [this](int, const QString &text) {
        if (text == QStringLiteral("取消")) {
            reject();
            return;
        }
        submit();
    });
    switchMode(0);
}

void ScanDialog::presetPath(const QString &path)
{
    if (path.trimmed().isEmpty())
        return;
    // 目录优先走「添加单个项目」：把某个具体仓库加进群，比"从根扫一遍"更贴近用户意图
    if (!m_addMode)
        switchMode(0);
    m_addPath->setText(path);
    m_addName->clear();
    const Verdict v = prepare(m_addPath->text());
    m_verdict->setText(v.acceptable ? QString() : v.problem);
    m_verdict->setVisible(!v.acceptable);
}

void ScanDialog::switchMode(int index)
{
    m_addMode = index == 0;
    m_stack->setCurrentIndex(index);
    m_result->hide();
    // 同一个焦点绑定，切模式重送焦点
    (m_addMode ? m_addPath : m_scanRoot)->setFocus();
}

void ScanDialog::pickPath()
{
    const QString dir = DFileDialog::getExistingDirectory(this, QStringLiteral("选择文件夹"),
        m_addMode ? m_addPath->text() : m_scanRoot->text());
    if (dir.isEmpty())
        return;
    (m_addMode ? m_addPath : m_scanRoot)->setText(dir);
}

void ScanDialog::submit()
{
    // 提交可用性直接挂判定结论
    const Verdict v = m_addMode ? prepare(m_addPath->text()) : validateScanRoot(m_scanRoot->text());
    if (!v.acceptable) {
        m_verdict->setText(v.problem);
        m_verdict->show();
        return;
    }
    // 结果由 AppModel 的 addFinished/scanFinished 信号经 PanelWindow 转发回本窗？
    // ——不：对话框自持 EngineCli 调用太散。这里只发信号给外部（见信号 addScanned）。
    emit submitted(m_addMode, v.path, m_addMode ? m_addName->text().trimmed()
                                                : QString::number(m_depth->value()));
    accept();
}
