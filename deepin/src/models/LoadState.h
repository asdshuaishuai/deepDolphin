// LoadState.h — 每个数据源一份自己的加载状态（SPEC §3.5）。
// 「读取失败」「读取中」「还没有内容」三句话必须长得不一样，且不共用 lastError。
#pragma once
#include <QString>

enum class LoadState {
    idle,     // 还没开始
    loading,  // 采集中
    loaded,   // 成功（内容可能为空：空 ≠ 失败）
    failed,   // 失败（message = 本数据源自己的失败原因）
};

struct LoadStateBox {
    LoadState state = LoadState::idle;
    QString message; // failed 时的原因；其余态为空
};

// 页面渲染相位。hasContent = 该数据源有没有可渲染内容（loaded 但空 → empty）。
enum class LoadPhase {
    loading,
    empty,
    failed,
    content,
};

inline LoadPhase loadPhase(const LoadStateBox &box, bool hasContent)
{
    switch (box.state) {
    case LoadState::idle:
    case LoadState::loading:
        return LoadPhase::loading;
    case LoadState::failed:
        return LoadPhase::failed;
    case LoadState::loaded:
        return hasContent ? LoadPhase::content : LoadPhase::empty;
    }
    return LoadPhase::loading;
}
