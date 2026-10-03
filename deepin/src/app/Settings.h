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

    // 同步落盘（退出前调用，防丢末次写入）
    void sync();

private:
    Settings();
    QSettings *m_s;
};
