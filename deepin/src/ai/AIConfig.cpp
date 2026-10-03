#include "AIConfig.h"
#include "SecretStore.h"
#include "../app/Settings.h"

AIConfig AIConfig::load()
{
    AIConfig c;
    c.providerID = Settings::instance().aiProviderID();
    c.model = Settings::instance().aiModel();
    c.baseURL = Settings::instance().aiBaseURL();
    return c;
}

bool AIConfig::saveTo(SecretStore *store, QString *errOut)
{
    Settings::instance().setAiIdentity(providerID, model, baseURL);
    if (providerID == QLatin1String("mock")) {
        // mock 通道：明文 Settings（PLAN §8 T9；正常保存路径清掉明文副本）
        Settings::instance().setAiApiKeyPlaintext(apiKey);
        keychainSaveFailed = false;
        return true;
    }
    // 正常渠道：key 只进 libsecret；清明文副本
    Settings::instance().setAiApiKeyPlaintext(QString());
    if (store) {
        QString err;
        // 空 key = 删除条目（mac AISDK.save 对位：清空保存也要真删，失败才报）
        const SecretStore::Status st = apiKey.trimmed().isEmpty() ? store->remove(&err)
                                                                  : store->save(apiKey, &err);
        if (st != SecretStore::Status::Ok) {
            keychainSaveFailed = true;
            if (errOut)
                *errOut = err;
            return false;
        }
    }
    keychainSaveFailed = false;
    return true;
}

QString AIConfig::loadKey(SecretStore *store, const QString &plaintextFallback)
{
    if (store) {
        const SecretStore::LoadResult r = store->load();
        if (r.st == SecretStore::Status::Ok && !r.key.isEmpty())
            return r.key;
    }
    return plaintextFallback; // GUI 线程自 Settings 取来的明文回退（仅 headless/mock 用）
}

bool AIConfig::isConfigured(QString *whyNot) const
{
    if (baseURL.trimmed().isEmpty()) {
        if (whyNot)
            *whyNot = QStringLiteral("Base URL 为空（请在 AI 设置里选择 provider 或填写覆盖）");
        return false;
    }
    if (providerID == QLatin1String("ollama") || providerID == QLatin1String("mock"))
        return true; // 本地服务通常无需 Key
    if (apiKey.trimmed().isEmpty()) {
        if (whyNot)
            *whyNot = QStringLiteral("API Key 为空（请填写；key 只存入安全存储）");
        return false;
    }
    return true;
}
