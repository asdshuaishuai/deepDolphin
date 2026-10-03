#include "ModelsDevCatalog.h"
#include "../app/Settings.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QTimer>
#include <algorithm>

ModelsDevCatalog ModelsDevCatalog::parse(const QByteArray &data)
{
    ModelsDevCatalog cat;
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return cat; // 畸形 → 空目录，不崩
    const QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        if (!it.value().isObject())
            continue;
        const QJsonObject po = it.value().toObject();
        CatalogProvider p;
        p.id = it.key();
        p.name = po.value(QLatin1String("name")).toString(p.id);
        if (po.value(QLatin1String("api")).isString())
            p.api = po.value(QLatin1String("api")).toString();
        const QJsonObject models = po.value(QLatin1String("models")).toObject();
        for (auto mt = models.begin(); mt != models.end(); ++mt) {
            if (!mt.value().isObject())
                continue;
            const QJsonObject mo = mt.value().toObject();
            CatalogModel m;
            m.id = mt.key();
            m.name = mo.value(QLatin1String("name")).toString(m.id);
            // 读**扁平键**（嵌套 limit{}/cost{} 兼容——实测快照是扁平的）
            const QJsonValue tc = mo.contains(QLatin1String("tool_call"))
                ? mo.value(QLatin1String("tool_call"))
                : mo.value(QLatin1String("limit")).toObject().value(QLatin1String("tool_call"));
            if (tc.isBool())
                m.toolCall = tc.toBool();
            const QJsonValue rs = mo.contains(QLatin1String("reasoning"))
                ? mo.value(QLatin1String("reasoning"))
                : mo.value(QLatin1String("limit")).toObject().value(QLatin1String("reasoning"));
            if (rs.isBool())
                m.reasoning = rs.toBool();
            const QJsonValue cx = mo.contains(QLatin1String("context"))
                ? mo.value(QLatin1String("context"))
                : mo.value(QLatin1String("limit")).toObject().value(QLatin1String("context"));
            if (cx.isDouble())
                m.context = static_cast<int>(cx.toDouble());
            const QJsonValue out = mo.contains(QLatin1String("output"))
                ? mo.value(QLatin1String("output"))
                : mo.value(QLatin1String("limit")).toObject().value(QLatin1String("output"));
            if (out.isDouble())
                m.output = static_cast<int>(out.toDouble());
            const QJsonValue ci = mo.contains(QLatin1String("cost_in"))
                ? mo.value(QLatin1String("cost_in"))
                : mo.value(QLatin1String("cost")).toObject().value(QLatin1String("cost_in"));
            if (ci.isDouble())
                m.costIn = ci.toDouble();
            const QJsonValue co = mo.contains(QLatin1String("cost_out"))
                ? mo.value(QLatin1String("cost_out"))
                : mo.value(QLatin1String("cost")).toObject().value(QLatin1String("cost_out"));
            if (co.isDouble())
                m.costOut = co.toDouble();
            p.models.push_back(std::move(m));
        }
        cat.providers.push_back(std::move(p));
    }
    return cat;
}

int ModelsDevCatalog::withEndpointCount() const
{
    int n = 0;
    for (const CatalogProvider &p : providers) {
        if (p.api.has_value() && !p.api->isEmpty())
            ++n;
    }
    return n;
}

std::vector<CatalogProvider> ModelsDevCatalog::sortedProviders() const
{
    std::vector<CatalogProvider> out = providers;
    std::sort(out.begin(), out.end(), [](const CatalogProvider &a, const CatalogProvider &b) {
        const bool aApi = a.api.has_value() && !a.api->isEmpty();
        const bool bApi = b.api.has_value() && !b.api->isEmpty();
        if (aApi != bApi)
            return aApi; // 有 api 端点在前
        return a.models.size() > b.models.size(); // 其余按模型数降序
    });
    return out;
}

const CatalogProvider *ModelsDevCatalog::find(const QString &id) const
{
    for (const CatalogProvider &p : providers) {
        if (p.id == id)
            return &p;
    }
    return nullptr;
}

ModelsDevCatalog ModelsDevCatalog::loadCached()
{
    // 顺序：缓存（Application Support/deepDolphin/models-dev.json）→ qrc 快照兜底。
    // mac 的顺序是缓存→bundle 快照，这里一致。
    const QString cachePath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/deepDolphin/models-dev.json");
    QFile cache(cachePath);
    if (cache.open(QIODevice::ReadOnly)) {
        ModelsDevCatalog cat = parse(cache.readAll());
        if (!cat.providers.empty())
            return cat;
    }
    QFile snapshot(QStringLiteral(":/resources/models-dev.json"));
    if (snapshot.open(QIODevice::ReadOnly))
        return parse(snapshot.readAll());
    return ModelsDevCatalog {};
}

void ModelsDevCatalog::refreshAsync()
{
    // 启动后台静默刷新（15s 超时）；**成功才置** models-dev.refreshed——
    // 先置位会让断网启动一次就终身不重试。失败静默（快照兜底，fail-open）。
    QCoreApplication *app = QCoreApplication::instance();
    if (!app)
        return;
    auto *nam = new QNetworkAccessManager(app);
    const QUrl url(QStringLiteral("https://models.dev/api.json"));
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = nam->get(req);
    QTimer::singleShot(15000, reply, &QNetworkReply::abort);
    QObject::connect(reply, &QNetworkReply::finished, app, [reply, nam] {
        reply->deleteLater();
        nam->deleteLater();
        if (reply->error() != QNetworkReply::NoError)
            return; // 失败静默
        const QByteArray data = reply->readAll();
        if (ModelsDevCatalog::parse(data).providers.empty())
            return; // 解析失败不当成功
        const QString cachePath =
            QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
            + QStringLiteral("/deepDolphin/models-dev.json");
        QDir().mkpath(QFileInfo(cachePath).absolutePath());
        QFile cache(cachePath);
        if (cache.open(QIODevice::WriteOnly | QIODevice::Truncate))
            cache.write(data);
        Settings::instance().setModelsDevRefreshed(true);
    });
}
