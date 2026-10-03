// AgentDialog.h — AI 助手对话页（mac AgentView sheet 对位，PLAN §2.6 / §4.6）。
//
// 固定 720×620；消息区（气泡，tool 消息按 AgentConversation 规则渲染）；
// 过程事件「🔧 <名>」「✓/✗ <名>」行可见；输入 Ctrl+Return 发送；错误横幅含「重发上一条」；
// 底部「用 UOS AI 打开这个问题」（系统级 AI 在本机唯一有意义的用法，PLAN §5.3）。
// 唯一动效 = 新消息自动滚动（0.20s easeInOut，DS::MotionStandardMs）。
#pragma once
#include "../../ai/AgentCore.h"
#include "../../ai/AgentConversation.h"
#include <DDialog>
#include <DSpinner> // DSpinner 直接带头（避免 using-namespace 下前向声明歧义）
#include <QAtomicInt>
#include <QPointer>
#include <QList>
#include <QSharedPointer>

class QLabel;
class QPlainTextEdit;
class QPushButton;
class QScrollArea;
class QVBoxLayout;
DWIDGET_USE_NAMESPACE

class AgentDialog : public DDialog {
    Q_OBJECT
public:
    // target：范围跟随 selection（选中项目=该项目否则 group），由调用方推导。
    // engineBin：引擎二进制（AgentCore 工具执行用）；空 = 引擎未找到（工具报 notFound 原文）。
    AgentDialog(QWidget *parent, const QString &engineBin, const AgentCore::Target &target);
    ~AgentDialog() override;

    // 换范围（selection 变化且对话未显示时调用）：历史属于旧范围，清空重来。
    void retarget(const AgentCore::Target &t);

protected:
    void closeEvent(QCloseEvent *event) override; // 关窗先停（对位 mac onDisappear stop）

private:
    void buildUi();
    void probeConfiguredAsync(); // key 读取（同步 libsecret）放 worker（PLAN §2.5）；结论回 GUI 回填
    void rebuildTranscript();
    void appendEvent(const QString &ev);
    void setBusy(bool busy);
    void send();
    void stop();
    void resendLast();
    void clearChat();
    void refreshSendButton();

    QString m_engineBin;
    AgentCore::Target m_target;

    QList<ChatMessage> m_history;
    bool m_busy = false;
    bool m_cancelled = false;
    QString m_errorText;
    // 停止旗标用 shared 持有：worker 线程持自己的引用计数副本，对话框析构
    //（置位当前旗标）不会让它悬空——裸 &m_cancelFlag 是退出期的窄窗口 UAF
    QSharedPointer<QAtomicInt> m_cancelFlag;

    QScrollArea *m_scroll = nullptr;
    QWidget *m_transcriptHost = nullptr;
    QVBoxLayout *m_transcriptLayout = nullptr;
    QWidget *m_emptyHint = nullptr;
    DSpinner *m_spinner = nullptr;
    QLabel *m_busyLabel = nullptr;
    QWidget *m_eventRow = nullptr;
    QLabel *m_eventLabel = nullptr;
    QWidget *m_errorBanner = nullptr;
    QLabel *m_errorLabel = nullptr;
    QPlainTextEdit *m_input = nullptr;
    QPushButton *m_sendBtn = nullptr;
    QPushButton *m_stopBtn = nullptr;
    QPushButton *m_clearBtn = nullptr;
    QPushButton *m_resendBtn = nullptr;
    QPushButton *m_uosBtn = nullptr;
    bool m_configured = false;
    QString m_notConfiguredWhy;
    QList<QPointer<QWidget>> m_bubbles; // rebuild 时统一回收
};
