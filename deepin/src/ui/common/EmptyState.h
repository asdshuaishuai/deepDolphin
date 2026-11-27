// EmptyState.h — 各页空态/失败态统一组件（标题 + 副说明 + 主 CTA 槽位）。
//
// plan §3b 增强：① iconTone 分档——「空」（还什么都没有，给了下一步就能有）与
// 「读不出来」（数据应在而引擎给不出）在图标上区分；② 主 CTA 槽位——空态给出
// 「下一步」按钮（原 accessory 槽位同名化，槽位语义不变）；③ compact() 卡内紧凑版
// ——DashboardPage 原 4 处「一句话 QLabel/SecondaryLabel 空态」半数无图标的散装
// 表达收编。图标名要另指时走显式 iconName 构造（MilestonesPage 的 flag、
// ProjectDetailPage 的 data-warning 是刻意保留的主题意象）。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include "../../logic/IconNames.h"
#include "../../platform/IconResolver.h"
#include "../DesignTokens.h"
#include "SecondaryLabel.h"
#include <QHBoxLayout>
#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>

class EmptyState : public QWidget {
public:
    // iconTone（plan §3b）：空与读不出来必须长得不同——
    // Empty = info（中性：还没有）；Warning = warning（告警：读不出来）。
    enum class Tone { Empty, Warning };

    // tone→**逻辑图标名**单点（SelfCheck 无头锁这条契约：--selfcheck 跑在
    // QGuiApplication 构造前，不实例化控件，纯字符串映射可跑）。
    // ⚠ 返回的是**逻辑名**不是主题名：真正取图标走 `platform::icon()`
    //   （候选链在 `logic/IconNames`）—— 主题缺名时才有路可走。
    static IconNames::Id toneIcon(Tone tone)
    {
        return tone == Tone::Warning ? IconNames::Id::warning : IconNames::Id::info;
    }

    // 页级版：竖排居中（stretch + 图标 + 标题 + 副题 + 主 CTA + stretch）。
    EmptyState(IconNames::Id logicalIcon, const QString &title, const QString &subtitle,
        QWidget *cta = nullptr, QWidget *parent = nullptr)
        : QWidget(parent)
    {
        init(logicalIcon, title, subtitle, cta);
    }
    EmptyState(Tone tone, const QString &title, const QString &subtitle = QString(),
        QWidget *cta = nullptr, QWidget *parent = nullptr)
        : QWidget(parent)
    {
        init(toneIcon(tone), title, subtitle, cta);
    }

    // 卡内紧凑版：小图标 + 一句话（不带 stretch 不带标题——那是页级版的事）。
    static EmptyState *compact(Tone tone, const QString &text, QWidget *parent = nullptr)
    {
        auto *w = new EmptyState(parent);
        auto *h = new QHBoxLayout(w);
        h->setContentsMargins(0, 0, 0, 0);
        h->setSpacing(DS::Spacing::sm);
        auto *icon = new QLabel(w);
        icon->setPixmap(platform::icon(toneIcon(tone)).pixmap(16, 16));
        h->addWidget(icon, 0, Qt::AlignTop);
        auto *t = new SecondaryLabel(text, w);
        t->setWordWrap(true);
        h->addWidget(t, 1);
        return w;
    }

private:
    explicit EmptyState(QWidget *parent = nullptr)
        : QWidget(parent)
    {
    }

    void init(IconNames::Id logicalIcon, const QString &title, const QString &subtitle,
        QWidget *cta)
    {
        auto *v = new QVBoxLayout(this);
        v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl);
        v->setSpacing(DS::Spacing::sm);
        v->addStretch(1);

        auto *icon = new QLabel(this);
        // 走统一入口：主题缺名时**不静默空图**（缺失会被告警并占位显形）。
        icon->setPixmap(platform::icon(logicalIcon).pixmap(36, 36));
        icon->setAlignment(Qt::AlignCenter);
        v->addWidget(icon);

        auto *t = new QLabel(title, this);
        t->setFont(DS::font(DS::FontT::sectionTitle));
        t->setAlignment(Qt::AlignCenter);
        t->setWordWrap(true);
        v->addWidget(t);

        if (!subtitle.isEmpty()) {
            auto *s = new SecondaryLabel(subtitle, this);
            s->setAlignment(Qt::AlignCenter);
            s->setWordWrap(true);
            s->setFont(DS::font(DS::FontT::body));
            v->addWidget(s);
        }
        if (cta) {
            // 主 CTA 槽位：空态给「下一步」（plan §3b）；按钮类与语义由调用方定。
            auto *wrap = new QHBoxLayout;
            wrap->addStretch(1);
            wrap->addWidget(cta);
            wrap->addStretch(1);
            v->addLayout(wrap);
        }
        v->addStretch(2);
    }
};
