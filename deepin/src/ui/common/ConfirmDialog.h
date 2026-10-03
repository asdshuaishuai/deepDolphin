// ConfirmDialog.h — 破坏性确认框（GuardSpec 唯一消费口；确认按钮「说会发生什么」）。
//
// 染红纪律：删除/放弃/提交确认用 DWarningButton；批量更新确认用普通按钮（有备份可回滚）。
#pragma once
#include "../../logic/DestructiveGuard.h"
#include <DDialog>
#include <DWarningButton>
#include <QAbstractButton>

DWIDGET_USE_NAMESPACE

class ConfirmDialog {
public:
    // spec.destructive → 确认按钮染红（DWarningButton）。
    static bool confirm(QWidget *parent, const DestructiveGuard::Spec &spec)
    {
        DDialog dlg(parent);
        dlg.setTitle(spec.title);
        dlg.setMessage(spec.body);
        dlg.addButton(QStringLiteral("取消"), false);

        bool confirmed = false;
        QAbstractButton *confirmBtn = nullptr;
        if (spec.destructive) {
            auto *warn = new DWarningButton(&dlg);
            warn->setText(spec.confirmLabel);
            dlg.insertButton(1, warn, true);
            confirmBtn = warn;
        } else {
            const int idx = dlg.addButton(spec.confirmLabel, true);
            confirmBtn = dlg.getButton(idx);
        }
        QObject::connect(confirmBtn, &QAbstractButton::clicked, &dlg, [&confirmed] {
            confirmed = true;
        });
        dlg.exec();
        return confirmed;
    }
};
