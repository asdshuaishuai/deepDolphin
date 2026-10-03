// AIConfig.h — AI 渠道配置（mac AISDK.swift:43-198 对位的最小子集，服务设置页 C7）。
//
// 红线：providerID/model/baseURL 进 QSettings（键 ai.providerID/ai.model/ai.baseURL）；
// apiKey **只进 libsecret**（SecretStore）；明文回退键 ai.apiKey 仅 mock/无头自测路径。
// isConfigured = baseURL 非空 &&（ollama/mock 或 key 非空）。
#pragma once
#include <QString>

class SecretStore;

struct AIConfig {
    QString providerID = QStringLiteral("deepseek");
    QString model;
    QString baseURL;
    QString apiKey; // 内存草稿；saveTo 时才落库（libsecret / mock 明文）
    bool keychainSaveFailed = false;

    // 从 Settings 读身份（不含 key；key 由 loadKey 单独取）
    static AIConfig load();
    // 身份写 Settings；key 写 SecretStore（mock 写 Settings 明文并清明文副本）
    bool saveTo(SecretStore *store, QString *errOut);
    // 读取 key：libsecret 优先，空则退回 Settings 明文 ai.apiKey（仅 headless/mock）
    static QString loadKey(SecretStore *store);
    bool isConfigured(QString *whyNot = nullptr) const;
};
