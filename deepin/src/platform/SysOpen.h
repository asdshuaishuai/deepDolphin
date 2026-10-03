// SysOpen.h — 系统打开动作（mac SysOpen.swift 对位）。
//
// · revealInFileManager：文件管理器定位目录（dde-file-manager）
// · openTerminal：deepin-terminal -w <path> → x-terminal-emulator 顺序兜底
// · openUrl：QDesktopServices
#pragma once
#include <QString>
#include <QUrl>

namespace SysOpen {

void revealInFileManager(const QString &path);
void openTerminal(const QString &path);
void openUrl(const QUrl &url);

} // namespace SysOpen
