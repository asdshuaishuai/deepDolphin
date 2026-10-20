// DocsDialogProbe.h — 固定文档页四语言的**无头行为探针**（批 AA）。
//
// 【为什么单独成文件】文档窗（`DocsDialog.cpp`）里**一个字符串字面量都不许有**
//   —— 用户可见文案全在判定层（`logic/DocPages`），四语言共用一份。
//   探针的「字段名」（title / close / …）是**机器格式**，不是用户可见文案
//   ⇒ 放这里，不去破那条纪律。
//
// 【它补的是什么】接线门是**源码扫描**：它能证明「代码里写了
//   `setButtonText` / `DocPages::content(k, m_language)`」，但**证明不了**
//   「用户点了语言之后，界面真的换了」—— 扫描看得见调用，看不见结果。
//   本探针**真跑**一遍切换，报出文档窗的**实际呈现**。
#pragma once
#include <QString>

class DocsDialog;

/// 把文档窗在四种语言下的**实际呈现**打成 `key=value` 行（每行一个字段）。
///
/// ⚠ 字段顺序固定：lang / title / close / segments / body / hint。
///   `segments` 的四档用 `|` 分隔；`body` 的换行折成 `|`。
///
/// ⚠ **会改文档窗当前语言**（走真实的 `currentIndexChanged` 信号路径）——
///   调用方负责隔离设置（`QStandardPaths::setTestModeEnabled(true)`）。
QString docsLangProbeReport(DocsDialog *dlg);
