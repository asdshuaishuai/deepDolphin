// SegmentedButton.h — 互斥分段按钮组（plan §3b 单一实现：收编 DashboardFilterBar 与
// AutomationPane 原各自为政的两份 segSheet）。
//
// 【实现边界（libdtk6widget 6.7.47 实测）】DTK 未导出 DSegmentedControl——用互斥
// QButtonGroup + 可勾选 QPushButton 自组：选中档 = DS::semColor(accent) 底 + 白字，
// 未选中档 = DS::surfaceAlt() 底 + DS::textPrimary() 字；几何只取 DS::Radius::chip
// 与 DS::buttonPaddingQss()（按钮 padding 一档，M3-5）。
// 【QSS 自包含（计划坑 #3）】sheet() 的占位符全部就地填满，绝不跨函数 .arg——曾把
// %1/%2 留给调用方二级填充，未选中分支缺第二个占位符，颜色喂进去只换来 6 条
// 「Argument missing」告警；SelfCheck 传固定色锁死这条（sheet 是纯函数，无头可跑）。
// 【无 Q_OBJECT（BoardCardWidget 同款）】点击动作走 onClicked 回调——本头是 header-only
// 且无配对 .cpp（CMakeLists 源列表之外），Q_OBJECT 的 moc 进不了 AUTOMOC 候选表
//（AutogenInfo.HEADERS 只收 target 源文件的同名配对 header）；回调随拥有者同生共死
//（SegmentedButton 挂在调用方树上，不比它活得久），无悬空。
// 【主题切换】选中/未选中档的重刷走调用方 reflect 回路与用户点击（同原两份实现）；
// 不设 ds 标签——DS::repolish 的 dsSecondary 分支只写 color，会把底色一起冲掉。
#pragma once
#include "../DesignTokens.h"
#include <QButtonGroup>
#include <QColor>
#include <QHBoxLayout>
#include <QPushButton>
#include <QWidget>

#include <functional>

class SegmentedButton : public QWidget {
public:
    explicit SegmentedButton(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        m_box = new QHBoxLayout(this);
        m_box->setContentsMargins(0, 0, 0, 0);
        m_box->setSpacing(2); // 分段贴合为一枚控件（AutomationPane segHost 原值）
        m_group = new QButtonGroup(this);
        m_group->setExclusive(true);
        connect(m_group, &QButtonGroup::idClicked, this, [this](int id) {
            restyle(); // 用户点击后按新选中态重刷（程序化切换在 setChecked 里刷）
            if (onClicked)
                onClicked(id);
        });
    }

    // 分段档 QSS（纯函数）：颜色由调用方喂入——组件内传 DS::* 取值，SelfCheck 无头
    // 传固定色（--selfcheck 跑在 QGuiApplication 构造前，DS 取色不可用）。
    static QString sheet(bool checked, const QColor &accent, const QColor &bg, const QColor &fg)
    {
        const QString base = QStringLiteral("QPushButton { border: none; border-radius: %1px; %2 }")
                                 .arg(DS::Radius::chip)
                                 .arg(DS::buttonPaddingQss());
        if (checked)
            return base
                + QStringLiteral("QPushButton { background: %1; color: white; }").arg(accent.name());
        return base
            + QStringLiteral("QPushButton { background: %1; color: %2; }").arg(bg.name(), fg.name());
    }

    // 加一档，返回档位 id（按添加顺序从 0 起）；toolTip 可省。
    int addButton(const QString &text, const QString &toolTip = QString())
    {
        auto *b = new QPushButton(text, this);
        b->setCheckable(true);
        if (!toolTip.isEmpty())
            b->setToolTip(toolTip);
        const int id = m_group->buttons().size();
        m_group->addButton(b, id);
        m_box->addWidget(b);
        b->setStyleSheet(sheet(false, DS::semColor(DS::SemColor::accent), DS::surfaceAlt(),
            DS::textPrimary()));
        return id;
    }

    // 程序化选中（reflect 回路）；越界 id 静默忽略（档位枚举超界是调用方代码缺陷，
    // 但段错误比忽略更糟）。
    void setChecked(int id)
    {
        if (QAbstractButton *b = m_group->button(id)) {
            b->setChecked(true);
            restyle();
        }
    }

    int checked() const { return m_group->checkedId(); }
    int count() const { return m_group->buttons().size(); }

    std::function<void(int)> onClicked; // 用户点击（互斥组已自动换选中并重刷）

private:
    void restyle()
    {
        const QColor accent = DS::semColor(DS::SemColor::accent);
        const QString on = sheet(true, accent, DS::surfaceAlt(), DS::textPrimary());
        const QString off = sheet(false, accent, DS::surfaceAlt(), DS::textPrimary());
        const QList<QAbstractButton *> bs = m_group->buttons();
        for (QAbstractButton *b : bs)
            b->setStyleSheet(b->isChecked() ? on : off);
    }

    QButtonGroup *m_group = nullptr;
    QHBoxLayout *m_box = nullptr;
};
