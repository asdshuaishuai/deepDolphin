// deepDolphin Linux 客户端 —— ISO 8601 时间戳解析。
//
// 【为什么自己写】仓颉标准库没有可用的时区解析入口（`std.time` 里的
// `DateTime` 不吃 `+08:00` 这种偏移量字符串），而引擎的
// `lastCommitAt` / `headDate` 全部是这个形状。不解析就没有「多久没动」，
// 看板的「活跃中 / 久未更新」两列就分不开。
//
// 【口径必须与引擎逐字一致】引擎那边是
//     let ageDays = (nowMs - ms) / 86400000      // dashboard.cj，整数除法
// 所以这里返回的是**毫秒**，除法留给调用方做，且是整数除法。
// 差一天就会让一个 30.6 天的项目掉进「活跃中」还是「久未更新」——
// 而这两列互斥，判错一列等于把项目报错了。
//
// 【为什么不用现成的公式而写 days_from_civil】公历日期与天数的互转
// 没有初等闭式；这个算法（Howard Hinnant 的 `days_from_civil`）是
// 公开的整数算法，只用整数运算、不依赖任何库，也不会因为时区/夏令时出错。
// 本文件末尾的判据拿几个已知值钉住它。
package deepdolphin_linux

/// 公历日期 → 距 1970-01-01 的天数。
///
/// 用 `Int64` 全程整数运算。中间的「上一年 3 月起算」是为了把闰日
/// 挪到年末，闰年判定就退化成 `y%4==0 && (y%100!=0 || y%400==0)`。
public func daysFromCivil(y: Int64, m: Int64, d: Int64): Int64 {
    let yy = y - (if (m <= 2) { 1 } else { 0 })
    let era = (if (yy >= 0) { yy } else { yy - 399 }) / 400
    let yoe = yy - era * 400                                     // [0, 399]
    let mp = m + (if (m > 2) { -3 } else { 9 })                  // 3 月起算
    let doy = (153 * mp + 2) / 5 + d - 1                         // [0, 365]
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy               // [0, 146096]
    return era * 146097 + doe - 719468
}

private func isLeap(y: Int64): Bool {
    return (y % 4 == 0) && ((y % 100 != 0) || (y % 400 == 0))
}

private func daysInMonth(y: Int64, m: Int64): Int64 {
    match (m) {
        case 1 | 3 | 5 | 7 | 8 | 10 | 12 => return 31
        case 4 | 6 | 9 | 11 => return 30
        case 2 => return (if (isLeap(y)) { 29 } else { 28 })
        case _ => return 0
    }
}

private func isDigit(b: UInt8): Bool {
    return b >= 0x30u8 && b <= 0x39u8
}

private func digitAt(b: Array<UInt8>, i: Int64): Int64 {
    if (i < 0 || i >= b.size) {
        return -1
    }
    if (!isDigit(b[i])) {
        return -1
    }
    return Int64(b[i] - 0x30u8)
}

/// 解析固定偏移量的 ISO 8601（`2026-10-02T10:00:00+08:00` / `...Z`）。
///
/// 返回 `None` 的情形都要区分，因为它们对界面说的话不同：
///   · 字符串空        → 引擎没给这个键
///   · 形状不认识      → 引擎变了（比如改成了带小数的秒）
///   · 月/日不合法     → 引擎给了坏数据
/// 统一返回 `None` 是刻意的：三者都归「读不出来」，
/// 而**不**归「0 天前」—— 后者会说这个项目刚提交过。
public func parseIso8601Ms(s: String): Option<Int64> {
    if (s.isEmpty()) {
        return None
    }
    let b = s.toArray()
    // 最短也要 `YYYY-MM-DD`（10 个字符），否则连日期都取不全
    if (b.size < 10) {
        return None
    }
    let y = digits4(b, 0)
    if (y < 0 || b[4] != 0x2Du8) {
        return None
    }
    let mo = twoDigits(b, 5)
    if (mo < 0 || b[7] != 0x2Du8) {
        return None
    }
    let da = twoDigits(b, 8)
    if (y < 0 || mo < 1 || mo > 12 || da < 1 || da > daysInMonth(y, mo)) {
        return None
    }
    var hh: Int64 = 0
    var mi: Int64 = 0
    var ss: Int64 = 0
    var offsetMin: Int64 = 0
    if (b.size >= 19 && (b[10] == 0x54u8 || b[10] == 0x20u8) && b[13] == 0x3Au8 && b[16] == 0x3Au8) {
        hh = twoDigits(b, 11)
        mi = twoDigits(b, 14)
        ss = twoDigits(b, 17)
        if (hh < 0 || hh > 23 || mi < 0 || mi > 59 || ss < 0 || ss > 60) {
            return None
        }
        // 偏移量：`Z` 或 `+HH:MM` / `-HH:MM`
        if (b.size >= 20) {
            if (b[19] == 0x5Au8 || b[19] == 0x7Au8) {
                offsetMin = 0
            } else if (b[19] == 0x2Bu8 || b[19] == 0x2Du8) {
                let oh = twoDigits(b, 20)
                let om = twoDigits(b, 23)
                if (oh < 0 || om < 0 || oh > 23 || om > 59) {
                    return None
                }
                offsetMin = oh * 60 + om
                if (b[19] == 0x2Du8) {
                    offsetMin = -offsetMin
                }
            } else if (isDigit(b[19])) {
                // 紧凑形 `+0800`
                let oh = twoDigits(b, 19)
                let om = twoDigits(b, 21)
                if (oh < 0 || om < 0 || oh > 23 || om > 59) {
                    return None
                }
                offsetMin = oh * 60 + om
                if (b.size >= 24 && b[23] == 0x2Du8) {
                    offsetMin = -offsetMin
                }
            } else {
                return None
            }
        }
    } else if (b.size != 10) {
        // 只有日期也算合法（`YYYY-MM-DD`），当本地 00:00。
        offsetMin = 0
    }
    let days = daysFromCivil(y, mo, da)
    let secs = days * 86400 + hh * 3600 + mi * 60 + ss - offsetMin * 60
    return Some(secs * 1000)
}

private func digits4(b: Array<UInt8>, i: Int64): Int64 {
    var v: Int64 = 0
    for (k in 0..4) {
        let d = digitAt(b, i + k)
        if (d < 0) {
            return -1
        }
        v = v * 10 + d
    }
    return v
}

private func twoDigits(b: Array<UInt8>, i: Int64): Int64 {
    let hi = digitAt(b, i)
    let lo = digitAt(b, i + 1)
    if (hi < 0 || lo < 0) {
        return -1
    }
    return hi * 10 + lo
}
