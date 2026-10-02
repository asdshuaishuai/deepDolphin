// deepDolphin Linux 客户端 —— 只读 JSON 解析（零第三方依赖）。
//
// 移植自 moonGit 引擎 `src/util/json.cj` 的**只读部分**：JsonValue、
// 字段访问器、JsonParser。序列化/构造那一半没有跟过来 —— 客户端只读引擎的
// stdout，从不写 JSON。留着它只会让这个仓多一份用不到的代码。
//
// 保留的是**原实现**而不是重写：这份解析器被引擎的 493 项测试锤过
// （严格数字文法、代理对 emoji、孤立代理项、超深嵌套不炸栈、UTF-8 BOM、
// 巨量数字不崩），重写等于把这些坑重新踩一遍。
// 两处针对本客户端的改动：
//   1) 崩溃后果的描述从「serve / mcp 进程」换成「窗口进程」；
//   2) 嵌套深度上限从 512 收到 128 —— 引擎的输入是用户文档，客户端的输入
//      是引擎自己的结构化输出（只有几层嵌套），而客户端崩了就是窗口直接没了。
package deepdolphin_linux

import std.collection.*
import std.convert.*

/// JsonValue 的数字只有 JNum(Float64) 一种形态，所有整数都经 Float64 中转。
/// Float64 能精确表示的整数上限是 2^53 —— 超出这个范围，数值在**读进来那一刻**
/// 就已经失真且不可逆。所以取整数的入口（`asInt`）必须先卡范围，
/// 超出则返回 None，让调用方走 fallback，而不是硬转 Int64 崩掉。
private const MAX_SAFE_INT: Float64 = 9007199254740992.0  // 2^53
private const MIN_SAFE_INT: Float64 = -9007199254740992.0

public enum JsonValue {
    | JNull
    | JBool(Bool)
    | JNum(Float64)
    | JStr(String)
    | JArr(ArrayList<JsonValue>)
    | JObj(ArrayList<(String, JsonValue)>)
}

public class Json {
    // ------------------------------ 取字段 ------------------------------


    public static func get(o: JsonValue, key: String): Option<JsonValue> {
        match (o) {
            case JObj(m) =>
                for ((k, v) in m) {
                    if (k == key) {
                        return Some(v)
                    }
                }
                return None
            case _ => return None
        }
    }

    /// 取字段，缺失时返回 JNull（避免 Option 解包噪音）
    public static func getOr(o: JsonValue, key: String): JsonValue {
        match (get(o, key)) {
            case Some(v) => return v
            case None => return JNull
        }
    }

    public static func has(o: JsonValue, key: String): Bool {
        return get(o, key).isSome()
    }

    public static func remove(o: JsonValue, key: String): Unit {
        match (o) {
            case JObj(m) =>
                var i = 0
                while (i < m.size) {
                    let (k, _) = m[i]
                    if (k == key) {
                        m.remove(at: i)
                    } else {
                        i += 1
                    }
                }
            case _ => ()
        }
    }

    public static func add(a: JsonValue, v: JsonValue): Unit {
        match (a) {
            case JArr(items) => items.add(v)
            case _ => ()
        }
    }

    // ------------------------------ 访问 ------------------------------
    public static func asStr(v: JsonValue): Option<String> {
        match (v) {
            case JStr(s) => return Some(s)
            case _ => return None
        }
    }

    public static func asNum(v: JsonValue): Option<Float64> {
        match (v) {
            case JNum(n) => return Some(n)
            case JBool(b) => return Some(if (b) { 1.0 } else { 0.0 })
            case _ => return None
        }
    }

    public static func asInt(v: JsonValue): Option<Int64> {
        match (asNum(v)) {
            case Some(n) =>
                // 必须先判范围：`Int64(n)` 在 |n| >= 2^63 时抛异常，
                // 而 intAt 声明了 fallback 参数、语义是「取不到就返回 fallback」。
                // 旧实现直接抛，fallback 保护形同虚设 —— 实测 `intAt(1e30)` 崩。
                if (n.isNaN() || n.isInf() || n < MIN_SAFE_INT || n > MAX_SAFE_INT) {
                    return None
                }
                try {
                    return Some(Int64(n))
                } catch (e: Exception) {
                    return None
                }
            case None => return None
        }
    }

    public static func asBool(v: JsonValue): Option<Bool> {
        match (v) {
            case JBool(b) => return Some(b)
            case _ => return None
        }
    }

    public static func asArr(v: JsonValue): Option<ArrayList<JsonValue>> {
        match (v) {
            case JArr(a) => return Some(a)
            case _ => return None
        }
    }

    public static func asObj(v: JsonValue): Option<ArrayList<(String, JsonValue)>> {
        match (v) {
            case JObj(m) => return Some(m)
            case _ => return None
        }
    }

    public static func isNull(v: JsonValue): Bool {
        match (v) {
            case JNull => return true
            case _ => return false
        }
    }

    /// 取字符串字段，缺省返回 fallback
    public static func strAt(o: JsonValue, key: String, fallback: String): String {
        match (get(o, key)) {
            case Some(v) => match (asStr(v)) {
                case Some(s) => return s
                case None => return fallback
            }
            case None => return fallback
        }
    }

    public static func strAtOpt(o: JsonValue, key: String): Option<String> {
        match (get(o, key)) {
            case Some(v) => return asStr(v)
            case None => return None
        }
    }

    public static func intAt(o: JsonValue, key: String, fallback: Int64): Int64 {
        match (get(o, key)) {
            case Some(v) => match (asInt(v)) {
                case Some(n) => return n
                case None => return fallback
            }
            case None => return fallback
        }
    }

    public static func numAt(o: JsonValue, key: String, fallback: Float64): Float64 {
        match (get(o, key)) {
            case Some(v) => match (asNum(v)) {
                case Some(n) => return n
                case None => return fallback
            }
            case None => return fallback
        }
    }

    public static func boolAt(o: JsonValue, key: String, fallback: Bool): Bool {
        match (get(o, key)) {
            case Some(v) => match (asBool(v)) {
                case Some(b) => return b
                case None => return fallback
            }
            case None => return fallback
        }
    }

    public static func arrAt(o: JsonValue, key: String): ArrayList<JsonValue> {
        match (get(o, key)) {
            case Some(v) => match (asArr(v)) {
                case Some(a) => return a
                case None => return ArrayList<JsonValue>()
            }
            case None => return ArrayList<JsonValue>()
        }
    }

    public static func strArrAt(o: JsonValue, key: String): ArrayList<String> {
        let out = ArrayList<String>()
        for (v in arrAt(o, key)) {
            match (asStr(v)) {
                case Some(s) => out.add(s)
                case None => ()
            }
        }
        return out
    }
    /// 代理对已在 `string()` 里正确合并（见那里），但外层这层 try/catch 是
    /// 契约本身的兑现点：解析器里任何一处未来引入的抛异常，都只会被降级为
    /// 「这个输入解析失败」，而不是杀死整个窗口进程。
    public static func parse(input: String): Option<JsonValue> {
        try {
            let bytes = input.toArray()
            // 跳过 UTF-8 BOM：Windows 工具链产出的 JSON 常带 EF BB BF，
            // 不跳过就直接解析失败（Python json 同样拒绝，但引擎的输入源
            // 包含用户用记事本改过的状态文件）。
            var start: Int64 = 0
            if (bytes.size >= 3 && bytes[0] == 0xefu8 && bytes[1] == 0xbbu8 && bytes[2] == 0xbfu8) {
                start = 3
            }
            let p = JsonParser(bytes, start)
            p.skipWs()
            match (p.value()) {
                case Some(v) =>
                    p.skipWs()
                    if (p.pos != bytes.size) {
                        return None
                    }
                    return Some(v)
                case None => return None
            }
        } catch (e: Exception) {
            return None
        } catch (e: Error) {
            // Error 不是 Exception 的子类（StackOverflowError 等走这一支）。
            // 有了深度上限这类情况本不该再发生，但兜住它成本为零，
            // 而漏掉它的代价是整个窗口进程裸崩。
            return None
        }
    }
}

/// 嵌套深度上限。JSON 规范本身不限，但**解析器在栈上递归**：
/// 无限深度的输入会触发 StackOverflowError，而 Cangjie 的 `Error` 不是
/// `Exception` —— 兜不住它，整个窗口进程裸崩（无清理、无日志）。
/// 实测阈值在 800~1000 之间。
/// 这里取 128：引擎的输出是它自己生成的结构化 JSON，嵌套只有几层，
/// 128 远高于真实载荷，同时把「吃满栈」需要的输入量缩到原来的四分之一。
private const MAX_DEPTH: Int64 = 128
class JsonParser {
    let b: Array<UInt8>
    var pos: Int64
    var depth: Int64

    init(b: Array<UInt8>, pos: Int64) {
        this.b = b
        this.pos = pos
        this.depth = 0
    }

    func peek(): Option<UInt8> {
        if (this.pos < this.b.size) {
            return Some(this.b[this.pos])
        }
        return None
    }

    func bump(): Option<UInt8> {
        let c = this.peek()
        match (c) {
            case Some(_) => this.pos += 1
            case None => ()
        }
        return c
    }

    func skipWs(): Unit {
        while (true) {
            match (this.peek()) {
                case Some(c) =>
                    if (c == 0x20u8 || c == 0x09u8 || c == 0x0au8 || c == 0x0du8) {
                        this.pos += 1
                    } else {
                        break
                    }
                case None => break
            }
        }
    }

    func value(): Option<JsonValue> {
        this.skipWs()
        match (this.peek()) {
            case Some(c) =>
                if (c == 0x7bu8) {
                    this.depth += 1
                    if (this.depth > MAX_DEPTH) { return None }
                    let r = this.object()
                    this.depth -= 1
                    return r
                } else if (c == 0x5bu8) {
                    this.depth += 1
                    if (this.depth > MAX_DEPTH) { return None }
                    let r = this.array()
                    this.depth -= 1
                    return r
                } else if (c == 0x22u8) {
                    match (this.string()) {
                        case Some(s) => return Some(JStr(s))
                        case None => return None
                    }
                } else if (c == 0x74u8) {
                    return if (this.lit("true")) { Some(JBool(true)) } else { None }
                } else if (c == 0x66u8) {
                    return if (this.lit("false")) { Some(JBool(false)) } else { None }
                } else if (c == 0x6eu8) {
                    return if (this.lit("null")) { Some(JNull) } else { None }
                } else if (c == 0x2du8 || (c >= 0x30u8 && c <= 0x39u8)) {
                    return this.number()
                } else {
                    return None
                }
            case None => return None
        }
    }

    func lit(s: String): Bool {
        let target = s.toArray()
        if (this.pos + target.size > this.b.size) {
            return false
        }
        for (i in 0..target.size) {
            if (this.b[this.pos + i] != target[i]) {
                return false
            }
        }
        this.pos += target.size
        return true
    }

    func object(): Option<JsonValue> {
        this.bump()  // {
        let m = ArrayList<(String, JsonValue)>()
        this.skipWs()
        match (this.peek()) {
            case Some(c) =>
                if (c == 0x7du8) {
                    this.bump()
                    return Some(JObj(m))
                } else if (c == 0x22u8) {
                    // 空对象以外的情况继续
                } else {
                    return None
                }
            case None => return None
        }
        while (true) {
            this.skipWs()
            match (this.string()) {
                case Some(key) =>
                    this.skipWs()
                    match (this.bump()) {
                        case Some(c) =>
                            if (c != 0x3au8) {
                                return None
                            }
                        case None => return None
                    }
                    match (this.value()) {
                        case Some(v) =>
                            // 注意：重复键必须**就地替换**，不能直接 add。
                            //
                            // JObj 是 pair 列表，直接 add 会让重复键留在表示里：
                            //   · 查找从头扫 ⇒ first-wins，而 Python / JS / Go /
                            //     Rust 全部是 last-wins —— 同一个文件，
                            //     moonGit 读到 a=1、别的工具读到 a=2
                            //   · 更糟的是 Json.compact 会把重复键**原样写回**
                            //     （实测 {"a":1,"a":2} 往返后仍是两个 a），
                            //     于是歧义被引擎亲手持久化下来
                            //
                            // 就地替换（保持首次出现的位置，顺序不变）同时解决两者：
                            // 读出来是 last-wins，存回去只剩一个键。
                            //
                            // 这里**不报错**：主流解析器都接受这个文件，
                            // moonGit 若独独拒绝，就成了唯一读不出的那个工具。
                            // 真正要消除的是「读法不一致」，而不是文件本身。
                            var replaced = false
                            for (i in 0..m.size) {
                                if (m[i][0] == key) {
                                    m[i] = (key, v)
                                    replaced = true
                                    break
                                }
                            }
                            if (!replaced) {
                                m.add((key, v))
                            }
                        case None => return None
                    }
                    this.skipWs()
                    match (this.bump()) {
                        case Some(c) =>
                            if (c == 0x2cu8) {
                                continue
                            } else if (c == 0x7du8) {
                                break
                            } else {
                                return None
                            }
                        case None => return None
                    }
                case None => return None
            }
        }
        return Some(JObj(m))
    }

    func array(): Option<JsonValue> {
        this.bump()  // [
        let a = ArrayList<JsonValue>()
        this.skipWs()
        match (this.peek()) {
            case Some(c) =>
                if (c == 0x5du8) {
                    this.bump()
                    return Some(JArr(a))
                }
            case None => ()
        }
        while (true) {
            match (this.value()) {
                case Some(v) => a.add(v)
                case None => return None
            }
            this.skipWs()
            match (this.bump()) {
                case Some(c) =>
                    if (c == 0x2cu8) {
                        continue
                    } else if (c == 0x5du8) {
                        break
                    } else {
                        return None
                    }
                case None => return None
            }
        }
        return Some(JArr(a))
    }

    func string(): Option<String> {
        match (this.bump()) {
            case Some(c) =>
                if (c != 0x22u8) {
                    return None
                }
            case None => return None
        }
        let sb = StringBuilder()
        var done = false
        while (!done) {
            match (this.bump()) {
                case Some(c) =>
                    if (c == 0x22u8) {
                        return Some(sb.toString())
                    } else if (c == 0x5cu8) {
                        match (this.bump()) {
                            case Some(e) =>
                                match (e) {
                                    case 0x22u8 => sb.append("\"")
                                    case 0x5cu8 => sb.append("\\")
                                    case 0x2fu8 => sb.append("/")
                                    case 0x62u8 => sb.append("\u{8}")
                                    case 0x66u8 => sb.append("\u{c}")
                                    case 0x6eu8 => sb.append("\n")
                                    case 0x72u8 => sb.append("\r")
                                    case 0x74u8 => sb.append("\t")
                                    case 0x75u8 =>
                                        match (this.hex4()) {
                                            case Some(cp) =>
                                                // UTF-16 代理对必须合并成一个码点。
                                                // `\uD83D\uDE00` 是 JSON 表示 emoji（😀）的
                                                // **标准写法**，Python 的 json.dumps 默认就产出它。
                                                // 旧实现把 0xD83D 直接交给 Rune()，抛
                                                // "not a valid Unicode scalar value"，
                                                // 一个表情就能杀掉 MCP / HTTP 进程。
                                                if (cp >= 0xd800u32 && cp <= 0xdbffu32) {
                                                    // 高位代理：必须紧跟一个 \uDC00-\uDFFF 的低位代理
                                                    if (this.peek() == Some(0x5cu8)) {
                                                        let save = this.pos
                                                        this.bump()
                                                        if (this.peek() == Some(0x75u8)) {
                                                            this.bump()
                                                            match (this.hex4()) {
                                                                case Some(lo) =>
                                                                    if (lo >= 0xdc00u32 && lo <= 0xdfffu32) {
                                                                        sb.append(Rune(0x10000u32 + ((cp - 0xd800u32) << 10) + (lo - 0xdc00u32)).toString())
                                                                    } else {
                                                                        // 不是合法低位代理：按 WHATWG 规范，
                                                                        // 高位代理替换为 U+FFFD，低位按普通码点处理
                                                                        sb.append("\u{fffd}")
                                                                        if (lo >= 0xd800u32 && lo <= 0xdfffu32) {
                                                                            sb.append("\u{fffd}")
                                                                        } else {
                                                                            sb.append(Rune(lo).toString())
                                                                        }
                                                                    }
                                                                case None =>
                                                                    this.pos = save
                                                                    sb.append("\u{fffd}")
                                                            }
                                                        } else {
                                                            this.pos = save
                                                            sb.append("\u{fffd}")
                                                        }
                                                    } else {
                                                        sb.append("\u{fffd}")
                                                    }
                                                } else if (cp >= 0xdc00u32 && cp <= 0xdfffu32) {
                                                    // 孤立低位代理
                                                    sb.append("\u{fffd}")
                                                } else {
                                                    sb.append(Rune(cp).toString())
                                                }
                                            case None => return None
                                        }
                                    case _ => return None
                                }
                            case None => return None
                        }
                    } else if (c < 0x20u8) {
                        return None
                    } else if (c < 0x80u8) {
                        sb.append(Rune(UInt32(c)).toString())
                    } else {
                        // UTF-8 多字节：回退一个字节，按 Rune 解码
                        this.pos -= 1
                        let rest = this.b[this.pos..]
                        match (runeFromUtf8(rest)) {
                            case Some(pair) =>
                                let (r, size) = pair
                                sb.append(r.toString())
                                this.pos += size
                            case None => return None
                        }
                    }
                case None =>
                    done = true
            }
        }
        return None
    }

    func hex4(): Option<UInt32> {
        var v: UInt32 = 0
        for (_ in 0..4) {
            match (this.bump()) {
                case Some(c) =>
                    var d: UInt32
                    if (c >= 0x30u8 && c <= 0x39u8) {
                        d = UInt32(c - 0x30u8)
                    } else if (c >= 0x61u8 && c <= 0x66u8) {
                        d = UInt32(c - 0x61u8 + 10u8)
                    } else if (c >= 0x41u8 && c <= 0x46u8) {
                        d = UInt32(c - 0x41u8 + 10u8)
                    } else {
                        return None
                    }
                    v = v * 16u32 + d
                case None => return None
            }
        }
        return Some(v)
    }

    /// 严格按 RFC 8259 的 number 文法解析：
    ///     -?  ( 0 | [1-9][0-9]* )  ( \. [0-9]+ )?  ( [eE] [+-]? [0-9]+ )?
    ///
    /// 原实现是「负号可选 + 数字随便吃 + 小数点可选 + 小数随便吃」，
    /// 剩下的全交给 `Float64.parse` 兜底，而后者**不抛**的几种输入
    /// 实测都被静默改写成了另一个数：
    ///     `-`    → 0        裸负号，一个数字都没有
    ///     `01`   → 1        JSON 禁止前导零
    ///     `00.5` → 0.5      同上
    ///     `1.`   → 1        小数点后必须有数字
    /// 而 `1e999` 更糟：解析成 Infinity，`Json.of` 把它渲染成 **null** ——
    /// 用户写的是数字，引擎存回去的是 null，任何下游读到的都是 null。
    /// 这和序列化侧那个 `1e308 → null` 是同一族（#139），修在了解析侧。
    ///
    /// 方向：**宁可拒绝**。把非法字面量猜成一个合法数字，比报错难查得多 ——
    /// 报错至少会说「第 N 行这里不合法」，猜出来的值则一路带着走下去。
    func number(): Option<JsonValue> {
        let start = this.pos
        if (this.peek() == Some(0x2du8)) {
            this.bump()
        }
        // 整数部分：0 或 [1-9][0-9]*
        match (this.peek()) {
            case Some(c) =>
                if (c == 0x30u8) {
                    this.bump()
                    // 前导零：`0` 后面必须不是数字
                    match (this.peek()) {
                        case Some(c2) =>
                            if (c2 >= 0x30u8 && c2 <= 0x39u8) {
                                return None
                            }
                        case None => ()
                    }
                } else if (c >= 0x31u8 && c <= 0x39u8) {
                    while (this.isDigit()) {
                        this.pos += 1
                    }
                } else {
                    // 包括裸 `-`、`.`、`e` —— 原实现到这里会交给 Float64.parse
                    return None
                }
            case None => return None
        }
        // 小数部分：. 之后必须至少一个数字
        if (this.peek() == Some(0x2eu8)) {
            this.bump()
            if (!this.isDigit()) {
                return None
            }
            while (this.isDigit()) {
                this.pos += 1
            }
        }
        // 指数：e 之后必须至少一个数字
        match (this.peek()) {
            case Some(c) =>
                if (c == 0x65u8 || c == 0x45u8) {
                    this.bump()
                    match (this.peek()) {
                        case Some(s) =>
                            if (s == 0x2bu8 || s == 0x2du8) {
                                this.bump()
                            }
                        case None => ()
                    }
                    if (!this.isDigit()) {
                        return None
                    }
                    while (this.isDigit()) {
                        this.pos += 1
                    }
                }
            case None => ()
        }
        let s = String.fromUtf8(this.b[start..this.pos])
        match (parseFloatOpt(s)) {
            case Some(n) =>
                // 溢出/溢出下溢都要拒。Infinity 存下去会变成 null，
                // 那就是把「超出范围」说成「没有值」。
                if (n.isNaN() || n.isInf()) {
                    return None
                }
                return Some(JNum(n))
            case None => return None
        }
    }

    func isDigit(): Bool {
        match (this.peek()) {
            case Some(c) => return c >= 0x30u8 && c <= 0x39u8
            case None => return false
        }
    }
}


func runeFromUtf8(b: Array<UInt8>): Option<(Rune, Int64)> {
    if (b.size == 0) {
        return None
    }
    let c0 = b[0]
    if (c0 < 0x80u8) {
        return Some((Rune(UInt32(c0)), 1))
    }
    var need: Int64 = 0
    var cp: UInt32 = 0
    if (c0 >= 0xc0u8 && c0 < 0xe0u8) {
        need = 2
        cp = UInt32(c0 & 0x1fu8)
    } else if (c0 >= 0xe0u8 && c0 < 0xf0u8) {
        need = 3
        cp = UInt32(c0 & 0x0fu8)
    } else if (c0 >= 0xf0u8 && c0 < 0xf8u8) {
        need = 4
        cp = UInt32(c0 & 0x07u8)
    } else {
        return None
    }
    if (b.size < need) {
        return None
    }
    for (i in 1..need) {
        let c = b[i]
        if (c < 0x80u8 || c >= 0xc0u8) {
            return None
        }
        cp = (cp << 6) | UInt32(c & 0x3fu8)
    }
    return Some((Rune(cp), need))
}
func parseFloatOpt(s: String): Option<Float64> {
    try {
        return Some(Float64.parse(s))
    } catch (e: Exception) {
        return None
    }
}
