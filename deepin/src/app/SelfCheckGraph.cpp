// SelfCheckGraph.cpp — `--selfcheck` 分片：**图谱/架构图 + 符号索引热力图 + 补丁体检**。
//
// ⚠ 为什么拆出来（批 AK · M4a）：`SelfCheck.cpp` 原本是**一个 3800 多行的函数**
//   ⇒ 按主题拆成多分片；「记一条判据」的实现仍只有一份（`SelfCheckInternal.h`）。
// ⚠ 拆分的验收：**判据条数不许变**（393 条）—— ci.sh 的 SC_MIN 盯着。
#include "SelfCheckInternal.h"
#include "../logic/AgentToolPlan.h"
#include "EngineCli.h"
#include "../logic/ArchReceipt.h"
#include "../logic/CodeGraphBuild.h"
#include "../logic/EngineConfig.h"
#include "../logic/IconNames.h"
#include "../logic/IndexStatus.h"
#include "../ui/DesignTokens.h"
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include "../logic/ArchViewport.h"
#include "../logic/CanvasFont.h"
#include "../logic/GraphInsight.h"
#include "../logic/GraphToken.h"
#include "../logic/HeatLayout.h"
#include "../logic/PatchCheck.h"
#include "../logic/SceneRender.h"
#include "../logic/SemColors.h"
#include "../platform/Canvas2D.h"
#include <QColor>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMargins>
#include <QPainter>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>

#include "SelfCheckInternal.h"
#include "../logic/ArchViewport.h"
#include "../logic/CanvasFont.h"
#include "../logic/GraphInsight.h"
#include "../logic/GraphToken.h"
#include "../logic/HeatLayout.h"
#include "../logic/PatchCheck.h"
#include "../logic/SceneRender.h"
#include "../logic/SemColors.h"
#include "../platform/Canvas2D.h"
#include <QColor>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMargins>
#include <QPainter>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>

using SelfCheckInternal::check;
using SelfCheckInternal::J;
using SelfCheckInternal::JO;

namespace SelfCheckInternal {

void checkGraph(QStringList &log)
{
    // ── 15. 图谱/架构图：场景契约 + token 解析 + 渲染指令 + Canvas2D 像素（章程 §3.5）──
    {
        const QString kSceneJson = QStringLiteral(R"JSON({
            "v":1,"gen":"moongit-graph",
            "meta":{"title":"架构图","truncated":false,
                    "warnings":{"violations":0,"cycleEdges":0,"violationPairs":[],"cycleModules":[]},
                    "chips":[{"layer":0,"count":1,"label":"基础层 1"}]},
            "themes":{
              "dark":{"text":"#e8eef8","muted":"#94a3b8","bg0":"#0b1220","border":"#1e293b",
                      "cols":["#38bdf8","#a78bfa"],"fills":["rgba(10,20,30,0.5)"],"langs":{"swift":"#f05138"}},
              "light":{"text":"#0f172a","muted":"#64748b","bg0":"#f8fafc","border":"#e2e8f0",
                      "cols":["#38bdf8"],"fills":[],"langs":{}}},
            "views":{
              "module:b":{"label":"B","nodeTheme":{"b":"cols.0"},"shapes":[],"particles":[],"hits":[],"edgesDropped":0,
                           "bounds":{"x0":-4,"y0":-34,"x1":324,"y1":162}},
              "arch":{"label":"架构","nodeTheme":{"a":"cols.1"},
                      "shapes":[
                        {"t":"frame","x":10,"y":20,"w":300,"h":120,"color":"cols.0","label":"L4 其他"},
                        {"t":"rrect","x":30,"y":40,"w":120,"h":60,"r":11,"fill":"panel","stroke":"node:a","sw":1.2},
                        {"t":"rect","x":34,"y":49,"w":3.2,"h":42,"fill":"node:a"},
                        {"t":"text","x":42,"y":62,"text":"cli","size":13,"weight":600,"color":"text","align":"left"},
                        {"t":"edge","p":[10,20,30,30,40,40,50,50],"c0":"node:a","c1":"node:b","sw":3.5,"alpha":0.9,"arrow":9,"delay":0},
                        {"t":"edge","p":[10,20,30,30,40,40,50,50],"c0":"node:a","c1":"node:b","delay":999999},
                        {"t":"weird","x":1}
                      ],
                      "particles":[{"p":[0,0,1,1,2,2,3,3],"n":3,"sp":0.001,"color":"accent"}],
                      "hits":[{"id":"a","x":30,"y":40,"w":120,"h":60,"drill":"module:a"}],
                      "edgesDropped":3,
                      "bounds":{"x0":-24,"y0":-54,"x1":512,"y1":228}}},
            "panels":{"arch:a":{"title":"a","sub":"s","stats":"t"}}
        })JSON");
        const auto scene = GraphScene::fromJson(JO(kSceneJson));
        check(log, "scene 契约：v=1 解出；arch 恒排第一（引擎导出顺序）",
            scene.has_value() && scene->views.size() == 2 && scene->views.at(0).id == QLatin1String("arch")
                && scene->views.at(1).id == QLatin1String("module:b"));

        // 契约版本不认识 → 明说不兼容，不静默兼容。
        QJsonObject badV = JO(kSceneJson);
        badV.insert(QStringLiteral("v"), 2);
        check(log, "scene 契约：v≠1 → 解不出（不静默兼容）",
            !GraphScene::fromJson(badV).has_value());

        // 必发键缺 → 契约过旧。
        QJsonObject noViews = JO(kSceneJson);
        noViews.remove(QStringLiteral("views"));
        check(log, "scene 契约：缺 views → 解不出（不许回落成空图）",
            !GraphScene::fromJson(noViews).has_value());

        // 恒发字段：edgesDropped=3（不是「没有丢弃」）；warnings 恒发；chips[].count 是数字。
        check(log, "scene 恒发字段：edgesDropped / meta.warnings / chips[].count 都读得出",
            scene.has_value() && scene->views.at(0).edgesDropped == 3
                && scene->warnings.violations == 0 && scene->warnings.cycleEdges == 0
                && scene->chips.size() == 1 && scene->chips.at(0).count == 1
                && scene->chips.at(0).label == QStringLiteral("基础层 1"));

        // 恒发字段**在不在**：值是 0/空时，「确实没有」与「契约没发」不可区分
        // → 必须另有标志把两者分开（缺字段不回落成 0 的同一条纪律）。
        check(log, "scene 恒发字段：present 标志区分「确实 0」与「契约没发」",
            scene.has_value() && scene->views.at(0).edgesDroppedPresent
                && scene->warningsPresent && scene->chipsPresent
                && scene->views.at(0).boundsPresent && scene->viewsMissingBounds == 0
                && scene->views.at(0).bx0 == -24 && scene->views.at(0).by1 == 228);

        // 缺键的场合：值全回落成 0/空，但 present 标志必须说「没有」
        {
            QJsonObject noBounds = JO(kSceneJson);
            QJsonObject views = noBounds.value(QStringLiteral("views")).toObject();
            QJsonObject arch = views.value(QStringLiteral("arch")).toObject();
            arch.remove(QStringLiteral("bounds"));
            views.insert(QStringLiteral("arch"), arch);
            noBounds.insert(QStringLiteral("views"), views);
            const auto s2 = GraphScene::fromJson(noBounds);
            check(log, "scene 缺 bounds → 不回落成 0（标志说没有，计入待披露）",
                s2.has_value() && !s2->views.at(0).boundsPresent
                    && s2->viewsMissingBounds == 1);

            QJsonObject noDropped = JO(kSceneJson);
            QJsonObject v2 = noDropped.value(QStringLiteral("views")).toObject();
            QJsonObject a2 = v2.value(QStringLiteral("arch")).toObject();
            a2.remove(QStringLiteral("edgesDropped"));
            v2.insert(QStringLiteral("arch"), a2);
            noDropped.insert(QStringLiteral("views"), v2);
            const auto s3 = GraphScene::fromJson(noDropped);
            check(log, "scene 缺 edgesDropped → 不当成「没丢边」（标志说没有）",
                s3.has_value() && !s3->views.at(0).edgesDroppedPresent
                    && s3->views.at(0).edgesDropped == 0);

            QJsonObject noMeta = JO(kSceneJson);
            QJsonObject meta = noMeta.value(QStringLiteral("meta")).toObject();
            meta.remove(QStringLiteral("warnings"));
            meta.remove(QStringLiteral("chips"));
            noMeta.insert(QStringLiteral("meta"), meta);
            const auto s4 = GraphScene::fromJson(noMeta);
            check(log, "scene 缺 warnings/chips → 不当成「没有违规/没有分层」",
                s4.has_value() && !s4->warningsPresent && !s4->chipsPresent
                    && s4->warnings.violations == 0 && s4->chips.isEmpty());
        }

        if (!scene.has_value()) {
            log << QStringLiteral("FAIL  scene 后续判据（场景没解出，后续用例无法跑）");
            ++g_fail;
        } else {
            const GraphView &v = scene->views.at(0);
            const GraphThemeTokens &th = scene->dark;

            // ── token 四形态 + 二跳 ──
            check(log, "token 直取：text/muted/bg0 走 themes 直取",
                GraphToken::resolve(th, QStringLiteral("text"), &v).value
                        == QStringLiteral("#e8eef8")
                    && GraphToken::resolve(th, QStringLiteral("muted"), &v).value
                        == QStringLiteral("#94a3b8"));
            check(log, "token 下标：cols.N / fills.N 走数组",
                GraphToken::resolve(th, QStringLiteral("cols.1"), &v).value
                        == QStringLiteral("#a78bfa")
                    && GraphToken::resolve(th, QStringLiteral("fills.0"), &v).value
                        == QStringLiteral("rgba(10,20,30,0.5)"));
            check(log, "token 字典：langs.<lang> 走 langs",
                GraphToken::resolve(th, QStringLiteral("langs.swift"), &v).value
                    == QStringLiteral("#f05138"));
            // 二跳：node:a → view.nodeTheme[a] = cols.1 → #a78bfa
            check(log, "token 二跳：node:<id> → 视图 nodeTheme → 基础 token",
                GraphToken::resolve(th, QStringLiteral("node:a"), &v).value
                    == QStringLiteral("#a78bfa"));
            // 查不到节点 → 回落 text（不是洋红：图上没有这个节点 ≠ 引擎违约）
            check(log, "token 二跳落空 → 回落 text（不是洋红）",
                GraphToken::resolve(th, QStringLiteral("node:zzz"), &v).value
                        == QStringLiteral("#e8eef8")
                    && !GraphToken::resolve(th, QStringLiteral("node:zzz"), &v).violation);
            // 未知 token → 洋红 + violation 标记（引擎违约的显式信号）
            const GraphToken::Resolved bad = GraphToken::resolve(th, QStringLiteral("nope"), &v);
            check(log, "token 未知 → 洋红兜底 + violation 标记（不静默当黑）",
                bad.violation && GraphToken::toColor(bad.value) == QColor(255, 0, 204));
            // 下标越界 → 也是未知 token → 洋红
            check(log, "token 下标越界 → 洋红兜底（不回落成第 0 项）",
                GraphToken::resolve(th, QStringLiteral("cols.99"), &v).violation);
            // 语言色查不到 → 回落 text
            check(log, "token 语言色查不到 → 回落 text（不是洋红）",
                !GraphToken::resolve(th, QStringLiteral("langs.rust"), &v).violation);

            // 颜色解析：#hex / #hex8 / #rgb / rgba()
            check(log, "颜色解析：#hex / #hexAA / #RGB / rgba() 四形态",
                GraphToken::toColor(QStringLiteral("#ff0000")).name() == QStringLiteral("#ff0000")
                    && GraphToken::toColor(QStringLiteral("#00ff0080")).alpha() == 128
                    && GraphToken::toColor(QStringLiteral("#abc")).name() == QStringLiteral("#aabbcc")
                    && GraphToken::toColor(QStringLiteral("rgba(10,20,30,0.5)")).alpha() > 100);

            // ── 渲染指令序列（记录式接收端）──
            RecordingSink sink;
            const SceneRender::Stats st = SceneRender::render(
                *scene, v, true, ArchViewport::Viewport { 1.0, 0.0, 0.0 }, 800, 600, 1000.0, sink);
            check(log, "渲染：背景先铺满画布（fillRect 用 bg0）",
                sink.ops.size() >= 2 && sink.ops.at(0).contains(QStringLiteral("#0b1220"))
                    && sink.ops.at(1) == QStringLiteral("fillRect(0,0,800,600)"));
            check(log, "渲染：frame → strokeRect + 层框标题",
                sink.ops.contains(QStringLiteral("strokeRect(10,20,300,120)"))
                    && sink.texts.contains(QStringLiteral("L4 其他")));
            check(log, "渲染：rrect → 圆角路径（arcTo×4）+ fill + stroke",
                sink.arcToCount >= 4);
            check(log, "渲染：text → fillText 且字体/对齐按契约",
                sink.texts.contains(QStringLiteral("cli")) && sink.lastFont.contains(QStringLiteral("600"))
                    && sink.lastAlign == QStringLiteral("left"));
            check(log, "渲染：edge → 贝塞尔 + 渐变 + 虚线 + 箭头（渐变 1 个、虚线 2 次）",
                sink.bezierCount >= 1 && sink.gradientCount == 1 && sink.dashCount >= 2);
            check(log, "渲染：入场未到的边不画（delay 999999 → edgesPending=1）",
                st.edgesPending == 1 && st.edges == 1);
            check(log, "渲染：不认识的 shape 类型计数披露（unknown=1，不静默跳）",
                st.unknown == 1);
            check(log, "渲染：粒子按 n 画 3 个（相位循环，不随机）",
                st.particles == 3);
            check(log, "渲染：统计里 drawn 与 unknown 分开（画了什么 vs 不认得什么）",
                st.shapes == 7 && st.drawn == 5 && st.unknown == 1);

            // 同一时刻重画 → 指令序列逐条相同（引擎保证两次导出逐字节一致）
            RecordingSink sink2;
            SceneRender::render(*scene, v, true, ArchViewport::Viewport { 1.0, 0.0, 0.0 }, 800, 600,
                1000.0, sink2);
            check(log, "渲染：同一时刻重画 → 指令序列逐条相同（可复现）",
                sink.ops == sink2.ops);
        }

        // ── Canvas2D 像素级（QPainter 背书）──
        // 差分法：同形状「有阴影 vs 无阴影」比形状外的着色像素数 —— 比绝对值稳。
        auto countOutside = [](bool withShadow) {
            QImage img(60, 60, QImage::Format_ARGB32_Premultiplied);
            img.fill(Qt::transparent);
            {
                QPainter p(&img);
                Canvas2D c(&p);
                c.setFillStyle(CanvasPaint(QColor(0, 0, 255)));
                if (withShadow) {
                    c.setShadowColor(QColor(0, 0, 0));
                    c.setShadowBlur(8);
                }
                c.fillRect(25, 25, 10, 10);
            }
            int n = 0;
            for (int y = 0; y < 60; ++y) {
                for (int x = 0; x < 60; ++x) {
                    if (x >= 25 && x < 35 && y >= 25 && y < 35)
                        continue;
                    if (qAlpha(img.pixel(x, y)) > 0)
                        ++n;
                }
            }
            return n;
        };
        const int noShadow = countOutside(false);
        const int withShadow = countOutside(true);
        check(log, "Canvas2D 像素：fillRect 真的填上了（形状内为实色）",
            noShadow == 0); // 无阴影时形状外一个像素都不该着色
        check(log, "Canvas2D 阴影：shadowBlur>0 时形状外出现淡出像素（阴影真的产生了）",
            withShadow > 0 && withShadow > noShadow);

        // 圆角语义的差分判据：同一个 20×20 方块，圆角(r=8) 的**四角**实心像素
        // 远少于直角 —— 只数 arcTo 调用次数是抓不到「圆角画成了直角」的。
        auto cornerFilled = [](bool rounded) {
            QImage img(40, 40, QImage::Format_ARGB32_Premultiplied);
            img.fill(Qt::transparent);
            {
                QPainter p(&img);
                Canvas2D c(&p);
                c.setFillStyle(CanvasPaint(QColor(0, 0, 255)));
                c.beginPath();
                if (rounded) {
                    const double x = 10, y = 10, w = 20, h = 20, r = 8;
                    c.moveTo(x + r, y);
                    c.arcTo(x + w, y, x + w, y + h, r);
                    c.arcTo(x + w, y + h, x, y + h, r);
                    c.arcTo(x, y + h, x, y, r);
                    c.arcTo(x, y, x + w, y, r);
                    c.closePath();
                } else {
                    c.rect(10, 10, 20, 20);
                }
                c.fill();
            }
            int n = 0;
            for (int cy : { 10, 26 }) {
                for (int cx : { 10, 26 }) {
                    for (int y = cy; y < cy + 4; ++y) {
                        for (int x = cx; x < cx + 4; ++x) {
                            if (qAlpha(img.pixel(x, y)) > 128)
                                ++n;
                        }
                    }
                }
            }
            return n;
        };
        const int sharpCorners = cornerFilled(false);
        const int roundCorners = cornerFilled(true);
        check(log, "Canvas2D 圆角：arcTo 真切出圆角（直角方块的四角实心像素远多于圆角）",
            sharpCorners >= 60 && roundCorners < 20 && roundCorners < sharpCorners);

        // ── 批 D2：架构图页的视口与命中（纯函数层，无头可判）──
        // 视口是最容易悄悄错的一环：缩放没跟上下标就「点不中」，
        // 命中区顺序错了就「选错节点」——两者都不该等到看图才发现。
        GraphView vv;
        vv.id = QStringLiteral("arch");
        vv.bx0 = 0; vv.by0 = 0; vv.bx1 = 200; vv.by1 = 100;
        const ArchViewport::Viewport vp = ArchViewport::fit(vv, 800, 600, 40);
        // scale = min((800-2*40)/200, (600-2*40)/100) = min(3.6, 5.2) = 3.6
        check(log, "视口 fit：缩放 = min((宽-2pad)/包围盒宽, (高-2pad)/包围盒高)",
            qAbs(vp.scale - 3.6) < 1e-6);
        check(log, "视口 fit：内容居中（包围盒中心 → 画布中心）",
            qAbs(ArchViewport::toScreen(vp, 100, 50).x() - 400) < 1e-6
                && qAbs(ArchViewport::toScreen(vp, 100, 50).y() - 300) < 1e-6);

        GraphView tinyView;
        tinyView.bx0 = 0; tinyView.by0 = 0; tinyView.bx1 = 10; tinyView.by1 = 10;
        GraphView hugeView;
        hugeView.bx0 = 0; hugeView.by0 = 0; hugeView.bx1 = 100000; hugeView.by1 = 100000;
        GraphView emptyView;
        check(log, "视口 fit：缩放夹在 [0.05, 4]（放大不越界）",
            qAbs(ArchViewport::fit(tinyView, 800, 600, 40).scale - 4.0) < 1e-6);
        check(log, "视口 fit：缩放夹在 [0.05, 4]（缩小不越界）",
            qAbs(ArchViewport::fit(hugeView, 800, 600, 40).scale - 0.05) < 1e-6);
        check(log, "视口 fit：包围盒非法（空视图）→ 恒等视口（不猜比例）",
            qAbs(ArchViewport::fit(emptyView, 800, 600, 40).scale - 1.0) < 1e-6);

        // 屏幕→世界→屏幕 往返一致（换算式自洽 = 点得中）
        const QPointF back = ArchViewport::toWorld(vp, 123.0, 456.0);
        const QPointF again = ArchViewport::toScreen(vp, back.x(), back.y());
        check(log, "视口换算：屏幕→世界→屏幕 往返一致",
            qAbs(again.x() - 123.0) < 1e-6 && qAbs(again.y() - 456.0) < 1e-6);

        // 命中测试：命中区内命中、 区外不命中（不随便挑一个）
        GraphHit hit;
        hit.id = QStringLiteral("mod:src");
        hit.x = 0; hit.y = 0; hit.w = 100; hit.h = 50;
        vv.hits.append(hit);
        const ArchViewport::Viewport identity { 1.0, 0.0, 0.0 };
        check(log, "命中：点在命中区内 → 命中该节点",
            ArchViewport::hitAt(vv, identity, 50, 25).value_or(QString())
                == QStringLiteral("mod:src"));
        check(log, "命中：点在命中区外 → 没命中（不随便挑一个）",
            !ArchViewport::hitAt(vv, identity, 500, 500).has_value());
        // 缩放后同一世界点仍命中 —— 命中与渲染必须共用同一个视口换算
        const QPointF screenCenter = ArchViewport::toScreen(vp, 50, 25);
        check(log, "命中：视口缩放后同一世界点仍命中（命中与渲染同源）",
            ArchViewport::hitAt(vv, vp, screenCenter.x(), screenCenter.y()).value_or(QString())
                == QStringLiteral("mod:src"));

        // ── 引擎回执提取（回执型命令的 stdout 是人话，不是 JSON）──
        check(log, "回执：取末个非空行（引擎回执最后一行是结论）",
            ArchReceipt::receipt(QStringLiteral("架构已生成：首版（第 0 版）\n  探针：库中无旧记录\n下一步：moongit arch query\n"))
                == QStringLiteral("下一步：moongit arch query"));
        check(log, "回执：全空 → 空串（不把空白行当回执）",
            ArchReceipt::receipt(QStringLiteral("  \n\n ")).isEmpty());
        check(log, "回执：抽出 HTML 绝对路径",
            ArchReceipt::htmlPath(QStringLiteral("已重绘：/tmp/x/store/p_1/arch.html · 第 1 版"))
                == QStringLiteral("/tmp/x/store/p_1/arch.html"));
        check(log, "回执：路径与文案用全角冒号粘连时也抽得出（引擎真实回执形态）",
            ArchReceipt::htmlPath(QStringLiteral("已重绘：/tmp/x/store/p_1/render/arch.html · 第 1 版"))
                == QStringLiteral("/tmp/x/store/p_1/render/arch.html"));
        // ⚠ 这条夹具是**实跑**出来的（2026-10-20 真跑 `moongit render arch`，
        //   原文照抄）：引擎真实回执里路径粘在**全角冒号**后、后面跟**中点**，
        //   两个分隔符**都在**，且尾部还跟着一句统计 ⇒ 两个分隔符都得认。
        //   批 AR 照这条实跑形态发现 mac 侧的同名实现抽不出路径（死按钮）。
        check(log, "回执：引擎实跑原文的形态也抽得出（已写入：<路径> · 共 N 个文件）",
            ArchReceipt::htmlPath(QStringLiteral("已写入：/home/superShuai/.deepgit/store/"
                                                 "p_f80de38f6095/render/arch.html · 共 0 个文件，"
                                                 "0 个函数（语法未通过则不计入）"))
                == QStringLiteral("/home/superShuai/.deepgit/store/p_f80de38f6095/render/arch.html"));
        check(log, "回执：相对路径不认（宁可不给「打开」入口，也不给坏按钮）",
            ArchReceipt::htmlPath(QStringLiteral("已重绘：render/arch.html")).isEmpty());

        // ── 两套输出契约（用错模式 = 成功被报成失败）──
        check(log, "输出契约：Text 模式收文本回执（非空即算成功）",
            EngineCli::stdoutSatisfies(EngineCli::OutputMode::Text, QStringLiteral("架构已生成：首版")));
        check(log, "输出契约：Text 模式空 stdout = 契约破坏（不回落成成功）",
            !EngineCli::stdoutSatisfies(EngineCli::OutputMode::Text, QStringLiteral("  \n ")));
        check(log, "输出契约：Json 模式不收文本（成功被误报成失败的根因）",
            !EngineCli::stdoutSatisfies(EngineCli::OutputMode::Json, QStringLiteral("架构已生成：首版"))
                && EngineCli::stdoutSatisfies(EngineCli::OutputMode::Json, QStringLiteral("{\"v\":1}")));
        check(log, "输出契约：Json 模式空 stdout = 契约破坏（不是合法空态）",
            !EngineCli::stdoutSatisfies(EngineCli::OutputMode::Json, QString()));
        // ── 回执通道：stdout 优先，stdout 空时取 stderr ──
        // ⚠ 引擎的 `report` 把「报告已生成：<路径>」写在 **stderr**
        //   （`arch gen` / `render arch` 才在 stdout —— 实测 2026-10-19）。
        //   只认 stdout 的话，report 会被判成「引擎没有回执（退出码 0）」：
        //   **明明成功却说失败**，报告其实已经落盘了。
        check(log, "输出契约：回执通道 stdout 优先（stdout 非空时不看 stderr）",
            EngineCli::receiptText(QStringLiteral("架构已生成：首版"), QStringLiteral("报告已生成：/x.md"))
                == QStringLiteral("架构已生成：首版"));
        check(log, "输出契约：stdout 空时回执取 stderr（引擎 report 把回执写 stderr）",
            EngineCli::receiptText(QString(), QStringLiteral("报告已生成：/x/report-1.md"))
                == QStringLiteral("报告已生成：/x/report-1.md"));
        check(log, "输出契约：两路都空 = 没有回执（不回落成成功）",
            EngineCli::receiptText(QStringLiteral("  \n "), QString()).isEmpty());

        // ── agent 工具表（纯函数，无头可判）──
        // 引擎 tools --json 声明 28 个工具；客户端必须**能执行全部 28 个**。
        // 漂移的症状很隐蔽：模型调了个客户端不会执行的工具，界面上只显示
        // 「未知工具：X」—— 很容易被当成模型乱调，真因却是两份清单不一致。
        {
            const QStringList names = AgentToolPlan::knownToolNames();
            check(log, "agent 工具表：清单恰好 28 个（与引擎 tools --json 声明集对位）",
                names.size() == 28);
            bool allPlanned = !names.isEmpty();
            for (const QString &tool : names) {
                const AgentToolPlan::Plan p = AgentToolPlan::planFor(tool, QJsonObject());
                if (!p.known || p.argv.isEmpty() || p.timeoutMs <= 0) {
                    allPlanned = false;
                    break;
                }
            }
            check(log, "agent 工具表：每个工具都有可执行的 argv 与超时预算（不是半张表）",
                allPlanned);
            check(log, "agent 工具表：未知工具明说（known=false，不静默成功）",
                !AgentToolPlan::planFor(QStringLiteral("没有这个工具"), QJsonObject()).known);

            // argv 形状：命令与引擎 usage 逐一对应
            const AgentToolPlan::Plan archGen
                = AgentToolPlan::planFor(QStringLiteral("arch_gen"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") } });
            check(log, "agent 工具表：arch_gen → arch gen <项目>",
                archGen.argv == (QStringList { QStringLiteral("arch"), QStringLiteral("gen"),
                    QStringLiteral("atlas") }));
            const AgentToolPlan::Plan cgSym
                = AgentToolPlan::planFor(QStringLiteral("codegraph_symbol"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("symbol"), QStringLiteral("main") } });
            check(log, "agent 工具表：codegraph_symbol → graph symbol <项目> <符号> --json",
                cgSym.argv == (QStringList { QStringLiteral("graph"), QStringLiteral("symbol"),
                    QStringLiteral("atlas"), QStringLiteral("main"), QStringLiteral("--json") }));

            // 开关型参数：引擎把 params 声明成**全 string 型必填**，模型多半发字符串。
            // 只认布尔会让 --force/--violations 永远不生效（形同虚设）。
            const AgentToolPlan::Plan forced
                = AgentToolPlan::planFor(QStringLiteral("arch_update"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("force"), QStringLiteral("true") } });
            const AgentToolPlan::Plan notForced
                = AgentToolPlan::planFor(QStringLiteral("arch_update"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("force"), QStringLiteral("false") } });
            check(log, "agent 工具表：开关参数收字符串形态（模型发 \"true\" 也算开）",
                forced.argv.contains(QStringLiteral("--force"))
                    && !notForced.argv.contains(QStringLiteral("--force")));

            // 数值型参数：不是数就不给（缺省交给引擎），不把垃圾递给引擎让它报错
            const AgentToolPlan::Plan badDepth
                = AgentToolPlan::planFor(QStringLiteral("codegraph_tree"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("depth"), QStringLiteral("abc") } });
            const AgentToolPlan::Plan goodDepth
                = AgentToolPlan::planFor(QStringLiteral("codegraph_tree"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("depth"), QStringLiteral("3") } });
            check(log, "agent 工具表：数值参数只给真数（非数不递给引擎）",
                !badDepth.argv.contains(QStringLiteral("--depth"))
                    && goodDepth.argv.contains(QStringLiteral("--depth"))
                    && goodDepth.argv.contains(QStringLiteral("3")));

            // 白名单：越界明说，不转交（引擎的 op 契约只有 pull|push）
            const AgentToolPlan::Plan badOp
                = AgentToolPlan::planFor(QStringLiteral("git_pull_push"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("op"), QStringLiteral("fetch") } });
            check(log, "agent 工具表：op 越界被拒（明说理由，不静默转交）",
                !badOp.reject.isEmpty() && badOp.argv.isEmpty());

            // 需要落临时文件的工具：纯函数层只声明「落哪个 + argv 哪一格放路径」
            const AgentToolPlan::Plan merge
                = AgentToolPlan::planFor(QStringLiteral("codegraph_patch_merge"),
                    QJsonObject { { QStringLiteral("algorithm_json"), QStringLiteral("{}") },
                        { QStringLiteral("agent_json"), QStringLiteral("{}") } });
            check(log, "agent 工具表：吃路径的工具声明临时文件（落盘交给执行方）",
                merge.tempParams.size() == 2
                    && merge.argv.contains(QStringLiteral("{{tmp:algorithm_json}}"))
                    && merge.argv.contains(QStringLiteral("{{tmp:agent_json}}")));

            // format 决定 flag：llm → --llm；text → 纯文本；缺省 → --json
            const AgentToolPlan::Plan confLlm
                = AgentToolPlan::planFor(QStringLiteral("codegraph_confidence"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("format"), QStringLiteral("llm") } });
            const AgentToolPlan::Plan confText
                = AgentToolPlan::planFor(QStringLiteral("codegraph_confidence"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") },
                        { QStringLiteral("format"), QStringLiteral("text") } });
            const AgentToolPlan::Plan confDefault
                = AgentToolPlan::planFor(QStringLiteral("codegraph_confidence"),
                    QJsonObject { { QStringLiteral("name"), QStringLiteral("atlas") } });
            check(log, "agent 工具表：format 决定 flag（llm/text/缺省各走各的）",
                confLlm.argv.contains(QStringLiteral("--llm"))
                    && !confText.argv.contains(QStringLiteral("--llm"))
                    && !confText.argv.contains(QStringLiteral("--json"))
                    && confDefault.argv.contains(QStringLiteral("--json")));
        }

        // ── 代码图谱数据层（三源 → 一棵树，纯函数）──
        // 合成规则里藏着三处最容易悄悄错的地方：符号 id 的构造式、疑点归属
        // （函数级那份已归属，置信度侧那份要去重）、汇总卷积。
        {
            const QJsonObject tree = QJsonDocument::fromJson(QByteArray(R"JSON({
              "root": "/tmp/atlas",
              "files": [
                {"path": "src/core/util.c", "lang": "c", "lines": 20,
                 "symbols": [{"kind": "func", "name": "worker", "line": 3},
                             {"kind": "func", "name": "helper", "line": 9}]},
                {"path": "src/main.c", "lang": "c", "lines": 5,
                 "symbols": [{"kind": "func", "name": "main", "line": 1}]}
              ],
              "referenceEdges": [["src/main.c", "src/core/util.c", 2]],
              "depth": 6, "truncated": false, "skipped": 0, "oversizeSkipped": 0,
              "unreadableDirs": [], "unreadableDirsTruncated": false
            })JSON")).object();
            const QJsonObject conf = QJsonDocument::fromJson(QByteArray(R"JSON({
              "root": "/tmp/atlas", "score": 76, "astUsed": false,
              "astNote": "语法树不可用：未安装 ast-grep",
              "dimensions": [{"id": "structure", "label": "结构级", "penalty": 12, "findings": 1, "score": 76}],
              "findings": [
                {"kind": "orphan", "file": "src/core/util.c", "line": 3, "symbol": "helper", "weight": 12, "evidence": "定义后无引用"},
                {"kind": "magic-number", "file": "src/main.c", "line": 1, "symbol": "main", "weight": 5, "evidence": "魔法数"}
              ]
            })JSON")).object();
            const QJsonObject fns = QJsonDocument::fromJson(QByteArray(R"JSON({
              "functions": [
                {"id": "f:src/core/util.c:3:worker", "file": "src/core/util.c", "name": "worker",
                 "kind": "func", "line": 3, "lang": "c", "weight": 12, "trunc": false,
                 "findings": [{"line": 3, "weight": 12, "kind": "orphan", "dim": "structure", "label": "孤儿符号", "evidence": "定义后无引用"}]},
                {"id": "f:src/main.c:1:main", "file": "src/main.c", "name": "main",
                 "kind": "func", "line": 1, "lang": "c", "weight": 0, "trunc": false, "findings": []}
              ],
              "functionEdges": [{"from": "f:src/main.c:1:main", "to": "f:src/core/util.c:3:worker", "w": 2, "tier": "resolved"}],
              "codeSnippets": {"f:src/core/util.c:3:worker": "void worker(void){}\nint x = 1;"}
            })JSON")).object();

            CodeGraphBuild::Source src;
            src.tree = tree;
            src.confidence = conf;
            src.functions = fns;
            const CodeGraphBuild::Result g = CodeGraphBuild::build(src, QStringLiteral("atlas"));

            check(log, "代码图谱：三源齐 → 合成成功（骨架：根+2 层目录+2 文件+3 符号 = 8 节点）",
                g.ok && g.graph.nodes.size() == 8 && g.graph.root >= 0);
            // 符号 id 构造式：tree 的 symbols 不带 id，客户端按引擎同形造
            check(log, "代码图谱：符号 id 按引擎同形构造（f:路径:行号:名字）",
                g.ok && g.graph.indexOf(QStringLiteral("f:src/core/util.c:3:worker")) >= 0
                    && CodeGraphBuild::symbolId(QStringLiteral("src/core/util.c"), 3,
                          QStringLiteral("worker"))
                        == QStringLiteral("f:src/core/util.c:3:worker"));
            // 疑点归属：函数级疑点挂符号；置信度侧同一条不再重复挂文件
            const int workerIdx = g.graph.indexOf(QStringLiteral("f:src/core/util.c:3:worker"));
            const int utilFileIdx = g.graph.indexOf(QStringLiteral("f:src/core/util.c"));
            const int mainFileIdx = g.graph.indexOf(QStringLiteral("f:src/main.c"));
            check(log, "代码图谱：函数级疑点挂到符号（不是文件）",
                g.ok && workerIdx >= 0 && g.graph.nodes.at(workerIdx).ownFindings.size() == 1);
            check(log, "代码图谱：已归属的疑点不重复挂文件（去重，疑点不被数两遍）",
                g.ok && utilFileIdx >= 0 && g.graph.nodes.at(utilFileIdx).ownFindings.isEmpty());
            check(log, "代码图谱：置信度侧的孤儿疑点挂到文件（没被任何符号领走的那些）",
                g.ok && mainFileIdx >= 0 && g.graph.nodes.at(mainFileIdx).ownFindings.size() == 1
                    && g.graph.nodes.at(mainFileIdx).ownFindings.first().kind
                        == QStringLiteral("magic-number"));
            // 汇总卷积：子树疑点数与最高权重
            check(log, "代码图谱：汇总卷积（子树疑点数 2 / 最高权重 12）",
                g.ok && g.graph.nodes.at(g.graph.root).rollN == 2
                    && g.graph.nodes.at(g.graph.root).rollW == 12
                    && g.graph.nodes.at(g.graph.root).fileCount == 2);
            // 排序：目录在前、文件按名、符号按声明行
            // 树形：root → src(目录) → { core(目录) → util.c(文件), main.c(文件) }
            const GraphNode *rootNode = g.ok ? g.graph.node(g.graph.root) : nullptr;
            bool orderOk = rootNode && rootNode->kids.size() == 1
                && g.graph.node(rootNode->kids.first())->kind == GraphNodeKind::dir;
            if (orderOk) {
                const GraphNode *srcDir = g.graph.node(rootNode->kids.first());
                orderOk = srcDir->kids.size() == 2
                    && g.graph.node(srcDir->kids.at(0))->kind == GraphNodeKind::dir
                    && g.graph.node(srcDir->kids.at(0))->name == QStringLiteral("core")
                    && g.graph.node(srcDir->kids.at(1))->kind == GraphNodeKind::file
                    && g.graph.node(srcDir->kids.at(1))->name == QStringLiteral("main.c");
                if (orderOk) {
                    const GraphNode *coreDir = g.graph.node(srcDir->kids.at(0));
                    orderOk = coreDir->kids.size() == 1
                        && g.graph.node(coreDir->kids.first())->name
                            == QStringLiteral("util.c");
                    if (orderOk) {
                        // 同一文件的符号按**声明行**排（不是按名字）
                        const GraphNode *utilFile = g.graph.node(coreDir->kids.first());
                        // ⚠ 夹具刻意让两种排序**分叉**：worker@3（名字在后）
                        //   排前、helper@9 排后 —— 若实现改成按名字排，这条会红。
                        orderOk = utilFile->kids.size() == 2
                            && g.graph.node(utilFile->kids.at(0))->name
                                == QStringLiteral("worker")
                            && g.graph.node(utilFile->kids.at(0))->declLine == 3
                            && g.graph.node(utilFile->kids.at(1))->name
                                == QStringLiteral("helper")
                            && g.graph.node(utilFile->kids.at(1))->declLine == 9;
                    }
                }
            }
            check(log, "代码图谱：排序（目录在前、文件按名、符号按声明行）", orderOk);
            // 符号级调用边 + 源码片段
            check(log, "代码图谱：符号级调用边与源码片段都读得出",
                g.ok && g.symEdges.size() == 1
                    && g.symEdges.first().from == QStringLiteral("f:src/main.c:1:main")
                    && g.symEdges.first().to == QStringLiteral("f:src/core/util.c:3:worker")
                    && g.snippets.contains(QStringLiteral("f:src/core/util.c:3:worker"))
                    && g.fileEdges.size() == 1);
            // 截断披露：0 与「没发」可区分
            check(log, "代码图谱：截断披露（缺键不得当作「没有」）",
                g.ok && g.truncatedPresent && g.skippedPresent
                    && g.oversizeSkippedPresent && g.depth == 6);
            // 置信度总分与降级说明
            check(log, "代码图谱：置信度总分与语法树降级说明都带出来",
                g.ok && g.score == 76 && !g.astNote.isEmpty() && !g.astUsed);
            // 缺源：说清是哪一种
            {
                CodeGraphBuild::Source s2;
                s2.confidence = conf;
                s2.functions = fns;
                const CodeGraphBuild::Result r2 = CodeGraphBuild::build(s2, QStringLiteral("atlas"));
                CodeGraphBuild::Source s3;
                s3.tree = tree;
                s3.functions = fns;
                const CodeGraphBuild::Result r3 = CodeGraphBuild::build(s3, QStringLiteral("atlas"));
                CodeGraphBuild::Source s4;
                s4.tree = tree;
                s4.confidence = conf;
                const CodeGraphBuild::Result r4 = CodeGraphBuild::build(s4, QStringLiteral("atlas"));
                check(log, "代码图谱：缺源明说是哪一种（不回落成空图）",
                    !r2.ok && r2.error.contains(QStringLiteral("图树"))
                        && !r3.ok && r3.error.contains(QStringLiteral("置信度"))
                        && !r4.ok && r4.error.contains(QStringLiteral("函数级")));
            }
            // 可见行：展开与搜索
            {
                QStringList expanded { QStringLiteral("root"), QStringLiteral("d:src") };
                const auto rows = CodeGraphBuild::visibleRows(g.graph, expanded, QString());
                check(log, "代码图谱：可见行随展开态算（根+目录 → 根+目录+2 文件）",
                    rows.size() == 4);
                const auto filtered
                    = CodeGraphBuild::visibleRows(g.graph, QStringList(), QStringLiteral("worker"));
                check(log, "代码图谱：搜索过滤只留命中的路径（含祖先）",
                    !filtered.isEmpty()
                        && filtered.last().node == workerIdx);
            }
        }
    }

    // ── 符号索引热力图（布局与走线，纯函数）──
    // 热力图是代码图谱左栏的另一种模式：文件层铺文件卡，点文件卡下钻到符号层。
    // 铺排与走线都在 logic/HeatLayout（零 QWidget 头），所以判据能无头跑。
    // 判据盯的是**画出来对不对**，不是「函数被调用了没有」：
    //   ① 分数公式与热色三档（契约色，逐字对齐 HTML 交付物）
    //   ② 身份色相：黄金角散布，且**与节点顺序无关**（换个顺序画得一样）
    //   ③ 作用域：文件层=全部文件；下钻层=该文件符号 + 跨作用域边界卡（≤9 + "+N"）
    //   ④ 铺排：不重叠、网格等距、序号连续、分带有序
    //   ⑤ 重心扫描**真的跑了**（关联卡的次序被重排）—— 这条最容易被悄悄摘掉
    //   ⑥ 走线：端点贴在卡上、边不丢、曲线过端点
    {
        // ---- 夹具：一棵两文件的树（a.c 两个符号、b.c 一个符号）----
        auto addNode = [](CodeGraph &g, GraphNodeKind kind, const QString &id, const QString &name,
                          const QString &path, int declLine) {
            GraphNode n;
            n.kind = kind;
            n.id = id;
            n.name = name;
            n.path = path;
            n.declLine = declLine;
            g.nodes << n;
            const int idx = g.nodes.size() - 1;
            g.indexById.insert(id, idx);
            return idx;
        };
        auto addSym = [&addNode](CodeGraph &g, int parent, const QString &path,
                        const QString &name, int line) {
            const int idx = addNode(g, GraphNodeKind::sym,
                QStringLiteral("f:%1:%2:%3").arg(path).arg(line).arg(name), name, path, line);
            g.nodes[parent].kids << idx;
            g.nodes[idx].parent = parent;
            return idx;
        };
        CodeGraph hg;
        const int hA = addNode(hg, GraphNodeKind::file, QStringLiteral("f:src/a.c"),
            QStringLiteral("a.c"), QStringLiteral("src/a.c"), 0);
        const int hB = addNode(hg, GraphNodeKind::file, QStringLiteral("f:src/b.c"),
            QStringLiteral("b.c"), QStringLiteral("src/b.c"), 0);
        hg.root = hA;
        addSym(hg, hA, QStringLiteral("src/a.c"), QStringLiteral("alpha"), 1);
        addSym(hg, hA, QStringLiteral("src/a.c"), QStringLiteral("beta"), 5);
        addSym(hg, hB, QStringLiteral("src/b.c"), QStringLiteral("gamma"), 2);
        hg.nodes[hA].rollWeightSum = 12; // 文件的子树罚分（热色输入）

        // alpha → gamma 是**跨文件**调用（下钻 a.c 时算跨作用域边界）；
        // beta → alpha 是**同文件**调用（下钻 a.c 时算作用域内的边）。
        const QVector<HeatLayout::Edge> hSymEdges {
            HeatLayout::Edge { QStringLiteral("f:src/a.c:1:alpha"),
                QStringLiteral("f:src/b.c:2:gamma"), 3, QStringLiteral("resolved") },
            HeatLayout::Edge { QStringLiteral("f:src/a.c:5:beta"),
                QStringLiteral("f:src/a.c:1:alpha"), 1, QStringLiteral("resolved") },
        };
        const QVector<GraphFileEdge> hFileEdges {
            GraphFileEdge { QStringLiteral("src/a.c"), QStringLiteral("src/b.c"), 2 },
        };
        // 文件层的边集（文件级引用边 → 节点 id 形如 f:路径）
        const QVector<HeatLayout::Edge> hFileEdgesOut
            = HeatLayout::scopeEdges(hg, hSymEdges, hFileEdges, -1);
        const QHash<QString, int> hHues = HeatLayout::huesFor(hg);

        // ① 分数公式（引擎 confidence 的镜像）与热色三档
        check(log, "热力图：置信度分数按罚分算（0→100 / 5→80 / 20→50，多文件摊薄）",
            HeatLayout::confScore(0, 1) == 100 && HeatLayout::confScore(5, 1) == 80
                && HeatLayout::confScore(20, 1) == 50 && HeatLayout::confScore(20, 2) == 66
                && HeatLayout::confScore(0, 1) > HeatLayout::confScore(5, 1)
                && HeatLayout::confScore(5, 1) > HeatLayout::confScore(20, 1));
        check(log, "热力图：热色三档边界（≥80 / ≥60 / 其余）且三色互异",
            HeatLayout::heatColor(80) == QColor(89, 240, 184)
                && HeatLayout::heatColor(79) == QColor(255, 200, 87)
                && HeatLayout::heatColor(60) == QColor(255, 200, 87)
                && HeatLayout::heatColor(59) == QColor(255, 107, 138)
                && HeatLayout::heatColor(85) != HeatLayout::heatColor(65)
                && HeatLayout::heatColor(65) != HeatLayout::heatColor(20));

        // ② 身份色：同色相稳定、不同色相不同色；色相按 id 字典序的黄金角分配
        check(log, "热力图：身份色同色相稳定、异色相异色",
            HeatLayout::idColor(30) == HeatLayout::idColor(30)
                && HeatLayout::idColor(30) != HeatLayout::idColor(200));
        {
            // 黄金角：排序后相邻两 id 的色相差 = round(137.508) = 138
            QStringList ids;
            for (const GraphNode &n : hg.nodes) {
                if (n.kind != GraphNodeKind::dir)
                    ids << n.id;
            }
            ids.sort();
            bool golden = ids.size() >= 2;
            if (golden) {
                const int d = (hHues.value(ids.at(1)) - hHues.value(ids.at(0)) + 360) % 360;
                golden = (d == 138);
            }
            check(log, "热力图：身份色相按黄金角 137.508° 散布（相邻 id 色相差 138）", golden);
        }
        {
            // 身份色相**与节点在 arena 里的顺序无关**（排序键是 id 字典序）——
            // 换一个遍历顺序画出来必须一模一样，否则「同一份数据两台机器两张脸」。
            CodeGraph hg2 = hg;
            std::reverse(hg2.nodes.begin(), hg2.nodes.end());
            const QHash<QString, int> hHues2 = HeatLayout::huesFor(hg2);
            bool same = hHues.size() == hHues2.size();
            for (auto it = hHues.constBegin(); same && it != hHues.constEnd(); ++it)
                same = (hHues2.value(it.key()) == it.value());
            check(log, "热力图：身份色相与节点顺序无关（同一份数据画出来一样）", same);
        }

        // ③ 作用域：文件层 = 全部文件；下钻层 = 该文件符号 + 跨作用域边界卡
        const QVector<HeatLayout::Card> hFileCards
            = HeatLayout::scopeCards(hg, hHues, -1, hSymEdges);
        check(log, "热力图：文件层铺全部文件卡（按名排序，无符号卡）",
            hFileCards.size() == 2 && hFileCards.at(0).name == QStringLiteral("a.c")
                && hFileCards.at(1).name == QStringLiteral("b.c")
                && hFileCards.at(0).kind == GraphNodeKind::file
                && !hFileCards.at(0).boundary);
        const QVector<HeatLayout::Card> hDrillCards
            = HeatLayout::scopeCards(hg, hHues, hA, hSymEdges);
        {
            bool shape = hDrillCards.size() == 3;
            if (shape) {
                // 两个符号卡（按声明行 alpha(1) → beta(5)）+ 一个跨作用域边界卡
                shape = hDrillCards.at(0).name == QStringLiteral("alpha")
                    && hDrillCards.at(1).name == QStringLiteral("beta")
                    && hDrillCards.at(0).declLine == 1 && hDrillCards.at(1).declLine == 5
                    && !hDrillCards.at(0).boundary && !hDrillCards.at(1).boundary
                    && hDrillCards.at(2).boundary
                    && hDrillCards.at(2).path == QStringLiteral("src/b.c");
            }
            check(log, "热力图：下钻层 = 该文件符号（按声明行）+ 跨作用域边界卡（按文件聚合）",
                shape);
        }
        {
            // 边界卡上限：跨作用域引用超过 9 个文件 → 9 张 + 一张「+N」
            CodeGraph many = hg;
            QVector<HeatLayout::Edge> edges = hSymEdges;
            for (int i = 0; i < 12; ++i) {
                const QString path = QStringLiteral("src/x%1.c").arg(i);
                const QString sid = QStringLiteral("f:%1:1:g%2").arg(path).arg(i);
                // ⚠ 这些符号**不能**挂到 a.c 的子节点下 —— 挂上去就在作用域内，
                //   就不算「跨作用域」了（那是夹具的坑，不是实现的坑）。
                addNode(many, GraphNodeKind::sym, sid, QStringLiteral("g%1").arg(i), path, 1);
                edges << HeatLayout::Edge { QStringLiteral("f:src/a.c:1:alpha"), sid, 1,
                    QStringLiteral("resolved") };
            }
            const QHash<QString, int> manyHues = HeatLayout::huesFor(many);
            const QVector<HeatLayout::Card> manyCards
                = HeatLayout::scopeCards(many, manyHues, hA, edges);
            int boundaryCards = 0;
            bool hasMore = false;
            for (const HeatLayout::Card &c : manyCards) {
                if (!c.boundary)
                    continue;
                ++boundaryCards;
                if (c.id == QStringLiteral("cgx:__more"))
                    hasMore = true;
            }
            check(log, "热力图：跨作用域边界卡封顶 9 张，溢出并成「+N」（不无限铺）",
                boundaryCards == 10 && hasMore);
        }
        {
            // 作用域内的边只留同文件那条；跨文件那条不混进来
            const QVector<HeatLayout::Edge> hDrillEdges
                = HeatLayout::scopeEdges(hg, hSymEdges, hFileEdges, hA);
            check(log, "热力图：下钻层的边只含作用域内的（同文件）调用",
                hDrillEdges.size() == 1
                    && hDrillEdges.first().from == QStringLiteral("f:src/a.c:5:beta")
                    && hDrillEdges.first().to == QStringLiteral("f:src/a.c:1:alpha"));
        }
        {
            // 文件层的边是文件级引用边（节点 id 形如 f:路径）
            check(log, "热力图：文件层的边是文件级引用边（id 形如 f:路径）",
                hFileEdgesOut.size() == 1
                    && hFileEdgesOut.first().from == QStringLiteral("f:src/a.c")
                    && hFileEdgesOut.first().to == QStringLiteral("f:src/b.c"));
        }

        // ④ 铺排：不重叠、网格等距、序号连续
        const QVector<HeatLayout::Card> hLaid
            = HeatLayout::layout(hFileCards, hFileEdgesOut, 800, 600);
        {
            bool noOverlap = true;
            for (int i = 0; i < hLaid.size() && noOverlap; ++i) {
                for (int j = i + 1; j < hLaid.size(); ++j) {
                    const HeatLayout::Card &x = hLaid.at(i);
                    const HeatLayout::Card &y = hLaid.at(j);
                    if (x.x < y.x + y.w && y.x < x.x + x.w && x.y < y.y + y.h
                        && y.y < x.y + x.h)
                        noOverlap = false;
                }
            }
            check(log, "热力图：卡片互不重叠（重叠的图没法读）", noOverlap && hLaid.size() == 2);
        }
        {
            // 同一行内：y 严格相等、卡高一致（网格工整）
            bool grid = hLaid.size() == 2;
            if (grid) {
                const HeatLayout::Card &x = hLaid.at(0);
                const HeatLayout::Card &y = hLaid.at(1);
                grid = qFuzzyCompare(x.y, y.y) && qFuzzyCompare(x.h, y.h)
                    && !qFuzzyCompare(x.x, y.x);
            }
            check(log, "热力图：同一行内卡片 y 相等（网格工整，不许参差）", grid);
        }
        {
            // 序号：带内**阅读序**（先 y 后 x）从 1 连续
            // ⚠ 序号跟的是排布后的阅读序，不是 arena/输入序 —— 重心扫描会换位，
            //   序号必须跟着换（不然徽标和看到的顺序对不上）。
            QVector<HeatLayout::Card> byRead = hLaid;
            std::sort(byRead.begin(), byRead.end(),
                [](const HeatLayout::Card &a, const HeatLayout::Card &b) {
                    if (!qFuzzyCompare(a.y, b.y))
                        return a.y < b.y;
                    return a.x < b.x;
                });
            bool rank = !byRead.isEmpty();
            for (int i = 0; i < byRead.size() && rank; ++i)
                rank = (byRead.at(i).rank == i + 1);
            check(log, "热力图：序号徽标按阅读序从 1 连续", rank);
        }
        {
            // 铺排结果**与输入顺序无关**（带内先按语义排序再铺）
            QVector<HeatLayout::Card> shuffled = hFileCards;
            std::reverse(shuffled.begin(), shuffled.end());
            const QVector<HeatLayout::Card> laid2
                = HeatLayout::layout(shuffled, hFileEdgesOut, 800, 600);
            bool same = laid2.size() == hLaid.size();
            for (int i = 0; same && i < hLaid.size(); ++i)
                same = (laid2.at(i).id == hLaid.at(i).id)
                    && qFuzzyCompare(laid2.at(i).x, hLaid.at(i).x)
                    && qFuzzyCompare(laid2.at(i).y, hLaid.at(i).y);
            check(log, "热力图：铺排结果与输入顺序无关（同一份数据画出来一样）", same);
        }
        {
            // 分带：文件带在上、符号带在下（下钻层才有两带）
            const QVector<HeatLayout::Card> drillLaid
                = HeatLayout::layout(hDrillCards, QVector<HeatLayout::Edge>(), 800, 600);
            bool banded = drillLaid.size() == 3;
            if (banded) {
                // 边界卡在独立的一带（layerIndex 更大），y 更大
                int symLayer = -1, bndLayer = -1;
                for (const HeatLayout::Card &c : drillLaid) {
                    if (c.boundary)
                        bndLayer = c.layerIndex;
                    else if (symLayer < 0)
                        symLayer = c.layerIndex;
                }
                banded = symLayer >= 0 && bndLayer > symLayer;
            }
            check(log, "热力图：分带有序（符号带在上、跨作用域边界带在下）", banded);
        }

        // ⑤ 重心扫描**真的跑了**（最容易悄悄摘掉的一段）
        // 夹具：三个文件排成一行，a.c ↔ c.c 有边。名次序是 a,b,c；
        // 重心扫描会把关联的两张卡重排到邻居重心一侧 —— 于是 a 的 x 跑到 c 的右边。
        // 摘掉扫描 → a 仍在最左 → 这条判据必须变红。
        {
            CodeGraph g3;
            auto addFile = [&g3](const QString &name) {
                GraphNode n;
                n.kind = GraphNodeKind::file;
                n.id = QStringLiteral("f:src/") + name;
                n.name = name;
                n.path = QStringLiteral("src/") + name;
                g3.nodes << n;
                return g3.nodes.size() - 1;
            };
            addFile(QStringLiteral("a.c"));
            addFile(QStringLiteral("b.c"));
            addFile(QStringLiteral("c.c"));
            const QHash<QString, int> hues3 = HeatLayout::huesFor(g3);
            const QVector<HeatLayout::Card> scope3
                = HeatLayout::scopeCards(g3, hues3, -1, QVector<HeatLayout::Edge>());
            const QVector<HeatLayout::Edge> edges3 {
                HeatLayout::Edge { QStringLiteral("f:src/a.c"), QStringLiteral("f:src/c.c"), 2,
                    QStringLiteral("resolved") },
            };
            const QVector<HeatLayout::Card> laid3
                = HeatLayout::layout(scope3, edges3, 800, 600);
            double ax = 0, cx = 0;
            bool found = laid3.size() == 3;
            for (const HeatLayout::Card &c : laid3) {
                if (c.id == QStringLiteral("f:src/a.c"))
                    ax = c.x;
                if (c.id == QStringLiteral("f:src/c.c"))
                    cx = c.x;
            }
            check(log, "热力图：重心扫描生效（关联卡被重排到邻居重心侧）",
                found && ax > cx);
        }

        // ⑥ 走线：端点贴在卡上、边不丢、曲线过端点
        {
            const QVector<HeatLayout::Route> hRoutes
                = HeatLayout::routes(hLaid, hFileEdgesOut);
            bool ends = hRoutes.size() == 1;
            if (ends) {
                const HeatLayout::Route &r = hRoutes.first();
                ends = r.points.size() >= 2 && r.smoothed.size() >= 2
                    && !r.smoothed.first().isNull() && !r.smoothed.last().isNull();
            }
            check(log, "热力图：走线有折线与平滑采样（边不丢）", ends);
        }
        {
            // Catmull-Rom：过端点、点数 = 1 + (n-1)*per
            const QVector<QPointF> pts { QPointF(0, 0), QPointF(10, 20), QPointF(30, 5),
                QPointF(50, 40) };
            const QVector<QPointF> sm = HeatLayout::catmull(pts, 8);
            check(log, "热力图：曲线过首尾端点且采样数按段数给足",
                sm.size() == 1 + (pts.size() - 1) * 8 && qFuzzyCompare(sm.first().x(), 0.0)
                    && qFuzzyCompare(sm.first().y(), 0.0) && qFuzzyCompare(sm.last().x(), 50.0)
                    && qFuzzyCompare(sm.last().y(), 40.0));
        }
    }

    // ── 补丁体检（引擎 graph patchconf 三层，判定层纯函数）──
    // 判据盯的是「披露得对不对」与「排序/阈值算得对不对」：
    //   ① null 信号 ≠ 0 分（null = 分母为 0、算不出）
    //   ② 契约形状不对时**必须报错**，不许当 0 分放行
    //   ③ 低置信度实体：阈值 + 升序 + 置信度未知不参与
    //   ④ 裁决 id **原样回填**（uncertain.id 与 entity.id 不是同一套 id 空间）
    //   ⑤ 终稿的复核数在 diagnostics.reviewed_by_agent（不在顶层 reviewed）
    //   ⑥ diff 抽实码：行号对得上、抽不到就说抽不到
    {
        // ---- 夹具：一份 Layer 1 载荷（形状照引擎实测）----
        const QString kLayer1 = QStringLiteral(R"JSON({
  "schema": "moongit-patch-confidence/1",
  "overall": 0.5625,
  "signals": {"S1": 1, "S2": 0, "S3": 0.5, "S4": null, "S5": 1,
              "S6": 0, "S7": null, "S8": 1, "S9": 1, "S10": 1},
  "entities": [
    {"id": "helper@src/util.c:5", "kind": "func", "confidence": 0.9,
     "file": "src/util.c", "line": 5, "relations": []},
    {"id": "weak@src/util.c:9", "kind": "func", "confidence": 0.4,
     "file": "src/util.c", "line": 9, "relations": []},
    {"id": "worse@src/util.c:12", "kind": "func", "confidence": 0.1,
     "file": "src/util.c", "line": 12, "relations": []},
    {"id": "unknown@src/util.c:20", "kind": "func",
     "file": "src/util.c", "line": 20, "relations": []}
  ],
  "uncertain": [
    {"id": "src/util.c@6:mystery_call", "issue": "unresolved_call",
     "detail": "call to mystery_call(…) not found in repo or patch",
     "candidates": [], "context_ref": {"file": "src/util.c", "line": 6}}
  ],
  "diagnostics": {"total_entities": 4, "total_relations": 3, "parse_errors": 0,
                  "patch_files": 1, "added_lines": 9, "null_signals": ["S4", "S7"],
                  "null_signals_note": "null 信号 = 词法层无法可靠计算"}
})JSON");
        const QJsonDocument kDoc = QJsonDocument::fromJson(kLayer1.toUtf8());
        const PatchLayer1 l1 = PatchCheck::parseLayer1(kDoc.object());

        check(log, "补丁体检：Layer 1 载荷解析（总分 / 实体 / 拿不准的项 / 诊断）",
            l1.ok && l1.schema == QLatin1String("moongit-patch-confidence/1")
                && l1.overallPresent && qFuzzyCompare(l1.overall, 0.5625)
                && l1.entities.size() == 4 && l1.uncertain.size() == 1
                && l1.uncertain.first().id == QLatin1String("src/util.c@6:mystery_call")
                && l1.uncertain.first().hasContext
                && l1.uncertain.first().file == QLatin1String("src/util.c")
                && l1.uncertain.first().line == 6
                && l1.diagnostics.present && l1.diagnostics.patchFiles == 1
                && l1.diagnostics.addedLines == 9
                && l1.diagnostics.nullSignals == QStringList({ "S4", "S7" }));

        // ① null 信号 ≠ 0 分：S4/S7 是 null，S2 是 0 —— 两者必须分得开
        {
            bool s4Null = false, s2Zero = false, s1One = false;
            for (const PatchSignal &s : l1.signalList) {
                if (s.key == QLatin1String("S4"))
                    s4Null = !s.hasValue;
                if (s.key == QLatin1String("S2"))
                    s2Zero = s.hasValue && qFuzzyCompare(s.value, 0.0);
                if (s.key == QLatin1String("S1"))
                    s1One = s.hasValue && qFuzzyCompare(s.value, 1.0);
            }
            check(log, "补丁体检：null 信号与 0 分可区分（算不出 ≠ 得了 0 分）",
                s4Null && s2Zero && s1One);
        }
        {
            // 信号键要**列全 10 个**（缺键的也要列出来标成算不出）——
                // 少了 S7，用户不知道是引擎没发还是这一项没算。
            check(log, "补丁体检：信号键列全 S1–S10（缺键不当成不存在）",
                l1.signalList.size() == 10);
        }
        {
            // ② 契约形状不对必须报错，不许当 0 分放行
            QJsonObject noSchema;
            noSchema.insert(QStringLiteral("overall"), 0.5);
            const PatchLayer1 bad1 = PatchCheck::parseLayer1(noSchema);
            QJsonObject oldSchema;
            oldSchema.insert(QStringLiteral("schema"),
                QStringLiteral("moongit-patch-confidence/0"));
            oldSchema.insert(QStringLiteral("signals"), QJsonObject());
            const PatchLayer1 bad2 = PatchCheck::parseLayer1(oldSchema);
            check(log, "补丁体检：契约形状不对时报错（缺 schema / 版本不认识），不当成 0 分",
                !bad1.ok && bad1.error.contains(QStringLiteral("schema")) && !bad2.ok
                    && bad2.error.contains(QStringLiteral("moongit-patch-confidence/1")));
        }
        {
            // ③ 低置信度：阈值 0.75、**升序**、置信度未知（缺键）不参与
            const QVector<PatchEntity> lows = PatchCheck::lowConfidenceEntities(l1);
            bool shape = lows.size() == 2;
            if (shape) {
                shape = qFuzzyCompare(lows.at(0).confidence, 0.1)
                    && qFuzzyCompare(lows.at(1).confidence, 0.4);
                // 0.9 的不参与、缺 confidence 的不参与
                for (const PatchEntity &e : lows)
                    shape = shape && e.confidence < 0.75 && e.confidencePresent;
            }
            check(log, "补丁体检：低置信度实体按 <0.75 筛出并**升序**（最不可信的排最前）", shape);
        }
        {
            // ④ 默认裁决：每个拿不准的项一条、默认存疑 / 0.5、id 原样回填
            const QVector<PatchVerdict> verdicts = PatchCheck::defaultVerdicts(l1);
            check(log, "补丁体检：默认裁决逐项给（存疑 / 0.5，id 原样回填）",
                verdicts.size() == 1
                    && verdicts.first().id == QLatin1String("src/util.c@6:mystery_call")
                    && verdicts.first().verdict == QLatin1String("ambiguous")
                    && qFuzzyCompare(verdicts.first().confidence, 0.5));
        }
        {
            // ⑤ agent.json 形状：task + items；id 原样回填；越界 verdict 归一
            QVector<PatchVerdict> v = PatchCheck::defaultVerdicts(l1);
            v[0].verdict = QLatin1String("resolved");
            v[0].confidence = 0.9;
            const QJsonObject payload = PatchCheck::agentPayload(v);
            const QJsonArray items = payload.value(QStringLiteral("items")).toArray();
            bool shape = payload.value(QStringLiteral("task")).toString()
                    == QLatin1String("layer2_review")
                && items.size() == 1
                && items.at(0).toObject().value(QStringLiteral("id")).toString()
                    == QLatin1String("src/util.c@6:mystery_call")
                && items.at(0).toObject().value(QStringLiteral("verdict")).toString()
                    == QLatin1String("resolved");
            // 越界值要归一，不能原样透给引擎
            QVector<PatchVerdict> bad = PatchCheck::defaultVerdicts(l1);
            bad[0].verdict = QLatin1String("whatever");
            const QJsonArray badItems
                = PatchCheck::agentPayload(bad).value(QStringLiteral("items")).toArray();
            shape = shape && badItems.at(0).toObject().value(QStringLiteral("verdict")).toString()
                == QLatin1String("ambiguous");
            check(log, "补丁体检：agent.json 形状对（task/items、id 原样回填、越界值归一）", shape);
        }
        {
            // ⑤ 终稿：复核数在 diagnostics.reviewed_by_agent（**不在**顶层 reviewed）
            const QString kMerged = QStringLiteral(R"JSON({
  "schema": "moongit-patch-confidence-merged/1",
  "overall": 0.475,
  "signals": {"S1": 0.5, "S4": null},
  "entities": [],
  "alerts": [{"level": "high", "type": "unresolved_call",
              "detail": "call to mystery_call(…) not found in repo or patch — agent 判定未解析"}],
  "sources": {"algorithm": true, "agent": true},
  "diagnostics": {"certain_from_algorithm": 1, "reviewed_by_agent": 1, "deferred": 0}
})JSON");
            const PatchMerged merged
                = PatchCheck::parseMerged(QJsonDocument::fromJson(kMerged.toUtf8()).object());
            check(log, "补丁体检：终稿读复核数走 diagnostics.reviewed_by_agent（顶层 reviewed 没有这个键）",
                merged.ok && merged.overallPresent && qFuzzyCompare(merged.overall, 0.475)
                    && merged.alerts.size() == 1
                    && merged.alerts.first().level == QLatin1String("high")
                    && merged.diagnosticsPresent && merged.reviewedByAgent == 1
                    && merged.certainFromAlgorithm == 1 && merged.deferred == 0
                    && merged.sourcesAlgorithm && merged.sourcesAgent);
        }
        {
            // ⑥ diff 抽实码：行号对得上、文件不在补丁里就是抽不到
            const QString kDiff = QStringLiteral(
                "diff --git a/src/util.c b/src/util.c\n"
                "index 41d0610..5ff4b9a 100644\n"
                "--- a/src/util.c\n"
                "+++ b/src/util.c\n"
                "@@ -1,3 +1,7 @@\n"
                " int compute(int n) {\n"
                "-    return n * 2;\n"
                "+    return n * 3;\n"
                "+}\n"
                "+\n"
                "+int helper(int a) {\n"
                "+    return compute(a) + 1;\n"
                " }\n");
            const QStringList snip
                = PatchCheck::diffSnippet(kDiff, QStringLiteral("src/util.c"), 6, 2);
            const QStringList other
                = PatchCheck::diffSnippet(kDiff, QStringLiteral("src/other.c"), 6, 2);
            check(log, "补丁体检：diff 抽实码行号对得上（抽不到就说抽不到，不给空壳）",
                snip.size() == 4 && snip.at(0).startsWith(QLatin1Char('4'))
                    && snip.at(1).startsWith(QLatin1Char('5'))
                    && snip.at(2) == QLatin1String("6\t    return compute(a) + 1;")
                    && snip.at(3).startsWith(QLatin1Char('7'))
                    && other.isEmpty());
        }
        {
            // hunk 头解析：@@ -3,7 +41,9 @@ → 新起始行 41
            check(log, "补丁体检：hunk 头的新起始行号解析（+41 → 41）",
                PatchCheck::parseNewStart(QStringLiteral("@@ -3,7 +41,9 @@")) == 41
                    && PatchCheck::parseNewStart(QStringLiteral("@@ -1,3 +1,7 @@")) == 1
                    && PatchCheck::parseNewStart(QStringLiteral("no hunk here")) == 0);
        }
        {
            // 分数档位边界（mac 同款：≥0.8 高 / ≥0.5 中 / 其余低）
            check(log, "补丁体检：分数档位边界（0.8 高 / 0.5 中 / 其余低）",
                PatchCheck::bandOf(0.8) == PatchCheck::ScoreBand::high
                    && PatchCheck::bandOf(0.79) == PatchCheck::ScoreBand::mid
                    && PatchCheck::bandOf(0.5) == PatchCheck::ScoreBand::mid
                    && PatchCheck::bandOf(0.49) == PatchCheck::ScoreBand::low);
        }
    }

}

} // namespace SelfCheckInternal
