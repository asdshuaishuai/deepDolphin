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

# ── 断言函数实参里的判据（批 BG 新增）────────────────────────────────────
# ⚠ **形态（实测，不是猜）**：contract-check.sh 里
#     check <名称> <python表达式（stdin 为 JSON 文本）> [json]
#     check_text <名称> <ERE> <文本>
#   ⇒ **判据就藏在第二个实参里** ⇒ 批 BF 的「if 条件」扫描**根本管不到**。
#   ⚠⚠⚠ **实测取证（批 BG）**：把其中一条 check 的 python 表达式掏空成 `True`
#     ⇒ 契约门仍 **120 passed, 0 failed** ⇒ 批 BC 的「93 处 check 调用不许被删」
#     **不红**（调用点数没变）⇒ 接线门**全绿** ⇒ 那条断言**从此永远不会红**。
#
# ⚠⚠ **实参必须自己解析，不能用正则**（实测踩到的坑）：
#   contract-check.sh:555 的描述里含 `==\"OK\"` ⇒ 正则抽实参会把
#   **描述与表达式粘成一块** ⇒ 判据抽错 ⇒ 门判错。
#   ⇒ 这里自己写一个**尊重引号与转义**的实参解析器。
#
# ⚠ **条数基线（完全相等，批 BB 口径）**：探针解析出的调用点数必须 == 这里的基线
#   ⇒ ① 解析器漂了（悄悄少看几条）⇒ 当场红；② 断言被增删 ⇒ 当场红。
ASSERT_CALL_BASELINE = {
    'contract-check.sh': {'check': 93, 'check_text': 6},
}

# ⚠ ERE 里的「字面字符」—— 没有字面字符的 ERE 匹配一切（`.*` / `^$` / 空串）⇒ 恒真
LITERAL_CHAR = re.compile(r'[^\^\$\.\*\+\?\(\)\[\]\{\}\|\\]')


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


def assert_arg_reason(helper, arg):
    """断言函数**实参里的判据**是不是恒真？是的话**返回原因**，不是就返回 None。

    ⚠⚠ **返回原因而不是布尔**（批 BF 的教训）：调用方若自己再判一次
      ⇒ 那个判定串会在文件里出现**两次** ⇒ 门按「恰好 1 次」钉它 ⇒
      **审计器立刻报配准失准**（批 BG 实测又踩了一次）⇒ 而且两份判定迟早漂。
    - `check` 的第二个实参是 **python 表达式**（作用域里 `d` = 被测 JSON）
      ⇒ 判据**必须引用 `d`** ⇒ 不引用就是「压根没碰被测数据」⇒ 恒真风险。
    - `check_text` 的第二个实参是 **ERE**
      ⇒ 必须含**至少一个字面字符** ⇒ 没有字面字符的 ERE（`.*` / `^$` / 空串）匹配一切。
    """
    if helper == 'check':
        if not re.search(r'\bd\b', arg):
            return '判据不引用被测数据 d（恒真/纯字面量）'
        return None
    if helper == 'check_text':
        if not LITERAL_CHAR.search(arg):
            return 'ERE 匹配一切（没有字面字符）'
        return None
    return None


def assertion_arg_is_tautology(helper, arg):
    """薄封装：自检用（**判定逻辑只有一份** ⇒ 在 assert_arg_reason 里）。"""
    return assert_arg_reason(helper, arg) is not None


def scan_shell(text):
    """把一段 shell 文本切成实参（**尊重引号与转义**）⇒ (tokens, 末尾引号状态)。

    ⚠⚠ **不能用正则抽实参**（实测：contract-check.sh:555 的描述里含 `==\"OK\"`
      ⇒ 正则会把描述与表达式粘成一块 ⇒ 判据抽错 ⇒ 门判错）。
    ⚠⚠⚠ **必须保留空实参**（批 BG 负控 B4 实测）：判据是「**第二个**实参」⇒
      若把空实参（`''`）吞掉 ⇒ `tokens[2]` 会**错位**成第三个实参
      ⇒ 判据抽成别的东西 ⇒ **恒真的空 ERE 判成了合法** ⇒ 漏判。
      ⇒ 所以要区分「**没开始一个 token**」与「**token 内容为空**」⇒ 用 `started`。
    """
    tokens = []
    cur = ''
    started = False       # ⚠ `started` 与 `cur` 分开：空实参也是实参
    state = None          # None / '"' / "'"
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if state == "'":
            if c == "'":
                state = None
            else:
                cur += c
            i += 1
            continue
        if state == '"':
            if c == '\\' and i + 1 < n and text[i + 1] in '"\\$`':
                cur += text[i + 1]
                i += 2
                continue
            if c == '"':
                state = None
            else:
                cur += c
            i += 1
            continue
        if c == '\\' and i + 1 < n:
            if text[i + 1] == '\n':
                cur += ' '
                started = True
                i += 2
                continue
            cur += text[i + 1]
            started = True
            i += 2
            continue
        if c in '"\'':
            state = c
            started = True
            i += 1
            continue
        if c.isspace():
            if started:
                tokens.append(cur)
                cur = ''
                started = False
            i += 1
            continue
        cur += c
        started = True
        i += 1
    if started:
        tokens.append(cur)
    return tokens, state


def find_assert_calls(path, helpers):
    """找出 `check` / `check_text` 这类断言函数的调用点。
    返回 {helper: [(行号, 第2个实参), …]}（⚠ 含跨行续行的调用）。
    """
    lines = open(path, encoding='utf-8').read().split('\n')
    out = {}
    for i, ln in enumerate(lines):
        m = re.match(r'^\s*(%s)\s+' % '|'.join(re.escape(h) for h in helpers), ln)
        if not m:
            continue
        helper = m.group(1)
        # 拼续行（⚠ 只在**引号外**的 `\` 才是续行 ⇒ 用 scan_shell 看引号状态）
        chunk = ln
        j = i
        while True:
            _t, st = scan_shell(chunk)
            if st is None and chunk.rstrip().endswith('\\') and j + 1 < len(lines):
                j += 1
                chunk = chunk.rstrip()[:-1] + ' ' + lines[j].strip()
                continue
            break
        tokens, _st = scan_shell(chunk)
        if len(tokens) < 3:
            continue
        out.setdefault(helper, []).append((i + 1, tokens[2]))
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
#   ⚠ 类别：`cond` = 判定层的判据条件；`assert_arg` = 断言函数实参里的判据。
SELF_TEST_CASES = [
    ('cond', 'true', True),
    ('cond', 'false', True),
    ('cond', '1 == 1', True),
    ('cond', '"a" == "a"', True),
    ('cond', 'ok || true', True),
    ('cond', 'a && false', True),
    ('cond', 'ok', False),
    ('cond', 'env.has_value()', False),
    ('cond', 'covered && count == expected', False),
    ('assert_arg', ('check', 'True'), True),
    ('assert_arg', ('check', '1 == 1'), True),
    ('assert_arg', ('check', "d.get('x')==1"), False),
    ('assert_arg', ('check_text', '.*'), True),
    ('assert_arg', ('check_text', ''), True),
    ('assert_arg', ('check_text', 'arch\\.json'), False),
    # ⚠⚠⚠ **第三类：实参解析器**（批 BG 负控 B4 实测出来的洞）：
    #   判据是「**第二个**实参」⇒ 若解析器把空实参（`''`）吞掉
    #   ⇒ `tokens[2]` 错位成第三个实参 ⇒ 判据抽成别的东西
    #   ⇒ **恒真的空 ERE 被判成合法** ⇒ 漏判。
    #   ⇒ 这条样例直接盯「空实参**在不在**」⇒ 解析器被改坏 ⇒ 自检当场红。
    ('shell_scan', ('check "名" \'\' "$J"', ['check', '名', '', '$J']), True),
]


def self_test():
    """跑合成样例 ⇒ 判定逻辑不对就红。"""
    bad = 0
    for kind, inp, want in SELF_TEST_CASES:
        if kind == 'cond':
            got = tautology_reason(inp) is not None
        elif kind == 'shell_scan':
            # ⚠ 走**同一条**解析路径（自检与实扫必须调同一个 scan_shell）
            text, exp = inp
            toks, _st = scan_shell(text)
            got = (toks == exp)
        else:
            helper, arg = inp
            got = assertion_arg_is_tautology(helper, arg)
        if got != want:
            print('%s探针自检失败：%s %r 期望 %s，实得 %s'
                  % (ERROR, kind, inp, want, got), file=sys.stderr)
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

    # ④ **断言函数实参里的判据**（批 BG 新增）：`check` / `check_text` 的第二个实参
    #    ⚠ 判据就藏在实参里 ⇒ ①②③ 三类扫描**都管不到**（实测：掏空成 `True`
    #    ⇒ 契约门仍 120/0 ⇒ 批 BC 的条数基线门不红 ⇒ 接线门全绿）。
    #    ⚠ **条数交叉校验**：探针解析出的调用点数必须 == 基线 ⇒
    #      ① 解析器漂了（悄悄少看几条）⇒ 当场红；② 断言被增删 ⇒ 当场红。
    n_assert = 0
    for fn, helpers in sorted(ASSERT_CALL_BASELINE.items()):
        path = os.path.join(scripts, fn)
        if not os.path.isfile(path):
            print('%s断言调用基线指向不存在的脚本：scripts/%s' % (ERROR, fn),
                  file=sys.stderr)
            bad += 1
            continue
        found = find_assert_calls(path, helpers.keys())
        for helper, want_n in sorted(helpers.items()):
            got_n = len(found.get(helper, []))
            if got_n != want_n:
                print('%sscripts/%s：%s 调用点解析出 %d 处，基线是 %d 处'
                      '（⚠ 解析器漂了或断言被增删 ⇒ 门会漏看）'
                      % (ERROR, fn, helper, got_n, want_n), file=sys.stderr)
                bad += 1
            for line, arg in found.get(helper, []):
                n_assert += 1
                why = assert_arg_reason(helper, arg)
                if not why:
                    continue
                print('%sscripts/%s:%d %s 的判据是%s：%s'
                      % (ERROR, fn, line, helper, why, arg[:100]), file=sys.stderr)
                bad += 1

    if bad:
        print('%s判据恒真检查失败：%d 处条件被掏空（这些判据永远不会红）'
              % (ERROR, bad), file=sys.stderr)
        return 1
    print('✓ 判据非恒真：判定层 %d 条判据的条件都含被测标识符；'
          'shell 与 python 脚本 %d 个 if 条件都非恒真；'
          '断言函数实参里 %d 条判据都非恒真' % (n_check, n_if, n_assert))
    return 0


if __name__ == '__main__':
    sys.exit(main())
