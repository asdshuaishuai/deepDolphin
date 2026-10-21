#!/usr/bin/env python3
"""ci-wiring-audit.py —— **门自审计**：审「门自己可不可信」。

【为什么需要它 · 第四次同一形状】
接线门判的是「某个串在不在」。⇒ 只要**同一个串在文件里出现不止一次**，
「改掉其中一处」这件事就**骗得过门**：别处还顶着呢。
这个形状在批 AS 之前已经踩了四次：
  · 批 AP —— 串出现在**注释/提示语**里（真接线被摘掉，门照样绿）
  · 批 AQ —— 串出现在**无关的另一行**里
  · 批 AR —— 串**只声明不编译**也算出现
  · 批 AS —— 同一个 `ToolArgs.flag(` 在测试文件里出现 **8 处**，
    负控的变异只动其中 1 处 ⇒ 门不红（负控当场抓到）
前三次都是**事后人工发现** ⇒ 这个工具把「事后」变成「**当场**」：
它逐条数每个门项的正则在目标文件里**命中几次**，命中 >1 ⇒ 报警。

【只审 arch_need，不审 arch_forbid】
arch_forbid 判的是「**不该有的东西没了**」⇒ 它的目标串出现 >0 本来就红，
>1 不是「被别处顶替」的隐患（是更严重的违规）⇒ 不在本工具的职责里。

【审计器自报盲区】
解析 ci-wiring.sh 时若漏掉门项（写法变了、参数换了引号），那部分门就**审不到**
⇒ 审计器自己有洞 ⇒ 比「门被骗过」更隐蔽。
⇒ 本工具比对「文件里各门型的行数」与「解析成功的条数」，
   不等就把差额报出来（**不许静默漏审**）。

【批 AV 扩了覆盖面】
原来只审 `arch_need`（单文件、「出现过即可」）。批 AU 给 `arch_need_min`
（单文件、「至少 N 次」）配了「下限必须 == 实际命中数」校准。
批 AV 把它**扩到全部剩下的门型**：
  · `arch_need_ml` —— 单文件、压行后匹配 ⇒ 现在查「压行后命中 >1」
  · `arch_need_any_count` —— glob 范围、**恰好** N 次 ⇒ 校准「实际 == 期望」
  · `arch_need_any_min` —— glob 范围、**至少** N 次 ⇒ 校准「下限 == 实际命中数」
  · `arch_need_count` —— 单文件、**恰好** N 次 ⇒ 校准「实际 == 期望」
⇒ 至此**五类「要出现」的门全部在校** ⇒ 覆盖缺口清零。

【⚠ 绝不复刻口径 —— 一律「抽取 ci-wiring.sh 的原文来跑」】
批 AS 实测教训：审计器一开始用 **Python 正则复刻**了 `strip_comments`
⇒ **两套实现** ⇒ 迟早漂移 ⇒ 报告里的次数不可信 ⇒ 人会据此做错判断。
⇒ 这里的做法是**从 ci-wiring.sh 里 `sed` 抽出函数原文**，
   拼成临时脚本再调 ⇒ 改门侧口径时审计侧**自动跟着变** ⇒ 零漂移。

用法：
  python3 ci-wiring-audit.py                 # 全量：人读的报告
  python3 ci-wiring-audit.py --list          # 机器可读：`相对路径|正则`（每行一条）
  python3 ci-wiring-audit.py --changed HEAD~1 # 只审 base..HEAD 里**新增**的门项
退出码：
  0 绿 / 2 审计器有盲区或缺文件 / 3 豁免外隐患（命中 >1）/ 4 次数门没配准
  5 正则写法体检不过 / 6 门项总数与基线不符 / 7 审计器自己有重名常量
  8 锚定形态违规（含自检不过）
  9 审计器引用了未定义的名字（改名漏改调用点）/ 锚定豁免基线有坏行
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))   # deepin/scripts
SRC = os.path.dirname(HERE)                        # deepin/（客户端源根）
REPO = os.path.dirname(SRC)                        # 仓根（macos/ 与 deepin/ 同仓）
WIRING = os.path.join(SRC, 'scripts', 'ci-wiring.sh')
# 豁免基线：已知「串不唯一」的历史门项，一行一条。
# ⚠ 键格式 = `<类型>:<相对路径或glob>|<正则>`
#   类型 ∈ {need, ml}（只有这两类会出「命中 >1」的隐患）
# ⚠ **纯数据、零注释**（行首 `#` 会被当成 pattern）⇒ 说明写在别的文件里。
EXEMPT = os.path.join(SRC, 'scripts', 'wiring-multi-hit.exempt')

# ⚠⚠⚨ 批 BN · 「整行锚定」的**豁免基线**（独立文件）——
# ⚠ **键格式 = `<门型>\t<目标相对路径>\t<门项正则>\t<理由>`**（**TAB** 分隔）
#   ⇒ 门项正则里**含 `|`**（如 `(sh|bash|python3) …`）⇒ 不能用 `|` 分隔 ⇒ 用 TAB。
# ⚠ **理由不许为空** ⇒ 空理由 = 无声地豁免一道门 ⇒ 坏行 ⇒ 该门项**不被豁免**
#   ⇒ 照样报红（**fail closed**：坏豁免只会被发现得**更早**，不会更晚）。
ANCHOR_EXEMPT = os.path.join(SRC, 'scripts', 'ci-wiring-anchor.exempt')

# ⚠⚠⚠ **门项行数基线**（批 BH）——
# ⚠ **起因（实测，不是推演）**：把 ci-wiring.sh 里**任意一条门项**改成注释
#   ⇒ 接线门 **rc=0**、审计器 **rc=0**、**CI 全流程 rc=0** ⇒ **全绿**
#   ⇒ 「门项被悄悄删」这件事，**没有任何机制会发现**。
# ⚠ **为什么基线要放在**另一个文件**里（而不是写死在审计器里）：
#   写死 ⇒ 审计器既是「执行者」又是「裁判」⇒ 改审计器就能同时改标准。
#   ⇒ 基线放在**独立文件** ⇒ 删基线文件 ⇒ 门与审计器**双双红**。
GATE_BASELINE = os.path.join(SRC, 'scripts', 'ci-wiring-gates.baseline')
# ⚠⚠⚠ **注意**：这里**不要**再定义 `GATE_LINE` —— 文件下方**已经有一个**
#   `GATE_LINE`（带捕获组，`check_rx_syntax` 在用）⇒ 同名 ⇒ **后者覆盖前者**
#   ⇒ 先定义的那个成了**死代码**。
#   ⚠⚠⚠ **本批自己就踩了这个**（批 AS 起反复出现的那一族：同名互相顶替）——
#   当时定义的 `GATE_LINE` 被下面的同名定义覆盖 ⇒ 它成了死代码 ⇒
#   「物理门项行」的口径用不上它（真正用的是下面那个**不撞名**的常量）⇒
#   ⇒ 差点让**审计器的对拍口径**与实现脱节。
#   ⇒ 现在有「模块级重名自检」（**模块级赋值名不许重复**）当场抓住。
#   ⚠ 物理门项行的口径在下面叫另一个名字（**故意不撞**）。
#   ⚠⚠⚠ **注意**：本文件里的 `#` 注释**也算进** count 族门项的命中数
#     （strip_comments 对 `.py` 只剥 `//`、**不剥 `#`）
#     ⇒ ⚠⚠⚠ **注释里千万别重复写被门盯的常量名** ⇒ 期望值会漂
#     ⇒ ⚠ 本批就因此踩了一次（期望 2、实际 4 ⇒ 门当场报失准）。

# 一行门项：arch_need <路径> '<正则>' '<说明>'
NEED_RE = re.compile(
    r'^\s*arch_need\s+'      # 门类型
    r'"([^"]+)"\s+'           # 目标文件（双引号）
    r"'([^']*)'\s+"           # 正则（单引号）
    r"'([^']*)'"              # 说明
)
# 兜底：目标文件与正则都用单引号
NEED_RE_SQ = re.compile(
    r"^\s*arch_need\s+"
    r"'([^']+)'\s+"
    r"'([^']*)'\s+"
    r"'([^']*)'"
)
# 兜底：说明用双引号（有人改引号就会落进这个分支）
NEED_RE_DQ = re.compile(
    r'^\s*arch_need\s+'
    r'"([^"]+)"\s+'
    r"'([^']*)'\s+"
    r'"([^"]*)"'
)
ANY_NEED_LINE = re.compile(r'^\s*arch_need\b')
ANY_FORBID_LINE = re.compile(r'^\s*arch_forbid\b')
# ⚠ `arch_need_min`（至少 N 次）：**天然**多点 ⇒ 不查「串是否唯一」，
#   但要**校准下限**：下限必须 == 当前命中数。
#   · 下限 < 命中数 ⇒ **门没牙**（删一处仍够 ⇒ 不红）—— 批 AU 实测踩到：
#     `Canvas2D` 在 HeatmapWidget.cpp 里命中 4 次（include + 3 处构造），
#     而下限写的是 3 ⇒ 删掉一处构造仍剩 3 ⇒ 门照样绿。
#   · 下限 > 命中数 ⇒ **门恒红**。
NEED_MIN_LINE = re.compile(
    r'^\s*arch_need_min\s+"([^"]+)"\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠ `arch_need_ml`（单文件、**压行后**匹配）：批 AV 起纳入覆盖
#   —— 压行后命中 >1 ⇒ 改一处骗得过门（实测：`platform::dpiPixmap(` 压行后 2 次）。
ML_LINE = re.compile(
    r'^\s*arch_need_ml\s+"([^"]+)"\s+\'([^\']*)\'\s+')
# ⚠ `arch_need_any_count`（glob 范围、**恰好** N 次）/ `arch_need_any_min`（**至少** N 次）
#   —— 批 AV 起纳入覆盖（它们是「跨文件」门 ⇒ 命中数是**所有匹配文件加总**）。
ANY_COUNT_LINE = re.compile(
    r'^\s*arch_need_any_count\s+\'([^\']*)\'\s+(\d+)\s+\'([^\']*)\'(?:\s+\'([^\']*)\')?\s*$')
ANY_MIN_LINE = re.compile(
    r'^\s*arch_need_any_min\s+\'([^\']*)\'\s+(\d+)\s+\'([^\']*)\'(?:\s+\'([^\']*)\')?\s*$')
# ⚠ `arch_need_count`（单文件、**恰好** N 次）：批 AV 起纳入校准。
COUNT_LINE = re.compile(
    r'^\s*arch_need_count\s+"([^"]+)"\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠ `arch_need_count_in_fn`（**函数体内**恰好 N 次）：它**自己数次数** ⇒ 天然有牙，
#   但「把期望从 1 改成 2 来躲变异」这种手法没人盯 ⇒ 批 AV 起也校准。
#   ⚠ 期望值校准要复刻「切函数体」那段 awk ⇒ **从 ci-wiring.sh 里抽取原文**（零漂移）。
COUNT_IN_FN_LINE = re.compile(
    r'^\s*arch_need_count_in_fn\s+"([^"]+)"\s+\'([^\']*)\'\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠ `arch_need_count_in_step`（**某一步的正文里**恰好 N 次）：批 BE 新门型。
#   它盯的是「这个标记串**还在这一步里**」⇒ 文件级门盯不到的「被挪到别处」由它抓。
#   ⚠ **新门型必须进审计覆盖**（批 AR/AV 纪律：「审计器自己有盲区 ⇒ 那些门根本没被审」）
#   ⇒ 这里加解析 + 配准校准；切步骤正文用的 awk **从 ci-wiring.sh 原文抽取**（零漂移）。
COUNT_IN_STEP_LINE = re.compile(
    r'^\s*arch_need_count_in_step\s+"([^"]+)"\s+(\d+)\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠⚠⚨ 批 BZ · **配对门**（`arch_need_count_pair`）：盯「**报错行数 == 计数行数** == 期望」
#   ⚠ **为什么需要它**（不是推演，是批 BY 留下的**具体**洞）：
#     两个**独立**的「恰好 N 次」门**彼此不知道对方**
#     ⇒ 「新增一条**只报错不计数**的失败路径」（有人新写了一条 `echo "  ✗ …"`
#       却忘了加 `fail=$((fail+1))`）
#     ⇒ 报错门红、计数门绿 ⇒ 人把**报错门**的期望值改大 ⇒ 两门都绿
#     ⇒ 但那条新报错**永远不计数** ⇒ 末尾判定恒真 ⇒ **CI 假绿**
#   ⇒ 必须有**一条**门**同时**盯住两个数 ⇒ 它们的差恒为 0
#   ⚠ **新门型必须进审计覆盖**（批 AR/AV 纪律）⇒ 解析 + 对拍登记 + 期望校准
PAIR_COUNT_LINE = re.compile(
    r'^\s*arch_need_count_pair\s+"([^"]+)"\s+\'([^\']*)\'\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠⚠ **count 族的兜底盲区检测**（批 BE）：
#   `ANY_NEED_LINE`（`arch_need\b`）**匹配不到** count 族（`_` 是单词字符 ⇒ 没有词边界）⇒
#   以前一条**写坏**的 `arch_need_count*` 门项会**静默被忽略** ⇒
#   **审计器审不到它 ⇒ 没人知道它没被审**（批 AR 说的「审计器自己有盲区」）。
#   ⇒ 这里加兜底：凡是 count 族、却没被上面任何一个门型解析到 ⇒ 记成盲区 ⇒ 硬门红。
COUNT_FAMILY_LINE = re.compile(r'^\s*arch_need_count\w*\s')
# ⚠ **函数定义行**长得像门项（`arch_need() { # ...`）⇒ 必须排除，
#   否则审计器把工具自己的定义算成「没解析到的门项」⇒ 假盲区。
FUNC_DEF_LINE = re.compile(r'^\s*arch_\w+\s*\(\)\s*\{')
# ⚠⚠⚠ 批 BH：门型清单 —— 「审计器认出来的门项行数」要能对上「文件里实际的门项行数」
#   ⇒ **每一种门型都要有一条自己的正则** ⇒ 将来新增一种门型而忘了在审计器里登记
#   ⇒ 审计器数出来的门项数会**少于**文件里的实际行数 ⇒ **当场红**（覆盖缺口）。
# ⚠ forbid 家族是**有意不审**（它判「不该有的东西没了」⇒ 目标串出现 >0 本来就红），
#   但**行数仍然要计入** ⇒ 否则「物理行数」对不上 ⇒ 假红。
FORBID_FAMILY = {
    'forbid': re.compile(r'^\s*arch_forbid\s'),
    'forbid_tree': re.compile(r'^\s*arch_forbid_tree\s'),
    'forbid_han': re.compile(r'^\s*arch_forbid_han\s'),
    'forbid_raw': re.compile(r'^\s*arch_forbid_raw\s'),
    'forbid_ml': re.compile(r'^\s*arch_forbid_ml\s'),
    'forbid_text_dup': re.compile(r'^\s*arch_forbid_text_dup\s'),
}

DEFAULT_ANY_GLOB = 'src/app/SelfCheck*.cpp'


def resolve(p):
    p = p.replace('$ROOT', REPO).replace('$SRC', SRC)
    return p.strip('"')


def rel(path):
    try:
        return os.path.relpath(path, REPO)
    except ValueError:
        return path


def strip_comments(path):
    """剥注释 —— ⚠ **直接调 ci-wiring.sh 用的同一条 perl/sed**，不复刻。

    ⚠⚠ **为什么必须用同一条命令**（批 AS 实测踩出来的）：
    审计器一开始用 **Python 正则复刻**了 `ci-wiring.sh` 的 `strip_comments`
    ⇒ **两套实现** ⇒ 迟早漂移。
    漂移的后果很隐蔽：审计器说「唯一」而门说「多处」（或反之）⇒ **豁免基线判错**
    ⇒ 而且**报告里的次数不可信** ⇒ 人会据此做错判断
    （本次实测：临时工具报「命中 2 次」，而手测与 shell 口径都是 4 次
      ⇒ 差点据此以为「4 行 vs 2 次」是矛盾）。
    ⇒ 复刻 = 两套口径 ⇒ **一律改成调同一条命令**。
    """
    # ⚠⚠⚨ **`.py` 也要剥 `#` 注释**（批 BK）：python 的注释是 `#`
    #   ⇒ 不剥 ⇒ **注释里的串会顶替真代码** ⇒ 盯串的门项**假绿**
    #   （实测：真代码换成 `pass  # 串` ⇒ 命中数不变 ⇒ 门照样绿）。
    # ⚠⚠⚨ **两侧必须同步**（门侧 `ci-wiring.sh` 的 `strip_comments` 同款）
    #   ⇒ 不一致 ⇒ 同一串两侧算得不一样 ⇒ 配准校准失准。
    # ⚠ **行首锚定** ⇒ 字符串里的 `#` 不受影响 ⇒ 安全。
    if path.endswith('.sh') or path.endswith('.txt') or path.endswith('.py'):
        cmd = ["sed", "-e", r's/^[[:space:]]*#.*$//']
    else:
        cmd = ["perl", "-pe", r's{(?<!:)(//)(?!:).*$}{}']
    out = subprocess.run(cmd + [path], capture_output=True, text=True)
    return out.stdout


def require_perl():
    """⚠⚠⚨ 批 CF · 剥注释工具的**前提**是 perl 在（审计器与门侧调同一条 perl）。

    ⚠⚠ **以前 perl 缺席时审计器会未捕获异常崩掉**（`FileNotFoundError: 'perl'`）
      ⇒ 退出码 **1** ⇒ 门侧报「**未知的失败码**」⇒ 真实原因（缺 perl）
      **没有任何一条消息提到** ⇒ 排障方向被带偏（诊断失真）。
    ⚠ 现在：**前置检查** ⇒ 缺 perl ⇒ 指名道姓 + 退出码 **2**
      （2 = 审计器有盲区或缺文件 ⇒ 缺 perl ⇒ C++ 侧的门项**根本没被审** ⇒ 正是盲区）
    ⇒ 与批 CB/CC/CD/CE 同款口径：**未验证不许被当成通过**。
    """
    if shutil.which('perl') is None:
        print('审计失败：没有 perl（剥注释工具）⇒ 判据口径无法确定 ⇒ '
              'C++ 侧的门项根本没被审（盲区）', file=sys.stderr)
        return 2
    return 0


def count_hits(path, rx):
    """用 grep -oE 数命中次数（与 arch_need_count 的口径一致）。"""
    if not os.path.isfile(path):
        return None
    text = strip_comments(path)
    try:
        out = subprocess.run(['grep', '-oE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode not in (0, 1):
        return None
    return len([ln for ln in out.stdout.split('\n') if ln])


def count_hits_ml(path, rx):
    """数**压行后**的命中次数（与 arch_need_ml 的口径一致：先剥注释再压成一行）。"""
    if not os.path.isfile(path):
        return None
    text = strip_comments(path).replace('\n', ' ')
    try:
        out = subprocess.run(['grep', '-oE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode not in (0, 1):
        return None
    return len([ln for ln in out.stdout.split('\n') if ln])


# ⚠⚠ **抽取而非复刻**（批 AV 起）：把 ci-wiring.sh 里的 shell 函数**原文**抠出来，
#   拼成临时脚本再调 ⇒ 门侧改了口径，审计侧自动跟着变 ⇒ 零漂移。
def extract_shell_func(name):
    """从 ci-wiring.sh 里 `sed` 抽出名为 <name> 的 shell 函数原文。"""
    out = subprocess.run(
        ['sed', '-n', '/^%s() {/,/^}/p' % re.escape(name), WIRING],
        capture_output=True, text=True)
    return out.stdout


def extract_fn_body_awk():
    """从 `arch_need_count_in_fn` 原文里抠出那段 awk 程序（切函数体用）。"""
    fn = extract_shell_func('arch_need_count_in_fn')
    m = re.search(r"awk -v sig=\"\$sig\" '(.*?)'\)\"", fn, re.S)
    return m.group(1) if m else None


def extract_step_awk():
    """从 `arch_need_count_in_step` 原文里抠出那段 awk 程序（切**步骤正文**用）。

    ⚠⚠ **必须抽取，不许复刻**（批 AV 起的纪律）：审计器自己写一套切段逻辑
      ⇒ 两套口径 ⇒ 迟早漂移 ⇒ 审计器报的次数不可信 ⇒ 人会据此做错判断。
    """
    fn = extract_shell_func('arch_need_count_in_step')
    if not fn:
        return None
    m = re.search(r"awk -v step=\"\$step\" '(.*?)'\)", fn, re.S)
    return m.group(1) if m else None


class AnyCounter(object):
    """批量数「glob 范围内**总命中数**」—— 口径 = ci-wiring.sh 的 `any_hits`（抽取原文）。"""

    def __init__(self, pairs):
        """pairs = [(rx, glob), ...]"""
        self.pairs = list(pairs)
        self.values = {}
        self._run()

    def _script(self):
        parts = ["#!/bin/bash", "SRC=%s" % shlex.quote(SRC)]
        for fn in ('strip_comments', 'any_hits'):
            body = extract_shell_func(fn)
            if not body:
                raise RuntimeError('抽不出 ci-wiring.sh 里的 %s() ⇒ 口径会漂移' % fn)
            parts.append(body)
        for i, (rx, gl) in enumerate(self.pairs):
            parts.append("printf '%d\\t%%s\\n' \"$(any_hits %s %s)\""
                         % (i, shlex.quote(rx), shlex.quote(gl)))
        return '\n'.join(parts) + '\n'

    def _run(self):
        if not self.pairs:
            return
        tmpd = tempfile.mkdtemp(prefix='wiring-audit-')
        try:
            path = os.path.join(tmpd, 'count.sh')
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(self._script())
            out = subprocess.run(['bash', path], capture_output=True, text=True)
            if out.returncode != 0:
                raise RuntimeError('any_hits 批量计数失败：%s' % out.stderr.strip()[:400])
            for ln in out.stdout.split('\n'):
                if '\t' not in ln:
                    continue
                idx, cnt = ln.split('\t', 1)
                try:
                    self.values[int(idx)] = int(cnt.strip())
                except ValueError:
                    continue
            missing = [i for i in range(len(self.pairs)) if i not in self.values]
            if missing:
                raise RuntimeError('any_hits 批量计数少 %d 条 ⇒ 对不上' % len(missing))
        finally:
            shutil.rmtree(tmpd, ignore_errors=True)

    def get(self, rx, gl):
        return self.values.get(self.pairs.index((rx, gl)))


# ⚠⚠⚠ **门型登记处**（批 BH）——「每一种门型一条正则」。
#   ⇒ 审计器**认领**的门项行数（total）必须 == 文件里**实际**的门项行数（物理行数）
#   ⇒ 不等 = **有一种门型没被登记** ⇒ 那些门项**根本没被审**（批 AR 说的「审计器自己有盲区」）。
#   ⇒ ⚠ **将来新增门型时，必须在这里登记一条** ⇒ 忘了登记 ⇒ 当场红。
#   ⚠ 这 14 条正则**互斥**（门型名后要求空白 ⇒ 家族成员之间不会互相命中），
#     且**天然排除函数定义行**（定义行里门型名后是 `(` 不是空白）⇒ 不会把工具自己的
#     定义算成门项。
GATE_TYPES = [
    ('need', ANY_NEED_LINE),
    ('need_ml', ML_LINE),
    ('need_any_count', ANY_COUNT_LINE),
    ('need_any_min', ANY_MIN_LINE),
    ('need_count', COUNT_LINE),
    ('need_count_in_fn', COUNT_IN_FN_LINE),
    ('need_count_in_step', COUNT_IN_STEP_LINE),
    ('need_count_pair', PAIR_COUNT_LINE),
    ('need_min', NEED_MIN_LINE),
] + sorted(FORBID_FAMILY.items())

# ⚠ **物理门项行**的口径：行首（去前导空白）以 `arch_` 开头、**后接空白**
#   ⇒ 与门型知识**完全无关** ⇒ 这是审计器认领数的**独立对拍口径**。
GATE_CALL_LINE = re.compile(r'^\s*arch_\w+\s')


def count_gate_types(path):
    """数门项 ⇒ (各门型条数, 审计器认领总数, 物理门项行数)。

    ⚠⚠ **两个数必须相等**：
      · 「审计器认领总数」= 上面 15 条门型正则各数一遍（互斥 ⇒ 不会重复计数）；
      · 「物理门项行数」= 用**不认识门型**的口径数一遍（只看「长得像门项」）。
      ⇒ 不等 ⇒ **有一种门型没被登记** ⇒ 那些门项**没被审**（批 BH 抓的就是这个）。
    """
    src = open(path, encoding='utf-8').read()
    lines = src.split('\n')
    counts = {}
    for name, rx in GATE_TYPES:
        # ⚠⚠ **必须排除函数定义行**（`arch_need() { …}`）：
        #   `ANY_NEED_LINE`（`arch_need\b`）里 `\b` 允许后接 `(` ⇒ 定义行**会被它命中**
        #   ⇒ 不排除就把「工具自己的定义」算成门项 ⇒ 与物理行数对不上。
        #   ⚠ `FUNC_DEF_LINE` 已改成通用版（`arch_\w+`）⇒ 覆盖**所有**门型的定义行。
        counts[name] = sum(1 for ln in lines
                           if rx.match(ln) and not FUNC_DEF_LINE.match(ln))
    total = sum(counts.values())
    physical = sum(1 for ln in lines if GATE_CALL_LINE.match(ln))
    return counts, total, physical


def read_gate_baseline():
    """读门项行数基线文件 ⇒ (数字, 错误原因)。

    ⚠⚠ **基线文件里不许写注释**（门项会管）⇒ 这里**直接读原文**，
      不走 strip_comments ⇒ 门侧（strip_comments）与审计侧（原文）看到的是同一行。
    """
    path = GATE_BASELINE
    if not os.path.isfile(path):
        return None, '基线文件不存在：%s' % path
    raw = open(path, encoding='utf-8').read()
    txt = raw.strip()
    if not txt:
        return None, '基线文件是空的'
    if not txt.isdigit():
        return None, '基线文件内容不是纯数字：%r' % txt
    if len(raw.strip().split('\n')) != 1:
        return None, '基线文件不止一行'
    return int(txt), None


def check_dup_module_names():
    """模块级赋值名不许重复（同名 ⇒ 后定义覆盖先定义 ⇒ 先那个成了**死代码**）。

    ⚠⚠⚠ **为什么要有这条**（本批自己踩出来的，不是推演）：
      本批加「物理门项行」口径时用的常量名**撞了**文件下方已有的同名常量
      ⇒ 后者覆盖前者 ⇒ 前者成了**死代码** ⇒ 差点让**对拍口径**与实现脱节
      （而且**没有任何门会红** ⇒ 因为「串还在」，只是不生效了）。
      ⚠ 这一族（「同名互相顶替」）从批 AS 起反复出现 ⇒ 值得让机器盯。
    ⚠ **只看模块级赋值**（函数内的局部同名是正常的）⇒ 用 ast 精确判定，
      不用正则（正则分不清「赋值」和「比较」）。
    """
    import ast
    with open(os.path.abspath(__file__), encoding='utf-8') as fh:
        tree = ast.parse(fh.read())
    seen = {}
    dups = []
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for t in node.targets:
            if not isinstance(t, ast.Name):
                continue
            if t.id in seen:
                dups.append((t.id, seen[t.id], node.lineno))
            else:
                seen[t.id] = node.lineno
    return dups


def check_gate_totals():
    """核门项行数 ⇒ 结果字典。

    ⚠⚠ **判定逻辑只有一份**（批 BF/BG 纪律）：硬门模式与报告模式**都调它**
      ⇒ 报告里印的数就是硬门判的数 ⇒ 两边不会漂。
    ⚠⚠ **两条核对，互补**：
      ① 「审计器认领的门项数」==「文件里实际的门项行数」
         ⇒ 不等 = **有一种门型没在门型清单里登记** ⇒ 那些门项**根本没被审**
           （批 AR 说的「审计器自己有盲区」）⇒ 退出码 2（盲区）。
      ② 「文件里实际的门项行数」==「基线文件里的数字」
         ⇒ 不等 = **有门项被删了 / 被改成注释了** ⇒ 那些承诺**没人守了**
           ⇒ 退出码 6（门项总数失配）。
    """
    gcounts, gtotal, gphysical = count_gate_types(WIRING)
    gbase, gwhy = read_gate_baseline()
    msgs = []
    blind = False
    total_bad = False
    # ⚠⚠⚠ **模块级重名**（本批自己踩出来的洞）⇒ 排在**最前**：
    #   有重名 ⇒ 那个常量是**死代码** ⇒ 下面的核对可能**用错常量** ⇒
    #   ⇒ 必须先说「审计器自己有洞」，再说别的。
    dups = check_dup_module_names()
    if dups:
        blind = True
        for name, first, second in dups:
            msgs.append('审计器有**重名常量**：`%s` 在第 %d 行与第 %d 行各定义一次'
                        ' ⇒ 后者覆盖前者 ⇒ **前者是死代码**'
                        % (name, first, second))
    if gtotal != gphysical:
        blind = True
        msgs.append('审计器有门型盲区：认领 %d 条 vs 文件里实际 %d 条门项行'
                    ' ⇒ 有门型没登记 ⇒ 那些门项**不会被审**'
                    % (gtotal, gphysical))
    if gbase is None:
        total_bad = True
        msgs.append('门项行数基线不可用：%s' % gwhy)
    elif gphysical != gbase:
        total_bad = True
        msgs.append('门项行数与基线不符：文件里 %d 条 vs 基线 %d 条'
                    ' ⇒ **有门项被删了 / 被改成注释了** ⇒ 那些承诺**没人守了**'
                    % (gphysical, gbase))
    return {
        'counts': gcounts, 'claimed': gtotal, 'physical': gphysical,
        'baseline': gbase, 'baseline_why': gwhy,
        'blind': blind, 'total_bad': total_bad, 'dups': dups, 'msgs': msgs,
    }


def parse_wiring():
    """解析 ci-wiring.sh ⇒ (need 门项, ml 门项, any_count 门项, any_min 门项,
    count 门项, count_in_fn 门项, count_in_step 门项, 各门型行数,
    解析失败行号, arch_forbid 行数)"""
    src = open(WIRING, encoding='utf-8').read()
    lines = src.split('\n')
    need, ml, anyc, anym, cnt, cif, cis, pair = [], [], [], [], [], [], [], []
    totals = {'need': 0, 'ml': 0, 'any_count': 0, 'any_min': 0,
              'count': 0, 'count_in_fn': 0, 'count_in_step': 0,
              'count_pair': 0}
    failed, forbid_lines = [], 0
    for i, ln in enumerate(lines, 1):
        if ANY_FORBID_LINE.match(ln) and not FUNC_DEF_LINE.match(ln):
            forbid_lines += 1
        if FUNC_DEF_LINE.match(ln):
            continue
        if ANY_NEED_LINE.match(ln):
            totals['need'] += 1
            m = NEED_RE.match(ln) or NEED_RE_SQ.match(ln) or NEED_RE_DQ.match(ln)
            if not m:
                failed.append((i, 'need'))
                continue
            need.append((i, resolve(m.group(1)), m.group(2)))
            continue
        if ML_LINE.match(ln):
            totals['ml'] += 1
            m = ML_LINE.match(ln)
            ml.append((i, resolve(m.group(1)), m.group(2)))
            continue
        if ANY_COUNT_LINE.match(ln):
            totals['any_count'] += 1
            m = ANY_COUNT_LINE.match(ln)
            anyc.append((i, m.group(1), int(m.group(2)), m.group(4) or DEFAULT_ANY_GLOB))
            continue
        if ANY_MIN_LINE.match(ln):
            totals['any_min'] += 1
            m = ANY_MIN_LINE.match(ln)
            anym.append((i, m.group(1), int(m.group(2)), m.group(4) or DEFAULT_ANY_GLOB))
            continue
        if COUNT_LINE.match(ln):
            totals['count'] += 1
            m = COUNT_LINE.match(ln)
            cnt.append((i, resolve(m.group(1)), m.group(2), int(m.group(3))))
            continue
        if COUNT_IN_STEP_LINE.match(ln):
            totals['count_in_step'] += 1
            m = COUNT_IN_STEP_LINE.match(ln)
            cis.append((i, resolve(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4))))
            continue
        if COUNT_IN_FN_LINE.match(ln):
            totals['count_in_fn'] += 1
            m = COUNT_IN_FN_LINE.match(ln)
            cif.append((i, resolve(m.group(1)), m.group(2), m.group(3), int(m.group(4))))
            continue
        if PAIR_COUNT_LINE.match(ln):
            totals['count_pair'] += 1
            m = PAIR_COUNT_LINE.match(ln)
            pair.append((i, resolve(m.group(1)), m.group(2), m.group(3),
                         int(m.group(4))))
            continue
        if COUNT_FAMILY_LINE.match(ln):
            # ⚠⚠ 走到这里 = 这一行**没被任何 count 门型解析到** ⇒ 审计器有盲区
            #   （批 BE：写坏的 count 族门项以前是**静默忽略** ⇒ 没人知道它没被审）
            failed.append((i, 'count-family'))
            continue
    return (need, ml, anyc, anym, cnt, cif, cis, pair,
            totals, failed, forbid_lines)


def changed_lines(base):
    """git diff base..HEAD 里 ci-wiring.sh 的**新增行行号**集合。"""
    try:
        out = subprocess.run(
            ['git', '-C', REPO, 'diff', '--unified=0', '%s..HEAD' % base,
             '--', 'deepin/scripts/ci-wiring.sh'],
            capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode != 0:
        return None
    nums = set()
    for ln in out.stdout.split('\n'):
        m = re.match(r'^@@ -\S+ \+(\d+)(?:,(\d+))? @@', ln)
        if not m:
            continue
        start = int(m.group(1))
        cnt = int(m.group(2) or '1')
        for k in range(cnt):
            nums.add(start + k)
    return nums


def read_exempt():
    """读豁免基线 ⇒ (集合, 文件是否存在, 行数)

    ⚠ **跳过 `#` 开头的行与空行** ⇒ 基线文件可以带说明注释
    （否则注释行会被当成 pattern 去 grep 整行匹配 ⇒ 误排除）。
    """
    if not os.path.isfile(EXEMPT):
        return set(), False, 0
    with open(EXEMPT, encoding='utf-8') as fh:
        lines = [ln.rstrip('\n') for ln in fh]
    keys = set(ln for ln in lines if ln.strip() and not ln.lstrip().startswith('#'))
    return keys, True, len(keys)


def check_min_gates(min_items):
    """校准 `arch_need_min` 的下限：必须 **== 当前命中数**。

    ⚠ 下限 < 命中数 ⇒ **门没牙**（删一处仍够 ⇒ 不红）——
      批 AU 实测踩到：`Canvas2D` 在 HeatmapWidget.cpp 里命中 4 次
      （include + 3 处构造），下限写 3 ⇒ 删掉一处构造仍剩 3 ⇒ 门照样绿。
    ⚠ 下限 > 命中数 ⇒ **门恒红**。
    ⇒ 这条校准把「`arch_need_min` 不在审计覆盖内」那个缺口补上了一半：
      它的「串不唯一」是**语义允许**的，但**下限必须配得准**。
    """
    bad = []
    for lineno, f, rx, want in min_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        got = count_hits(f, rx)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '下限 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def count_lines(path, rx):
    """数**行数**（`grep -cE` 口径）⇒ 与 `arch_need_count_pair` 的门**完全一致**。

    ⚠⚠ 与 `count_hits`（`grep -oE` ⇒ 数**出现次数**）**故意不同**：
      配对门盯的是「有**几行**涉及报错 / 计数」⇒ 一行里写两次只算 1 行。
    ⚠ `grep -c` 无命中时**退出码是 1**（但仍打印 "0"）⇒ 两种退出码都算正常。
    """
    if not os.path.isfile(path):
        return None
    text = strip_comments(path)
    try:
        out = subprocess.run(['grep', '-cE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode not in (0, 1):
        return None
    try:
        return int(out.stdout.strip() or '0')
    except ValueError:
        return None


def check_pair_count_gates(pair_items):
    """校准 `arch_need_count_pair`：**报错行数**与**计数行数**都必须 == 期望。

    ⚠ 口径与门一致（**行数**）⇒ 一行里写两次只算 1 行。
    ⚠ 期望 < 实际 ⇒ 门**没牙**；期望 > 实际 ⇒ 门**恒红**。
    ⚠ 两个数**不等** ⇒ 存在「**只报错不计数**」的失败路径 ⇒ 假绿 ⇒ 必须红。
    """
    bad = []
    for lineno, f, ra, rb, want in pair_items:
        rx_desc = '%s | %s' % (ra, rb)
        if not os.path.isfile(f):
            bad.append((lineno, f, rx_desc, want, None, '文件不存在'))
            continue
        na = count_lines(f, ra)
        nb = count_lines(f, rb)
        if na is None or nb is None:
            continue
        if na != want or nb != want:
            why = ('期望 报错 %d 且 计数 %d ⇒ 实际 报错 %d / 计数 %d ⇒ %s'
                   % (want, want, na, nb,
                      '**两者不等 ⇒ 存在「只报错不计数」的失败路径 ⇒ 假绿**'
                      if na != nb else '两个数都与期望不符 ⇒ 门恒红/没牙'))
            bad.append((lineno, f, rx_desc, want,
                        '报错 %d / 计数 %d' % (na, nb), why))
    return bad


def check_count_gates(count_items):
    """校准 `arch_need_count` 的期望次数：必须 **== 当前命中数**。

    ⚠ 期望 < 实际 ⇒ 门**没牙**（删一处仍够 ⇒ 不红）；
      期望 > 实际 ⇒ 门**恒红**。
    ⚠ 这条门自己数次数 ⇒ 天然有牙，但「把期望改大来躲变异」没人盯 ⇒ 这里补上。
    """
    bad = []
    for lineno, f, rx, want in count_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        got = count_hits(f, rx)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '期望 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


# ⚠⚠⚨ 批 BL/BM/BN/BR · 「整行锚定」的**适用范围**（单一真相源）──────────────────
#
# ⚠⚠⚨ **起因（批 BJ 负控坐实，批 BK 根治了一半）**：
#   门项盯**串** ⇒ 判定被掏空但**串还在** ⇒ 门照样绿。
#   例：把 `if bad:` 改成 `if bad or True:` ⇒ 串还在 ⇒ 盯串的门**假绿**
#   ⇒ 而 `if bad:` 正是**探针「违规 ⇒ 判红」的那一行** ⇒ 掏空它 = 探针集体失效。
# ⚠⚠⚨ 批 BK 根治了「**注释顶替代码**」（`.py` 也剥 `#`）
#   ⇒ 但「**判定被掏空、串还在**」这一头仍只靠**整行锚定**挡。
# ⚠⚠⚨ **适用范围 = 「哪些文件的门项必须整行锚定」**（批 BM 扩到审计器自身，
#   批 BN 再扩到 `ci.sh`，**批 BR 再扩到 `ci-wiring.sh`**）：
#   · `ci-tautology-check.py` / `ci-wiring-audit.py` —— 「门自己的工具」
#     ⇒ 它被掏空 = 门**集体**失效 ⇒ 风险最高。
#   · `ci.sh` —— **CI 入口本体** ⇒ 它的判定被掏空 ⇒ CI 整条流水线失信
#     ⇒ 风险与「门自己的工具」同级。
#   · `ci-wiring.sh` —— **门脚本本体**（批 BR）⇒ 它的门项就是
#     「**判定层不许被掏空**」那一整类承诺的**载体** ⇒ 载体被掏空 = 承诺集体失效
#     ⇒ 风险与「门自己的工具」同级 ⇒ 本批把它那 5 条非锚定门项改成精确形式。
#   · **5 个 CI 里跑的断言脚本**（批 BS：`ci-platform-probe.sh` /
#     `ci-docs-lang-probe.sh` / `ci-divider-probe.sh` /
#     `probe-agent-tool-surface.sh` / `ci-orphan-probe.sh`）
#     ⇒ 它们的门项盯的正是**探针自己的判定行** ⇒ 判定被掏空 = 那批断言静默失效
#     ⇒ ⇒ 批 BS 把其中 10 条改成**整行锚定**，5 条「真报错行」条数门**显式豁免**
#     （行尾是自由文本 ⇒ 锚定会改窄语义 ⇒ 登记在豁免表里，不是漏网）。
#   ⚠ 全仓其余门项仍逐批推进（已知边界，如实记着）。
#   ⚠⚠ **C++ 判定层的门项仍刻意保持「盯串」**（批 BR 判定，如实记着）：
#     那些门项的承诺是「**这个 API 必须在某处被调用**」（**调用点**承诺）
#     ⇒ 整行锚定会把它**改窄**成「这一种整行形态」⇒ 合法重构就会断门
#     ⇒ ⇒ **锚定只对「判定行/定义行」承诺有意义**，不对「调用点」承诺有意义。
#     ⇒ 且 C++ 侧「判定被掏空」的另一半（`|| true` 之类）**另有探针**兜着
#     （恒真探针的捷径规则）⇒ 不是没有防线。
# ⚠⚠⚨ **改名记录**（批 BN）：`GATE_TOOL_SUFFIXES` → `ANCHOR_SCOPE_SUFFIXES`
#   ⇒ 名字里的 `GATE_TOOL` 已经不副实（范围不再只是「门自己的工具」）
#   ⇒ ⚠ **改名必须连带改掉所有引用点**（批 BM 就是漏了一处 ⇒ 报告模式崩
#   ⇒ 见 `check_undefined_names` 的说明）⇒ 所以本批同时加了那道静态检查。
ANCHOR_SCOPE_SUFFIXES = ('ci-tautology-check.py', 'ci-wiring-audit.py', 'ci.sh', 'ci-wiring.sh', 'ci-platform-probe.sh', 'ci-docs-lang-probe.sh', 'ci-divider-probe.sh', 'probe-agent-tool-surface.sh', 'ci-orphan-probe.sh', 'check-deb-layout.sh', 'contract-check.sh', 'ci-d2.sh', 'smoke.sh', 'bootstrap-deps.py')


def has_unbounded_wildcard(mid):
    """中段里有没有**未被转义**的「点星」（无界通配）⇒ 中间什么都能吃。

    ⚠⚠⚨ **批 BQ 实测坐实的洞**：整行锚定只看「行首 `^`」+「行尾 `$`」
      ⇒ 中间放一个**点星** ⇒ 行首行尾锚死、**中间什么都能吃**
      ⇒ ⇒ 「判定被掏空但串还在」这一类洞照样躲过门
      ⇒ ⇒ 「整行锚定」**名存实亡**。
      实测：原表形态门项 `^\\s+\\(.*,\\s*(True|False)\\),$` 就是这种写法
      ⇒ 样例表的内容随便改都照样命中 ⇒ 门是假的。
    ⚠ **只认未被转义的**：`.` 前面**偶数**个反斜杠 ⇒ 这个 `.` 是通配的元字符
      ⇒ 配 `*` 就是无界通配；**奇数**个 ⇒ `.` 被转义 ⇒ 是字面点（`\\.\\*`）⇒ 放行。
    ⚠ **有界通配放行**（如 `[^,]*`）：它吃不掉引号/逗号这类**结构分隔符**
      ⇒ 行结构仍被钉住 ⇒ 与无界通配不是一回事。
    ⚠ **已知边界（如实记着）**：字符类**内部**的点星（如 `[.*]`）会被当成通配
      ⇒ 假红（fail closed 方向 ⇒ 不漏 ⇒ 只是误报）。
    """
    i = mid.find('.*')
    while i >= 0:
        nb = 0
        j = i - 1
        while j >= 0 and mid[j] == '\\':
            nb += 1
            j -= 1
        if nb % 2 == 0:
            return True
        i = mid.find('.*', i + 2)
    return False


def anchoring_violation(rx):
    """判定一个门项正则**是不是整行锚定**（`^` 开头且 `$` 结尾，且**中间不许无界通配**）。

    ⚠⚠⚨ **判定逻辑只有一份**（批 BF/BG 纪律）⇒ 实扫与自检**都走它**。
    ⚠⚠⚨ **返回「原因」而不是布尔**（批 BJ 纪律：判定函数返回原因）
      ⇒ 调用方不再自己算一遍 ⇒ 判定串不会在源码里出现两次
      ⇒ 门项盯它时不会「命中两次」而对不上期望次数。
    ⚠⚠⚨ **批 BQ**：只看 `^` + `$` **不够** ⇒ 中间放无界通配 ⇒ 整行锚定名存实亡
      ⇒ 第 4 步（`has_unbounded_wildcard`）把这一头堵上。
    """
    if not rx.startswith('^'):
        return '行首没有 ^ 锚点 ⇒ 盯的是串 ⇒ 判定被掏空但串还在 ⇒ 门假绿'
    if not rx.endswith('$'):
        return '行尾没有 $ 锚点 ⇒ 盯的是串 ⇒ 判定被掏空但串还在 ⇒ 门假绿'
    # ⚠⚠⚨ **批 BS 实测坐实的假红**（本批自己撞上的，不是推演）：
    #   原判据是 `rx.endswith('\\$')`（末两字符是 `\$`）
    #   ⇒ ⚠⚠⚨ **但 `\\$`（转义的反斜杠 + 行尾锚点）也被误判成「被转义」**
    #   ⇒ 合法的整行锚定门项被红 ⇒ 逼着人把门项**写弱**。
    #   ⇒ ⚠⚠⚨ **假红比假绿更坏**：假绿是承诺悄悄消失；假红是**逼人把承诺改弱**
    #   （本批就撞上了：一条要钉住「行尾反斜杠」的合法门项被红 ⇒ 只好去改弱它）。
    #   ⇒ 改成**数反斜杠个数**（**奇数** = 这个 `$` 被转义）
    #   ⇒ 与 `has_unbounded_wildcard` 的同款奇偶口径一致（批 BQ）。
    nb = 0
    j = len(rx) - 2
    while j >= 0 and rx[j] == '\\':
        nb += 1
        j -= 1
    if nb % 2 == 1:
        return '行尾的 $ 是被转义的 ⇒ 不算行尾锚点'
    if has_unbounded_wildcard(rx[1:-1]):
        return '中间有无界通配（点星）⇒ 行首行尾锚死但中间什么都能吃 ⇒ 判定被掏空但串还在 ⇒ 门假绿'
    return None


def anchoring_selftest():
    """自检：让门**自己证明自己有牙**（合成样例）。

    ⚠⚠⚨ 样例必须**既含「该判为违规」也含「不该判为违规」**（批 BF 纪律）
      ⇒ 只有「该违规」的样例 ⇒ 「永远判违规」也能过 ⇒ 自检没牙。
    ⚠⚠⚨ **自检必须放在最前**（批 BI 纪律）：放在后面 ⇒ 前面的检查一红就 exit
      ⇒ 自检永远没机会跑 ⇒ 形同虚设。
    """
    cases = [
        # ⚠⚠⚨ 样例行的**行尾不许有注释** ⇒ 门项要用 `^\s+\(r\.[^,]*, (True|False)\),$`
        #   **整行**数样例条数 ⇒ 行尾注释会让 `$` 锚不上 ⇒ 计数失准（批 BQ 实测踩到）。
        # ⚠ 样例文本里**不许有逗号** ⇒ 同上（`[^,]*` 会被逗号截断）。
        # 纯盯串 ⇒ 必须判违规
        (r'def X\(', True),
        # 只有行首 ⇒ 必须判违规
        (r'^\s+if bad:', True),
        # 整行锚定 ⇒ 必须判合规
        (r'^def X\(foo\):$', False),
        # 整行锚定 ⇒ 必须判合规
        (r'^\s+if bad:$', False),
        # ⚠⚠⚨ 批 BQ：中间有无界通配 ⇒ 行首行尾锚死但中间什么都能吃
        #   ⇒ 「整行锚定」名存实亡 ⇒ 必须判违规
        (r'^\s+if bad:.*$', True),
        # ⚠ 有界通配（吃不掉结构分隔符）⇒ 行结构仍被钉住 ⇒ 必须判合规
        (r'^\s+if \w+:$', False),
        # ⚠ 转义的点星（字面点星）⇒ 不是通配 ⇒ 必须判合规
        (r'^\s+if \.\*:$', False),
        # ⚠⚠⚨ 批 BS：末尾的 `$` **被转义** ⇒ 它是字面美元号、不是行尾锚点 ⇒ 必须判违规
        (r'^\s+if bad:\$', True),
        # ⚠⚠⚨ 批 BS：**转义的反斜杠 + 行尾锚点**（`\\$`）⇒ 它**是**锚点 ⇒ 必须判合规
        #   ⚠⚠⚨ 这条样例是**批 BS 自己撞出来的假红的护栏**：原判据按「末两字符是 `\$`」
        #   ⇒ 把 `\\$` 误判成「被转义」⇒ 合法门项被红 ⇒ 逼人把门项改弱。
        (r'^\s+if bad:\\$', False),
    ]
    bad = []
    for rx, should in cases:
        got = anchoring_violation(rx) is not None
        if got != should:
            bad.append((rx, should, got))
    return bad


def read_anchor_exempt():
    """读「整行锚定」的豁免基线 ⇒ (键集合, 文件是否存在, 条数, 坏行列表)

    ⚠⚠⚨ **键 = (门型, 相对路径, 正则)** —— 三者合起来才唯一：
      只用「路径+正则」不够 ⇒ 同一个正则可能被**不同门型**用（如 `arch_need`
      与 `arch_need_count` 都盯 `--color-sample`）⇒ 豁免会**跨门型漏过去**。
    ⚠⚠⚨ **比较时 rstrip**（正则**尾部空格**在文本文件里极难保持）
      ⇒ 豁免文件里写 `› [0-9]+/15`（无尾空格）也要能命中门项里的
      `› [0-9]+/15 `（有尾空格）⇒ **两边都 rstrip 后再比**。
    ⚠ **纯数据、零注释**（行首 `#` 会被当成 pattern）⇒ 说明写在别的文件里。
    ⚠ **理由不许为空** ⇒ 空理由 ⇒ 坏行 ⇒ **不豁免**（fail closed）。
    """
    if not os.path.isfile(ANCHOR_EXEMPT):
        return set(), False, 0, []
    keys = set()
    bad = []
    with open(ANCHOR_EXEMPT, encoding='utf-8') as fh:
        for lineno, raw in enumerate(fh, 1):
            ln = raw.rstrip('\n')
            if not ln.strip() or ln.lstrip().startswith('#'):
                continue
            parts = ln.split('\t')
            if len(parts) != 4:
                bad.append((lineno, '字段数 %d（应为 4：门型<TAB>路径<TAB>正则<TAB>理由）'
                            % len(parts)))
                continue
            kind, path, rx, why = parts[0].strip(), parts[1].strip(), parts[2], parts[3].strip()
            if not kind or not path or not rx.strip():
                bad.append((lineno, '门型/路径/正则不许为空'))
                continue
            if not why:
                bad.append((lineno, '**豁免理由不许为空**'))
                continue
            # ⚠ **只 rstrip，不 strip** ⇒ 正则的**前导空格是有意义的**
            #   （`^ foo` 与 `foo` 是两条不同的正则）⇒ 不能顺手 strip 掉。
            keys.add((kind, path, rx.rstrip()))
    return keys, True, len(keys), bad


def is_anchor_exempted(kind, relpath, rx, exempt):
    """这条门项是否在「整行锚定」的豁免基线里。

    ⚠ **rstrip 后比较**（见 `read_anchor_exempt` 的说明）。
    """
    return (kind, relpath, rx.rstrip()) in exempt


def check_anchor_exempt_reconcile(need_exempt, exempt):
    """豁免表里的每一条都必须对得上**一条「需要豁免」的门项**（反向配准）。

    ⚠⚠⚨ **为什么要有这条**（豁免表 = 「**被允许弱化的门项**」白名单）：
      表里的一行 = 一个**弱化点** ⇒ 弱化点必须**有对应物**。
      ⇒ 出现一条**对不上**的行，只有三种可能，**都要红**：
        (a) 门项被删了 / 被改写了，**却忘了清豁免** ⇒ 那个承诺**悄悄消失**
            （⚠ 批 BH 的洞：门项被删 ⇒ 没人守了 ⇒ 但门项总数基线只能挡「总数」，
              挡不住「删一条 + 换一条等量的」）；
        (b) 有人塞了条**空豁免**（对不上任何需要豁免的门项）⇒ 豁免表在说谎
            ⇒ 以后谁看到「表里有 N 条」会以为「有 N 个弱化点」⇒ **误判覆盖率**；
        (c) 有人给一条**已经锚定**的门项加了豁免 ⇒ 这条豁免**不弱化任何东西**
            ⇒ 却是白占一行 ⇒ 豁免表在**悄悄变长** ⇒ 「表里的条数 = 弱化点数」
            这条等式被破坏 ⇒ **必须红**（否则「不许悄悄变长」就没钉死）。
    ⚠⚠⚨ **对标的是「非锚定门项」而不是「任何门项」** ⇒ (c) 才抓得住
      （若只对标「任何门项」⇒ 给已锚定门项加豁免照样混过去 ⇒ 这道门没牙）。
    """
    dead = []
    for kind, path, rx in sorted(exempt):
        if (kind, path, rx.rstrip()) not in need_exempt:
            dead.append((kind, path, rx))
    return dead


def check_undefined_names():
    """查「**引用了但没定义**」的名字（改名漏改调用点 ⇒ NameError）。

    ⚠⚠⚨ **为什么要有这条**（批 BN 实测坐实，**不是推演**）：
      批 BM 把 `check_probe_gate_anchoring` 改名成 `check_gate_tool_anchoring`
      ⇒ **漏改了报告模式（无参）那处调用点** ⇒ 报告模式一跑就 `NameError` 崩掉。
      ⚠ 而 CI **只跑 `--list`** ⇒ 报告模式**根本没人跑** ⇒ 这个崩**没人发现**
      ⇒ 一路带到了已推送的 HEAD。
      ⇒ 静态上「**引用了未定义的名字**」是**能抓到的**（symtable 实测能抓到那个名字）。
    ⚠ 只查**模块级未定义名**（函数内的局部名不算）⇒ 用 `symtable` 精确判定。
    ⚠ **只查「函数里引用的全局名」** ⇒ 模块顶层的引用在 import 时就会炸 ⇒ 不必查。
    """
    import symtable
    path = os.path.abspath(__file__)
    with open(path, encoding='utf-8') as fh:
        src = fh.read()
    top = symtable.symtable(src, path, 'exec')
    defined = set(top.get_identifiers())
    import builtins
    builtins_set = set(dir(builtins))
    missing = []

    def walk(tbl):
        for sym in tbl.get_symbols():
            name = sym.get_name()
            if (sym.is_global() and not sym.is_assigned()
                    and name not in defined and name not in builtins_set):
                missing.append((tbl.get_name(), name))
        for child in tbl.get_children():
            walk(child)

    walk(top)
    return missing


def check_anchor_scope(cnt_items, exempt):
    """盯**适用范围**内的 `arch_need_count` 门项必须**整行锚定**（或被显式豁免）。

    ⚠ 只查 `arch_need_count`（单文件、整行匹配）⇒ `arch_need_count_in_fn`
      / `_in_step` 盯的是**函数体内/步骤内**的标记串（跨行是常态）⇒ 不要求。
    ⚠⚠⚨ **也不查裸 `arch_need`**（「至少 1 次」门）—— **不是漏掉，是语义不许**：
      `arch_need` 的语义是「这个串**出现在任何位置**」⇒ 整行锚定会把它
      **改窄**成「这个串出现在这一种整行形态」⇒ 语义被改窄 = 门变弱
      ⇒ 与「期望 0 次」的白名单门**同一类**（见豁免基线里的理由）。
      ⇒ 且 `ci.sh` 上每条 `arch_need` 都已有**对位的 `arch_need_count` 整行锚定门**
      ⇒ 覆盖面不丢。
    ⚠⚠⚨ **适用范围由 `ANCHOR_SCOPE_SUFFIXES` 一个常量说了算**（单一真相源）
      ⇒ 改一处就废掉另一处 ⇒ 那条门项守着它。
    ⚠ **豁免是「显式列举 + 必须写理由 + 坏行不豁免」** ⇒ 不是「随便放过」。
    ⚠⚠⚨ 返回 **(违规列表, 「需要豁免」的集合)**：
      「需要豁免」= 适用范围内**没锚定**的门项键（门型, 路径, 正则）
      ⇒ 它就是**豁免表的唯一合法来源** ⇒ 正向（不豁免就红）与反向（豁免对不上就红）
      双向配准 ⇒ **豁免表 ≡「非锚定门项」集合** ⇒ 条数是**推导出来的**
      （⇒ 少一处可以被人偷偷改的地方 ⇒ 也不必另写一个条数基线）。
    """
    bad = []
    need_exempt = set()
    for lineno, f, rx, want in cnt_items:
        if not f.endswith(ANCHOR_SCOPE_SUFFIXES):
            continue
        why = anchoring_violation(rx)
        if not why:
            continue
        key = ('arch_need_count', rel(f), rx.rstrip())
        need_exempt.add(key)
        if is_anchor_exempted(key[0], key[1], key[2], exempt):
            continue
        bad.append((lineno, rel(f), rx, why))
    return bad, need_exempt


def check_count_in_fn_gates(cif_items):
    """校准 `arch_need_count_in_fn` 的期望次数（函数体内）。

    ⚠ 切函数体的那段 awk **从 ci-wiring.sh 原文抽取** ⇒ 零漂移。
    """
    awk_src = extract_fn_body_awk()
    if awk_src is None:
        return []
    bad = []
    for lineno, f, sig, rx, want in cif_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, sig, rx, want, None, '文件不存在'))
            continue
        out = subprocess.run(
            ['awk', '-v', 'sig=' + sig, awk_src],
            input=strip_comments(f), capture_output=True, text=True)
        body = out.stdout
        if not body.strip():
            bad.append((lineno, f, sig, rx, want, None, '找不到函数体'))
            continue
        r = subprocess.run(['grep', '-oE', '--', rx], input=body,
                           capture_output=True, text=True)
        got = len([x for x in r.stdout.split('\n') if x])
        if got != want:
            bad.append((lineno, f, sig, rx, want, got,
                        '期望 %d ≠ 函数体内实际 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def check_count_in_step_gates(cis_items):
    """校准 `arch_need_count_in_step` 的期望次数：必须 == **该步正文里**的实际命中数。

    ⚠⚠ **切步骤正文的那段 awk 从 ci-wiring.sh 原文抽取** ⇒ 零漂移
      （门侧改了切段口径，审计侧自动跟着变 ⇒ 不会两套口径打架）。
    ⚠ 期望值被改大来躲变异（例如 1 改成 2）⇒ 这里立刻报「没配准」⇒ 红。
    """
    awk_src = extract_step_awk()
    if awk_src is None:
        return []
    bad = []
    for lineno, f, step, rx, want in cis_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        out = subprocess.run(
            ['awk', '-v', 'step=%d' % step, awk_src],
            input=strip_comments(f), capture_output=True, text=True)
        body = out.stdout
        if not body.strip():
            bad.append((lineno, f, rx, want, None,
                        '抽不出第 %d 步的正文（打点行没找到？）' % step))
            continue
        r = subprocess.run(['grep', '-oE', '--', rx], input=body,
                           capture_output=True, text=True)
        got = len([x for x in r.stdout.split('\n') if x])
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '第 %d 步正文里期望 %d ≠ 实际 %d ⇒ %s'
                        % (step, want, got, '门没牙（挪走仍够）' if got > want else '门恒红')))
    return bad


def check_any_gates(anyc_items, anym_items, counter):
    """校准跨文件的两个门型：
      · `arch_need_any_count`：实际总命中 == 期望
      · `arch_need_any_min`：下限 == 实际总命中（否则门没牙/恒红）

    ⚠ **总命中数** = glob 范围内**所有**匹配文件命中数**加总**
      —— 跨文件多现**同样是洞**（批 AV 实测的老 `arch_need_any` 洞就在这）。
    """
    bad = []
    for lineno, rx, want, gl in anyc_items:
        got = counter.get(rx, gl)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, 'any_count', gl, rx, want, got,
                        '期望 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    for lineno, rx, want, gl in anym_items:
        got = counter.get(rx, gl)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, 'any_min', gl, rx, want, got,
                        '下限 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def main():
    # ⚠⚠⚨ 批 CF · **环境前提**（不是检查项）：剥注释工具必须在。
    #   ⇒ 缺它时审计器压根跑不动 ⇒ 与其崩在栈里（退出码 1 = 未知的失败码），
    #     不如**指名道姓**地说清楚（批 CB/CC/CE：未验证不许被当成通过）。
    _rp = require_perl()
    if _rp != 0:
        return _rp
    args = sys.argv[1:]
    want_list = '--list' in args
    want_list_all = '--list-all' in args
    base = None
    if '--changed' in args:
        i = args.index('--changed')
        base = args[i + 1] if i + 1 < len(args) else 'HEAD~1'

    (need, ml, anyc, anym, cnt, cif, cis, pair,
     totals, failed, forbid_lines) = parse_wiring()

    # ⚠⚠⚨ 批 BN · 「整行锚定」的豁免基线（**先读** ⇒ 后面两处判定共用同一份）
    anchor_exempt, anchor_exempt_exists, anchor_exempt_rows, anchor_exempt_bad = \
        read_anchor_exempt()

    if base is not None:
        nums = changed_lines(base)
        if nums is None:
            print('审计失败：git diff %s 拿不到' % base, file=sys.stderr)
            return 2
        need = [x for x in need if x[0] in nums]
        ml = [x for x in ml if x[0] in nums]
        anyc = [x for x in anyc if x[0] in nums]
        anym = [x for x in anym if x[0] in nums]
        cnt = [x for x in cnt if x[0] in nums]
        cif = [x for x in cif if x[0] in nums]
        cis = [x for x in cis if x[0] in nums]

    # ⚠ 跨文件命中数：一次批量算（口径 = 抽取自 ci-wiring.sh 的 any_hits）
    pairs = [(rx, gl) for _, rx, _, gl in anyc] + [(rx, gl) for _, rx, _, gl in anym]
    try:
        counter = AnyCounter(pairs)
    except RuntimeError as e:
        print('审计失败：%s' % e, file=sys.stderr)
        return 2

    multi, zero = [], []
    for lineno, f, rx in need:
        if not os.path.isfile(f):
            zero.append((lineno, f, rx, '文件不存在'))
            continue
        n = count_hits(f, rx)
        if n is None:
            continue
        if n == 0:
            zero.append((lineno, f, rx, '命中 0 次'))
        elif n > 1:
            multi.append((lineno, f, rx, n))

    mlmulti = []
    for lineno, f, rx in ml:
        if not os.path.isfile(f):
            zero.append((lineno, f, rx, '文件不存在'))
            continue
        n = count_hits_ml(f, rx)
        if n is None:
            continue
        if n == 0:
            zero.append((lineno, f, rx, '命中 0 次'))
        elif n > 1:
            mlmulti.append((lineno, f, rx, n))

    # 豁免键：`<类型>:<相对路径|glob>|<正则>`
    keys = ['need:%s|%s' % (rel(f), rx) for _, f, rx, _ in multi]
    keys += ['ml:%s|%s' % (rel(f), rx) for _, f, rx, _ in mlmulti]
    exempt, exempt_exists, exempt_rows = read_exempt()
    outside = [k for k in keys if k not in exempt]
    stale = [k for k in exempt if k not in set(keys)]

    if want_list_all:
        for k in keys:
            print(k)
        return 0

    if want_list:
        # ⚠⚠⚨ 批 BN · 审计器**自己**引用了未定义的名字 ⇒ **改名漏改调用点**
        #   ⚠ 放在**最前**：这是「审计器自身能不能跑」的前置条件
        #     ⇒ 它坏了 ⇒ 后面所有检查的结果都不可信。
        undef = check_undefined_names()
        if undef:
            print('审计器**引用了未定义的名字**（%d 处）⇒ **改名漏改了调用点**'
                  % len(undef), file=sys.stderr)
            for scope, name in undef:
                print('  · 作用域 %s ⇒ %s' % (scope, name), file=sys.stderr)
            print('  ⇒ 改名时**所有**引用点都要一起改；本批的 `check_undefined_names` '
                  '就是为「漏改」而设的', file=sys.stderr)
            return 9
        # ⚠⚠⚨ 批 BN · 豁免基线**坏行**必须红（理由为空 / 字段数不对）
        #   ⚠ **fail closed**：坏行 ⇒ **不豁免** ⇒ 对应门项照红
        #   ⇒ 但坏行本身也要报出来 ⇒ 否则人只会看到「门红」而不知道「豁免文件坏了」
        if anchor_exempt_bad:
            print('锚定豁免基线里有**坏行**（%d 条）⇒ 这些行**没有豁免任何门项**'
                  % len(anchor_exempt_bad), file=sys.stderr)
            for lineno, why in anchor_exempt_bad:
                print('  · %s 第 %d 行：%s'
                      % (os.path.relpath(ANCHOR_EXEMPT, REPO), lineno, why),
                      file=sys.stderr)
            return 9
        if not anchor_exempt_exists:
            print('锚定豁免基线文件不在：%s' % ANCHOR_EXEMPT, file=sys.stderr)
            return 9
        # ⚠⚠⚨ 批 BL · 锚定形态**自检**（放在**最前**：批 BI 纪律——
        #   自检放在后面 ⇒ 前面的检查一红就 exit ⇒ 自检永远没机会跑 ⇒ 形同虚设）
        stbad = anchoring_selftest()
        if stbad:
            print('锚定形态自检不过（%d 条）⇒ **判定逻辑被掏空了**'
                  % len(stbad), file=sys.stderr)
            for rx, should, got in stbad:
                print('  · 正则=%s  期望判违规=%s  实际判违规=%s'
                      % (rx, should, got), file=sys.stderr)
            return 8
        # ⚠⚠⚨ 批 BL/BN · 适用范围（含 `ci.sh`）内的门项必须**整行锚定**
        #   （探针与审计器是「门自己的工具」⇒ 它被掏空 = 门**集体**失效）
        #   ⚠ 第二返回值 = 「需要豁免」的门项集合（= 豁免表的唯一合法来源）
        anchbad, anchor_need = check_anchor_scope(cnt, anchor_exempt)
        if anchbad:
            print('适用范围内的门项**不是整行锚定**（%d 条）⇒ 判定被掏空但串还在 ⇒ 门假绿'
                  % len(anchbad), file=sys.stderr)
            for lineno, f, rx, why in anchbad:
                print('  · %s:%d  %s  %s'
                      % (os.path.basename(WIRING), lineno, f, rx), file=sys.stderr)
                print('      ⇒ %s' % why, file=sys.stderr)
            return 8
        # ⚠⚠⚨ 批 BN · 豁免表**反向配准**（正向在上面的 `check_anchor_scope` 里：
        #   适用范围内的非锚定门项若没被豁免 ⇒ 照红 ⇒ rc=8）
        #   ⚠ 只在**全量**模式下做（`--changed` 只审新增门项 ⇒ 「需要豁免」的集合
        #     不全 ⇒ 反向配准会**误报**「对不上」⇒ 与门项总数核对同一口径）
        if base is None:
            dead = check_anchor_exempt_reconcile(anchor_need, anchor_exempt)
            if dead:
                print('锚定豁免基线里有**对不上「需要豁免」的门项**的条目（%d 条）⇒ '
                      '要么门项被删/被改写却忘了清豁免（承诺悄悄消失），'
                      '要么塞了空豁免，要么给已锚定的门项白占了行（豁免表在悄悄变长）'
                      % len(dead), file=sys.stderr)
                for kind, path, rx in dead:
                    print('  · %s  %s  %s' % (kind, path, rx), file=sys.stderr)
                return 9
        # ⚠⚠⚠ **门项总数核对**（批 BH）——「门项被悄悄删」此前**无人发现**。
        #   ⚠ 只在**全量**模式下做（--changed 只审新增门项 ⇒ 门项总数本就不全）
        if base is None:
            # ⚠⚠⚠ **门项总数核对**（批 BH）——「门项被悄悄删」此前**无人发现**。
            #   ⚠ 只在**全量**模式下做（--changed 只审新增门项 ⇒ 门项总数本就不全）
            #   ⚠ 判定逻辑在 `check_gate_totals()` 里（**只有一份** ⇒ 报告与硬门不漂）
            g = check_gate_totals()
            if g['dups']:
                for m in g['msgs']:
                    print(m, file=sys.stderr)
                return 7
            if g['blind']:
                for m in g['msgs']:
                    print(m, file=sys.stderr)
                return 2
            if g['total_bad']:
                for m in g['msgs']:
                    print(m, file=sys.stderr)
                return 6
        # 硬门模式：只吐**豁免之外**的隐患；有 ⇒ 退出码 3（红）
        if not exempt_exists:
            print('豁免基线文件不在：%s' % EXEMPT, file=sys.stderr)
            return 2
        if failed:
            # ⚠ **审计器自己有盲区 ⇒ 那些门根本没被审** ⇒ 必须红。
            #   否则「审不到的门项」就成了逃逸口（批 AR「只声明不编译也算出现」的同构：
            #   判据写在那里，却没有任何机制保证它**真的被检查**）。
            # ⚠⚠⚨ **一个退出码有两种原因**（批 BM 负控 H2 实测撞出）：
            #   ① 真的**有门项没解析到**（盲区）；
            #   ② **门型对拍的判定被掏空**（`if gtotal != gphysical:` 变成
            #      `if gtotal != gphysical or True:` ⇒ 恒真 ⇒ **恒走 blind 分支**
            #      ⇒ 明明没有盲区也报「盲区」）。
            #   ⇒ 两者**现象相同**（都走这一支）⇒ **不能只报一种** ⇒ 会带偏排障。
            print('审计器有盲区：%d 行门项没解析到（%s）⇒ 它们**没被审**'
                  % (len(failed), ','.join('%d行/%s' % x for x in failed)), file=sys.stderr)
            print('  ⚠⚠⚨ 注意：也可能是「**门型对拍的判定被掏空**」（`if gtotal != gphysical:` '
                  '被改成 `… or True:` ⇒ 恒真 ⇒ 恒走这一支 ⇒ **明明没有盲区也报盲区**）'
                  ' ⇒ 这时看的是**次数门配准**那条（rc=4，指名道姓是哪条门项命中 0）',
                  file=sys.stderr)
            return 2
        # ⚠⚠⚠ **门项正则的写法体检**（批 AX）：正则里写了 GNU grep -E **不认**的转义
        #   （`\d` / `\D`）⇒ 那条门**永远匹配不到任何东西** ⇒ **门形同虚设**。
        #   ⚠ 对 `arch_forbid` 门这是**静默**失效（forbid 本来就常年绿 ⇒ 写坏了跟没写一样）。
        rxsyn = check_rx_syntax()
        if rxsyn:
            print('门项正则里有 grep -E **不认**的转义（%d 条）⇒ 这些门**永远匹配不到**'
                  % len(rxsyn), file=sys.stderr)
            for lineno, kind, rx, be in rxsyn:
                print('  · %s:%d  [%s] 正则=%s  危险转义=%s'
                      % (os.path.basename(WIRING), lineno, kind, rx,
                         ','.join(t for _, t in be)), file=sys.stderr)
            print('  ⇒ 改用 POSIX 写法：`\\d` → `[0-9]`、`\\D` → `[^0-9]`', file=sys.stderr)
            return 5
        # ⚠⚠ **「命中 0 次」也是红**（批 AX 补的第二个盲区）：
        #   `arch_need` / `arch_need_ml` 的语义是「**必须存在**这个串」
        #   ⇒ 命中 0 次 = 门永远匹配不到 = 门是空的。
        #   （这两类门在 ci-wiring.sh 里自己就会红 ⇒ 不是静默失效；
        #     但在**提交前**由审计器明确指出「哪条门是空的」比让 CI 报一堆 ✗ 更好。）
        if zero:
            print('有门项**命中 0 次**（%d 条）⇒ 那些门**永远匹配不到**（形同虚设）'
                  % len(zero), file=sys.stderr)
            for lineno, f, rx, why in zero:
                print('  · %s:%d  %s  %s | %s'
                      % (os.path.basename(WIRING), lineno, why, rel(f), rx), file=sys.stderr)
            return 5
        # ⚠ 次数门的**配准校准**（下限/期望 必须 == 实际命中数）
        minbad = []
        for lineno, f, rx, want in parse_min_gates():
            if not os.path.isfile(f):
                minbad.append((lineno, f, rx, want, None, '文件不存在'))
                continue
            got = count_hits(f, rx)
            if got is None:
                continue
            if got != want:
                minbad.append((lineno, f, rx, want, got,
                               '下限 %d ≠ 实际命中 %d ⇒ %s'
                               % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
        cntbad = check_count_gates(cnt)
        cifbad = check_count_in_fn_gates(cif)
        cisbad = check_count_in_step_gates(cis)
        pairbad = check_pair_count_gates(pair)
        anybad = check_any_gates(anyc, anym, counter)
        bad_all = minbad + cntbad + cifbad + cisbad + pairbad + anybad
        if bad_all:
            print('次数门没配准（%d 条）：' % len(bad_all), file=sys.stderr)
            for b in bad_all:
                if b[1] == 'any_count' or b[1] == 'any_min':
                    _, kind, gl, rx, want, got, why = b
                    print('  · %s:%d  [%s] %s | %s ⇒ %s'
                          % (os.path.basename(WIRING), _, kind, gl, rx, why),
                          file=sys.stderr)
                elif len(b) == 6:
                    lineno, f, rx, want, got, why = b
                    print('  · %s:%d  %s | %s ⇒ %s'
                          % (os.path.basename(WIRING), lineno, rel(f), rx, why),
                          file=sys.stderr)
                else:
                    lineno, f, sig, rx, want, got, why = b
                    print('  · %s:%d  %s  fn=%s | %s ⇒ %s'
                          % (os.path.basename(WIRING), lineno, rel(f), sig, rx, why),
                          file=sys.stderr)
            return 4
        for k in outside:
            print(k)
        return 3 if outside else 0

    print('门自审计：ci-wiring.sh 里的门项')
    print('  arch_need %d 条 / arch_need_ml %d 条 / arch_need_any_count %d 条 / '
          'arch_need_any_min %d 条' % (totals['need'], totals['ml'],
                                        totals['any_count'], totals['any_min']))
    print('  arch_need_count %d 条 / arch_need_count_in_fn %d 条'
          % (totals['count'], totals['count_in_fn']))
    print('  arch_need_count_in_step %d 条（批 BE 新门型：盯「标记串**还在这一步里**」）'
          % totals['count_in_step'])
    print('  arch_need_count_pair %d 条（批 BZ 新门型：盯「**报错行数 == 计数行数**」）'
          % totals['count_pair'])
    print('（arch_forbid 门项 %d 条**有意不审**：它判「不该有的东西没了」，'
          '目标串出现 >0 本来就红，不属于「被别处顶替」的隐患）' % forbid_lines)
    # ⚠⚠⚠ 门项行总数（批 BH）：三个数摆在一起 ⇒ 差在哪一眼看得出
    g = check_gate_totals()
    print('门项行总数：文件里 **%d** 条（审计器认领 %d 条）｜基线 %s'
          % (g['physical'], g['claimed'],
             ('%d' % g['baseline']) if g['baseline'] is not None
             else ('**不可用（%s）**' % g['baseline_why'])))
    for m in g['msgs']:
        print('  ⚠ %s' % m)
    if failed:
        print('⚠ **审计器有盲区**：有 %d 行门项没解析到（%s）'
              % (len(failed), ','.join('%d行/%s' % x for x in failed)))
        print('   ⇒ 这些门**审不到**（写法变了？）⇒ 审计器本身要改，不能静默漏审')
    rxsyn = check_rx_syntax()
    print('门项正则写法体检（grep -E 认不认）：%d 条危险' % len(rxsyn))
    for lineno, kind, rx, be in rxsyn:
        print('  · %s:%d  [%s] 正则=%s  危险转义=%s'
              % (os.path.basename(WIRING), lineno, kind, rx,
                 ','.join(t for _, t in be)))
    if rxsyn:
        print('   ⇒ 这些门**永远匹配不到**（形同虚设）⇒ 改用 POSIX 写法（`\\d` → `[0-9]`）')
    if base is not None:
        print('（只审 %s..HEAD 的新增门项）' % base)

    # ⚠⚠⚨ 批 BL/BN · 报告段也要说（无参模式只出报告、退出码恒 0 ⇒ 判红必须用 --list）
    # ⚠⚠⚨ 批 BN · ⚠ **这里曾是一个真 bug**（批 BM 改名 `check_probe_gate_anchoring`
    #   → `check_gate_tool_anchoring` 时**漏改了这一处**）⇒ 无参模式一跑就
    #   `NameError` 崩掉 ⇒ 而 CI **只跑 `--list`** ⇒ 这条路径**没人跑**
    #   ⇒ 崩了**没人发现** ⇒ 一路带到了已推送的 HEAD。
    #   ⇒ 现在：① 这里用**同一个**函数名（不再各写各的）；② 加了
    #   `check_undefined_names()` **静态**抓「改名漏改」（见该函数说明）。
    anchrep, anchor_need_rep = check_anchor_scope(cnt, anchor_exempt)
    print('适用范围内的门项**整行锚定**：%d 条违规（豁免基线 %d 条）'
          % (len(anchrep), anchor_exempt_rows))
    for lineno, f, rx, why in anchrep:
        print('  · %s:%d  %s  %s' % (os.path.basename(WIRING), lineno, f, rx))
        print('      ⇒ %s' % why)
    undefrep = check_undefined_names()
    print('审计器**引用了未定义的名字**：%d 处' % len(undefrep))
    for scope, name in undefrep:
        print('  · 作用域 %s ⇒ %s' % (scope, name))
    if anchor_exempt_bad:
        print('锚定豁免基线**坏行**：%d 条（这些行没有豁免任何门项）'
              % len(anchor_exempt_bad))
        for lineno, why in anchor_exempt_bad:
            print('  · 第 %d 行：%s' % (lineno, why))
    deadrep = check_anchor_exempt_reconcile(anchor_need_rep, anchor_exempt)
    print('锚定豁免基线**对不上「需要豁免」的门项**的条目：%d 条' % len(deadrep))
    for kind, path, rx in deadrep:
        print('  · %s  %s  %s' % (kind, path, rx))
    print('arch_need 命中 >1 次 ⇒ **改一处骗得过门**：%d 条' % len(multi))
    for lineno, f, rx, n in multi:
        mark = '（已豁免）' if 'need:%s|%s' % (rel(f), rx) in exempt else '**⇒ 硬门会红**'
        print('  · %s:%d  命中 %d 次  %s  %s'
              % (os.path.basename(WIRING), lineno, n, rel(f), mark))
        print('      正则：%s' % rx)
    print('arch_need_ml 压行后命中 >1 次 ⇒ **改一处骗得过门**：%d 条' % len(mlmulti))
    for lineno, f, rx, n in mlmulti:
        mark = '（已豁免）' if 'ml:%s|%s' % (rel(f), rx) in exempt else '**⇒ 硬门会红**'
        print('  · %s:%d  命中 %d 次  %s  %s'
              % (os.path.basename(WIRING), lineno, n, rel(f), mark))
        print('      正则：%s' % rx)

    print('豁免基线：%d 条（文件：%s）'
          % (len(exempt), os.path.relpath(EXEMPT, REPO) if exempt_exists else '**缺失**'))
    if not exempt_exists:
        print('  ⚠ 豁免基线文件缺失 ⇒ 硬门会红')
    print('豁免之外（**新加的门不许落进这里**）：%d 条' % len(outside))
    for k in outside:
        print('  · %s' % k)

    minbad = check_min_gates(parse_min_gates())
    print('arch_need_min 下限校准（须 == 实际命中数）：%d 条失准' % len(minbad))
    for lineno, f, rx, want, got, why in minbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    cntbad = check_count_gates(cnt)
    print('arch_need_count 期望校准（须 == 实际命中数）：%d 条失准' % len(cntbad))
    for lineno, f, rx, want, got, why in cntbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    cifbad = check_count_in_fn_gates(cif)
    print('arch_need_count_in_fn 期望校准（须 == 函数体内实际次数）：%d 条失准' % len(cifbad))
    for lineno, f, sig, rx, want, got, why in cifbad:
        print('  · %s:%d  %s  fn=%s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), sig, rx, why))

    cisbad = check_count_in_step_gates(cis)
    print('arch_need_count_in_step 期望校准（须 == **该步正文里**实际次数）：%d 条失准'
          % len(cisbad))
    for lineno, f, rx, want, got, why in cisbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    pairbad = check_pair_count_gates(pair)
    print('arch_need_count_pair 期望校准（须 **报错行数 == 计数行数** == 期望）：%d 条失准'
          % len(pairbad))
    for lineno, f, rx, want, got, why in pairbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    anybad = check_any_gates(anyc, anym, counter)
    print('arch_need_any_count / arch_need_any_min 配准校准：%d 条失准' % len(anybad))
    for b in anybad:
        _, kind, gl, rx, want, got, why = b
        print('  · %s:%d  [%s] %s | %s ⇒ %s'
              % (os.path.basename(WIRING), _, kind, gl, rx, why))

    if stale:
        print('豁免基线里**已失效**（门已收紧，可以清掉）：%d 条' % len(stale))
        for k in stale:
            print('  · %s' % k)
    print('命中 0 次 ⇒ **门本身就是红的**：%d 条' % len(zero))
    for lineno, f, rx, why in zero:
        print('  · %s:%d  %s  %s' % (os.path.basename(WIRING), lineno, why, rel(f)))
        print('      正则：%s' % rx)
    return 0


def parse_min_gates():
    """解析所有 `arch_need_min` 门项 ⇒ [(行号, 文件, 正则, 下限)]"""
    out = []
    src = open(WIRING, encoding='utf-8').read()
    for i, ln in enumerate(src.split('\n'), 1):
        m = NEED_MIN_LINE.match(ln)
        if m:
            out.append((i, resolve(m.group(1)), m.group(2), int(m.group(3))))
    return out


# ⚠⚠⚠ **门项正则的「写法体检」**（批 AX）——
# ⚠ **起因（本批实测抓到）**：门是用 `grep -E` 匹配的 ⇒ 只有 **GNU grep -E 认的**
#   转义才有效。实测（GNU grep 3.11）：
#     `\s` `\S` `\w` `\W` `\b` **都有效**（GNU 扩展），
#     ⚠⚠ **`\d` / `\D` 无效**（那是 `grep -P` 的 Perl 扩展）⇒
#     写了 `\d` 的门 **永远匹配不到任何东西** ⇒ **门形同虚设**。
# ⚠⚠ **为什么这是「静默」失效（比批 AS 那种更隐蔽）**：
#   · `arch_need` 门写坏了 ⇒ 匹配不到 ⇒ **门自己会红** ⇒ CI 能发现（不算静默）；
#   · ⚠ **`arch_forbid` 门写坏了 ⇒ 永远零命中 ⇒ 永远绿** ⇒
#     **没有任何信号** ⇒ 而 forbid 门判的正是「不该有的东西没了」⇒
#     这类门**本来就是绿的** ⇒ 写坏了跟没写一样 ⇒ **静默**。
#     （本批实测：仓里现有 forbid 门**一条都没写坏** ⇒ 批 AP 那 11 条
#      「不许再开 1x 位图」的门**是真门**，不是空门。）
# ⇒ 下面这项检查把「写坏了」当场抓出来。
#
# ⚠ **只列实测确认无效的**（`\s`/`\S`/`\w`/`\W`/`\b` 都有效 ⇒ 不许误报）。
BAD_ESCAPES = ('d', 'D')


def split_args(rest):
    """把门项行的参数部分切成列表（支持 '…' 与 "…" 两种引号；引号本身不入参）。"""
    args, cur, i, q = [], '', 0, None
    while i < len(rest):
        c = rest[i]
        if q:
            if c == q:
                q = None
            else:
                cur += c
        else:
            if c in "'\"":
                q = c
            elif c.isspace():
                if cur:
                    args.append(cur)
                    cur = ''
            else:
                cur += c
        i += 1
    if cur:
        args.append(cur)
    return args


# 门型 → **正则参数**在参数列表里的下标（0-based）。
# ⚠ `arch_forbid_han`（盯内容不看写法）与 `arch_forbid_text_dup`（盯重复文本）没有正则参数。
RX_ARG_IDX = {
    'arch_need': 1, 'arch_need_ml': 1, 'arch_need_min': 1,
    'arch_need_count': 1, 'arch_need_count_in_fn': 2,
    # ⚠ 批 BE 新门型：<文件> <步号> <正则> <期望次数> ⇒ 正则在第 3 个参数（index 2）
    'arch_need_count_in_step': 2,
    'arch_need_any_count': 0, 'arch_need_any_min': 0,
    'arch_forbid': 1, 'arch_forbid_ml': 1, 'arch_forbid_raw': 1,
    'arch_forbid_tree': 0,
}
GATE_LINE = re.compile(r'^\s*(arch_[a-z_]+)\s+(.*)$')


def bad_escapes(rx):
    """找出「**单个**反斜杠 + d/D」的位置 —— GNU grep -E 不认 ⇒ 门永远匹配不到。

    ⚠ `\\\\d`（**两个**反斜杠）是「字面反斜杠 + d」⇒ 合法，不算。
    ⇒ 判据 = 「连续反斜杠数为**奇数**」⇒ 最后一个反斜杠是转义符。
    """
    out = []
    i = 0
    while i < len(rx):
        if rx[i] == '\\':
            j = i
            while j < len(rx) and rx[j] == '\\':
                j += 1
            n = j - i
            if j < len(rx) and rx[j] in BAD_ESCAPES and n % 2 == 1:
                out.append((i, '\\' + rx[j]))
            i = j
        else:
            i += 1
    return out


def check_rx_syntax():
    """体检**所有**门项的正则参数 ⇒ [(行号, 门型, 正则, 危险转义)]"""
    bad = []
    src = open(WIRING, encoding='utf-8').read()
    for i, ln in enumerate(src.split('\n'), 1):
        m = GATE_LINE.match(ln)
        if not m:
            continue
        kind, rest = m.group(1), m.group(2)
        idx = RX_ARG_IDX.get(kind)
        if idx is None:
            continue
        args = split_args(rest)
        if len(args) <= idx:
            continue
        rx = args[idx]
        be = bad_escapes(rx)
        if be:
            bad.append((i, kind, rx, be))
    return bad


if __name__ == '__main__':
    sys.exit(main())
