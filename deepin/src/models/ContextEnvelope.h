// ContextEnvelope.h — `context [项目] [--budget N] --json` 载荷（CONTRACT §2.6）。
// {scope: "group"|"project", budget, context: "<markdown>"}
//
// decode 对「没解出来」的三种失败（非 JSON / 缺键 / context 空串）分别产出说明文案
// ——「没解出来」≠「没有」，agent 层要把说明文案与正文一起给模型（SPEC §4.4）。
#pragma once
#include <QByteArray>
#include <QString>

struct ContextEnvelope {
    // 解码结论。ok 之外的每种都要配一句用户/模型可读的说明（noteText）。
    enum class Note {
        ok,
        notJson,     // stdout 不是合法 JSON
        missingKeys, // 缺 scope/budget/context 任一键
        emptyContext, // context 键在但为空串
    };

    QString scope;   // "group"|"project"
    int budget = 0;
    QString context; // markdown 上下文包

    // 解码；note 恒被赋值（可空指针）。失败时返回 nullopt + note 说明原因。
    static std::optional<ContextEnvelope> decode(const QByteArray &raw, Note *note);

    static QString noteText(Note n)
    {
        switch (n) {
        case Note::ok:
            return QString();
        case Note::notJson:
            return QStringLiteral("引擎输出不是合法 JSON，上下文包没有解出来。");
        case Note::missingKeys:
            return QStringLiteral("引擎输出缺少 scope/budget/context 之一，上下文包没有解出来。");
        case Note::emptyContext:
            return QStringLiteral("引擎返回了空的上下文包（context 为空串）——这表示没取到内容，不是没有项目。");
        }
        return QString();
    }
};
