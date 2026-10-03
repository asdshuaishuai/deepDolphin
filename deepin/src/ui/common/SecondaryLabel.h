// SecondaryLabel.h — 次级文字标签（plan §3b 组件化：「同一件事 N 种写法」收敛）。
//
// 内部走 DS::tagSecondaryStyle 同机制：dsSecondary property 登记意图，DS::repolish()
// 在用户切主题/字号时按新 token 重算（M3-4）——不是构建时拍死的颜色快照。
// 原 28 处「new QLabel + DS::tagSecondaryStyle()」两步（更早是 28 处
// setStyleSheet("color: %1;").arg(DS::textSecondary().name()) 复制）收成一个构造；
// 标签上另设的字号/双态色（红/橙告警等）仍由调用方自理（决策 56 的渐进项口径）。
// header-only 与 ui/common 主流一致（8/10 组件如此）；无 Q_OBJECT：纯呈现。
#pragma once
#include "../DesignTokens.h"
#include <QLabel>

class SecondaryLabel : public QLabel {
public:
    explicit SecondaryLabel(QWidget *parent = nullptr)
        : QLabel(parent)
    {
        DS::tagSecondaryStyle(this);
    }

    SecondaryLabel(const QString &text, QWidget *parent = nullptr)
        : QLabel(text, parent)
    {
        DS::tagSecondaryStyle(this);
    }
};
