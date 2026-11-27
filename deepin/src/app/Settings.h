// Settings.h — 应用配置存储（QSettings，INI）。
//
// 【取舍】QSettings 而非 DConfig（PLAN §8 T3）：二进制免安装可跑（冒烟要求），
// DConfig meta 未装到 /etc/dsg/configs 时键不可用。落盘
// ~/.config/deepin/deepDolphin.conf（organizationName=deepin）。
//
// 【键名红线】键名沿用 mac 版 UserDefaults（对齐 cn.deepdolphin.app 域）：
//   · update.autoHours        —— 定时更新周期（小时；0 = 关闭；mac AIIntegration.swift:121）
//   · models-dev.refreshed    —— models.dev 目录已成功刷新过（mac ModelsDev.swift:127）
//   · ai.providerID/ai.model/ai.baseURL —— AI 渠道（mac AISDK.swift:53-57）
//   · ai.preset               —— 旧键迁移源（custom→deepseek，其余为 provider id）
//   · ai.apiKey               —— **明文回退键**：key 正常只进 libsecret（AI 阶段），
//                                此键仅 mock/无头自测路径使用；正常保存路径会清掉它。
//   · app.language             —— 应用语言（BCP 47 风格标签；批 AA 新增）。
//                                键名与 mac 的 UserDefaults `app.language` **逐字对齐**
//                                （mac L10n.swift:2042）—— 当前**只有固定文档页**跟它走
//                                （台账 B8 的全应用 i18n 未做）；全应用化之后是**同一个键**，
//                                不必迁移，也不会出现两个「语言设置」打架。
//   · notify.timeoutMs         —— 通知显示时长（毫秒；批 AI 新增）。
//                                ⚠ **mac 侧无对位**：mac 的 UNNotificationRequest 没有超时
//                                概念（通知常驻通知中心）⇒ 这个键是 **deepin 自有**，
//                                不存在「与 mac 逐字对齐」一说。
#pragma once
#include <QObject>
#include <QString>

class QSettings;

class Settings : public QObject {
    Q_OBJECT
public:
    static Settings &instance();

    // ── update.autoHours ──
    int autoUpdateHours() const;               // 缺省 0 = 关闭
    void setAutoUpdateHours(int hours);

    // ── notify.timeoutMs ──
    /// 通知显示时长（毫秒，**已归一**：越界夹进范围、非正取缺省 5s）。
    /// ⚠ 归一在判定层 `logic/Notifications::normalizeTimeoutMs` ——
    ///   D-Bus 语义里 0 = 「永不消失」⇒ 不能原样传给通知服务器。
    int notifyTimeoutMs() const;
    void setNotifyTimeoutMs(int ms);

    // ── models-dev.refreshed ──
    bool modelsDevRefreshed() const;           // 缺省 false
    void setModelsDevRefreshed(bool refreshed);

    // ── ai.* ──
    QString aiProviderID() const;              // ai.providerID；旧 ai.preset 迁移（custom→deepseek）
    QString aiModel() const;                   // ai.model
    QString aiBaseURL() const;                 // ai.baseURL
    void setAiIdentity(const QString &providerID, const QString &model, const QString &baseURL);

    // ai.apiKey 明文回退（仅 mock/无头自测）；setAiApiKeyPlaintext 保存时清明文副本
    QString aiApiKeyPlaintext() const;
    void setAiApiKeyPlaintext(const QString &key);
    void clearAi();                            // 清除全部 ai.* 键

    // ── app.language ──
    /// 应用语言（持久化值；**BCP 47 风格**的语言标签，如 "zh-CN"/"en"）。
    ///
    /// ⚠ 缺省空串 = 还没选过 ⇒ 调用方回落到默认语言（简体中文）。
    ///   **不在这里回落**：这里只存「用户选了什么」，不替他决定。
    ///
    /// ⚠ **作用域**：当前**只有固定文档页**跟这个值走（台账 B8 的全应用 i18n
    ///   未做）—— 文档窗里的语言选择器会**如实说明**这一点。
    QString appLanguageKey() const;
    void setAppLanguageKey(const QString &key);

    // 同步落盘（退出前调用，防丢末次写入）
    void sync();

private:
    Settings();
    QSettings *m_s;
};
