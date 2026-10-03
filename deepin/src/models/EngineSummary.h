// EngineSummary.h — `status --json` envelope 的 summary（CONTRACT §2.1，12 键恒发）。
//
// 【口径】projectCount 只数采集成功的；projectCount + failedProjects == listedProjects
// 是恒等式（scripts/contract-check.sh 对账用）。缺 failedProjects/listedProjects
// ⇒ 契约过旧判据（CONTRACT §4.4）：fromJson 返回 nullopt，调用方按「引擎过旧」处理，
// 模型层兜底显示 `?` 而不是 0。
#pragma once
#include <QJsonObject>
#include <optional>

struct EngineSummary {
    int projectCount = 0;             // 只数采集成功的
    int listedProjects = 0;           // 注册表条目总数（含失败项）
    int failedProjects = 0;           // 采集失败（带 error 键）条数
    int degradedStores = 0;           // storeHealth != "ok" 的项目数
    int activeProjects = 0;
    int staleProjects = 0;
    int dirtyProjects = 0;
    int branchCount = 0;              // 追踪到基线的分支总数（非仓库总数）
    int repoBranchTotal = 0;          // 仓库真实分支总数（-1 的项目不计入）
    int branchTruncatedProjects = 0;
    int branchUnknownProjects = 0;
    QString generatedAt;

    // 全键齐才解析成功；缺任一键 → nullopt（契约过旧）
    static std::optional<EngineSummary> fromJson(const QJsonObject &o)
    {
        static const char *kKeys[] = {
            "projectCount", "listedProjects", "failedProjects", "degradedStores",
            "activeProjects", "staleProjects", "dirtyProjects", "branchCount",
            "repoBranchTotal", "branchTruncatedProjects", "branchUnknownProjects",
            "generatedAt",
        };
        for (const char *k : kKeys) {
            if (!o.contains(QLatin1String(k)))
                return std::nullopt;
        }
        EngineSummary s;
        s.projectCount = o.value(QLatin1String("projectCount")).toInt();
        s.listedProjects = o.value(QLatin1String("listedProjects")).toInt();
        s.failedProjects = o.value(QLatin1String("failedProjects")).toInt();
        s.degradedStores = o.value(QLatin1String("degradedStores")).toInt();
        s.activeProjects = o.value(QLatin1String("activeProjects")).toInt();
        s.staleProjects = o.value(QLatin1String("staleProjects")).toInt();
        s.dirtyProjects = o.value(QLatin1String("dirtyProjects")).toInt();
        s.branchCount = o.value(QLatin1String("branchCount")).toInt();
        s.repoBranchTotal = o.value(QLatin1String("repoBranchTotal")).toInt();
        s.branchTruncatedProjects = o.value(QLatin1String("branchTruncatedProjects")).toInt();
        s.branchUnknownProjects = o.value(QLatin1String("branchUnknownProjects")).toInt();
        s.generatedAt = o.value(QLatin1String("generatedAt")).toString();
        return s;
    }
};
