// PathInput.h — 用户路径在发给引擎前的判定（mac PathInput.swift 对位，纯函数层）。
//
// 【红线】客户端只负责两件事：**去掉首尾空白**、**拒绝相对路径**；
// `~/x` 与尾斜杠**原样交引擎**（引擎自己展开/消解，客户端不造第二套规则）。
// 扫描根必须是 directory（file/missing 三态分开——「不存在」与「是个文件」不许压成一句）。
#pragma once
#include <QString>
#include <QStringList>

namespace PathInput {

enum class PathKind { missing, file, directory };

struct Verdict {
    QString path;      // 可用时非空
    QString problem;   // 不可用原因；可用时空串。必须说清楚，不能只说「无效路径」
    bool acceptable = false;
};

// 整理文本框输入。纯函数：不碰文件系统。
Verdict prepare(const QString &raw);

// 路径在磁盘上是什么（调用方注入 classify 便于测试）。
PathKind classify(const QString &path);

// 扫描模式：要求路径是一个已存在的文件夹。
Verdict validateScanRoot(const QString &raw);

// 从拖放候选里挑第一个文件夹，并把「为什么不是别的」说清楚。
Verdict pickDirectory(const QStringList &candidates);

} // namespace PathInput
