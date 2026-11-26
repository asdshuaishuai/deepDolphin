// EngineMirrorDriftTest.kt —— 镜像漂移检查：真引擎输出 vs Kotlin 镜像，逐键比对（双向）。
//
// 【为什么要有这个】ignoreUnknownKeys=true 会把客户端不认识的键静默吞掉——镜像写错
// 一个键名（如 kind≠type）界面就永远显示默认值，而「能解码」的判据照样是绿的。
// 反过来，镜像里凭空猜出来的字段（引擎从不发）也永远是默认值，同样骗过「能解码」。
//   正向：引擎发了、镜像没接住/类型不符的键 = 漂移；
//   反向：镜像声明了、所有真机样本里都没出现的字段 = 猜出来的。
// 两类都必须要么修镜像、要么进显式豁免表（写明为什么有意如此）。豁免之外出现即红。
//
// 【三档】
//   ① fixtures 档：恒跑，拿仓内 fixture 逐键比（fixture 必须是真机输出）；
//   ② 真机正向档：本机有引擎才跑（没有即跳过并说明）；
//   ③ 真机反向档：同上。

package canopy.engine

import kotlin.test.Test
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.StructureKind
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

class EngineMirrorDriftTest {

    private val lenient = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    /** 一条漂移：path 为归一化路径（数组下标折叠成 []），message 说明差异。 */
    private data class Drift(val path: String, val message: String)

    // ── 豁免表：有意不接的键 / 有意保留的字段（必须写明理由）──

    /** 引擎发了、镜像有意不接的键（归一化路径）。 */
    private val waivedEngineKeys: Map<String, String> = mapOf(
        // 契约 §3.8：只有 add 路径的里程碑带 id，「读取出口剥掉它」。界面用 projectId/name 组合键，
        // 这个 id 不进镜像（Milestone.id 是派生属性，不是字段）。
        "$.milestone.id" to "contract: add-only key",
    )

    /** 镜像声明、引擎不发、有意保留的字段（"Dto.field" → 出处）。新增豁免必须给出契约或样本出处。 */
    private val waivedMirrorFields: Map<String, String> = mapOf(
        // CONTRACT §2.1（deepin StatusTypes.h MergeHint 注释）：仅 git 项目且有合入建议时出现；
        // fixtures/status.json 里有实例（fast-forward / merge 两条）。真机样本当前分支都是默认分支。
        "canopy.engine.Project.mergeHint" to "contract-conditional",
        // 只在采集失败的项目上出现；fixtures/status.json 里有三条实例（路径不存在或卷未挂载）。
        "canopy.engine.Project.error" to "contract-conditional",
        // CONTRACT 脏度结构（deepin StatusTypes.h DirtyState）：err 仅 ok=false 时有。
        "canopy.engine.Dirty.err" to "contract-conditional",
    )

    // ── 正向：逐键比对 ──

    /** 不透明叶子：多态/密封/上下文（JsonElement、二态异构条目等）由各自序列化器把关，不逐键。 */
    private fun opaque(desc: SerialDescriptor): Boolean =
        desc.serialName.startsWith("kotlinx.serialization.json.") ||
            desc.kind.toString().let { it.contains("POLYMORPHIC") || it.contains("SEALED") || it == "CONTEXTUAL" }

    private fun isObjectKind(desc: SerialDescriptor) =
        desc.kind == StructureKind.OBJECT || desc.kind == StructureKind.CLASS

    private fun drift(element: JsonElement, desc: SerialDescriptor, path: String, out: MutableList<Drift>) {
        when (element) {
            is JsonObject -> {
                if (opaque(desc) || desc.kind == StructureKind.MAP) return
                if (!isObjectKind(desc)) {
                    out += Drift(path, "镜像期望 ${desc.kind}，引擎发了对象")
                    return
                }
                for ((k, v) in element) {
                    val idx = desc.getElementIndex(k)
                    if (idx < 0) {
                        out += Drift("$path.$k", "镜像没有这个键（被静默忽略）")
                    } else {
                        drift(v, desc.getElementDescriptor(idx), "$path.$k", out)
                    }
                }
            }
            is JsonArray -> {
                if (opaque(desc)) return
                if (desc.kind != StructureKind.LIST) {
                    out += Drift(path, "镜像期望 ${desc.kind}，引擎发了数组")
                    return
                }
                val item = desc.getElementDescriptor(0)
                element.forEach { drift(it, item, "$path[]", out) }
            }
            is JsonNull -> return // null 语义由可空/默认值承担，不算漂移
            is JsonPrimitive -> {
                if (opaque(desc)) return
                if (desc.kind !is PrimitiveKind) {
                    out += Drift(path, "镜像期望 ${desc.kind}，引擎发了标量 ${element.content.take(40)}")
                    return
                }
                val ok = when (desc.kind) {
                    PrimitiveKind.BOOLEAN -> element.booleanOrNull != null
                    PrimitiveKind.STRING -> element.isString
                    else -> !element.isString && element.doubleOrNull != null
                }
                if (!ok) out += Drift(path, "镜像期望 ${desc.kind}，引擎发了 ${element.content.take(40)}")
            }
            else -> return
        }
    }

    // ── 反向：声明了却从不出现的字段 ──

    private val declared = LinkedHashMap<String, LinkedHashSet<String>>()
    private val present = HashMap<String, MutableSet<String>>()
    private val optional = HashSet<String>()

    private fun collectPresence(element: JsonElement, desc: SerialDescriptor) {
        when (element) {
            is JsonObject -> {
                if (opaque(desc) || desc.kind == StructureKind.MAP || !isObjectKind(desc)) return
                val dto = desc.serialName
                for (i in 0 until desc.elementsCount) {
                    val name = desc.getElementName(i)
                    declared.getOrPut(dto) { LinkedHashSet() } += name
                    if (desc.isElementOptional(i)) optional += dto.removeSuffix("?") + ".$name"
                }
                for ((k, v) in element) {
                    val idx = desc.getElementIndex(k)
                    if (idx >= 0) {
                        present.getOrPut(dto) { HashSet() } += k
                        collectPresence(v, desc.getElementDescriptor(idx))
                    }
                }
            }
            is JsonArray -> {
                if (opaque(desc) || desc.kind != StructureKind.LIST) return
                val item = desc.getElementDescriptor(0)
                element.forEach { collectPresence(it, item) }
            }
            else -> return
        }
    }

    /** 镜像声明了、但所有样本都没出现的字段（豁免之外的）。 */
    private fun neverSent(): List<String> {
        val out = mutableListOf<String>()
        for ((rawDto, dec) in declared) {
            val seen = present[rawDto] ?: emptySet()
            // 可空属性的描述符名带尾问号（Dirty?）；豁免表按去掉问号后的 DTO 名书写
            val dto = rawDto.removeSuffix("?")
            for (f in dec) {
                val id = "$dto.$f"
                if (f !in seen && id !in waivedMirrorFields) {
                    out += id + if (id in optional) "（可空）" else "（必填默认）"
                }
            }
        }
        return out
    }

    private fun report(label: String, raw: String, serializer: KSerializer<*>): List<String> {
        val out = ArrayList<Drift>()
        val tree = lenient.parseToJsonElement(raw)
        drift(tree, serializer.descriptor, "$", out)
        collectPresence(tree, serializer.descriptor)
        return out
            .filter { it.path !in waivedEngineKeys }
            .groupBy({ it.path + "：" + it.message }, { it.path })
            .map { (line, _) -> "[$label] $line" }
    }

    private fun fixtureText(rel: String): String {
        val f = java.io.File("src/jvmTest/resources/fixtures/$rel.json")
        check(f.isFile) { "fixture 缺失：${f.absolutePath}" }
        return f.readText()
    }

    // ── ① fixtures 档（恒跑）──

    @Test
    fun fixturesHaveNoSilentDrift() {
        val findings = mutableListOf<String>()
        findings += report("fx:status", fixtureText("status"), StatusEnvelope.serializer())
        findings += report("fx:dashboard", fixtureText("dashboard"), DashboardData.serializer())
        findings += report("fx:milestones", fixtureText("milestones"), MilestoneList.serializer())
        findings += report("fx:docs", fixtureText("docs"), DocsPayload.serializer())
        findings += report("fx:journal", fixtureText("journal"), JournalPayload.serializer())
        findings += report("fx:update", fixtureText("update"), UpdateReceipt.serializer())
        findings += report("fx:update_all", fixtureText("update_all"), MultiResults.serializer())
        findings += report("fx:update_all_failed", fixtureText("update_all_failed"), MultiResults.serializer())
        findings += report("fx:scan", fixtureText("scan"), ScanPayload.serializer())
        findings += report("fx:milestone_add", fixtureText("milestone_add"), MilestoneAddReceipt.serializer())
        findings += report("fx:milestone_remove", fixtureText("milestone_remove"), MilestoneRemoveReceipt.serializer())
        assertTrue(findings.isEmpty(), "fixture 与镜像存在漂移：\n" + findings.joinToString("\n"))
    }

    // ── ② 真机正向档（有引擎才跑）──

    private fun liveEngine(): String? {
        val probe = runBlocking { EngineLocator.probe() }
        if (!probe.found) {
            println("SKIP 镜像漂移真机档：本机未找到 cambium 引擎")
            return null
        }
        return probe.path
    }

    @Test
    fun liveEngineOutputHasNoSilentDrift() {
        val bin = liveEngine() ?: return
        val findings = mutableListOf<String>()
        runBlocking {
            suspend fun check(label: String, args: List<String>, serializer: KSerializer<*>, timeout: Long = 120) {
                val (rc, out) = EngineLocator.run(bin, args + listOf("--json"), timeout)
                if (rc != 0 || out.isBlank()) {
                    findings += "[$label] 引擎调用失败 rc=$rc：${out.take(120)}"
                    return
                }
                findings += report(label, out, serializer)
            }
            val names = Engine(bin).status().projects.filter { it.isReadable }.map { it.name }
            check("live:status", listOf("status"), StatusEnvelope.serializer(), 60)
            check("live:dashboard", listOf("dashboard"), DashboardData.serializer(), 180)
            check("live:milestone list", listOf("milestone", "list"), MilestoneList.serializer(), 60)
            for (n in names.take(2)) {
                check("live:status $n", listOf("status", n), StatusEnvelope.serializer(), 60)
                check("live:docs $n", listOf("docs", n), DocsPayload.serializer(), 60)
                check("live:journal $n", listOf("journal", n, "--limit", "30"), JournalPayload.serializer(), 60)
            }
            names.firstOrNull()?.let { n ->
                check("live:dendro check $n", listOf("dendro", "check", n), ConfidenceReport.serializer(), 300)
            }
        }
        assertTrue(findings.isEmpty(), "真引擎输出与镜像存在漂移：\n" + findings.joinToString("\n"))
    }

    // ── ③ 真机反向档（有引擎才跑）──

    @Test
    fun liveEngineSendsEveryMirroredField() {
        val bin = liveEngine() ?: return
        runBlocking {
            suspend fun grab(args: List<String>, serializer: KSerializer<*>, timeout: Long = 120) {
                val (rc, out) = EngineLocator.run(bin, args + listOf("--json"), timeout)
                if (rc == 0 && out.isNotBlank()) collectPresence(lenient.parseToJsonElement(out), serializer.descriptor)
            }
            val names = Engine(bin).status().projects.filter { it.isReadable }.map { it.name }
            grab(listOf("status"), StatusEnvelope.serializer(), 60)
            grab(listOf("dashboard"), DashboardData.serializer(), 180)
            grab(listOf("milestone", "list"), MilestoneList.serializer(), 60)
            for (n in names.take(2)) {
                grab(listOf("status", n), StatusEnvelope.serializer(), 60)
                grab(listOf("docs", n), DocsPayload.serializer(), 60)
                grab(listOf("journal", n, "--limit", "30"), JournalPayload.serializer(), 60)
            }
            names.firstOrNull()?.let { grab(listOf("dendro", "check", it), ConfidenceReport.serializer(), 300) }
            // 条件性字段（只在失败项目 / 有合入建议时出现）靠真机 fixture 补样本
            grab(listOf("status"), StatusEnvelope.serializer(), 60)
            Unit
        }
        val never = neverSent()
        assertTrue(never.isEmpty(), "镜像声明了但真引擎从不发的字段：\n" + never.joinToString("\n"))
    }
}
