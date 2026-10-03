#include "SidebarNav.h"
#include "../logic/DashFilter.h"
#include "../logic/Derived.h"
#include "DesignTokens.h"
#include "common/CountLabel.h"
#include "common/StatusDot.h"
#include <QColor>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPainter>
#include <QPushButton>
#include <QVBoxLayout>
#include <dlineedit.h>
#include <dsearchedit.h>

DWIDGET_USE_NAMESPACE

using Dtk::Widget::DSearchEdit;

namespace {
constexpr int kRoleSelection = Qt::UserRole + 1; // 存 Selection::Kind
constexpr int kRoleProjectName = Qt::UserRole + 2;
constexpr int kRoleIsHeader = Qt::UserRole + 3;
constexpr int kRoleIsView = Qt::UserRole + 4;

// countedRow（PanelView.swift:127-140 对位）：行 widget = 图标 + 名称 + 拉伸 + 行内计数。
// 子控件全部 WA_TransparentForMouseEvents → 点击落回列表项；
// 计数控件经 row property「countLabel」回取（避免 findChildren 的 Q_OBJECT 约束）。
QWidget *countedRow(const QIcon &icon, const QString &text, QWidget *parent)
{
    auto *w = new QWidget(parent);
    auto *h = new QHBoxLayout(w);
    h->setContentsMargins(4, 2, 6, 2);
    h->setSpacing(6);
    auto *ic = new QLabel(w);
    ic->setPixmap(icon.pixmap(14, 14));
    ic->setAttribute(Qt::WA_TransparentForMouseEvents);
    h->addWidget(ic);
    auto *name = new QLabel(text, w);
    name->setAttribute(Qt::WA_TransparentForMouseEvents);
    name->setMaximumWidth(120); // 单行截断（60 字项目名在最窄窗口截断带省略号为预期行为）
    h->addWidget(name);
    h->addStretch(1);
    auto *count = new CountLabel(w);
    count->setAttribute(Qt::WA_TransparentForMouseEvents);
    h->addWidget(count);
    w->setProperty("countLabel", QVariant::fromValue(static_cast<QWidget *>(count)));
    return w;
}
} // namespace

SidebarNav::SidebarNav(QWidget *parent)
    : QWidget(parent)
{
    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(8, 8, 8, 8);
    layout->setSpacing(6);

    // 搜索框：自建（不用系统 searchable 等价物——焦点必须可由 Ctrl+F 外部送入）
    m_search = new DSearchEdit(this);
    m_search->setPlaceHolder(QStringLiteral("搜索项目或分支"));
    layout->addWidget(m_search);
    // DSearchEdit 自身不发 textChanged；用基类 DLineEdit 的信号（DTK6 实测签名）
    connect(m_search, &Dtk::Widget::DLineEdit::textChanged, this, [this](const QString &t) {
        m_query = t;
        rebuildProjectRows();
        emit searchQueryChanged(t);
    });

    m_list = new QListWidget(this);
    m_list->setFrameShape(QFrame::NoFrame);
    m_list->setSelectionMode(QAbstractItemView::SingleSelection);
    layout->addWidget(m_list, 1);

    // ── 底部动作区（列表外）：添加 / 扫描项目 ──
    m_addOrScan = new QPushButton(QStringLiteral("添加 / 扫描项目"), this);
    m_addOrScan->setIcon(QIcon::fromTheme(QStringLiteral("list-add")));
    layout->addWidget(m_addOrScan);
    connect(m_addOrScan, &QPushButton::clicked, this, &SidebarNav::addOrScanClicked);

    // ── 状态条：圆点 + 文案（正在采集…/空闲/引擎连接失败/尚未刷新）──
    auto *strip = new QHBoxLayout;
    m_statusDot = new QLabel(this);
    m_statusText = new QLabel(m_statusTextCache, this);
    DS::tagSecondaryStyle(m_statusText); // 次级文字色单点（原 QSS palette(mid)）
    strip->addWidget(m_statusDot);
    strip->addWidget(m_statusText);
    strip->addStretch(1);
    layout->addLayout(strip);

    // 固定分组与视图行（项目行由 rebuildProjectRows 重建）
    auto addHeader = [this](const QString &title) {
        auto *item = new QListWidgetItem(title, m_list);
        item->setFlags(Qt::NoItemFlags); // 分组头不是导航项
        QFont f = item->font();
        f.setBold(true);
        item->setFont(f);
        item->setData(kRoleIsHeader, true);
        item->setForeground(QBrush(DS::textSecondary())); // 原 palette().mid()：与全仓同一颜色语言
    };
    addHeader(QStringLiteral("视图"));
    const QVector<QPair<QString, Selection::Kind>> views = {
        { QStringLiteral("仪表盘"), Selection::Kind::dashboard },
        { QStringLiteral("看板"), Selection::Kind::board },
        { QStringLiteral("里程碑"), Selection::Kind::milestones },
    };
    for (const auto &v : views) {
        // 文本留给行 widget 的 QLabel：item 自带文本 + setItemWidget 会双重绘制（快照实证）
        auto *item = new QListWidgetItem(m_list);
        item->setData(kRoleSelection, static_cast<int>(v.second));
        item->setData(kRoleIsView, true);
        const QString themeIcon = v.second == Selection::Kind::dashboard
            ? QStringLiteral("preferences-desktop-wallpaper")
            : (v.second == Selection::Kind::board ? QStringLiteral("view-list-details")
                                                  : QStringLiteral("flag"));
        // 行尾计数语义：看板=attention 数（不受时间窗筛选）；里程碑=open+done
        auto *row = countedRow(QIcon::fromTheme(themeIcon), v.first, this);
        row->setProperty("viewKind", static_cast<int>(v.second));
        m_list->setItemWidget(item, row);
        item->setSizeHint(row->sizeHint());
    }
    addHeader(QStringLiteral("仓库（0/0）"));

    connect(m_list, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        if (item->data(kRoleIsHeader).toBool())
            return; // 分组头不吃点击
        const auto kind = static_cast<Selection::Kind>(item->data(kRoleSelection).toInt());
        if (kind == Selection::Kind::project)
            select(Selection::project(item->data(kRoleProjectName).toString()));
        else
            select(Selection { kind, QString() });
    });

    select(Selection::dashboard(), false);
    setStatusStrip(m_statusTextCache, m_statusLiveness);
}

void SidebarNav::select(Selection sel, bool emitSignal)
{
    if (m_selection == sel)
        return;
    m_selection = sel;
    // 同步高亮
    const int row = rowIndexOfSelection(sel);
    if (row >= 0)
        m_list->setCurrentRow(row);
    if (emitSignal)
        emit selectionChanged(sel);
}

int SidebarNav::rowIndexOfSelection(Selection sel) const
{
    for (int i = 0; i < m_list->count(); ++i) {
        auto *item = m_list->item(i);
        if (item->data(kRoleIsHeader).toBool())
            continue;
        const auto kind = static_cast<Selection::Kind>(item->data(kRoleSelection).toInt());
        if (kind != sel.kind)
            continue;
        if (kind == Selection::Kind::project
            && item->data(kRoleProjectName).toString() != sel.projectName)
            continue;
        return i;
    }
    return -1;
}

void SidebarNav::setProjects(const QVector<ProjectStatus> &projects, int shown, int total)
{
    m_projects = projects;
    m_shown = shown;
    m_total = total;
    rebuildProjectRows();
}

void SidebarNav::rebuildProjectRows()
{
    // 先删旧的项目行（固定行保留）
    for (int i = m_list->count() - 1; i >= 0; --i) {
        auto *item = m_list->item(i);
        if (static_cast<Selection::Kind>(item->data(kRoleSelection).toInt())
                == Selection::Kind::project)
            delete item;
    }
    // 分组头「仓库（shown/total）」更新（搜索时 = 匹配数/总数）
    // ⚠ 匹配必须用 QStringLiteral：QLatin1String 会把 UTF-8 中文按 Latin-1 逐字节解释，
    //   startsWith 永远为假——表头永不更新（恒 0/0），插入点搜索失败（项目行插到列表顶）
    int visible = 0;
    for (const ProjectStatus &p : m_projects) {
        const bool keep = m_query.trimmed().isEmpty()
            || projectMatchesQuery(p, m_query);
        if (keep)
            ++visible;
    }
    const int shown = m_query.trimmed().isEmpty() ? m_shown : visible;
    const int total = m_query.trimmed().isEmpty() ? m_total : m_projects.size();
    for (int i = 0; i < m_list->count(); ++i) {
        auto *item = m_list->item(i);
        if (item->data(kRoleIsHeader).toBool() && item->text().startsWith(QStringLiteral("仓库"))) {
            item->setText(QStringLiteral("仓库（%1/%2）").arg(shown).arg(total));
            break;
        }
    }
    // 仓库分组头后插入项目行
    int insertAt = 0;
    for (int i = 0; i < m_list->count(); ++i) {
        if (m_list->item(i)->data(kRoleIsHeader).toBool()
            && m_list->item(i)->text().startsWith(QStringLiteral("仓库"))) {
            insertAt = i + 1;
            break;
        }
    }
    for (const ProjectStatus &p : m_projects) {
        if (!m_query.trimmed().isEmpty() && !projectMatchesQuery(p, m_query))
            continue; // 搜索：名称或任一分支名匹配才显示
        // 文本留给行 widget 的 QLabel（双重绘制同上）
        auto *item = new QListWidgetItem(m_list);
        item->setData(kRoleSelection, static_cast<int>(Selection::Kind::project));
        item->setData(kRoleProjectName, p.name);
        // 项目行 = 状态点（错误 → 红 exclamation）+ 名称（单行截断）+ ●N 橙（userDirtyCount>0）
        auto *dot = new StatusDot(this);
        if (p.isUnreadable()) {
            dot->setColor(Derived::livenessColor(Liveness::unreadable));
            dot->setToolTip(p.error.value_or(QStringLiteral("读不出来")));
        } else {
            dot->setLiveness(Derived::liveness(p));
        }
        auto *row = new QWidget(this);
        auto *h = new QHBoxLayout(row);
        h->setContentsMargins(4, 2, 6, 2);
        h->setSpacing(6);
        h->addWidget(dot);
        auto *name = new QLabel(p.name, row);
        name->setAttribute(Qt::WA_TransparentForMouseEvents);
        name->setMaximumWidth(120);
        h->addWidget(name);
        h->addStretch(1);
        auto *count = new CountLabel(row);
        count->setAttribute(Qt::WA_TransparentForMouseEvents);
        h->addWidget(count);
        // ●N 橙（userDirtyCount>0）；-1 = 读不出来 → nullopt 不显示（读不出来 ≠ 0）
        count->setCount(p.userDirtyCount > 0 ? std::optional<int>(p.userDirtyCount)
                                             : std::nullopt);

        m_list->insertItem(insertAt++, item);
        m_list->setItemWidget(item, row);
        item->setSizeHint(row->sizeHint());
    }
    rebuildViewRowLabels();
}

void SidebarNav::rebuildViewRowLabels()
{
    // 视图行计数（countedRow 的行尾 CountLabel；经 row property 取，避免 findChildren 的
    // Q_OBJECT 约束）
    for (int i = 0; i < m_list->count(); ++i) {
        QListWidgetItem *item = m_list->item(i);
        QWidget *row = m_list->itemWidget(item);
        if (!row || !item->data(kRoleIsView).toBool())
            continue;
        const auto kind = static_cast<Selection::Kind>(row->property("viewKind").toInt());
        auto *countWidget = row->property("countLabel").value<QWidget *>();
        auto *count = static_cast<CountLabel *>(countWidget);
        if (!count)
            continue;
        if (kind == Selection::Kind::board)
            count->setCount(m_attention); // 读不出 → nullopt 不显示
        else if (kind == Selection::Kind::milestones)
            count->setCount(m_milestones);
    }
}

void SidebarNav::setAttentionCount(std::optional<int> n)
{
    m_attention = n;
    rebuildViewRowLabels();
}

void SidebarNav::setMilestoneCount(std::optional<int> n)
{
    m_milestones = n;
    rebuildViewRowLabels();
}

void SidebarNav::setStatusStrip(const QString &text, Liveness dot)
{
    m_statusTextCache = text;
    m_statusLiveness = dot;
    m_statusText->setText(text);
    const QColor c = Derived::livenessColor(dot);
    QPixmap pm(10, 10);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setBrush(c);
    p.setPen(Qt::NoPen);
    p.drawEllipse(0, 0, 10, 10);
    m_statusDot->setPixmap(pm);
}

void SidebarNav::focusSearch()
{
    m_search->setFocus();
}
