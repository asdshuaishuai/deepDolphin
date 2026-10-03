// SelfCheck.h — `--selfcheck`：模型层内置 fixtures 自检（无 GUI、无引擎依赖）。
//
// PLAN §8 T9 / scripts/smoke.sh 的冒烟判据：`./build/deepDolphin --selfcheck` 全绿。
// fixtures 按 CONTRACT §2/§3 键表逐键生成；引擎缺席时它就是唯一的契约判据
//（真实引擎对账由 scripts/contract-check.sh 负责，引擎缺席则 SKIP 不算过）。
#pragma once
#include <QStringList>

namespace SelfCheck {

// 运行全部用例；返回失败条目数（0 = 全绿），并把逐条 PASS/FAIL 追加到 log。
int run(QStringList &log);

} // namespace SelfCheck
