#include "Settings.h"
#include <QSettings>
#include <QVariant>

Settings &Settings::instance()
{
    static Settings s;
    return s;
}

Settings::Settings()
    : QObject(nullptr)
    // 对齐 PLAN §3：organizationName=deepin → ~/.config/deepin/deepDolphin.conf
    , m_s(new QSettings(QStringLiteral("deepin"), QStringLiteral("deepDolphin"), this))
{
}

int Settings::autoUpdateHours() const
{
    return m_s->value(QStringLiteral("update.autoHours"), 0).toInt();
}

void Settings::setAutoUpdateHours(int hours)
{
    m_s->setValue(QStringLiteral("update.autoHours"), hours);
}

bool Settings::modelsDevRefreshed() const
{
    return m_s->value(QStringLiteral("models-dev.refreshed"), false).toBool();
}

void Settings::setModelsDevRefreshed(bool refreshed)
{
    m_s->setValue(QStringLiteral("models-dev.refreshed"), refreshed);
}

QString Settings::aiProviderID() const
{
    const QString pid = m_s->value(QStringLiteral("ai.providerID")).toString();
    if (!pid.isEmpty())
        return pid;
    // 旧预设迁移：custom 之外的名字都是 models.dev provider id（mac AISDK.swift:50-54）
    const QString legacy = m_s->value(QStringLiteral("ai.preset")).toString();
    if (!legacy.isEmpty())
        return legacy == QLatin1String("custom") ? QStringLiteral("deepseek") : legacy;
    return QStringLiteral("deepseek"); // mac 缺省 providerID
}

QString Settings::aiModel() const
{
    return m_s->value(QStringLiteral("ai.model")).toString();
}

QString Settings::aiBaseURL() const
{
    return m_s->value(QStringLiteral("ai.baseURL")).toString();
}

void Settings::setAiIdentity(const QString &providerID, const QString &model, const QString &baseURL)
{
    m_s->setValue(QStringLiteral("ai.providerID"), providerID);
    m_s->setValue(QStringLiteral("ai.model"), model);
    m_s->setValue(QStringLiteral("ai.baseURL"), baseURL);
}

QString Settings::aiApiKeyPlaintext() const
{
    return m_s->value(QStringLiteral("ai.apiKey")).toString();
}

void Settings::setAiApiKeyPlaintext(const QString &key)
{
    if (key.isEmpty())
        m_s->remove(QStringLiteral("ai.apiKey"));
    else
        m_s->setValue(QStringLiteral("ai.apiKey"), key);
}

void Settings::clearAi()
{
    for (const QString &k : { QStringLiteral("ai.providerID"), QStringLiteral("ai.model"),
             QStringLiteral("ai.baseURL"), QStringLiteral("ai.preset"),
             QStringLiteral("ai.apiKey") })
        m_s->remove(k);
}

void Settings::sync()
{
    m_s->sync();
}
