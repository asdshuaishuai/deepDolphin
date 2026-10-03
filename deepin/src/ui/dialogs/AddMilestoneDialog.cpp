#include "AddMilestoneDialog.h"
#include <QAbstractButton>
#include "../DesignTokens.h"
#include <QCheckBox>
#include <QComboBox>
#include <QDateEdit>
#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QTextEdit>
#include <QVBoxLayout>

AddMilestoneDialog::AddMilestoneDialog(QWidget *parent, const QStringList &projects,
    const QString &defaultProject)
    : DDialog(parent)
{
    setWindowTitle(QStringLiteral("新建里程碑"));
    resize(440, 340);
    setMinimumSize(440, 340);
    setMaximumSize(440, 420);

    auto *content = new QWidget(this);
    auto *form = new QFormLayout(content);
    form->setSpacing(DS::Spacing::sm);

    m_project = new QComboBox(content);
    m_project->addItems(projects);
    if (!defaultProject.isEmpty()) {
        const int idx = m_project->findText(defaultProject);
        if (idx >= 0)
            m_project->setCurrentIndex(idx); // 默认当前选中项目
    }
    form->addRow(QStringLiteral("项目"), m_project);

    m_name = new QLineEdit(content);
    m_name->setPlaceholderText(QStringLiteral("里程碑名称"));
    m_name->setClearButtonEnabled(true);
    form->addRow(QStringLiteral("名称"), m_name);

    m_tag = new QLineEdit(content);
    m_tag->setPlaceholderText(QStringLiteral("tag 存在即自动达成（可选）"));
    m_tag->setClearButtonEnabled(true);
    form->addRow(QStringLiteral("绑定 tag"), m_tag);

    m_hasDate = new QCheckBox(QStringLiteral("设置目标日期"), content);
    m_date = new QDateEdit(content);
    m_date->setCalendarPopup(true);
    m_date->setDisplayFormat(QStringLiteral("yyyy-MM-dd"));
    m_date->setDate(QDate::currentDate().addDays(30)); // 默认今天+30 天
    m_date->setEnabled(false);
    connect(m_hasDate, &QCheckBox::toggled, m_date, &QDateEdit::setEnabled);
    auto *dateRow = new QWidget(content);
    auto *dh = new QHBoxLayout(dateRow);
    dh->setContentsMargins(0, 0, 0, 0);
    dh->addWidget(m_hasDate);
    dh->addWidget(m_date, 1);
    form->addRow(QString(), dateRow);

    m_desc = new QTextEdit(content);
    m_desc->setPlaceholderText(QStringLiteral("描述（可选）"));
    m_desc->setFixedHeight(64);
    form->addRow(QStringLiteral("描述"), m_desc);

    m_error = new QLabel(content);
    m_error->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name()));
    m_error->setWordWrap(true);
    m_error->hide();
    form->addRow(m_error);

    addContent(content);
    addButton(QStringLiteral("取消"), false);
    addButton(QStringLiteral("创建"), true, DDialog::ButtonRecommend);
    // 按钮点击**不自动关窗**：校验失败红字贴表单下方（不关窗重试）
    setOnButtonClickedClose(false);
    // 「创建」仅在 project 与 name 非空时可用（defaultAction 的可用性纪律）
    if (QAbstractButton *create = getButton(1))
        create->setEnabled(false);
    connect(m_name, &QLineEdit::textChanged, this, [this](const QString &t) {
        if (QAbstractButton *create = getButton(1))
            create->setEnabled(!t.trimmed().isEmpty()
                && !m_project->currentText().trimmed().isEmpty());
    });
    connect(m_project, &QComboBox::currentIndexChanged, this, [this](int) {
        if (QAbstractButton *create = getButton(1))
            create->setEnabled(!m_name->text().trimmed().isEmpty());
    });

    // 焦点默认落名称框
    m_name->setFocus();
    connect(this, &DDialog::buttonClicked, this, [this](int index, const QString &text) {
        Q_UNUSED(index);
        if (text == QStringLiteral("取消")) {
            reject();
            return;
        }
        // 创建：project 与 name 非空才行——不够格时红字提示且不关窗
        if (m_project->currentText().trimmed().isEmpty()
            || m_name->text().trimmed().isEmpty()) {
            m_error->setText(QStringLiteral("项目与名称不能为空。"));
            m_error->show();
            return;
        }
        accept();
    });
}

QString AddMilestoneDialog::project() const
{
    return m_project->currentText().trimmed();
}

QString AddMilestoneDialog::name() const
{
    return m_name->text().trimmed();
}

QString AddMilestoneDialog::tag() const
{
    return m_tag->text().trimmed();
}

QString AddMilestoneDialog::targetDate() const
{
    // 未勾选 → 空串（空 date 不发键）
    return m_hasDate->isChecked() ? m_date->date().toString(QStringLiteral("yyyy-MM-dd"))
                                  : QString();
}

QString AddMilestoneDialog::desc() const
{
    return m_desc->toPlainText().trimmed();
}

void AddMilestoneDialog::setError(const QString &message)
{
    m_error->setText(message);
    m_error->show();
}
