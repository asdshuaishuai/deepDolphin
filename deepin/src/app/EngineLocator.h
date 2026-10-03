// EngineLocator.h — 引擎二进制发现链（CONTRACT §1.1，SPEC §0）。
//
// 顺序（deepDolphin/linux/src/engine.cj:274-303 对位 + 任务书常见路径）：
//   1. 环境变量 DEEPGIT_BIN —— 设置且非空时**必须**可用，否则报错而不是静默跳过；
//   2. 仓内开发构建 <工作区根>/moonGit/target/release/bin/main（仅开发场景）；
//   3. ~/.local/bin/moongit → ~/.local/bin/deepgit（装到用户目录的 install.sh 默认位）
//   4. /usr/local/bin、/usr/bin 的 moongit → deepgit（常见路径）
//   5. PATH 上的 moongit → deepgit（旧名兜底不能省：装在用户机器上的旧版仍是 deepgit）
// 全落空 → 给出可操作提示（绝不静默降级）。
//
// 探活 = 跑 `<bin> version`（8s 超时，exit 0 即可用）——仓颉 FileInfo 无权限位可查。
#pragma once
#include <QString>
#include <QStringList>
#include <functional>

struct EngineLocator {
    struct Result {
        QString bin;            // 找到的引擎路径；found=false 时空
        QStringList problems;   // 逐条失败原因（DEEPGIT_BIN 不可用等）
        bool found = false;
        bool pending = false;   // 发现链仍在跑（locateAsync 未收尾）——UI 走忙态而非"未找到"
    };

    static Result locate();

    // 异步发现链（M0-2）：探活在 worker 线程跑，`cb` 在 GUI 线程（qApp 事件循环）执行。
    // 为什么：候选最多 ~10 个，每个最坏 ≈11s（waitForStarted 3s + version 8s）+ kill 2s，
    // 同步 locate() 放在 show() 之前 = 白屏数十秒、点「重新检测引擎」= UI 冻结。
    // 同步 locate() 保留给无头路径（--selfcheck / --agent-selftest / --snapshot 不建 GUI）。
    static void locateAsync(const std::function<void(const Result &)> &cb);

    // 对候选路径跑 `version`（8s 超时，exit 0 即可用）
    static bool probe(const QString &bin);

    // 引擎缺失的安装引导文案（CONTRACT §1.1 原文口径）
    static QString installHint();
};
