// deepDolphin Linux 客户端 —— JSON **写**侧。
//
// 【为什么单独一个文件】`json.cj` 整个文件是**只读**的：它服务引擎 `--json`
// 契约，职责是「把引擎给的东西读成模型」。AI 通道要往反方向走 —— 组装
// 请求体发给 provider。两种方向混在一个文件里，读的人会以为契约层也在发数据。
//
// 【为什么必须是真转义，不能拼字符串】请求体里装着**用户自己打的字**和
// **模型返回的原文**。提示词里一个 `"`、一段换行、一个反斜杠，直接拼进去
// 就是一份语法坏掉的 JSON，而症状是「偶发地 400」或「模型答非所问」——
// 极难定位。更糟的是反向：模型返回里的换行如果不转义就落进界面，
// 排版会直接乱掉。
package deepdolphin_linux

import std.collection.*

/// \u00XX 用的两位小写十六进制表。
private let HEX: Array<String> = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"
]

/// `JsonValue` → JSON 文本。
public func jsonWrite(v: JsonValue): String {
    let sb = StringBuilder()
    jsonWriteInto(sb, v)
    return sb.toString()
}

/// 常用构造子，省调用点满地写 `JStr(...)`。
public func jstr(s: String): JsonValue {
    return JsonValue.JStr(s)
}

public func jnum(n: Float64): JsonValue {
    return JsonValue.JNum(n)
}

public func jarr(items: ArrayList<JsonValue>): JsonValue {
    return JsonValue.JArr(items)
}

public func jobj(pairs: ArrayList<(String, JsonValue)>): JsonValue {
    return JsonValue.JObj(pairs)
}

/// 追加一个 `"key": value`。键的转义与值同规则。
public func jobjAdd(pairs: ArrayList<(String, JsonValue)>, key: String, v: JsonValue): Unit {
    pairs.add((key, v))
}

private func jsonWriteInto(sb: StringBuilder, v: JsonValue): Unit {
    match (v) {
        case JsonValue.JNull => sb.append("null")
        case JsonValue.JBool(b) => sb.append(if (b) { "true" } else { "false" })
        case JsonValue.JNum(n) => writeNumber(sb, n)
        case JsonValue.JStr(s) => writeJsonString(sb, s)
        case JsonValue.JArr(items) =>
            sb.append("[")
            var first = true
            for (it in items) {
                if (!first) { sb.append(",") }
                first = false
                jsonWriteInto(sb, it)
            }
            sb.append("]")
        case JsonValue.JObj(pairs) =>
            sb.append("{")
            var first = true
            for ((k, val) in pairs) {
                if (!first) { sb.append(",") }
                first = false
                writeJsonString(sb, k)
                sb.append(":")
                jsonWriteInto(sb, val)
            }
            sb.append("}")
    }
}

/// 整数就写整数。
///
/// `Float64.toString()` 在本工具链上是定点格式：`1.5` → `1.500000`。
/// 它**是**合法 JSON，但 `max_tokens: 4000.000000` 这种东西会让
/// 某些 provider 的参数校验挑刺，而且排查时看着像脏数据。
private func writeNumber(sb: StringBuilder, n: Float64): Unit {
    // NaN / Inf 不是合法 JSON 字面量。这里出现的唯一入口是
    // 「把读不出来的数字凑成 0」的兜底，所以直接归零而不是崩掉。
    if (n != n) {
        sb.append("0")
        return
    }
    if (n > 1.0e300 || n < -1.0e300) {
        sb.append("0")
        return
    }
    let i = Int64(n)
    if (Float64(i) == n) {
        sb.append(i.toString())
        return
    }
    sb.append(n.toString())
}

/// 字符串字面量，含引号。
///
/// ⚠ 按 **rune** 迭代、用**首字节**判断 ASCII 控制字符。
/// 曾经按字节迭代再 `String.fromUtf8([b])` 拼回去 ——
/// 那条路在中文上必炸：多字节序列的续字节（0x80–0xBF）单独拿去解码
/// 是非法 UTF-8 序列，`String.fromUtf8` 直接抛
/// `IllegalArgumentException: Invalid utf8 byte sequence`。
/// 也就是说，只要提示词里有一个汉字，AI 通道就完全不可用。
///
/// 为什么首字节就够了：需要转义的那些字符（`"` `\` `\n` …）
/// **全都是 ASCII**，而 ASCII 字符的 UTF-8 首字节就是它自己。
/// 首字节 >= 0x20 的 rune 一律原样输出 —— JSON 允许字符串里出现原始 UTF-8，
/// 逐字符转成 \uXXXX 既慢又更容易写错。
private func writeJsonString(sb: StringBuilder, s: String): Unit {
    sb.append("\"")
    for (r in s.runes()) {
        let b = r.toString().toArray()[0]
        match (b) {
            case 0x22u8 => sb.append("\\\"") // "
            case 0x5cu8 => sb.append("\\\\") // \
            case 0x08u8 => sb.append("\\b")
            case 0x0cu8 => sb.append("\\f")
            case 0x0au8 => sb.append("\\n")
            case 0x0du8 => sb.append("\\r")
            case 0x09u8 => sb.append("\\t")
            case _ =>
                if (b < 0x20u8) {
                    sb.append("\\u00")
                    sb.append(HEX[Int64(b >> 4)])
                    sb.append(HEX[Int64(b & 0x0fu8)])
                } else {
                    sb.append(r.toString())
                }
        }
    }
    sb.append("\"")
}

/// 把字符串列表拼成 `a、b、c`。仓颉的 `Array` / `ArrayList` 都没有 `join`。
public func joinList(items: Array<String>): String {
    let sb = StringBuilder()
    for (i in 0..items.size) {
        if (i > 0) { sb.append("、") }
        sb.append(items[i])
    }
    return sb.toString()
}
