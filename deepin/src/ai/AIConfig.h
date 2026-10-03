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

    // 从 Settings 读身份（不含 key；key 由 loadKey 单独取）。**GUI 线程专用**：
    // worker 不得直接碰 Settings 单例（M0-4）——worker 需要时由 GUI 线程先取好按值传入。
    static AIConfig load();
    // 身份写 Settings；key 写 SecretStore（mock 写 Settings 明文并清明文副本）。GUI 线程专用。
    bool saveTo(SecretStore *store, QString *errOut);
    // 读取 key：libsecret 优先，空则用调用方传入的明文回退键（GUI 线程从 Settings
    // ai.apiKey 取好带来；仅 mock/headless 场景有值）。worker 内不得自读 Settings（M0-4）。
    static QString loadKey(SecretStore *store, const QString &plaintextFallback);
    bool isConfigured(QString *whyNot = nullptr) const;
};
