// ModelsDevCatalog.h — models.dev 目录解析（mac ModelsDev.swift 对位的最小子集）。
//
// 【边界】本类只服务设置页选择器（C7）：provider id/name/api 端点、模型 id 与扁平键
// tool_call/reasoning/context/output/cost_in/cost_out（嵌套 limit{}/cost{} 兼容）。
// 畸形输入 → 空目录**不崩**；解析在锁外（mac P0 死锁教训）。
// 快照链：qrc 内置 models-dev.json → ~/.local/share/deepDolphin/models-dev.json 缓存。
// 后台静默刷新 https://models.dev/api.json（15s 超时；成功才置 models-dev.refreshed）。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <optional>
#include <vector>

struct CatalogModel {
    QString id;
    QString name;
    std::optional<bool> toolCall;
    std::optional<bool> reasoning;
    std::optional<int> context;
    std::optional<int> output;
    std::optional<double> costIn;
    std::optional<double> costOut;
};

struct CatalogProvider {
    QString id;
    QString name;
    std::optional<QString> api; // 端点；空 = 无（只能走 Base URL 覆盖）
    std::vector<CatalogModel> models;
};

class ModelsDevCatalog {
public:
    // 读 qrc 快照（失败 → 读缓存；都失败 → 空目录不崩）。
    static ModelsDevCatalog loadCached();
    // 后台静默刷新（成功才置 Settings::modelsDevRefreshed）。
    static void refreshAsync();

    // 纯解析（可测）：畸形 → 空目录。
    static ModelsDevCatalog parse(const QByteArray &data);

    // 有 api 端点在前，其余按模型数降序（mac ModelsDev.swift 排序对位）。
    std::vector<CatalogProvider> sortedProviders() const;
    std::vector<CatalogProvider> providers;
    int totalProviders() const { return static_cast<int>(providers.size()); }
    int withEndpointCount() const;
    const CatalogProvider *find(const QString &id) const;
};
