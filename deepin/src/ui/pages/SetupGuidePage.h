// SetupGuidePage.h — 引擎未找到页（CONTRACT §1.1 安装指引 + 「重新检测引擎」）。
// busy = 引擎发现链在跑（M0-2 异步 locate）：马上下结论会闪烁，用忙态如实表达"还在探"。
//
// 【为什么这里有「下载并安装引擎」】⚠ **实测（2026-10-20）**：引擎缺失时，
//   用户**第一眼**看到的就是这个页面 —— 而客户端**自己就有下载链**
//   （设置·通用页的「下载并安装引擎」）。⚠ 原来这个首屏**只有**「重新检测引擎」，
//   而提示文案让用户去跑 `moonGit/scripts/install.sh`
//   ⇒ 拿 deb 的普通用户**没有那个仓库** ⇒ 指了一条走不通的路。
//   ⇒ 引擎缺失时**用户唯一的出路**必须在这块屏幕上，不许绕到设置页去找。
#pragma once
#include <QWidget>
#include <dspinner.h>

class QLabel;
class QPushButton;

DWIDGET_USE_NAMESPACE

class SetupGuidePage : public QWidget {
    Q_OBJECT
public:
    /// ⚠ `downloadLabel` / `downloadTooltip` 由**上层传入**（判定层真相源经 AppModel 转来）。
    ///   本页**不许**直接 include 判定层 —— 与设置页 GeneralPane 同一纪律
    ///   （接线门 arch_forbid 盯着：界面不自己读判定层，结论经 AppModel 传上来）。
    explicit SetupGuidePage(const QString &problem, const QString &downloadLabel,
        const QString &downloadTooltip, QWidget *parent = nullptr);
    void setProblem(const QString &problem);
    void setBusy(bool busy);

    /// 下载态：正在下载 / 结果说明。
    /// ⚠ `message` 由**判定层**生成（AppModel::engineDownloadMessage）——
    ///   UI 层不许自己写下载相关的文案（那会与引擎下载链的结论说法漂移）。
    /// ⚠ 空 message = 没在下载（收起提示行）。
    void setDownloadState(bool downloading, const QString &message = QString());

signals:
    void redetectClicked();
    /// 用户点了「下载并安装引擎」——由上层接去跑引擎下载链。
    void downloadClicked();

private:
    QLabel *m_icon = nullptr;
    DSpinner *m_spinner = nullptr;
    QLabel *m_title = nullptr;
    QLabel *m_problem = nullptr;
    QPushButton *m_redetect = nullptr;
    QPushButton *m_download = nullptr;
    QLabel *m_downloadMsg = nullptr;
    bool m_busy = false;
    bool m_downloading = false;
};
