#include "ContextEnvelope.h"
#include <QJsonDocument>
#include <QJsonObject>

std::optional<ContextEnvelope> ContextEnvelope::decode(const QByteArray &raw, Note *note)
{
    auto setNote = [note](Note n) {
        if (note)
            *note = n;
    };

    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
    if (raw.isEmpty() || !doc.isObject() || err.error != QJsonParseError::NoError) {
        setNote(Note::notJson);
        return std::nullopt;
    }
    const QJsonObject o = doc.object();
    if (!o.contains(QLatin1String("scope")) || !o.contains(QLatin1String("budget"))
        || !o.contains(QLatin1String("context"))) {
        setNote(Note::missingKeys);
        return std::nullopt;
    }
    ContextEnvelope e;
    e.scope = o.value(QLatin1String("scope")).toString();
    e.budget = o.value(QLatin1String("budget")).toInt();
    e.context = o.value(QLatin1String("context")).toString();
    if (e.context.isEmpty()) {
        setNote(Note::emptyContext);
        return std::nullopt;
    }
    setNote(Note::ok);
    return e;
}
