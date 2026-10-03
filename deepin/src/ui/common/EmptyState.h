// EmptyState.h — 各页空态/失败态统一组件（标题 + 副说明 + 可选附加控件）。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include "../DesignTokens.h"
#include "SecondaryLabel.h"
#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>

class EmptyState : public QWidget {
public:
    EmptyState(const QString &iconName, const QString &title, const QString &subtitle,
        QWidget *accessory = nullptr, QWidget *parent = nullptr)
        : QWidget(parent)
    {
        auto *v = new QVBoxLayout(this);
        v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl);
        v->setSpacing(DS::Spacing::sm);
        v->addStretch(1);

        auto *icon = new QLabel(this);
        icon->setPixmap(QIcon::fromTheme(iconName,
                            QIcon::fromTheme(QStringLiteral("dialog-information")))
                            .pixmap(36, 36));
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
        if (accessory) {
            auto *wrap = new QHBoxLayout;
            wrap->addStretch(1);
            wrap->addWidget(accessory);
            wrap->addStretch(1);
            v->addLayout(wrap);
        }
        v->addStretch(2);
    }
};
