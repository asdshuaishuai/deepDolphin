// EngineTimeouts.h — 引擎命令的超时预算（纯常量，无行为）。
//
// 【为什么住在 logic/】
// 超时预算原来写在 `app/EngineCli.h` 里，但 agent 的工具表（`logic/AgentToolPlan`）
// 也要用同一批数字 —— 同一件事两处字面量必然漂移（改了引擎调用忘了改工具表，
// 症状是「大仓整图构建在 agent 里被砍成 120 秒」这类难查的问题）。
// logic/ 不依赖 app/，所以常量下沉到这一层，app/ 侧 include 它。
// **数字本身一个都没改**（只是搬家）—— 语义归属没变，调用点零改动。
#pragma once

namespace EngineTimeouts {
constexpr int Version = 8'000;        // 探活
constexpr int Status = 30'000;        // status --json（全群）
constexpr int StatusProject = 60'000; // status <name> --json
constexpr int Dashboard = 180'000;
constexpr int Milestones = 60'000;    // milestone list/add/done/drop/reopen/remove
constexpr int Docs = 60'000;
constexpr int Verify = 60'000;      // verify <name>（只读：文档完整性校验）
constexpr int Graph = 300'000;      // graph arch <name> --format scene（只读：架构图场景）
constexpr int Journal = 30'000;
constexpr int Update = 300'000;       // update <name>
constexpr int Deep = 600'000;         // deep <name>
constexpr int UpdateAll = 900'000;    // update（全项目）
constexpr int DeepAll = 1'800'000;    // deep（全项目）
constexpr int Git = 120'000;
constexpr int Add = 30'000;
constexpr int Scan = 300'000;
constexpr int Tools = 30'000;
constexpr int Hook = 30'000;    // hook status/install/uninstall（装/卸钩子，秒级）
constexpr int Context = 60'000;
} // namespace EngineTimeouts
