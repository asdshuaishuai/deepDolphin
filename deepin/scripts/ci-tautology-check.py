#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ci-tautology-check.py — 判据不许被「掏空成恒真」（批 BF）。

【为什么要有它 —— 实测取证，不是推演】
  批 BC/BB 的门盯的是「**判据条数**」（selfcheck `SC_MIN`、各断言脚本的条数基线）
  ⇒ ⚠⚠⚠ **条数不变，但条件被掏空成恒真 ⇒ 门照样全绿**：
  把 `check(log, "…", env.has_value())` 改成 `check(log, "…", true)`
  ⇒ 判据**条数不变**（395）⇒ SC_MIN 门绿 ⇒ 接线门绿 ⇒ CI 绿
  ⇒ 而这条判据**从此永远不会红** ⇒ 判据被悄悄削弱无人知晓。
  ⇒ 本脚本管两处：
    ① **判定层 C++**（`src/app/SelfCheck*.cpp`）：`check(…)` 的**条件**不许是恒真/纯字面量；
    ② **shell 断言脚本**（`scripts/*.sh`）：`if` 的**条件**不许是恒真/恒假。

【判定口径（实测，不是猜）】
  ① C++ 侧用**括号配平**抽 `check(…)` 的第三个参数 —— ⚠ **不用正则猜**：
     条件里可能有逗号、嵌套括号、字符串里的逗号 ⇒ 正则会抽错。
  ② 「恒真」的判据 = 条件里**去掉字面量与关键字后，一个标识符都不剩**
     （`true` / `false` / `1 == 1` / `"a" == "a"` 都落这一档）。
     ⚠ 判据是「**至少有一个被测标识符**」而不是「不许出现 true」——
       后者只能抓最浅的手改形态，抓不到 `1 == 1`。
  ③ 另禁「捷径」写法：`|| true` / `&& false` / `or true` / `and false`
     （条件里有个恒真项 ⇒ 整条判据被短路成恒真）。
  ④ shell 侧：`if` 的条件（跨行续行也拼起来）不许是 `true` / `false` / `:`。

【用法】python3 scripts/ci-tautology-check.py <源码根目录>
  退出码 0 = 通过；非 0 = 有恒真条件（stderr 里有清单）。
"""
import os
import re
import sys

# ── 关键字/字面量：抽掉它们之后，「一个标识符都不剩」才算恒真 ──────────────
KEYWORDS = {
    'true', 'false', 'nullptr', 'NULL', 'this', 'sizeof', 'static_cast',
    'const_cast', 'reinterpret_cast', 'dynamic_cast', 'new', 'delete',
    'not', 'and', 'or', 'int', 'bool', 'char', 'double', 'float', 'void',
    'unsigned', 'signed', 'long', 'short', 'auto', 'return',
}

# ⚠「捷径」：条件里带一个恒真项 ⇒ 整条判据被短路
SHORTCUT = re.compile(r'\|\|\s*true\b|&&\s*false\b|\bor\s+true\b|\band\s+false\b')

# ⚠ shell 侧的恒真条件（只有这三个是「无条件成立/不成立」）
SH_CONST = re.compile(r'^\s*(true|false|:)\s*$')

# ⚠ python 侧：`if True:` / `if False:` / `if 1:` 这类恒真条件
#    （⚠ 与 shell 口径**分开** —— python 的 if 用冒号收尾，条件里也有 `:`）
PY_CONST_IF = re.compile(r'^\s*if\s+(True|False|1|0)\s*:')

ERROR = '✗ '

# ⚠ 判定层文件名前缀（**单一出处** —— 门要盯的就是这一行）
JUDGEMENT_PREFIX = 'SelfCheck'


def strip_literals(cond):
    """去掉字符串/字符/数字字面量（保留结构）。"""
    s = re.sub(r'"(?:[^"\\]|\\.)*"', ' ', cond)
    s = re.sub(r"'(?:[^'\\]|\\.)*'", ' ', s)
    s = re.sub(r'\b0[xX][0-9a-fA-F]+\b', ' ', s)
    s = re.sub(r'\b\d+(?:\.\d+)?\b', ' ', s)
    return s


def meaningful_idents(cond):
    s = strip_literals(cond)
    return [w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', s)
            if w not in KEYWORDS]


def extract_check_conds(text):
    """抽出 `check(…)` 的第三个参数（条件）—— 用括号配平，⚠ 不用正则猜。"""
    out = []
    for m in re.finditer(r'\bcheck\s*\(', text):
        i = m.end()
        depth = 1
        args = []
        cur = ''
        in_str = False
        in_chr = False
        esc = False
        while i < len(text):
            c = text[i]
            if in_str:
                cur += c
                if esc:
                    esc = False
                elif c == '\\':
                    esc = True
                elif c == '"':
                    in_str = False
                i += 1
                continue
            if in_chr:
                cur += c
                if esc:
                    esc = False
                elif c == '\\':
                    esc = True
                elif c == "'":
                    in_chr = False
                i += 1
                continue
            if c == '"':
                in_str = True
                cur += c
            elif c == "'":
                in_chr = True
                cur += c
            elif c == '(':
                depth += 1
                cur += c
            elif c == ')':
                depth -= 1
                if depth == 0:
                    args.append(cur)
                    break
                cur += c
            elif c == ',' and depth == 1:
                args.append(cur)
                cur = ''
            else:
                cur += c
            i += 1
        if len(args) >= 3:
            line = text.count('\n', 0, m.start()) + 1
            out.append((line, args[2].strip()))
    return out


def shell_if_conds(path):
    """抽出 shell 脚本里每个 `if` 的条件（⚠ 跨行续行要拼起来）。"""
    out = []
    lines = open(path, encoding='utf-8').read().split('\n')
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith('if ') or s == 'if':
            cond = s[3:] if s.startswith('if ') else ''
            j = i
            while j < len(lines):
                if ';' in cond:
                    break
                j += 1
                if j >= len(lines):
                    break
                cond += ' ' + lines[j].strip()
            # 条件 = 第一个 `;` 之前（含续行）
            cut = cond.find(';')
            if cut >= 0:
                cond = cond[:cut]
            out.append((i + 1, cond.strip()))
            i = j + 1
            continue
        i += 1
    return out


def tautology_reason(cond):
    """这条判据条件是不是「恒真」？是的话**返回原因**，不是就返回 None。

    ⚠⚠ **返回原因而不是布尔** —— 这样调用方不必**再算一遍**：
      若调用方自己重算，判定表达式就会在文件里出现**两次**
      ⇒ 门若按「恰好 1 次」钉它 ⇒ 审计器立刻报配准失准（批 BF 实测踩到）
      ⇒ 而且两份判定迟早会漂。
    ⚠⚠ **自检与实扫必须走同一条判定路径**（否则自检测的不是真判定 ⇒ 假的保证）
    ⇒ 两者都调本函数。
    """
    if not meaningful_idents(cond):
        return '恒真/纯字面量'
    if SHORTCUT.search(cond):
        return '含恒真捷径（|| true / && false）'
    return None


# ⚠⚠ **自检（self-test）**：门自己证明自己有牙。
#   每次运行先拿**合成样例**跑一遍判定 ⇒ 判定逻辑被掏空/改坏 ⇒ 本门当场红。
#   ⚠ 合成样例必须**同时**含「该判为恒真的」与「不该判为恒真的」⇒
#   只测前者 ⇒ 判成「恒真」也能过；只测后者 ⇒ 判成「不是恒真」也能过。
SELF_TEST_CASES = [
    ('true', True),
    ('false', True),
    ('1 == 1', True),
    ('"a" == "a"', True),
    ('ok || true', True),
    ('a && false', True),
    ('ok', False),
    ('env.has_value()', False),
    ('covered && count == expected', False),
]


def self_test():
    """跑合成样例 ⇒ 判定逻辑不对就红。"""
    bad = 0
    for cond, want in SELF_TEST_CASES:
        got = tautology_reason(cond) is not None
        if got != want:
            print('%s探针自检失败：条件 %r 期望 %s，实得 %s'
                  % (ERROR, cond, want, got), file=sys.stderr)
            bad += 1
    return bad


def main():
    if len(sys.argv) < 2:
        print('用法：ci-tautology-check.py <源码根目录>', file=sys.stderr)
        return 2
    root = sys.argv[1].rstrip('/')
    bad = 0
    n_check = 0
    n_if = 0

    # ⚠ ① **先自检**：判定逻辑本身坏了 ⇒ 本门必须红（否则这道门是空门）
    st_bad = self_test()
    if st_bad:
        print('%s判据恒真检查失败：探针自检不过（判定逻辑没有牙）' % ERROR,
              file=sys.stderr)
        return 1

    # ① 判定层 C++：check(…) 的条件不许恒真
    appdir = os.path.join(root, 'src', 'app')
    for fn in sorted(os.listdir(appdir)):
        if not (fn.startswith(JUDGEMENT_PREFIX) and fn.endswith('.cpp')):
            continue
        path = os.path.join(appdir, fn)
        text = open(path, encoding='utf-8').read()
        for line, cond in extract_check_conds(text):
            n_check += 1
            why = tautology_reason(cond)
            if not why:
                continue
            print('%s%s:%d 判据条件是%s：%s'
                  % (ERROR, fn, line, why, cond[:100]), file=sys.stderr)
            bad += 1

    # ② shell 断言脚本：if 的条件不许恒真/恒假
    scripts = os.path.join(root, 'scripts')
    for fn in sorted(os.listdir(scripts)):
        if not fn.endswith('.sh'):
            continue
        path = os.path.join(scripts, fn)
        for line, cond in shell_if_conds(path):
            n_if += 1
            if SH_CONST.match(cond):
                print('%sscripts/%s:%d if 的条件是恒真/恒假：%s'
                      % (ERROR, fn, line, cond[:80]), file=sys.stderr)
                bad += 1

    # ③ python 工具脚本：if 的条件不许恒真/恒假（`if True:` 这类）
    #    ⚠ python 的 if 用**冒号**收尾 ⇒ 单独一条正则口径（不与 shell 混用）。
    for fn in sorted(os.listdir(scripts)):
        if not fn.endswith('.py'):
            continue
        path = os.path.join(scripts, fn)
        for i, ln in enumerate(open(path, encoding='utf-8').read().split('\n'), 1):
            m = PY_CONST_IF.match(ln)
            if m:
                print('%sscripts/%s:%d if 的条件是恒真/恒假：%s'
                      % (ERROR, fn, i, m.group(1)), file=sys.stderr)
                bad += 1
                n_if += 1

    if bad:
        print('%s判据恒真检查失败：%d 处条件被掏空（这些判据永远不会红）'
              % (ERROR, bad), file=sys.stderr)
        return 1
    print('✓ 判据非恒真：判定层 %d 条判据的条件都含被测标识符；'
          'shell 与 python 脚本 %d 个 if 条件都非恒真' % (n_check, n_if))
    return 0


if __name__ == '__main__':
    sys.exit(main())
