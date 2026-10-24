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
  0 绿 / 2 审计器有盲区或缺文件 / **或有门型没登记在正则体检登记册里
     （那一族门项的正则从来没被体检过）/ 或有判定函数被掏空** / 3 豁免外隐患（命中 >1）/ 4 次数门没配准
  5 正则写法体检不过 / 6 门项总数与基线不符 / 7 审计器自己有重名常量
  8 锚定形态违规（含自检不过）
  9 审计器引用了未定义的名字（改名漏改调用点）/ 锚定豁免基线有坏行
    / **或门型清单与正则体检登记册对不上（漏登记）**
"""
import ast
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
# ⚠⚠⚨ 批 EB · **审计器自己的源码路径**（「静默跳过」规则要扫它 ⇒ 路径要**可被门钉住**）
AUDIT_SELF = os.path.join(HERE, 'ci-wiring-audit.py')
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

# ⚠⚠⚨ 批 CR · **门项条数的第二个记录**（判据层的承诺不许被「惯常动作」掩护）
#   ⇒ ⚠⚠⚨ **实测坐实的洞**（不是推演）：删掉一条门项行 **且** 把基线文件 -1
#     ⇒ 审计器 rc=0、接线门 rc=0、✗ 行数 0 ⇒ **全绿** ⇒ 承诺**悄悄消失**
#   ⇒ 「基线放独立文件」（上面已写）**不够**：基线文件**自己**也是可改的
#     ⇒ 「删门项 + 改基线」是**两个协同编辑** ⇒ 躲得过
#   ⇒ 本批：**同一件事记三遍**（基线文件 / 本常量 / 门项里那个数字）
#     ⇒ 改其中任意一边 ⇒ 另外两边对不上 ⇒ **红**
#   ⇒ ⚠ **不宣称完全堵死**（四处协同编辑仍能躲过）⇒ 但成本从 2 处升到 4 处、
#     跨 2 个文件 ⇒ **极显眼** ⇒ 惯常动作不再是掩护
#   ⇒ ⚠⚠⚨ 名字**故意不叫** `GATE_BASELINE_EXPECTED`（那太像上面的路径常量
#     `GATE_BASELINE` ⇒ 批 AS 的「同名互相顶替 / 看错」那一族）
GATE_LINES_EXPECTED = 1498
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
# ⚠⚠⚨ 批 EF 新门型：`arch_need_count_ml`（**跨行**、**恰好** N 次）
#   ⇒ ⇒ 段级 trailer 的「判定 ⇒ 报红 ⇒ 记全局红过」是**跨行**的关系
#   ⇒ ⇒ 按行匹配的 count 门盯不住 ⇒ ⇒ 「判定被掏空但那几行还在」⇒ 假绿
COUNT_ML_LINE = re.compile(
    r'^\s*arch_need_count_ml\s+"([^"]+)"\s+\'([^\']*)\'\s+(\d+)\s+')
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

# ⚠⚠⚨ 批 CQ · **失败态收集器**（判据层「先红遮后红」不许再遮）
#   ⇒ 以前硬门模式里是 **15 个顺序 `return N` 早退** ⇒ 同时有两处问题时
#     **先红的那个 rc 遮住后面的**（实测：rc=6「条数与基线不符」遮住 rc=4「次数失准」）
#   ⇒ 现在：每一处失败**记进这里**、**继续往下跑** ⇒ 末尾**一次报全**
#   ⇒ ⚠ **rc 仍取最先失败的那个**（`FAILS[0]`）⇒ **门侧分诊表零改动**（码值语义不变）
#   ⇒ ⚠ 模块级是**故意**的：`main()` 的兜底 except 也要看得见它
#     ⇒ 崩了 ⇒ 记 rc=2（盲区）⇒ 仍是「最先失败的那个」⇒ 码值语义不被顶替
FAILS = []

# ⚠⚠⚨ 批 CT · **崩了的退出码**（单独一个常量 ⇒ 可被门**整行锚定**地钉住）
#   ⇒ ⚠⚠⚨ **批 CW**：这是**专属码**（rc=10）—— 不再与「盲区 rc=2」混在一档
#     ⇒ 崩了 ⇒ **专属码** ⇒ 分诊表里**单独一档** ⇒ 人不会把它当成「盲区」去查
#   ⇒ ⚠⚠⚨ **为什么要单独一个常量**（不是就地写 10）：
#     就地写 10 ⇒ 整行锚定的门**分不出**「这处 return 10 是崩了、还是别处」
#     ⇒ 单独一个常量 ⇒ 门能**指名道姓**地盯住崩了的那一处。
#   ⇒ ⚠⚠⚨ **为什么崩了要强制这个码**（不是「取最先失败的那个」）：
#     实测：先造一处别的失败（rc=6）**且**让审计器崩 ⇒ 旧行为 **rc=6**
#     ⇒ ⇒ 「崩了」被顶替 ⇒ **CI 的分诊依据（rc）指向另一个原因** ⇒ 排障被带偏
#     ⇒ ⇒ 崩了时**强制**这个码 ⇒ 分诊依据不再被顶替。
CRASH_RC = 10


def resolve(p):
    p = p.replace('$ROOT', REPO).replace('$SRC', SRC)
    return p.strip('"')


def rel(path):
    try:
        return os.path.relpath(path, REPO)
    except ValueError:
        return path


class UnreadableSource(Exception):
    """⚠⚠⚨ 批 CH · 源文件**读不了** ⇒ 不是「没问题」，是**没验过**。

    ⚠⚠⚨ **实测坐实的三个洞**（python 侧 —— ⚠ 批 CG 只收了 **shell 侧**那三处）：
    ① **诊断失真**：被盯的源文件不可读 ⇒ `strip_comments` 静默返回空
       ⇒ 报成「**门永远匹配不到（形同虚设）**」
       ⇒ ⚠⚠⚨ **完全不提「不可读 / 权限」** ⇒ 排障被带偏
       （真实原因是权限，报告说的是「门写错了」）；
    ② ⚠⚠⚨ **彻底假绿**：仓里有 **36** 条「**期望 0 次**」的 `arch_need_count` 门
       ⇒ 文件不可读 ⇒ 命中 0 == 期望 0 ⇒ 配准校准说「0 条失准」
       ⇒ **审计器判绿** ⇒ 而那个文件**根本没被审**；
    ③ **崩在栈里**：审计器自己依赖的文件（门脚本 / 豁免基线 / 门项总数基线）
       不可读 ⇒ 未捕获 `PermissionError` ⇒ 退出码 **1**
       ⇒ 门侧报「**未知的失败码**」⇒ 真实原因没有任何一条消息提到
       （⚠ 批 CF 修过「缺 perl」的同一形状，但**没管「文件读不了」**）。

    ⇒ 与门侧（shell）口径对齐：批 CG 的三个脚本已经「失败留标记 + 末尾统一判红」
    ⇒ ⚠⚠⚨ **审计器就是判定层自己的「盘点方法」**
    ⇒ 它不可靠 ⇒ 盘点结论就不可靠
    ⇒ 这正是「**盘点方法本身也要被门守**」的第一块砖。
    """

    def __init__(self, path, why):
        super().__init__('%s：%s' % (path, why))
        self.path = path
        self.why = why


def read_source(path):
    """读**被审的源文件** ⇒ 内容；**读不了 ⇒ 指名道姓地抛**（不许静默当空）。

    ⚠⚠⚨ 批 CD / 批 CE 同款口径：**扫描之前先验可读性**
    ⇒ 读不了 = 没验过 ⇒ 必须红（不许当成「没问题」）。
    ⚠ **文件不存在也抛** —— 调用方若要区分「不存在」与「读不了」，
    自己先 `os.path.isfile()`（既有语义保持不变）。
    """
    try:
        with open(path, encoding='utf-8') as fh:
            return fh.read()
    except OSError as e:
        raise UnreadableSource(path, '读不了（%s）' % e)


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
    # ⚠⚠⚨ 批 CH · **先验可读性**（批 CD / 批 CE 同款口径：扫描之前先验）
    #   ⇒ ⚠⚠⚨ **实测**：perl 打不开文件时**退出码仍是 0**（只往 stderr 打一句
    #     「Can't open …: 权限不够」）⇒ **靠退出码抓不住「读不了」**
    #     ⇒ 所以必须**先验**（`os.access` 用真实 uid ⇒ 与 shell 的 `-r` 同口径
    #     ⇒ **两侧口径一致**，不会一边绿一边红）
    if not os.access(path, os.R_OK):
        raise UnreadableSource(path, '对工具不可读（权限）')
    out = subprocess.run(cmd + [path], capture_output=True, text=True)
    # ⚠⚠⚨ 批 CH · **接住工具的退出码**（批 CG 纪律：工具失败 ≠ 没找到）
    #   ⇒ 工具失败 ⇒ 抛（不许把空输出当成「这个文件里没有」）
    #   ⚠⚠⚨ **变量名带前缀** ⇒ 这一行在仓里**唯一**
    #     （与别处同缩进的 `if out.returncode != 0:` 撞形态 ⇒ 整行锚定罩不住 ⇒ 批 CG 教训）
    _tool_rc = out.returncode
    if _tool_rc != 0:
        raise UnreadableSource(path, '剥注释工具退出码 %d' % _tool_rc)
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


# ⚠⚠⚨ 批 EB · **工具失败登记簿**（零名单维护 ⇒ 工具失败**自己登记**）
#
#   ⇒ 起因（实测坐实）：`count_hits` 以前在工具起不来时 `return None`
#     ⇒ 而 5 个调用点都是 `if got is None: continue`
#     ⇒ ⇒ 那些次数门**根本没被校准** ⇒ ⇒ 审计器**照样 rc=0** ⇒ ⇒ **假绿**
#     （单测证据：期望 999 vs 实际 1 ⇒ 工具坏了 ⇒ **一条失准都不报**）
#   ⇒ 现在：工具失败 ⇒ **登记到这里** ⇒ `main_body` 统一判红（fail closed）
#   ⇒ ⇒ **只改一处收口点** ⇒ ⇒ 不会漏（漏一处 = 洞还在）
#   ⚠ 键 = (相对路径, 正则) ⇒ 与门项的键同口径 ⇒ 报错能指名道姓
TOOL_FAILURES = []


def _tool_failed(path, rx, why):
    """登记一次「工具用不了」⇒ 返回 None（调用点照旧，但**信息不丢**）。"""
    TOOL_FAILURES.append((rel(path), rx, why))
    return None


def count_hits(path, rx):
    """用 grep -oE 数命中次数（与 arch_need_count 的口径一致）。

    ⚠⚠⚨ 批 EB · **工具失败不许静默跳过**：起不来 ⇒ 登记 ⇒ 统一判红（fail closed）
    """
    if not os.path.isfile(path):
        return None
    text = strip_comments(path)
    try:
        out = subprocess.run(['grep', '-oE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError as e:
        # ⚠⚠⚨ 批 EB：以前是 `return None` ⇒ **静默跳过** ⇒ 那一族次数门**没被校准**
        #   ⇒ ⇒ 审计器照样 rc=0 ⇒ ⇒ **假绿** ⇒ ⇒ 现在**登记** ⇒ 统一判红
        return _tool_failed(path, rx, 'grep 起不来（%s）' % e)
    if out.returncode not in (0, 1):
        return _tool_failed(path, rx, 'grep 退出码 %d（不是 0/1）' % out.returncode)
    return len([ln for ln in out.stdout.split('\n') if ln])


def count_hits_ml(path, rx):
    """数**压行后**的命中次数（与 arch_need_ml 的口径一致：先剥注释再压成一行）。"""
    if not os.path.isfile(path):
        return None
    text = strip_comments(path).replace('\n', ' ')
    try:
        out = subprocess.run(['grep', '-oE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError as e:
        # ⚠⚠⚨ 批 EB：以前是 `return None` ⇒ **静默跳过** ⇒ 那一族次数门**没被校准**
        #   ⇒ ⇒ 审计器照样 rc=0 ⇒ ⇒ **假绿** ⇒ ⇒ 现在**登记** ⇒ 统一判红
        return _tool_failed(path, rx, 'grep 起不来（%s）' % e)
    if out.returncode not in (0, 1):
        return _tool_failed(path, rx, 'grep 退出码 %d（不是 0/1）' % out.returncode)
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
    ('need_count_ml', COUNT_ML_LINE),
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
    src = read_source(path)
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
    raw = read_source(path)
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


# ══════════════════════════════════════════════════════════════════════
# 批 CO · 门项行的**实参数个数**必须与门型签名对得上
# ══════════════════════════════════════════════════════════════════════
def split_shell_args(line):
    """按 **shell 顶层分词** ⇒ 参数列表。

    ⚠⚠⚨ **引号闭合后紧跟的非空白要并进同一个词** ⇒ 这正是
      「**两条门粘在一行**」的特征：后一条的前半截被并进了前一条的 label
      ⇒ 后一条**从来没被执行过** ⇒ 门形同虚设（批 CO 实测在 ci-wiring.sh 里逮到一条）。

    ⚠ 行尾注释（引号**外**的 `#`）不算参数 ⇒ 先截掉。
    """
    args = []
    cur = ''
    have = False
    inq = False
    for c in line:
        if inq:
            if c == "'":
                inq = False
            else:
                cur += c
            continue
        if c == "'":
            inq = True
            have = True
            continue
        if c == '#' and (not cur or cur[-1] in ' \t'):
            break                      # ⚠ 引号外的行尾注释
        if c in ' \t':
            if have:
                args.append(cur)
                cur = ''
                have = False
            continue
        cur += c
        have = True
    if have:
        args.append(cur)
    return args


def gate_arity_map(names):
    """现抽每个门型函数的**必填参数数**与「可否多传」。

    ⚠⚠ **口径单一真相源**（批 AV 纪律）：**从 ci-wiring.sh 原文现抽**，不复刻。
    ⚠ 三种形态：
      · **定长**（无默认值、无 `shift`）⇒ 实参数必须**恰好**等于必填数
      · **可选**（`local` 里有 `${N:-…}`）⇒ 实参数 >= 必填数
      · **变参**（函数体里有 `shift`）⇒ 实参数 >= 必填数
    ⚠⚠⚨ 必填数 = **没有默认值的那些参数里的最大序号**
      ⇒ 不能用 max($N)（`${4:-…}` 那个是可选的 ⇒ 必填数是 3 不是 4）。
    """
    out = {}
    for nm in names:
        body = extract_shell_func(nm)
        if not body:
            continue
        nums, opt = [], set()
        variadic = False
        for ln in body.split('\n'):
            if ln.strip().startswith('local '):
                for mm in re.finditer(r'\$\{?(\d)(:-|:\+|\})?', ln):
                    if mm.group(2) in (':-', ':+'):
                        opt.add(int(mm.group(1)))
                    else:
                        nums.append(int(mm.group(1)))
            if re.search(r'(^|[;\s])shift\b', ln):
                variadic = True
        if not nums:
            continue
        out[nm] = (max(nums), bool(opt) or variadic)
    return out


def check_gate_arity():
    """门项行的**实参数个数**必须与门型签名对得上 ⇒ 否则**可能藏着另一条门**。

    ⚠⚠⚨ **实测逮到的洞（批 CO）**：ci-wiring.sh 里有一行把**两条门粘在一起**
      （前一条的说明文字后面**直接**接了后一条 ⇒ 中间连空格都没有）
      ⇒ shell 解析时后一条被并进前一条的 label ⇒ **后一条从来没跑过**
      ⇒ 而它盯的形态**早已不存在** ⇒ 它真跑起来**就该是红的**
      ⇒ ⚠⚠⚨ **CI 一直是假绿** ⇒ 且负控的定位串**命中 2 条**却只跑了其中一条。

    ⇒ 这里的检查是**结构性**的：实参数个数对不上 ⇒ 那行**藏着东西** ⇒ 报。
    """
    src = read_source(WIRING)
    lines = src.split('\n')
    names = []
    gate_lines = []
    for i, ln in enumerate(lines, 1):
        if not GATE_CALL_LINE.match(ln):
            continue
        gate_lines.append((i, ln))
        w = ln.strip().split(None, 1)[0]
        if w not in names:
            names.append(w)
    arity = gate_arity_map(names)
    bad = []
    for i, ln in gate_lines:
        args = split_shell_args(ln)
        if not args:
            continue
        nm = args[0]
        got = len(args) - 1
        info = arity.get(nm)
        if info is None:
            bad.append((i, nm, got, None, True,
                        '门型 %s 没抽到签名（函数定义不在 ci-wiring.sh 里？）' % nm))
            continue
        need, may_extra = info
        if may_extra:
            ok = got >= need
        else:
            ok = got == need
        if not ok:
            bad.append((i, nm, got, need, may_extra,
                        '实参 %d 个（签名必填 %d%s）'
                        % (got, need, '，可多传' if may_extra else '')))
    return bad


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
    # ⚠⚠⚨ 批 CQ · **按类分开**（硬门模式要分别报 ⇒ 报告模式仍用合并的 msgs）
    msgs_dups = []
    msgs_blind = []
    msgs_total = []
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
            msgs_dups.append(msgs[-1])
    if gtotal != gphysical:
        blind = True
        msgs.append('审计器有门型盲区：认领 %d 条 vs 文件里实际 %d 条门项行'
                    ' ⇒ 有门型没登记 ⇒ 那些门项**不会被审**'
                    % (gtotal, gphysical))
        msgs_blind.append(msgs[-1])
    # ⚠⚠⚨ 批 CO：门项行的**实参数个数**必须与门型签名对得上
    #   ⇒ 不对 ⇒ 那行**可能藏着另一条门** ⇒ 后者**从来没被执行过** ⇒ 门形同虚设
    #   ⇒ 归入 rc=2（盲区）：「那条门**根本没被审**」正是盲区的定义。
    arity_bad = check_gate_arity()
    for lineno, nm, got, need, may_extra, why in arity_bad:
        blind = True
        msgs.append('门项行的**实参数个数**与门型签名对不上（行 %d · %s）：%s'
                    ' ⇒ ⚠⚠⚨ **这行可能藏着另一条门**（后一条被并进了前一条的 label'
                    ' ⇒ **它从来没被执行过** ⇒ 门形同虚设）'
                    % (lineno, nm, why))
        msgs_blind.append(msgs[-1])
    if gbase is None:
        total_bad = True
        msgs.append('门项行数基线不可用：%s' % gwhy)
        msgs_total.append(msgs[-1])
    elif gphysical != gbase:
        total_bad = True
        msgs.append('门项行数与基线不符：文件里 %d 条 vs 基线 %d 条'
                    ' ⇒ **有门项被删了 / 被改成注释了** ⇒ 那些承诺**没人守了**'
                    % (gphysical, gbase))
        msgs_total.append(msgs[-1])
    # ⚠⚠⚨ 批 CR · **基线值的第二个记录**（与本文件里的常量交叉核对）
    #   ⇒ 上面那条核对的是「文件 vs 基线文件」⇒ **两边都在仓里、都可改**
    #     ⇒ 「删一条门项 + 改基线文件」= 两个协同编辑 ⇒ 旧行为**全绿**
    #   ⇒ 这里再加一遍「基线文件 vs **审计器源码里钉死的条数**」
    #     ⇒ 三处（基线文件 / 本常量 / 门项里那个数字）**互相对不上就红**
    #   ⇒ ⚠ **不宣称完全堵死**（四处协同编辑仍能躲过）⇒ 成本从 2 处升到 4 处
    if gbase is not None and gbase != GATE_LINES_EXPECTED:
        total_bad = True
        msgs.append('门项行数基线与**审计器里钉死的条数**对不上：基线文件 %d vs 审计器常量 %d'
                    ' ⇒ 两个记录**只改了一边** ⇒ 有人删了门项又顺手改了基线'
                    ' ⇒ **门项总数核对已不可信**'
                    % (gbase, GATE_LINES_EXPECTED))
        msgs_total.append(msgs[-1])
    return {
        'counts': gcounts, 'claimed': gtotal, 'physical': gphysical,
        'baseline': gbase, 'baseline_why': gwhy,
        'blind': blind, 'total_bad': total_bad, 'dups': dups, 'msgs': msgs,
        # ⚠⚠⚨ 批 CQ · **按类分开的消息**（硬门模式分别报 ⇒ 不指错方向）
        'msgs_by_kind': {'dups': msgs_dups, 'blind': msgs_blind,
                         'total': msgs_total},
    }


def parse_wiring():
    """解析 ci-wiring.sh ⇒ (need 门项, ml 门项, any_count 门项, any_min 门项,
    count 门项, count_in_fn 门项, count_in_step 门项, 各门型行数,
    解析失败行号, arch_forbid 行数)"""
    src = read_source(WIRING)
    lines = src.split('\n')
    need, ml, anyc, anym, cnt, cif, cis, pair = [], [], [], [], [], [], [], []
    cntml = []
    totals = {'need': 0, 'ml': 0, 'any_count': 0, 'any_min': 0,
              'count': 0, 'count_in_fn': 0, 'count_in_step': 0,
              'count_pair': 0, 'count_ml': 0}
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
        if COUNT_ML_LINE.match(ln):
            totals['count_ml'] += 1
            m = COUNT_ML_LINE.match(ln)
            cntml.append((i, resolve(m.group(1)), m.group(2), int(m.group(3))))
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
    return (need, ml, anyc, anym, cnt, cif, cis, pair, cntml,
            totals, failed, forbid_lines)


def changed_lines(base):
    """git diff base..HEAD 里 ci-wiring.sh 的**新增行行号**集合。"""
    try:
        out = subprocess.run(
            ['git', '-C', REPO, 'diff', '--unified=0', '%s..HEAD' % base,
             '--', 'deepin/scripts/ci-wiring.sh'],
            capture_output=True, text=True)
    except OSError as e:
        # ⚠⚠⚨ 批 EB：以前是裸 `return None` ⇒ 静默跳过 ⇒ 那些门项**没被校准**
        #   ⇒ ⇒ 现在**登记** ⇒ 统一收口判红（fail closed）
        return _tool_failed(__file__, '(git diff 新增行)', 'git 起不来（%s）' % e)
    if out.returncode != 0:
        return _tool_failed(__file__, '(git diff 新增行)',
                            'git diff 退出码 %d' % out.returncode)
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
    lines = [ln.rstrip('\n')
             for ln in read_source(EXEMPT).split('\n')]
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
    except OSError as e:
        # ⚠⚠⚨ 批 EB：以前是 `return None` ⇒ **静默跳过** ⇒ 配对门的行数**没被校准**
        #   ⇒ ⇒ **假绿** ⇒ ⇒ 现在**登记** ⇒ 统一判红
        return _tool_failed(path, rx, 'grep 起不来（%s）' % e)
    if out.returncode not in (0, 1):
        return _tool_failed(path, rx, 'grep 退出码 %d（不是 0/1）' % out.returncode)
    try:
        return int(out.stdout.strip() or '0')
    except ValueError as e:
        return _tool_failed(path, rx, 'grep 输出不是数字（%s）' % e)


# ⚠⚠⚨ 批 EB · **「静默跳过」的零名单维护规则**
#
#   ⇒ 起因（实测坐实）：`except OSError` 块里裸 `return None`
#     ⇒ 调用点 `if got is None: continue` ⇒ ⇒ 那一族门项**根本没被校准**
#     ⇒ ⇒ 审计器**照样 rc=0** ⇒ ⇒ **假绿**
#   ⇒ ⇒ 手工登记名单**必然会漏**（新增一个工具调用点 ⇒ 忘了登记 ⇒ 洞回来）
#     ⇒ ⇒ 改成**扫全文件**：凡 `except OSError` 块里出现
#       ① 裸 `return None`，或 ② `continue`
#     ⇒ 而该块内**没有** `_tool_failed(...)` 登记 ⇒ ⇒ 判红（rc=2 = 盲区）
#
#   ⚠ **口径只管 `except OSError`**（工具坏了 ⇒ 门项没被校准 ⇒ 盲区）
#     ⇒ `except (UnreadableSource, SyntaxError)`（源读不了）与 `except ValueError`
#       （门项解析失败）**不在本规则范围**（那是**另一个家族** ⇒ 已知边界，如实记着）
#
#   ⚠ **零名单维护** ⇒ 扫**全文件**所有 except 块 ⇒ 不用维护名单
#   ⚠ **判定逻辑只有一份**（批 BF/BG 纪律）⇒ 实扫与自检走同一函数
def check_silent_tool_skip(path):
    """审计器里**不许有「静默跳过」**：`except OSError` 块里的裸 `return None` / `continue`。

    ⇒ 返回 [(行号, 说明)]；空列表 = 通过。
    """
    bad = []
    try:
        with open(path, encoding='utf-8') as fh:
            tree = ast.parse(fh.read(), filename=path)
    except (OSError, SyntaxError) as e:
        return [(0, '读不了/解析不了 %s（%s）⇒ 自检做不了（fail closed）' % (path, e))]
    for node in ast.walk(tree):
        if not isinstance(node, ast.ExceptHandler):
            continue
        # ⚠ 只认 `except OSError`（含 `except OSError as e`）
        types = []
        if node.type is None:
            types = []
        elif isinstance(node.type, ast.Tuple):
            types = [ast.dump(t) for t in node.type.elts]
        else:
            types = [ast.dump(node.type)]
        if not any('OSError' in t for t in types):
            continue
        # ⚠ 该块内**有没有**登记（`_tool_failed(...)`）
        registered = any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                         and n.func.id == '_tool_failed' for n in ast.walk(node))
        if registered:
            continue
        for st in node.body:
            # ⚠⚠⚨ **AST 里 `return None` ≠ 裸 `return`**：
            #   裸 `return`     ⇒ `Return(value=None)`             ⇒ `st.value is None`
            #   `return None`   ⇒ `Return(value=Constant(value=None))` ⇒ ⚠ **`st.value is None` 是 False**！
            #   ⇒ ⇒ 批 EB **第一版规则只抓得住裸 `return`** ⇒ ⇒ 审计器里**真实的静默点全是 `return None`**
            #   ⇒ ⇒ **一条都抓不到** ⇒ ⇒ **规则是空的**（负控 NC31 实测撞出 ⇒ 幸好有负控）
            #   ⇒ ⇒ 现在两种都认。
            is_none_return = (isinstance(st, ast.Return) and
                              (st.value is None or
                               (isinstance(st.value, ast.Constant) and st.value.value is None)))
            if is_none_return:
                bad.append((st.lineno, '`except OSError` 块里裸 `return None` ⇒ **静默略过** ⇒ '
                                     '那些门项**根本没被校准** ⇒ 假绿'))
            elif isinstance(st, ast.Continue):
                bad.append((st.lineno, '`except OSError` 块里 `continue` ⇒ **静默略过** ⇒ '
                                     '那些门项**根本没被校准** ⇒ 假绿'))
    return bad


def check_pair_segment_bad(path, ra, rb):
    """逐段核对「报错行 ↔ 计数行」：每一段（从一处报错行到**下一处报错行之前**）
    必须**恰好有 1 处**计数行。

    ⚠⚠⚨ **为什么需要它**（批 BZ 遗留 ① · **本批实测坐实**，不是推演）：
      配对门只保证「**报错行数 == 计数行数** == 期望」⇒ **总数相等**
      ⇒ 实测：把某处的计数行**挪到别的一段** ⇒ 总数**仍相等**
      ⇒ ⇒ 老门**全绿**（审计器 rc=0、接线门 rc=0、✗ 0 行）
      ⇒ ⇒ 但那一处报错**不再被计数** ⇒ 末尾判定恒真 ⇒ **CI 假绿**
    ⇒ 逐段核对 ⇒ 哪一段的计数数不是 1 ⇒ 立刻红 ⇒ 洞堵死。

    ⚠ 口径：**行号**用 `grep -nE`（与门侧 `grep -cE` **同一份正则、同一份剥注释文本**）
      ⇒ 两侧口径一致 ⇒ 零漂移。
    ⚠ 段的定义：从一处报错行（含）到下一处报错行（不含）；**最后一段**到文件末。
    ⚠⚠⚨ 批 DM · **工具失败必须判红**（批 CD/CH 纪律）：
      以前这里返回 `None`（=「工具失败 ⇒ 调用方跳过」）
      ⇒ 这一族配对门的**逐段配对检查静默失效**而**没人知道** ⇒ **假绿**
      ⇒ 现在：工具失败 / 文件不存在 ⇒ 返回一条违规（说清失败原因）⇒ 红。
    ⚠ **判定函数 = 名字以 `check_` 开头** ⇒ 批 DM 的 AST 自检自动纳入它
      ⇒ 它**不许被掏空**成「返回字面量」。
    """
    if not os.path.isfile(path):
        why = '文件不存在 ⇒ 逐段配对无法核对（未验证不许被当成通过）'
        return [(0, 0, why)]
    text = strip_comments(path)

    def line_numbers(rx):
        err = None
        res = []
        try:
            out = subprocess.run(['grep', '-nE', '--', rx], input=text,
                                 capture_output=True, text=True)
        except OSError as e:
            err = 'grep 调用失败：%s' % e
            # ⚠⚠⚨ 批 EB：以前只返回 err（**不登记**）⇒ 逐段配对的结论**不可信**
            #   ⇒ ⇒ 却**没人知道** ⇒ ⇒ 现在**登记** ⇒ 统一判红
            _tool_failed(path, rx, 'grep 起不来（%s）' % e)
            return err, res
        if out.returncode not in (0, 1):
            err = 'grep 退出码 %d（既不是 0 也不是 1）' % out.returncode
            # ⚠⚠⚨ 批 EB：同上 ⇒ 登记
            _tool_failed(path, rx, err)
            return err, res
        for ln in out.stdout.split('\n'):
            if not ln.strip():
                continue
            head = ln.split(':', 1)[0]
            if head.isdigit():
                res.append(int(head))
        return err, res

    err_a, errs = line_numbers(ra)
    err_b, cnts = line_numbers(rb)
    if err_a is not None or err_b is not None:
        why = ('工具失败（%s）⇒ 逐段配对**无法核对**'
               '（工具失败 ≠ 没找到 ⇒ 未验证不许被当成通过）'
               % (err_a or err_b))
        return [(0, 0, why)]
    nlines = len(text.split('\n'))
    bad = []
    for k, s in enumerate(errs):
        e = errs[k + 1] if k + 1 < len(errs) else nlines
        seg_n = sum(1 for c in cnts if s <= c < e)
        if seg_n != 1:
            why = ('「%s」第 %d 行那一段（从这处报错到下一处报错之前）**段内计数 %d 处**'
                   ' ⇒ 必须是 **1** 处 ⇒ 那一处报错**没被计数** ⇒ 末尾判定恒真'
                   ' ⇒ **CI 假绿**（⚠ 批 CS：**总数相等也躲不过**）'
                   % (rel(path), s, seg_n))
            bad.append((s, seg_n, why))
    return bad


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
        # ⚠⚠⚨ 批 CS · **逐段配对**（总数相等**不够** ⇒ 见 check_pair_segment_bad 的说明）
        # ⚠⚠⚨ 批 DM · 判定函数**自己**把失败原因写进 `why`（判定逻辑只有一份）
        segbad = check_pair_segment_bad(f, ra, rb)
        for seg_line, seg_n, why in segbad:
            # ⚠⚠⚨ **关键信息必须进 `why`**（批 CS 负控撞出来的）：6 字段形态的打印器
            #   **只打 `why`**（`got` 那一项被丢）⇒ 消息里少写 ⇒ 诊断就少一截
            #   ⇒ ⇒ 消息要自带：文件、行号、段内计数数、为什么是红
            bad.append((lineno, f, rx_desc, want,
                        '段内计数 %d' % seg_n, why))
    return bad


# ⚠⚠⚨ 批 EA · **说明文字里的条数必须等于期望值**
#
#   ⇒ 起因（实测）：批 DZ 台账坑 ③ 立的纪律「改条数时说明文字也要改」
#   ⇒ **批 EA 又踩了一次** ⇒ 「人工纪律」已被证明不可靠 ⇒ 必须落成门。
#   ⇒ ⚠ 审计器本来**只校准期望值**（对不对由 grep 说了算）⇒ **不管说明文字**
#   ⇒ ⇒ 说明文字可以在期望值变了之后**继续说旧数字** ⇒ **文字在骗人**。
#
#   ⚠ **口径（批 EB 扩展）**：现在**两种写法都认** ——
#     ① 「（恰好 N 处」（紧跟左括号）
#     ② 「**必须恰好 N 处**」（主语就是本门 ⇒ 说的是**自己**的条数）
#   ⇒ ⇒ **批 EA 当时的口径太窄**：它把 ② 和「**有门钉住恰好 23 处**」
#      （那个**说的是别的门**）混为一谈 ⇒ ⇒ **为避开一个例子 ⇒ 误排了 30 条真·自己的门项**
#      ⇒ ⇒ 实测：全仓 **44 条**门项的说明文字写了条数，其中 **30 条**用 ② 写法
#      ⇒ ⇒ ② 那些门项的说明文字**完全不受管** ⇒ ⇒ **已经有 2 条在骗人**：
#      ① ci-wiring.sh:3323  实参 **6** 而文字称「恰好 5 处」（批 CQ 历史遗留）
#      ② ci-wiring.sh:3943  实参 **13** 而文字称「恰好 12 处」（**批 EB 自己引入的**）
#      ⇒ ⇒ 口径扩开后实测：**零误报**（44 条里只有那 2 条真失准）⇒ 可以扩
#   ⚠ **只查第一个** ⇒ 改成**全部都要对上**（一行里写了两个数 ⇒ 两个都得对）
def check_label_count_text(count_items):
    """核对门项说明文字里的「条数」与该门项的期望值是否一致。"""
    bad = []
    for lineno, f, rx, want in count_items:
        # ⚠ 说明文字是门项行的第 4 个参数 ⇒ 从**行原文**里取（不复刻解析）
        raw = _raw_gate_line(lineno)
        if raw is None:
            continue
        ms = re.findall(r"(?:（恰好 |必须恰好 )(\d+) 处", raw)
        if not ms:
            continue
        for m in ms:
            said = int(m)
            if said != want:
                bad.append((lineno, f, rx, want, said,
                            '说明文字称「恰好 %d 处」但期望值是 %d ⇒ **文字在骗人**'
                            % (said, want)))
    return bad


def _raw_gate_line(lineno):
    """取 ci-wiring.sh 第 lineno 行的**原文**（1 起算）。"""
    try:
        with open(WIRING, encoding='utf-8') as fh:
            lines = fh.read().split('\n')
    except OSError as e:
        # ⚠⚠⚨ 批 EB：以前是裸 `return None` ⇒ 调用点 `if raw is None: continue`
        #   ⇒ ⇒ **说明文字的条数校准被静默跳过** ⇒ ⇒ 假绿 ⇒ ⇒ 现在**登记** ⇒ 统一判红
        return _tool_failed(WIRING, '(门项说明文字)', '读不了 %s（%s）' % (WIRING, e))
    if lineno < 1 or lineno > len(lines):
        return None
    return lines[lineno - 1]


def check_count_ml_gates(count_ml_items):
    """校准 `arch_need_count_ml` 的期望次数：必须 == **压行后**的实际命中数。

    ⚠⚠⚨ 批 EF 新门型：口径与 `arch_need_ml` **完全一致**（同一段剥注释 + 同一个
      `tr '\n' ' '`）⇒ ⇒ 门侧与审计侧**同口径** ⇒ ⇒ 不漂移。
    """
    bad = []
    for lineno, f, rx, want in count_ml_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        got = count_hits_ml(f, rx)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '期望 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
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
ANCHOR_SCOPE_SUFFIXES = ('ci-tautology-check.py', 'ci-wiring-audit.py', 'ci.sh', 'ci-wiring.sh', 'ci-platform-probe.sh', 'ci-docs-lang-probe.sh', 'ci-divider-probe.sh', 'probe-agent-tool-surface.sh', 'ci-orphan-probe.sh', 'check-deb-layout.sh', 'contract-check.sh', 'ci-d2.sh', 'smoke.sh', 'bootstrap-deps.py', 'ci-true-audit.py', 'build-deb.sh', 'ci-unverified-audit.py', 'ci-shell-parity.sh')


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
    for lineno, raw in enumerate(read_source(ANCHOR_EXEMPT).split('\n'), 1):
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
    src = read_source(path)
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


def check_judge_return_literals(tree):
    """判定一棵 AST 里有没有「**判定函数返回了字面量**」⇒ [(函数名, 行号, 说明)]

    ⚠⚠⚨ 批 DM · **实测坐实的洞**（不是推演）：
      审计器的判定函数（`check_` 前缀）被掏空成「返回 `[]` / `None`」
      ⇒ 那一族门项的**校准静默失效**
      ⇒ 实测：**13 个**判定函数逐个掏空 ⇒ ⚠⚠⚨ **审计器 rc=0 + 接线门 rc=0**
      ⇒ **全绿假绿**（承诺悄悄消失，没有任何机制报警）。
    ⇒ 判定口径：**判定函数的 `return` 表达式里必须至少有一个「名字」**
      ⇒ 返回字面量（`[]` / `None` / `True` / `0` / 字符串 …）⇒ 掏空 ⇒ 必红。
    ⚠ **判定函数 = 名字以 `check_` 开头**（自动纳入 ⇒ 新增判定函数自动受管
      ⇒ **零名单维护** ⇒ 不存在「忘了登记」这一类漏）。
    ⚠ **嵌套函数也算**（否则嵌套 helper 被掏空仍然静默）。
    """
    bad = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        if not node.name.startswith('check_'):
            continue
        for r in ast.walk(node):
            if not isinstance(r, ast.Return):
                continue
            v = r.value
            if v is None:
                bad.append((node.name, r.lineno,
                            '裸 return（没返回值）⇒ 判定函数被掏空'))
                continue
            if not any(isinstance(x, ast.Name) for x in ast.walk(v)):
                bad.append((node.name, r.lineno,
                            'return 的是**字面量**（%s）⇒ 判定函数被掏空'
                            % type(v).__name__))
    return bad


def check_judge_funcs_selftest():
    """自检：让**判定逻辑自己**证明自己有牙（批 BF 纪律：两种极性都要有样例）。

    ⚠⚠⚨ 样例必须**既含「该判为违规」也含「不该判为违规」** ⇒ 只有「该违规」的样例
      ⇒ 「永远判违规」也能过 ⇒ 自检没牙。
    """
    cases = [
        # 返回空列表 ⇒ 掏空 ⇒ 必须判违规
        ('def check_a():\n    return []\n', True),
        # 返回 None ⇒ 掏空 ⇒ 必须判违规
        ('def check_b():\n    return None\n', True),
        # 返回常量 True ⇒ 掏空 ⇒ 必须判违规
        ('def check_c():\n    return True\n', True),
        # 返回变量 ⇒ 正常 ⇒ 不许判违规
        ('def check_d():\n    return bad\n', False),
        # 返回元组（都含名字）⇒ 正常 ⇒ 不许判违规
        ('def check_e():\n    return bad, need\n', False),
        # ⚠ **不叫 `check_` 前缀** ⇒ 不在判定函数口径内 ⇒ 不许判违规
        ('def helper_f():\n    return []\n', False),
    ]
    bad = []
    for src, should in cases:
        got = bool(check_judge_return_literals(ast.parse(src)))
        if got != should:
            bad.append((src.replace('\n', ' / '), should, got))
    return bad


def check_judge_funcs():
    """判定函数（`check_` 前缀）不许被掏空 ⇒ [(函数名, 行号, 说明)]

    ⚠⚠⚨ 批 DM · **一次挡住整类**：实测 13 个判定函数逐个掏空
      ⇒ 审计器与接线门**双双全绿** ⇒ 假绿坐实 ⇒ 现在由这条 AST 自检一次挡住。
    ⚠⚠⚨ **自检必须放最前**（批 BI 纪律）：前面的检查一红就 exit
      ⇒ 自检永远没机会跑 ⇒ 形同虚设。
    ⚠⚠⚨ **自检自己也要有自检**（批 BF 纪律：两种极性都要有样例）。
    ⚠ **fail closed**：解析自己失败 ⇒ 判红（不许「读不到就当没问题」）。
    """
    bad = []
    for src, should, got in check_judge_funcs_selftest():
        bad.append(('judge-funcs-selftest', 0,
                    '判定逻辑**自检不过**（样例 %s：期望判违规=%s，实际=%s）'
                    % (src, should, got)))
    try:
        tree = ast.parse(read_source(os.path.abspath(__file__)))
    except (UnreadableSource, SyntaxError) as e:
        bad.append(('judge-funcs', 0,
                    '解析审计器自己失败（%s）⇒ 判定体检做不了'
                    '（fail closed：未验证不许被当成通过）' % e))
    else:
        for name, lineno, why in check_judge_return_literals(tree):
            bad.append((name, lineno, why))
    return bad


SELF_TEST_NAME_HINTS = ('selftest', 'self_test')


def _name_has_hint(name):
    """名字里含「自检」提示词（`selftest` / `self_test`）⇒ 是**自检函数**。"""
    return any(h in name for h in SELF_TEST_NAME_HINTS)


def _calls_named(node, names):
    """函数体里**直接调用**了 `names` 里的任意一个（只看 `Name` 形态的调用）。

    ⚠ **不用 `return True` / `return False` 字面量** ⇒ 全文件「`return True` 恰好 1 处」
      那条门盯的是 `has_unbounded_wildcard` 的「判违规」返回 ⇒ 多一处就失准。
    """
    found = False
    for sub in ast.walk(node):
        if (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name)
                and sub.func.id in names):
            found = True
            break
    return found


def _own_return_nodes(node):
    """函数**自己**的 `return` 节点（**不进嵌套函数**）。

    ⚠ 为什么要排除嵌套函数：嵌套 helper 的多个出口（早返回/多分支返回）
      是**正常写法** ⇒ 混进来会把「提前 return」这个口径**判得过宽** ⇒ 假红。
    """
    nested = set()
    for sub in ast.walk(node):
        if sub is node:
            continue
        if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):
            nested.add(id(sub))
            for d in ast.walk(sub):
                nested.add(id(d))
    return [r for r in ast.walk(node)
            if isinstance(r, ast.Return) and id(r) not in nested]


def check_self_test_funcs():
    """判据脚本里的**自检函数**不许被掏空 ⇒ [(文件名, 函数名, 行号, 说明)]

    ⚠⚠⚨ 批 DN · **实测坐实的洞**（不是推演）：
      `ci-true-audit.py` 的 `selftest_strip_parity` 被掏空（在函数体里插一句
      提前 `return`）⇒ 那道「两侧剥注释口径必须一致」的自检**静默失效**
      ⇒ 该脚本 rc=0 + 接线门 rc=0 ⇒ **全绿假绿**（承诺悄悄消失，没人报警）。

    ⇒ 判定口径（**零名单维护**）：
      ① **自检函数**（名字含 `selftest` / `self_test`）**不许有提前 return**
         ⇒ 提前 return 就是「掏空」⇒ 必红；
      ② **自检的宿主**（`check_` 前缀、且函数体里**调用了**自检函数）
         **同样不许有提前 return** ⇒ 否则「在跑自检之前先 return」
         ⇒ 自检**根本没机会跑**而门全绿；
      ③ 自检函数**一条 return 都没有** ⇒ 也算被掏空（自检必须**给出结论**）。

    ⚠ **跨脚本**（扫 `deepin/scripts/*.py` 全部）⇒ 别的判据脚本里的自检自动受管。
    ⚠ **fail closed**：列不出目录 / 解析失败 ⇒ 判红（不许「读不到就当没问题」）。
    ⚠ **规则自己也被规则保护**（批 DM 同款）：本函数名字含 `self_test`
      ⇒ 它自己也在口径内 ⇒ 它不许有提前 return。
    """
    bad = []
    scripts_dir = os.path.join(SRC, 'scripts')
    try:
        names = sorted(os.listdir(scripts_dir))
    except OSError as e:
        bad.append(('(范围)', '(范围)', 0,
                    '列不出判据脚本目录（%s）⇒ 自检体检做不了（fail closed）' % e))
        names = []
    for fn in names:
        if not fn.endswith('.py'):
            continue
        path = os.path.join(scripts_dir, fn)
        try:
            tree = ast.parse(read_source(path))
        except (UnreadableSource, SyntaxError) as e:
            bad.append((fn, '(解析)', 0,
                        '解析失败（%s）⇒ 自检体检做不了（fail closed）' % e))
            continue
        hints = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) and _name_has_hint(node.name):
                hints.add(node.name)
        for node in ast.walk(tree):
            if not isinstance(node, ast.FunctionDef):
                continue
            host = node.name.startswith('check_') and _calls_named(node, hints)
            if not (_name_has_hint(node.name) or host):
                continue
            rets = _own_return_nodes(node)
            if not rets:
                bad.append((fn, node.name, node.lineno,
                            '自检函数**一条 return 都没有** ⇒ 自检被掏空'
                            '（自检必须给出结论）'))
                continue
            last = node.body[-1]
            early = [r for r in rets if r is not last]
            if early:
                bad.append((fn, node.name, early[0].lineno,
                            '自检函数有**提前 return**（第 %d 行）⇒ 自检被掏空'
                            % early[0].lineno))
    return bad


# ⚠⚠⚨ 批 DO · 「失败态上报」的**守卫口径**（**零名单维护**）
#   ⇒ 守卫条件**只许**「名字 / 下标」两种形态 ⇒ 取反 / 与或 / 比较 / 调用 /
#     布尔字面量 一律不许 ⇒ 理由见 `check_fail_guards` 的说明。
GUARD_SHAPE_OK = (ast.Name, ast.Subscript)
# ⚠⚠⚨ 批 DO · **守卫登记册**（口径 ④ 的另一半 ⇒ **双向红**）
#   ⇒ 「用到的守卫」必须在册里 ⇒ 新增失败态忘了登记 ⇒ 红；
#   ⇒ 「册里的守卫」必须都被用到 ⇒ 某个收集点被挪走 / 删了 ⇒ 红。
#   ⇒ ⚠ 登记册**内容由本仓的收集点现抽生成** ⇒ 不手抄 ⇒ 零漂移。
FAIL_GUARDS = ('TOOL_FAILURES', 'anchbad', 'anchor_exempt_bad', 'anchor_exempt_missing', 'bad_all', 'cntmlbad', 'dead', 'dt_bad', 'es_bad', 'exempt_missing', 'failed', 'fg_bad', 'fr_bad', "g['blind']", "g['dups']", "g['total_bad']", 'guard_bad', 'judge_bad', 'labelbad', 'rxmiss', 'rxsyn', 'rxunreg', 'self_bad', 'skipbad', 'stbad', 'undef', 'zero')


def _is_fails_append(node):
    """这个表达式是不是 `FAILS.append(...)`？"""
    return (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == 'append'
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == 'FAILS')


def _guard_shape_ok(test):
    """守卫条件的**形态**合不合规？⇒ 只许「名字 / 下标」。

    ⚠ **不用 `return True` / `return False` 字面量** ⇒ 全文件「`return True` 恰好
      1 处」那条门盯的是 `has_unbounded_wildcard` 的「判违规」返回 ⇒ 多一处就失准。
    """
    ok = False
    if isinstance(test, ast.Name):
        ok = True
    elif isinstance(test, ast.Subscript) and isinstance(test.value, ast.Name):
        ok = True
    return ok


def check_fail_guards():
    """审计器自己的**失败态上报**不许被静默关掉 ⇒ [(行号, 说明)]

    ⚠⚠⚨ 批 DO · **实测坐实的洞**（不是推演）：把 main_body 里的
      `if g['blind']:` 改成恒假 ⇒ **审计器自己有盲区**（比如门型登记册
      被摘了一条）时**不再上报** ⇒ 审计器 rc=0 + 接线门 rc=0
      ⇒ **全绿假绿** ⇒ 「那些门项**从来没被审**」这件事**彻底没人知道**。
      ⇒ 批 DM 的规则只管 `check_` 前缀**函数**里的 `return`
        ⇒ **main_body 的内联判定是一个逃逸口**。

    ⇒ 判定口径（三条腿，**零名单维护**）：
      ① 每个 `FAILS.append(rc)` 调用点**必须有守卫**
        （最内层 `if` 的条件；或处在 `except` 里 —— 崩了的兜底）
        ⇒ 没有守卫 ⇒ 那个失败态**恒定触发** ⇒ 假红 ⇒ 必红；
        ⇒ ⚠⚠⚨ **实测如实记着**：现有 20 处收集点**全都**嵌在某个 `if` 里
        ⇒ ⇒ 这一条**当前触发不到** ⇒ **它现在是面向将来的**，**现在没有牙**
        ⇒ 现在的牙在 ② ③ 两条腿上 ⇒ ⚠ **不假装它现在就有用**；
      ② 守卫条件**只许**是「名字 / 下标」两种形态
        ⇒ **不许**取反（`if not x:` ⇒ 判定被**反过来**）
        / 与或（`if a and b:` ⇒ 判定被**改窄**）
        / 比较（`if x == 0:`）/ 调用（`if g.get('blind'):`）
        / 布尔字面量（`if False:` ⇒ 判定被**关掉**）
        ⇒ 守卫的职责是「**取出一个判定结果**」⇒ 写成常量或表达式
        ⇒ 就是在**改判定** ⇒ 必须走门 ⇒ 逼着人同步；
      ③ 守卫**不许重复**
        ⇒ 每个失败态各有**自己的**判定结果 ⇒ 两个收集点用同一个守卫
        ⇒ 说明其中一个**指错了判定**（如把「盲区」那一档换成「总数」那一档）
        ⇒ ⇒ 那一类失败**不再上报**而没人知道 ⇒ 必红
        ⇒ ⚠ 这条抓的是**换指向**（形态不变 ⇒ ② 抓不到）。

    ⚠ **规则自己也被规则保护**（批 DM/DN 同款）：本函数名字以 `check_` 开头
      ⇒ 批 DM 的「判定函数不许被掏空」管它；本函数**自己**也在批 DN 的
      「自检函数不许提前 return」口径外（它不是自检函数）
      ⇒ ⚠ 但它**必须**只有一条 `return` ⇒ 本函数用 `tree = None` + 条件分支
      ⇒ **没有提前 return**（批 DN 口径 ③：自检/判定函数不许没有结论）。

    ⚠ **fail closed**：解析不了审计器自己 ⇒ 判红（不许「读不到就当没问题」）。
    """
    bad = []
    try:
        tree = ast.parse(read_source(os.path.abspath(__file__)))
    except (UnreadableSource, SyntaxError) as e:
        bad.append((0, '解析审计器自己失败（%s）⇒ 守卫体检做不了（fail closed）' % e))
        tree = None
    if tree is not None:
        found = []

        def scan_body(body, guard, in_except):
            for stmt in body:
                if isinstance(stmt, ast.If):
                    scan_body(stmt.body, stmt.test, in_except)
                    scan_body(stmt.orelse, guard, in_except)
                elif isinstance(stmt, ast.Try):
                    scan_body(stmt.body, guard, in_except)
                    for h in stmt.handlers:
                        scan_body(h.body, None, True)
                    scan_body(stmt.orelse, guard, in_except)
                    scan_body(stmt.finalbody, guard, in_except)
                elif isinstance(stmt, (ast.For, ast.While, ast.With,
                                       ast.AsyncFor, ast.AsyncWith)):
                    scan_body(stmt.body, guard, in_except)
                    scan_body(getattr(stmt, 'orelse', []) or [], guard, in_except)
                elif isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    # ⚠ 进入函数 ⇒ 守卫**不继承**外层（函数体里的 append
                    #   该由**它自己**的 if 守卫 ⇒ 否则外层的 if 会替它背书）
                    scan_body(stmt.body, None, False)
                elif isinstance(stmt, ast.Expr) and _is_fails_append(stmt.value):
                    found.append((stmt.lineno, guard, in_except))

        scan_body(tree.body, None, False)
        for lineno, guard, in_except in found:
            if guard is None and not in_except:
                bad.append((lineno, '`FAILS.append(...)` **没有守卫**'
                            ' ⇒ 那个失败态**恒定触发** ⇒ 必红'))
            elif guard is not None and not _guard_shape_ok(guard):
                bad.append((lineno, '`FAILS.append(...)` 的守卫条件形态不合规'
                            '（%s）⇒ 只许「名字 / 下标」⇒ 取反 / 与或 / 比较 /'
                            ' 调用 / 布尔字面量 都是**在改判定**'
                            % type(guard).__name__))
        # ⚠⚠⚨ 口径 ④ · **守卫登记册双向红**
        #   ⇒ 「用到的守卫」不在册里 ⇒ 新增失败态忘了登记 ⇒ 红；
        #   ⇒ 「册里的守卫」没被用到 ⇒ 那个收集点**被挪走 / 删了** ⇒ 红
        #     ⇒ ⚠ 这一条抓的是「挪进一个**以变量为条件**的少真分支」
        #       （新守卫**仍是名字** ⇒ ② 不抓、③ 不重复 ⇒ 只有它抓得住）
        used = set()
        for lineno, guard, in_except in found:
            if guard is None or in_except:
                continue
            used.add(ast.unparse(guard))
        for gname in sorted(set(FAIL_GUARDS) - used):
            bad.append((0, '登记册里的守卫 `%s` **没有被任何收集点用到** ⇒ '
                        '那个失败态的收集点**被挪走或删了** ⇒ 它**永远不会报出来**'
                        % gname))
        for gname in sorted(used - set(FAIL_GUARDS)):
            bad.append((0, '收集点的守卫 `%s` **不在登记册里** ⇒ 新增失败态忘了登记'
                        ' ⇒ 登记册与实际**漂了**' % gname))
        # ⚠⚠⚨ 口径 ③ · **守卫不许重复**（抓「换指向」：形态不变 ⇒ ② 抓不到）
        #   ⇒ 每个失败态各有**自己的**判定结果 ⇒ 两个收集点用同一个守卫
        #     ⇒ 其中的一个**指错了判定** ⇒ 那一类失败**不再上报**而没人知道
        seen = {}
        for lineno, guard, in_except in found:
            if guard is None or in_except:
                continue
            key = ast.unparse(guard)
            if key in seen:
                bad.append((lineno, '`FAILS.append(...)` 的守卫与第 %d 行**重复**'
                            '（%s）⇒ 两个失败态用同一个判定 ⇒ 其中的一个'
                            '**指错了判定** ⇒ 那一类失败**不再上报**'
                            % (seen[key], key)))
            else:
                seen[key] = lineno
    return bad



# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ 批 DP · 「失败态上报」的**跨脚本**体检（零名单维护）
# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ **范围** = `deepin/scripts/*.py` 全部，**审计器自己除外**
#   ⇒ 排除项**由本文件名现算**（不是手抄名单）⇒ 零名单维护
#   ⇒ 审计器自己由**批 DO** 的 `check_fail_guards` 管 ⇒ 两批口径**不重叠**
DP_SELF = os.path.basename(os.path.abspath(__file__))

# ⚠⚠⚨ **失败上报点登记册**（口径 ④ ⇒ **双向红**）
#   ⇒ 「用到的」不在册 ⇒ 新增失败态忘了登记 ⇒ 红
#   ⇒ 「册里的」实测数对不上 ⇒ 那个失败上报点**被挪走 / 删了 / 变了** ⇒ 红
#   ⇒ ⚠ 数量**由本仓的判据脚本现抽生成** ⇒ 不手抄 ⇒ 零漂移
#   ⇒ ⚠ 类别：`fail_exit` = 失败出口（`sys.exit(X)`，X 非 `main()` 调用）
#     / `fail_ret` = 失败返回（`return <非零>`）
#     / `fail_count` = 失败累加器上的**追加型写**（`X += …` / `X.append(…)`）
FAIL_REPORT_COUNTS = (('bootstrap-deps.py', 'fail_count', 2), ('bootstrap-deps.py', 'fail_ret', 1), ('ci-tautology-check.py', 'fail_count', 18), ('ci-tautology-check.py', 'fail_ret', 3), ('ci-true-audit.py', 'fail_count', 7), ('ci-true-audit.py', 'fail_exit', 16), ('ci-true-audit.py', 'fail_ret', 1), ('ci-unverified-audit.py', 'fail_count', 10), ('ci-unverified-audit.py', 'fail_exit', 9), ('ci-unverified-audit.py', 'fail_ret', 1))


def _dp_is_main_call(node):
    """这个表达式是不是 `main()` 调用？（成功出口 ⇒ 不算失败出口）"""
    ok = False
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id == 'main'):
        ok = True
    return ok


def _dp_is_sys_exit(node):
    """这个表达式是不是 `sys.exit(...)`？"""
    ok = False
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == 'exit' and isinstance(node.func.value, ast.Name)
            and node.func.value.id == 'sys'):
        ok = True
    return ok


def _dp_nonzero_int(node):
    """是不是「非零整数字面量」？（⚠ bool 是 int 的子类 ⇒ 必须排除）"""
    ok = False
    if (isinstance(node, ast.Constant) and isinstance(node.value, int)
            and not isinstance(node.value, bool) and node.value != 0):
        ok = True
    return ok


def _dp_is_literal_int(node):
    """是不是「整数字面量」？（含 0；⚠ bool 排除）"""
    ok = False
    if (isinstance(node, ast.Constant) and isinstance(node.value, int)
            and not isinstance(node.value, bool)):
        ok = True
    return ok


def _dp_zero_exit_code(node):
    """这个 `sys.exit(...)` 的实参会不会让退出码变成 **0**？

    ⚠⚠⚨ `sys.exit(0)` / `sys.exit(False)` / `sys.exit(None)` ⇒ **退出码 0**
      ⇒ 失败被报成「成功」⇒ **假绿**。
    ⚠ `sys.exit('…')` ⇒ 退出码是 **1**（Python 语义）⇒ 合规。
    ⚠ `sys.exit('…' % x)` ⇒ 还是字符串 ⇒ 退出码 1 ⇒ 合规。
    ⚠ 其它形态（变量 / 调用）⇒ **静态判不了** ⇒ 放行（**如实记为边界**）。
    """
    zero = False
    if isinstance(node, ast.Constant):
        v = node.value
        # ⚠⚠⚨ **三个形态一次算完**（`None` / `False` / `0`）⇒ **一行**
        #   ⇒ 这一行是**关键判定** ⇒ 被门**整行钉住** ⇒ 改它 ⇒ 门红
        #   ⇒ ⚠ 分成三个分支 ⇒ 三行都没被钉 ⇒ 改任何一行都**静默失去牙**
        zero = (v is None) or (v is False) or (v == 0)
    return zero


# ⚠⚠⚨ 批 DP · 守卫形态的判定**复用批 DO 的 `_guard_shape_ok`**
#   ⇒ 「判定逻辑只有一份」（批 BF/BG 纪律）⇒ 零漂移
#   ⇒ ⚠ **不要另写一份**：另写一份若与它**逐字相同** ⇒ 批 DO 那条门命中数翻倍
#     ⇒ 期望 1 ≠ 实际 2 ⇒ 门没牙（实测踩到过，已改）


def check_fail_report_points():
    """判据脚本（**审计器之外**）的「失败态上报」不许被静默关掉 ⇒ [(文件, 行号, 说明)]

    ⚠⚠⚨ 批 DP · **实测坐实的洞**（不是推演；两个都跑过对照实验）：
      ① `ci-tautology-check.py` 的 **16 处 `bad += 1`** 全被改成 `bad += 0`
         ⇒ 探针**不再计数** ⇒ 真的恒真判据（注入的 `if True:`）**照样打印到
           stderr**，但**退出码是 0** ⇒ 探针 rc=0 + 接线门 rc=0
         ⇒ **全绿假绿**（CI 第 16 步照样绿 ⇒ 那批判据**不再被查**没人知道）。
      ② `ci-true-audit.py` 的 `sys.exit('✗ 登记册不存在：%s' % BASELINE)`
         被改成 `sys.exit(0)` ⇒ 登记册真被藏起来时，盘点**静默退出 0**
         （输出为空）⇒ 盘点 rc=0 + 接线门 rc=0 ⇒ **全绿假绿**。

    ⇒ 判定口径（四条腿，**零名单维护**）：
      ① **失败出口不许以 0 退出**
         （`sys.exit(X)` 且 X 不是 `main()` 调用 ⇒ X 是 0 / False / None ⇒ 红）
      ② **失败计数增量不许是 0**
         （**失败累加器**上的 `X += <整数字面量>` ⇒ 增量必须 ≠ 0）
      ③ **失败返回的守卫不许被改形**
         （`return 1` 所在的最内层 `if` 守卫**必须存在**，
           且测试**只许「名字 / 下标」** ⇒ 取反 / 比较 / 与或 / 布尔字面量 一律红）
      ④ **失败上报点不许被摘掉**（登记册**双向红**）

    ⚠ **失败累加器** = 出现在「失败守卫」测试里的名字；
      「失败守卫」= 直接 body 里含 `return <非零>` 或 `sys.exit(...)` 的 `if`。
    ⚠ **rc 语义**：rc=1 = 失败；rc=2 = 用法错（批 CC 立的约定）⇒ 腿 ③ **不管 rc=2**。
    ⚠ **规则自己也被规则保护**（批 DM/DN/DO 同款）：本函数名字以 `check_` 开头
      ⇒ 批 DM 的「判定函数不许被掏空」管它 ⇒ 本函数**只有一条 return**。
    ⚠ **fail closed**：列不出目录 / 解析失败 ⇒ 判红（不许「读不到就当没问题」）。
    """
    bad = []
    counts = {}
    scripts_dir = os.path.join(SRC, 'scripts')
    try:
        names = sorted(os.listdir(scripts_dir))
    except OSError as e:
        bad.append(('(范围)', 0,
                    '列不出判据脚本目录（%s）⇒ 失败态体检做不了（fail closed）' % e))
        names = []
    for fn in names:
        if not fn.endswith('.py') or fn == DP_SELF:
            continue
        path = os.path.join(scripts_dir, fn)
        try:
            tree = ast.parse(read_source(path))
        except (UnreadableSource, SyntaxError) as e:
            bad.append((fn, 0,
                        '解析失败（%s）⇒ 失败态体检做不了（fail closed）' % e))
            continue
        exits = []
        rets = []
        augs = []
        appends = []
        accs = set()

        def scan(body, guard):
            for stmt in body:
                if isinstance(stmt, ast.If):
                    # ⚠ 「失败守卫」？⇒ 它的测试里的名字 = 失败累加器候选
                    if isinstance(stmt.test, ast.Name):
                        for st in stmt.body:
                            if ((isinstance(st, ast.Return)
                                 and _dp_nonzero_int(st.value))
                                    or (isinstance(st, ast.Expr)
                                        and _dp_is_sys_exit(st.value))):
                                accs.add(stmt.test.id)
                                break
                    scan(stmt.body, stmt.test)
                    scan(stmt.orelse, guard)
                elif isinstance(stmt, ast.Try):
                    scan(stmt.body, guard)
                    for h in stmt.handlers:
                        scan(h.body, guard)
                    scan(stmt.orelse, guard)
                    scan(stmt.finalbody, guard)
                elif isinstance(stmt, (ast.For, ast.While, ast.With,
                                       ast.AsyncFor, ast.AsyncWith)):
                    scan(stmt.body, guard)
                    scan(getattr(stmt, 'orelse', []) or [], guard)
                elif isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    # ⚠ 进入函数 ⇒ 守卫**不继承**外层
                    scan(stmt.body, None)
                elif isinstance(stmt, ast.Return):
                    if _dp_nonzero_int(stmt.value):
                        rets.append((stmt.lineno, stmt.value.value, guard))
                elif isinstance(stmt, ast.Expr) and _dp_is_sys_exit(stmt.value):
                    arg = stmt.value.args[0] if stmt.value.args else None
                    if not (arg is not None and _dp_is_main_call(arg)):
                        exits.append((stmt.lineno, arg))
                elif isinstance(stmt, ast.AugAssign):
                    if isinstance(stmt.target, ast.Name):
                        augs.append((stmt.lineno, stmt.target.id, stmt.value))
                elif (isinstance(stmt, ast.Expr)
                      and isinstance(stmt.value, ast.Call)
                      and isinstance(stmt.value.func, ast.Attribute)
                      and stmt.value.func.attr == 'append'
                      and isinstance(stmt.value.func.value, ast.Name)):
                    appends.append((stmt.lineno, stmt.value.func.value.id))

        scan(tree.body, None)
        # ⚠⚠⚨ 口径 ① · **失败出口不许以 0 退出**
        for lineno, arg in exits:
            if arg is None:
                bad.append((fn, lineno,
                            '`sys.exit()` **没有实参** ⇒ 退出码是 0 ⇒ 失败被报成成功'))
            elif _dp_zero_exit_code(arg):
                bad.append((fn, lineno,
                            '`sys.exit(...)` 的实参会让**退出码变成 0**'
                            ' ⇒ 失败被报成成功'))
        # ⚠⚠⚨ 口径 ② · **失败计数增量不许是 0**
        for lineno, name, val in augs:
            if name in accs and _dp_is_literal_int(val) and val.value == 0:
                bad.append((fn, lineno,
                            '失败累加器 `%s` 上的增量是 **0** ⇒ 那个失败'
                            '**永远不被计数** ⇒ 退出码永远是 0' % name))
        # ⚠⚠⚨ 口径 ③ · **失败返回的守卫不许被改形**
        for lineno, code, guard in rets:
            if code == 2:
                continue          # rc=2 = 用法错（批 CC 立的约定）⇒ 不在口径内
            if guard is None:
                bad.append((fn, lineno,
                            '`return %d` **没有守卫** ⇒ 那个失败**恒定触发**（假红）'
                            % code))
            elif not _guard_shape_ok(guard):
                bad.append((fn, lineno,
                            '`return %d` 的守卫条件形态不合规（%s）⇒ 只许「名字 / 下标」'
                            ' ⇒ 取反 / 与或 / 比较 / 布尔字面量 都是**在改判定**'
                            % (code, type(guard).__name__)))
        # ⚠⚠⚨ 口径 ④ 的**实测数**（追加型写 = `X += …` 与 `X.append(…)`）
        n_count = len([1 for _l, n, _v in augs if n in accs]) \
            + len([1 for _l, n in appends if n in accs])
        counts[fn] = {'fail_exit': len(exits), 'fail_ret': len(rets),
                      'fail_count': n_count}
    # ⚠⚠⚨ 口径 ④ · **登记册双向红**
    used = set()
    for fn in sorted(counts):
        for kind in sorted(counts[fn]):
            if counts[fn][kind]:
                used.add((fn, kind))
    reg = set((a, b) for a, b, _n in FAIL_REPORT_COUNTS)
    for key in sorted(used - reg):
        bad.append((key[0], 0,
                    '失败上报点 `%s/%s` **不在登记册里** ⇒ 新增失败态忘了登记'
                    ' ⇒ 登记册与实际**漂了**' % key))
    for a, b, n in FAIL_REPORT_COUNTS:
        got = counts.get(a, {}).get(b, 0)
        if got != n:
            bad.append((a, 0,
                        '登记册记的 `%s/%s` 数量 %d ≠ 实测 %d ⇒ 那个失败上报点'
                        '**被挪走 / 删了**（或数量变了没登记）' % (a, b, n, got)))
    return bad

# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ 批 DR · **失败出口的守卫不许被悄悄改弱**
# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ **实测坐实的洞（不是推演）**：
#   把 `ci-true-audit.py` 的 `if '\ufffd' in raw:` 改成
#   `if '\ufffd' in raw and False:` ⇒ 那个失败出口**恒不触发**
#   ⇒ 登记册里真的塞了 U+FFFD 时**不再被报出来**
#   ⇒ 而盘点 rc=0 + 审计器 rc=0 + 接线门 rc=0 ⇒ ⚠⚠⚨ **全绿假绿**
#   ⇒ ⚠ 恒真探针抓不到（条件里还有标识符 ⇒ 不是「恒真」）
#   ⇒ ⚠ 批 DP 的口径 ③ 只管「决定退出码的守卫」（`return 1`）⇒ 管不到这里
#   ⇒ ⚠ 批 DO / 批 DM 只管审计器自己 ⇒ 也管不到这里
#   ⇒ ⇒ **这批失败出口的守卫，一个门都没钉住**（实测：23 处里只有 9 处被门钉住）。
#
# ⚠⚠⚨ **修法（两条腿）**：
#   腿 ① **守卫登记册（双向红）** ⇒ 守卫**表达式**级 ⇒ 改弱（`and False` /
#       `or True` / 换形态 / 换比较值 / 换标识符）⇒ 表达式对不上 ⇒ 红
#   腿 ② **守卫里不许有布尔字面量** ⇒ 一次挡住整类（批 CD 纪律：一次挡住整类）
#       ⇒ 布尔字面量 ⇒ 守卫要么**恒假**（死代码 ⇒ 失败永远不被报出）
#         要么**恒真**（永远被报出 ⇒ 变成无条件失败）
#         ⇒ 两种都不是「失败条件的忠实表达」
#
# ⚠ 本登记册是**名单** ⇒ 「改代码 + 改登记册」的协同编辑**抓不到**
#   （⚠ 批 CR / 批 DO / 批 DP 同款已知边界）
# ⚠ 腿 ② **不依赖登记册** ⇒ 协同编辑躲不过这一腿（部分独立）

# ⚠⚠⚨ **守卫登记册**的路径（⚠ 与其它基线**分开文件** ⇒ 批 BH 纪律）
FAIL_GUARD_BASELINE = os.path.join(SRC, 'scripts', 'ci-fail-guard.baseline')

# ⚠⚠⚨ **登记册条数基线**（批 BC 纪律：清单不许被删）⇒ **恰好**（批 BB 口径）
FAIL_GUARD_EXPECTED_ROWS = 25


def _fg_ascii(s):
    r"""非 ASCII 一律转成 `\uXXXX` ⇒ 登记册里**不会有真 U+FFFD**。"""
    out = []
    for ch in s:
        if ord(ch) < 128:
            out.append(ch)
        else:
            out.append('\\u%04x' % ord(ch))
    return ''.join(out)


def _fg_bool_literal(node):
    """这个表达式里**有没有布尔字面量**（`True` / `False`）？

    ⚠⚠⚨ 守卫里出现布尔字面量 ⇒ 守卫**要么恒假**（死代码 ⇒ 失败永远不被报出）
      ⇒ **要么恒真**（永远被报出 ⇒ 变成无条件失败）
      ⇒ 两种都不是「失败条件的忠实表达」⇒ 一律红（批 DR）。
    ⚠ **判定收成单行** ⇒ 门项可**整行钉住**（批 AH~AX 纪律：关键判定整行锚定）
      ⇒ 改它 ⇒ 门红 ⇒ 规则不会**静默失去牙**。
    """
    return any(isinstance(s, ast.Constant) and isinstance(s.value, bool) for s in ast.walk(node))


def _fg_collect_exits(tree):
    """判据脚本里全部**失败出口** ⇒ [(行号, 守卫表达式, 守卫 AST 节点)]。

    ⚠⚠⚨ **「失败出口」的定义与批 DP 口径①**完全一致（`_dp_is_sys_exit` +
      `_dp_is_main_call`）⇒ 两批口径**不会各算各的**（批 BF：判定逻辑只有一份）。
    ⚠ **守卫** = **最内层**那个 `if` 的条件（`else` 分支**不继承**那个 `if`）。
    ⚠ **函数体 / 类体不继承**外层守卫（与批 DP 口径③的 `scan` 同款约定）。
    """
    out = []

    def walk_body(stmts, if_test, in_except):
        for st in stmts:
            if isinstance(st, ast.If):
                walk_body(st.body, st.test, in_except)
                walk_body(st.orelse, if_test, in_except)
            elif isinstance(st, ast.Try):
                walk_body(st.body, if_test, in_except)
                for h in st.handlers:
                    walk_body(h.body, if_test, True)
                walk_body(st.orelse, if_test, in_except)
                walk_body(st.finalbody, if_test, in_except)
            elif isinstance(st, (ast.For, ast.AsyncFor, ast.While,
                                 ast.With, ast.AsyncWith)):
                walk_body(st.body, if_test, in_except)
                walk_body(getattr(st, 'orelse', []) or [], if_test, in_except)
            elif isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef,
                                 ast.ClassDef)):
                walk_body(st.body, None, False)
            elif isinstance(st, ast.Expr) and _dp_is_sys_exit(st.value):
                arg = st.value.args[0] if st.value.args else None
                if arg is not None and _dp_is_main_call(arg):
                    continue        # `sys.exit(main())` ⇒ 入口，不是失败出口
                if if_test is not None:
                    try:
                        g = _fg_ascii(ast.unparse(if_test))
                    except Exception:
                        g = '(unparse 失败)'
                elif in_except:
                    g = '(except 兜底)'
                else:
                    g = '(无 if 守卫)'
                out.append((st.lineno, g, if_test))

    walk_body(tree.body, None, False)
    return out


def check_fail_guard_shapes():
    """失败出口的守卫**不许被悄悄改弱** ⇒ [(文件, 行号, 说明)]

    ⚠⚠⚨ 两条腿（见上方注释）：
      腿 ① 守卫登记册**双向红**（表达式级）
      腿 ② 守卫里**不许有布尔字面量**
    ⚠ **fail closed**：列不出目录 / 解析失败 / 读不了登记册 ⇒ 判红。
    ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP 同款）：本函数名字以 `check_`
      开头 ⇒ 批 DM 管它 ⇒ **只有一条 return**。
    """
    bad = []
    scripts_dir = os.path.join(SRC, 'scripts')
    try:
        names = sorted(os.listdir(scripts_dir))
    except OSError as e:
        bad.append(('(范围)', 0,
                    '列不出判据脚本目录（%s）⇒ 守卫体检做不了（fail closed）' % e))
        names = []
    actual = {}
    for fn in names:
        if not fn.endswith('.py') or fn == DP_SELF:
            continue
        path = os.path.join(scripts_dir, fn)
        try:
            tree = ast.parse(read_source(path))
        except (UnreadableSource, SyntaxError) as e:
            bad.append((fn, 0,
                        '解析失败（%s）⇒ 守卫体检做不了（fail closed）' % e))
            continue
        for lineno, g, node in _fg_collect_exits(tree):
            key = (fn, g)
            actual[key] = actual.get(key, 0) + 1
            # ⚠⚠⚨ 腿 ② · 守卫里**不许有布尔字面量**
            if node is not None and _fg_bool_literal(node):
                bad.append((fn, lineno,
                            '失败出口的守卫里**有布尔字面量**（`True` / `False`）'
                            ' ⇒ 守卫要么**恒假**（死代码 ⇒ 失败永远不被报出）'
                            '、要么**恒真**（永远被报出）'
                            ' ⇒ 都不是「失败条件的忠实表达」'))
    # ⚠⚠⚨ 腿 ① · **登记册双向红**（表达式级 ⇒ 改弱就红）
    reg = {}
    n_reg = 0
    raw = None
    try:
        with open(FAIL_GUARD_BASELINE, encoding='utf-8') as fh:
            raw = fh.read()
    except OSError as e:
        bad.append(('(登记册)', 0,
                    '读不了守卫登记册（%s）⇒ 无处对账 ⇒ 判红（fail closed）' % e))
    if raw is not None:
        for no, line in enumerate(raw.split('\n'), 1):
            t = line.rstrip('\r\n')
            if not t.strip() or t.strip().startswith('#'):
                continue
            parts = t.split('\t')
            if len(parts) != 3:
                bad.append(('(登记册)', no,
                            '不是 3 段（脚本|守卫表达式|理由）：%r' % t))
                continue
            if not parts[2].strip():
                bad.append(('(登记册)', no,
                            '**没有理由** ⇒ 不许「登记了但没写为什么」'))
                continue
            key = (parts[0], parts[1])
            reg[key] = reg.get(key, 0) + 1
            n_reg += 1
        if n_reg != FAIL_GUARD_EXPECTED_ROWS:
            bad.append(('(登记册)', 0,
                        '登记册条数 %d ≠ 基线 %d ⇒ 整份清单被删/被改'
                        % (n_reg, FAIL_GUARD_EXPECTED_ROWS)))
    for key in sorted(set(actual) - set(reg)):
        bad.append((key[0], 0,
                    '失败出口的守卫 `%s` **不在登记册里** ⇒ 新增失败出口忘了登记'
                    ' ⇒ 登记册与实际**漂了**' % key[1]))
    for key in sorted(set(reg) - set(actual)):
        bad.append((key[0], 0,
                    '登记册里的守卫 `%s` **实测没有** ⇒ 那个失败出口'
                    '**被挪走 / 删了 / 改了形态**' % key[1]))
    for key in sorted(set(actual) & set(reg)):
        if actual[key] != reg[key]:
            bad.append((key[0], 0,
                        '守卫 `%s` 的处数：实测 %d ≠ 登记册 %d'
                        % (key[1], actual[key], reg[key])))
    return bad



# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ 批 DS · **抽取器必须被 e2e 自检覆盖**
# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ **实测坐实的洞**（不是推演）：把 `ci-true-audit.py` 的
#   `find_subst_spans` 的**反引号分支**摘掉 ⇒ 新增一处**反引号形态**的
#   `|| true` **不再被发现** ⇒ 而盘点 rc=0 + 审计器 rc=0 + 接线门 rc=0
#   ⇒ ⚠⚠⚨ **全绿假绿**。
#   ⇒ ⚠ 恒真探针抓不到（那是**条件**恒真，不是**抽取器**坏）
#   ⇒ ⚠ 批 DR 的守卫登记册抓不到（守卫没被改，是**抽取器**坏了）
#   ⇒ ⇒ 抽取器必须**有 e2e 自检**（批 DF / 批 DN 同款纪律）
#
# ⚠ **前缀是单一真相源** ⇒ 新抽取器自动纳入 ⇒ **零名单维护**
EXTRACTOR_PREFIXES = ('extract_', 'find_', 'scan_', 'parse_', 'collect_', 'strip_')

# ⚠⚠⚨ **实测坐实的洞**（不是推演）：`dash` 的 `echo` **解释**反斜杠转义，
#   而 `bash` 的 `echo` **不解释**（POSIX 规定）⇒ 同一份判据脚本，
#   在 `sh`（dash）与 `bash` 下**输出不同** ⇒ 门项的**诊断文案随执行 shell 变**
#   ⇒ 而**负控的「真红」判定靠文案命中** ⇒ 文案不稳定 ⇒ 真红判定不可信
#   ⇒ ⇒ 门型函数体内**不许用 `echo`** ⇒ 一律 `printf '%s\n'`
# ⚠ **零名单维护**：口径 = 函数名以这个前缀开头（门型前缀）⇒ 新门型自动纳入
GATE_FN_PREFIX = 'arch_'


# ⚠ **「模块级入口」不算函数体 / 类体 / lambda 体里的调用**
#   （⚠ 写成**单行** ⇒ 可整行钉住 ⇒ 批 AH~AX 纪律）
_DS_SKIP_NODES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)


def _ds_module_calls(tree):
    """模块级语句里**直接调用**到的函数名（⚠ **不进入**函数体 / 类体 / lambda 体）

    ⚠⚠⚨ **为什么要「不进入」**（⚠ 批 DS 负控 NC8/NC9 实测坐实）：
      `ast.walk` 会**走进函数体** ⇒ 函数体内的调用会被**误当成**顶层调用
      ⇒ 「模块级入口」被算多 ⇒ 「自检会不会真的执行」这条判定**失效**。
    ⚠ 顶层 `if __name__ == '__main__': main()` 里的调用**算**模块级入口
      ⇒ 递归进 If / For / While / Try / With 的体里找。
    """
    out = set()

    def walk(nodes):
        for node in nodes:
            if isinstance(node, _DS_SKIP_NODES):
                continue
            if isinstance(node, ast.Call):
                f = node.func
                nm = (f.attr if isinstance(f, ast.Attribute)
                      else (f.id if isinstance(f, ast.Name) else None))
                if nm:
                    out.add(nm)
            for child in ast.iter_child_nodes(node):
                walk([child])

    walk(tree.body)
    return out


def _ds_live_funcs(tree, callees):
    """「会被执行」的函数集合（live）= 从**模块级入口**沿调用图**反向**可达

    ⚠⚠⚨ **为什么必须算 live**（⚠ 批 DS 负控 NC8/NC9 实测坐实）：
      抽取器**被某个自检函数调用**还不够 ⇒ 那个自检函数**从不被调用**
      ⇒ 自检**永远不会执行** ⇒ 抽取器坏了**没人发现**
      ⇒ ⚠ 而 `selftest_extractors` 自己的名字就含 `selftest`
      ⇒ 「从自检函数出发做传递闭包」会把它**当成起点**
      ⇒ ⇒ **覆盖判定必须加上「这个自检函数真的会被执行」这一条**。
    ⚠ **反向可达**（不动点）：X 被某个 live 的 Y 调用 ⇒ X 也会被执行。
      ⚠⚠⚨ **方向不能反**（⚠ 批 DS 收紧时踩到）：
        `callees[X]` = X **调用了谁** ⇒ 「X 调用了 live 的 Y」**推不出** X live
        ⇒ 必须先建**反向边** `callers[Y] = {X}` ⇒ 再按「谁调用了 live 的」扩张。
    """
    callers = {}
    for name, cs in callees.items():
        for c in cs:
            callers.setdefault(c, set()).add(name)
    live = set(_ds_module_calls(tree))
    changed = True
    while changed:
        changed = False
        for name, cs in callees.items():
            if name in live or not (callers.get(name, set()) & live):
                continue
            live.add(name)
            changed = True
    return live


def _ds_is_selftest(name):
    """这个函数名是不是「自检函数」？（批 DN 的口径：`selftest` / `self_test`）"""
    return ('selftest' in name) or ('self_test' in name)


def check_extractor_self_tests():
    """判据脚本里**以抽取器前缀开头**的函数必须**能被自检覆盖** ⇒ [(文件, 说明)]

    ⚠⚠⚨ **为什么**（批 DF 纪律）：抽取器的输出是**判据的原料**
      ⇒ 抽取器坏了 ⇒ 判据看的是**错的东西**
      ⇒ 而脚本自己**照样绿**（批 DN/DF 的实测洞）⇒ 必须有 e2e 自检兜住。
    ⚠ **「被覆盖」= 能从某个**会被执行的**自检函数沿调用图**传递**到达**
      ⇒ 薄封装也算覆盖（它被自检**真的走过**了）
      ⇒ ⚠⚠⚨ **「会被执行」这一条不能少**（⚠ 批 DS 负控 NC8/NC9 实测坐实）：
        `selftest_extractors` 自己的名字就含 `selftest` ⇒ 若只看名字
        ⇒ 它**从不被调用**时也算「覆盖」⇒ 覆盖判定**静默失效**
        ⇒ ⇒ 起点必须再过 `n in live`（live = 从模块级入口反向可达）
    ⚠ **fail closed**：列不出目录 / 解析失败 ⇒ 判红。
    ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP 同款）：名字以 `check_` 开头
      ⇒ 批 DM 管它 ⇒ **只有一条 return**。
    """
    bad = []
    scripts_dir = os.path.join(SRC, 'scripts')
    try:
        names = sorted(os.listdir(scripts_dir))
    except OSError as e:
        bad.append(('(范围)',
                    '列不出判据脚本目录（%s）⇒ 抽取器体检做不了（fail closed）' % e))
        names = []
    for fn in names:
        if not fn.endswith('.py') or fn == DP_SELF:
            continue
        path = os.path.join(scripts_dir, fn)
        try:
            tree = ast.parse(read_source(path))
        except (UnreadableSource, SyntaxError) as e:
            bad.append((fn, '解析失败（%s）⇒ 抽取器体检做不了（fail closed）' % e))
            continue
        funcs = {}
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                funcs.setdefault(node.name, node)
        # 调用图：每个函数**调用了谁**（⚠ 嵌套函数体也进图 ⇒ 嵌套的同样被覆盖）
        callees = {}
        for name, node in funcs.items():
            cs = set()
            for sub in ast.walk(node):
                if isinstance(sub, ast.Call):
                    f = sub.func
                    nm = (f.attr if isinstance(f, ast.Attribute)
                          else (f.id if isinstance(f, ast.Name) else None))
                    if nm:
                        cs.add(nm)
            callees[name] = cs
        # 从**会被执行的自检函数**出发做**传递闭包**
        # ⚠⚠⚨ 「会被执行」这一条**必须有**（⚠ 批 DS 负控 NC8/NC9 实测坐实）：
        #   只看「是不是自检函数」⇒ `selftest_extractors` 自己就含 `selftest`
        #   ⇒ 它**从不被调用**时也算「覆盖」⇒ 覆盖判定**失效**
        #   ⇒ ⇒ 起点必须再过一道「**这个自检函数真的会被执行**」。
        live = _ds_live_funcs(tree, callees)
        covered = set()
        stack = [n for n in funcs if _ds_is_selftest(n) and n in live]
        while stack:
            cur = stack.pop()
            if cur in covered:
                continue
            covered.add(cur)
            for c in callees.get(cur, ()):
                if c not in covered:
                    stack.append(c)
        for name in sorted(funcs):
            if not name.startswith(EXTRACTOR_PREFIXES):
                continue
            if _ds_is_selftest(name):
                continue
            if name not in covered:
                bad.append((fn, '抽取器 `%s`（行 %d）**没有任何 e2e 自检覆盖**'
                            ' ⇒ 它被抽坏 ⇒ 判据看的是**错的东西**而脚本照样绿'
                            '（批 DF / 批 DN 同款洞）'
                            % (name, funcs[name].lineno)))
    return bad


def check_gate_output_shell():
    """门型函数体内**不许用 `echo`** ⇒ [(说明)]

    ⚠⚠⚨ **为什么**（实测坐实，不是推演）：POSIX 规定 **`dash` 的 `echo`
      解释反斜杠转义、`bash` 的 `echo` 不解释** ⇒ 同一份判据脚本，
      在 `sh`（dash）与 `bash` 下**输出不同**
      ⇒ 实测 `ci-wiring.sh`：2 条门项的**诊断文案分叉**（label 含反斜杠的共 11 条）
      ⇒ 而**负控的「真红」判定靠文案命中** ⇒ 文案不稳定 ⇒ 真红判定不可信
      ⇒ ⇒ 门型函数体内一律 `printf '%s\n'`（**不解释**参数里的转义 ⇒ 跨 shell 一致）。
    ⚠ **零名单维护**：口径 = 函数名以 `GATE_FN_PREFIX` 开头（门型前缀）
      ⇒ 新门型**自动纳入** ⇒ 新门型若用 `echo` ⇒ **立即红**。
    ⚠ **fail closed**：列不出门型 / 抽不出函数体 / 函数体**抽不全** ⇒ 判红。
    ⚠ 判定口径：`echo` 前面是**行首或空白**（= 独立的命令 token）
      ⇒ awk 程序里的 `/^echo` / `sub(/^echo` **不算**（那是正则字面量，改了会坏 awk）。
    ⚠ **规则自己也被规则保护**（批 DM/DN/DO/DP/DS 同款）：名字以 `check_` 开头
      ⇒ 批 DM 管它 ⇒ **只有一条 return**。
    """
    bad = []
    try:
        src = read_source(WIRING)
        names = sorted(set(re.findall(r'^(%s[a-z_]+)\(\) \{' % GATE_FN_PREFIX, src, re.M)))
    except (UnreadableSource, OSError) as e:
        bad.append(('(范围)', '读不出 ci-wiring.sh ⇒ 门型输出体检做不了（fail closed）%s' % e))
        names = []
    for n in names:
        fn = extract_shell_func(n)
        if not fn or not fn.rstrip().endswith('}'):
            bad.append(('(门型)', '门型函数 `%s` **抽不出 / 抽不全** ⇒ 门型输出体检做不了（fail closed）' % n))
            continue
        body = [ln for ln in fn.split('\n') if ln.strip()]
        for ln in body:
            if re.search(r'(?:^|\s)echo\s', ln):
                bad.append(('ci-wiring.sh',
                            '门型函数 `%s` 体内**不许用 `echo`** ⇒ `echo` 会解释反斜杠'
                            '（dash 解释、bash 不解释）⇒ 诊断文案**随执行 shell 变** ⇒ '
                            '负控的文案命中判定不可信 ⇒ **必须用 printf 的 %%s 形式**' % n))
                break
    return bad


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
    bad = []
    if awk_src is None:
        # ⚠⚠⚨ 批 DM：以前这里是 `return []` ⇒ **工具失败 ⇒ 这一族校准被静默跳过**
        #   ⇒ 那些门项的期望次数失准**没人知道** ⇒ **假绿**
        #   ⇒ 现在：**工具失败必须判红**（批 CD/CH 纪律：未验证不许被当成通过）
        bad.append((0, '', '', '', 0, None,
                    '切不出函数体（工具失败）⇒ 这一族门项**根本没被校准**'
                    '（未验证不许被当成通过）'))
        return bad
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
        try:
            r = subprocess.run(['grep', '-oE', '--', rx], input=body,
                               capture_output=True, text=True)
        except OSError as e:
            # ⚠⚠⚨ 批 EB：以前**没保护** ⇒ grep 挂 ⇒ 整个审计器**崩**（rc=10）
            #   ⇒ 方向对（红）但**诊断失真**（说「崩了」而不是「工具用不了」）
            #   ⇒ ⇒ 现在**登记** ⇒ 统一判红 + 指名道姓
            _tool_failed(f, rx, 'grep 起不来（%s）' % e)
            bad.append((lineno, f, sig, rx, want, None,
                        '**工具用不了** ⇒ 函数体内的实际次数**算不出来** ⇒ 校准**没做成**'))
            continue
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
    bad = []
    if awk_src is None:
        # ⚠⚠⚨ 批 DM：同款（工具失败 ⇒ 静默跳过 ⇒ 假绿）⇒ 改成判红
        bad.append((0, '', '', 0, None,
                    '切不出步骤正文（工具失败）⇒ 这一族门项**根本没被校准**'
                    '（未验证不许被当成通过）'))
        return bad
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
        try:
            r = subprocess.run(['grep', '-oE', '--', rx], input=body,
                               capture_output=True, text=True)
        except OSError as e:
            # ⚠⚠⚨ 批 EB：以前**没保护** ⇒ grep 挂 ⇒ 整个审计器**崩**（rc=10）
            #   ⇒ 方向对（红）但**诊断失真**（说「崩了」而不是「工具用不了」）
            #   ⇒ ⇒ 现在**登记** ⇒ 统一判红 + 指名道姓
            _tool_failed(f, rx, 'grep 起不来（%s）' % e)
            # ⚠ **in_step 的 bad 元组是 6 元组**（没有 sig 那一段）⇒ 别照抄 in_fn
            bad.append((lineno, f, rx, want, None,
                        '**工具用不了** ⇒ 该步正文里的实际次数**算不出来** ⇒ 校准**没做成**'))
            continue
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
    """⚠⚠⚨ 批 CH · 顶层**兜住「源文件读不了」** ⇒ 指名道姓 + 退出码 **2**。

    ⚠⚠⚨ **为什么必须有这一层**：
    ① 审计器读不到**被审的源文件** ⇒ 那条门项**根本没被审** ⇒ **盲区**
      ⇒ 与「缺 perl」同款 ⇒ 同用 **rc=2**（门侧的分派消息会点名这一类）；
    ② 以前是**未捕获异常** ⇒ 退出码 **1** ⇒ 门侧报「**未知的失败码**」
      ⇒ 真实原因（权限）**没有任何一条消息提到**（批 CF 的教训重演）。
    """
    try:
        return main_body()
    except UnreadableSource as e:
        print('审计失败：源文件**读不了** ⇒ 那些门项**根本没被审**'
              '（未验证不许被当成通过）：%s' % e, file=sys.stderr)
        return 2
    except Exception as e:
        # ⚠⚠⚨ 批 CQ · **崩了也要判红**，且**不许**崩成「未知的失败码」(1)
        #   ⇒ 崩 ⇒ 那些门项**根本没被审** ⇒ 与「源文件读不了」同款 ⇒ rc=2（盲区）
        #   ⇒ ⚠ **已报出来的失败态不丢**（它们已经打印在 stderr 上了）
        #     ⇒ 不遮蔽 ⇒ 一次看得见**全部**问题
        # ⚠⚠⚨ 关键词必须落在**同一行**（批 CM 口径数的是「提示行」⇒
        #   关键词若落在续行上 ⇒ 盘点**数不到** ⇒ 等于**漏登记** ⇒ 违反双向红）
        print('审计器**崩了**（未验证不许被当成通过）：%s: %s'
              ' ⇒ 那些门项**根本没被审**' % (type(e).__name__, e),
              file=sys.stderr)
        FAILS.append(2)
        # ⚠⚠⚨ 批 CT · **崩了 ⇒ rc 强制走 CRASH_RC**（**不被更早的失败态顶替**）
        #   ⇒ 否则「崩了」这个信号只活在 stderr 的一行里，而 **rc**（CI 的分诊依据）
        #     指向别的原因 ⇒ 排障被带偏（实测：先造 rc=6 再崩 ⇒ 旧行为 rc=6）
        #   ⇒ ⚠ **已报出来的失败态不丢**（批 CQ：一次报全）⇒ 别的失败照样看得见
        # ⚠⚠⚨ 批 CW · CRASH_RC 现在是**专属码 10** ⇒ 与「盲区 rc=2」**完全分离**
        #   ⇒ 分诊表里单独一档 ⇒ 不会再被当成「盲区」去查
        #   ⇒ ⚠ 上面 `FAILS.append(2)` **照旧**（崩 ⇒ 那些检查没跑完 ⇒ **性质**
        #     仍是盲区）⇒ 报告里的「性质」分桶不变 ⇒ 只改**分诊用的 rc**
        return CRASH_RC


def tool_failure_rc():
    """⚠⚠⚨ 批 EB · **工具用不了 ⇒ 那些门项根本没被校准 ⇒ 判红**（fail closed）

    ⇒ 起因（实测坐实）：`count_hits` 以前在工具起不来时 `return None`
      ⇒ 而 5 个调用点都是 `if got is None: continue`
      ⇒ ⇒ 那些次数门**根本没被校准** ⇒ ⇒ 审计器**照样 rc=0** ⇒ ⇒ **假绿**
      （单测证据：期望 999 vs 实际 1 ⇒ 工具坏了 ⇒ **一条失准都不报**）

    ⚠⚠⚨ **必须在**所有出口**之前**都调它 —— 批 EB 第一版把它插在**硬门模式**分支里
      ⇒ ⇒ 而 `--list`（CI 实际用的）与**报告模式**都没被覆盖
      ⇒ ⇒ 单测跑出来 **rc=0** ⇒ ⇒ **看着像没修** ⇒ ⇒ 教训：收口点不能只管一个分支。

    ⇒ 返回 rc（2 = 盲区：那些门项**根本没被审**）/ None（没失败）
    """
    if TOOL_FAILURES:
        print('**工具用不了** ⇒ %d 条门项**根本没被校准**'
              '（未验证不许被当成通过）：' % len(TOOL_FAILURES), file=sys.stderr)
        for tf in TOOL_FAILURES[:20]:
            print('  · %s | %s ⇒ %s' % (tf[0], tf[1], tf[2]), file=sys.stderr)
        if len(TOOL_FAILURES) > 20:
            print('  … 另有 %d 条' % (len(TOOL_FAILURES) - 20), file=sys.stderr)
        print('  ⇒ 那些次数门**没被校准** ⇒ 期望值对不对**没人知道** ⇒ 判红',
              file=sys.stderr)
        FAILS.append(2)
        return 2
    return None


def main_body():
    # ⚠⚠⚨ 批 CQ · **清空失败态收集器**（幂等 ⇒ 同一进程里跑多次也不串味）
    del FAILS[:]
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

    (need, ml, anyc, anym, cnt, cif, cis, pair, cntml,
     totals, failed, forbid_lines) = parse_wiring()

    # ⚠⚠⚨ 批 BN · 「整行锚定」的豁免基线（**先读** ⇒ 后面两处判定共用同一份）
    anchor_exempt, anchor_exempt_exists, anchor_exempt_rows, anchor_exempt_bad = \
        read_anchor_exempt()
    # ⚠⚠⚨ 批 DO · 守卫条件**只许「名字 / 下标」**（口径 ②）⇒ 取反要**先算好**
    anchor_exempt_missing = not anchor_exempt_exists

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
    # ⚠⚠⚨ 批 DO · 守卫条件**只许「名字 / 下标」**（口径 ②）⇒ 取反要**先算好**
    exempt_missing = not exempt_exists
    outside = [k for k in keys if k not in exempt]
    stale = [k for k in exempt if k not in set(keys)]

    if want_list_all:
        for k in keys:
            print(k)
        # ⚠⚠⚨ 批 EB：工具用不了 ⇒ 那些键**不完整** ⇒ ⇒ 也要判红
        return tool_failure_rc() or 0

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
            FAILS.append(9)
        # ⚠⚠⚨ 批 DM · **判定函数不许被掏空**（一次挡住整类）
        #   ⇒ 必须**放在最前**：前面的检查一红就 exit ⇒ 自检永远没机会跑 ⇒ 形同虚设
        judge_bad = check_judge_funcs()
        if judge_bad:
            print('审计器的**判定函数被掏空**（%d 处）⇒ 那些门项**根本没被校准**'
                  % len(judge_bad), file=sys.stderr)
            for fnm, jl, jwhy in judge_bad:
                print('  · %s:%d  %s  ⇒ %s'
                      % (os.path.basename(os.path.abspath(__file__)), jl, fnm, jwhy),
                      file=sys.stderr)
            print('  ⇒ 判定函数（`check_` 前缀）的 `return` 必须返回**含名字**的表达式'
                  '（不许返回 `[]` / `None` / `True` 这类字面量）', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DN · **自检函数不许被掏空**（跨脚本 ⇒ 零名单维护）
        #   ⇒ 必须**放在最前**：前面的检查一红就 exit ⇒ 自检永远没机会跑 ⇒ 形同虚设
        self_bad = check_self_test_funcs()
        if self_bad:
            print('判据脚本里的**自检函数被掏空**（%d 处）⇒ 那些自检**静默失效**'
                  % len(self_bad), file=sys.stderr)
            for fnm, fn2, jl, jwhy in self_bad:
                print('  · scripts/%s:%d  %s  ⇒ %s'
                      % (fnm, jl, fn2, jwhy), file=sys.stderr)
            print('  ⇒ 自检函数（名字含 `selftest` / `self_test`）**不许有提前 return**'
                  ' ⇒ 提前 return 就是「掏空」', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DO · **失败态上报**不许被静默关掉（零名单维护）
        #   ⇒ 必须**放在最前**：前面的检查一红就 exit ⇒ 这条永远没机会跑 ⇒ 形同虚设
        guard_bad = check_fail_guards()
        if guard_bad:
            print('审计器自己的**失败态上报被静默关掉**（%d 处）'
                  ' ⇒ 那些失败态**永远不会报出来** ⇒ 假绿'
                  % len(guard_bad), file=sys.stderr)
            for jl, jwhy in guard_bad:
                print('  · ci-wiring-audit.py%s  %s'
                      % (':%d' % jl if jl else '', jwhy), file=sys.stderr)
            print('  ⇒ 每个 `FAILS.append(rc)` **必须有守卫**（最内层 `if` 的条件）'
                  '，且守卫条件**只许「名字 / 下标」**', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DP · 判据脚本（**审计器之外**）的「失败态上报」不许被静默关掉
        #   ⇒ 必须**放在最前**：前面的检查一红就 exit ⇒ 这条永远没机会跑 ⇒ 形同虚设
        fr_bad = check_fail_report_points()
        if fr_bad:
            print('判据脚本的**失败态上报被静默关掉**（%d 处）'
                  ' ⇒ 那些失败态**永远不会报出来** ⇒ 假绿'
                  % len(fr_bad), file=sys.stderr)
            for fnm, jl, jwhy in fr_bad:
                print('  · scripts/%s%s  %s'
                      % (fnm, (':%d' % jl) if jl else '', jwhy), file=sys.stderr)
            print('  ⇒ 失败出口不许以 0 退出 + 失败计数增量不许是 0'
                  ' + 失败返回的守卫不许被改形 + 登记册双向红', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DR · 判据脚本的**失败出口守卫**不许被悄悄改弱
        #   ⇒ 必须与批 DP 那条**放在同一处** ⇒ 前面的检查一红就 exit
        #     ⇒ 这条永远没机会跑 ⇒ 形同虚设（批 DP 同款教训）
        fg_bad = check_fail_guard_shapes()
        if fg_bad:
            print('判据脚本的**失败出口守卫被改弱**（%d 处）'
                  ' ⇒ 那些失败**永远不会被报出来** ⇒ 假绿'
                  % len(fg_bad), file=sys.stderr)
            for fnm, jl, jwhy in fg_bad:
                print('  · scripts/%s%s  %s'
                      % (fnm, (':%d' % jl) if jl else '', jwhy), file=sys.stderr)
            print('  ⇒ 守卫登记册双向红（表达式级）'
                  ' + 守卫里不许有布尔字面量', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DS · 判据脚本的**抽取器**必须被 e2e 自检覆盖
        #   ⇒ 必须与前面那几条**放在同一处** ⇒ 前面的检查一红就 exit
        #     ⇒ 这条永远没机会跑 ⇒ 形同虚设（批 DP 同款教训）
        es_bad = check_extractor_self_tests()
        if es_bad:
            print('判据脚本的**抽取器没有 e2e 自检覆盖**（%d 处）'
                  ' ⇒ 那些抽取器被抽坏 ⇒ 判据看的是**错的东西**而脚本照样绿'
                  % len(es_bad), file=sys.stderr)
            for fnm, jwhy in es_bad:
                print('  · scripts/%s  %s' % (fnm, jwhy), file=sys.stderr)
            print('  ⇒ 抽取器必须**从某个自检函数可达**'
                  '（前缀是单一真相源 ⇒ 新抽取器自动纳入）', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DT · 门型函数的**诊断输出不许随执行 shell 变**
        #   ⇒ 必须与前面那几条**放在同一处** ⇒ 前面的检查一红就 exit
        #     ⇒ 这条永远没机会跑 ⇒ 形同虚设（批 DP 同款教训）
        #   ⇒ `dash` 的 `echo` 解释反斜杠、`bash` 的不解释（POSIX 规定）
        #     ⇒ 同一份脚本两种 shell **输出不同** ⇒ 负控的文案命中判定不可信
        dt_bad = check_gate_output_shell()
        if dt_bad:
            print('门型函数的**诊断输出随执行 shell 变**（%d 处）'
                  ' ⇒ `echo` 解释反斜杠（dash 解释、bash 不解释）'
                  ' ⇒ 同一份脚本在 `sh` 与 `bash` 下输出不同'
                  ' ⇒ **负控的文案命中判定不可信**' % len(dt_bad), file=sys.stderr)
            for fnm, jwhy in dt_bad:
                print('  · scripts/%s  %s' % (fnm, jwhy), file=sys.stderr)
            print('  ⇒ 门型函数体内一律 `printf`（不解释参数里的转义）'
                  ' ⇒ 跨 shell 一致', file=sys.stderr)
            FAILS.append(2)
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
            FAILS.append(9)
        if anchor_exempt_missing:
            print('锚定豁免基线文件不在：%s' % ANCHOR_EXEMPT, file=sys.stderr)
            FAILS.append(9)
        # ⚠⚠⚨ 批 CQ · 「先红遮后红」不许再遮 ⇒ **依赖失败**的检查要**明确跳过**，
        #   不能默默不跑（不跑 = 「没验」⇒ 必须说出来）
        scope_skip = bool(anchor_exempt_bad) or not anchor_exempt_exists
        # ⚠⚠⚨ 批 BL · 锚定形态**自检**（放在**最前**：批 BI 纪律——
        #   自检放在后面 ⇒ 前面的检查一红就 exit ⇒ 自检永远没机会跑 ⇒ 形同虚设）
        stbad = anchoring_selftest()
        if stbad:
            print('锚定形态自检不过（%d 条）⇒ **判定逻辑被掏空了**'
                  % len(stbad), file=sys.stderr)
            for rx, should, got in stbad:
                print('  · 正则=%s  期望判违规=%s  实际判违规=%s'
                      % (rx, should, got), file=sys.stderr)
            FAILS.append(8)
            # ⚠⚠⚨ 批 CQ：锚定判定逻辑**自己坏了** ⇒ 下面两项的结论**不可信**
            #   ⇒ 明确**跳过**（不许默默不跑 ⇒ 不跑 = 「没验」）
            scope_skip = True
        # ⚠⚠⚨ 批 BL/BN · 适用范围（含 `ci.sh`）内的门项必须**整行锚定**
        #   （探针与审计器是「门自己的工具」⇒ 它被掏空 = 门**集体**失效）
        #   ⚠ 第二返回值 = 「需要豁免」的门项集合（= 豁免表的唯一合法来源）
        if scope_skip:
            print('⚠ **跳过**「适用范围整行锚定」与「豁免反向配准」两项检查：'
                  '它们的**输入**不可信（豁免基线坏了/不在，或锚定判定自检不过）'
                  ' ⇒ **不是「没问题」，是「没验」**', file=sys.stderr)
            anchbad, anchor_need = [], set()
        else:
            anchbad, anchor_need = check_anchor_scope(cnt, anchor_exempt)
        if anchbad:
            print('适用范围内的门项**不是整行锚定**（%d 条）⇒ 判定被掏空但串还在 ⇒ 门假绿'
                  % len(anchbad), file=sys.stderr)
            for lineno, f, rx, why in anchbad:
                print('  · %s:%d  %s  %s'
                      % (os.path.basename(WIRING), lineno, f, rx), file=sys.stderr)
                print('      ⇒ %s' % why, file=sys.stderr)
            FAILS.append(8)
        # ⚠⚠⚨ 批 BN · 豁免表**反向配准**（正向在上面的 `check_anchor_scope` 里：
        #   适用范围内的非锚定门项若没被豁免 ⇒ 照红 ⇒ rc=8）
        #   ⚠ 只在**全量**模式下做（`--changed` 只审新增门项 ⇒ 「需要豁免」的集合
        #     不全 ⇒ 反向配准会**误报**「对不上」⇒ 与门项总数核对同一口径）
        if base is None and not scope_skip:
            dead = check_anchor_exempt_reconcile(anchor_need, anchor_exempt)
            if dead:
                print('锚定豁免基线里有**对不上「需要豁免」的门项**的条目（%d 条）⇒ '
                      '要么门项被删/被改写却忘了清豁免（承诺悄悄消失），'
                      '要么塞了空豁免，要么给已锚定的门项白占了行（豁免表在悄悄变长）'
                      % len(dead), file=sys.stderr)
                for kind, path, rx in dead:
                    print('  · %s  %s  %s' % (kind, path, rx), file=sys.stderr)
                FAILS.append(9)
        # ⚠⚠⚠ **门项总数核对**（批 BH）——「门项被悄悄删」此前**无人发现**。
        #   ⚠ 只在**全量**模式下做（--changed 只审新增门项 ⇒ 门项总数本就不全）
        if base is None:
            # ⚠⚠⚠ **门项总数核对**（批 BH）——「门项被悄悄删」此前**无人发现**。
            #   ⚠ 只在**全量**模式下做（--changed 只审新增门项 ⇒ 门项总数本就不全）
            #   ⚠ 判定逻辑在 `check_gate_totals()` 里（**只有一份** ⇒ 报告与硬门不漂）
            g = check_gate_totals()
            # ⚠⚠⚨ 批 CQ · 三类消息**分开打印**（原来混在一起 ⇒ 只报一类时
            #   会把另外两类的消息也打出来 ⇒ 指错方向）
            #   ⚠ **保持「按码值分桶」**（批 CA/CC 纪律：改一个码值 ⇒
            #     旧桶 -1 + 新桶 +1 ⇒ **两条都红**）⇒ 不许用循环写成一个动态 rc
            if g['dups']:
                for m in g['msgs_by_kind']['dups']:
                    print(m, file=sys.stderr)
                FAILS.append(7)
            if g['blind']:
                for m in g['msgs_by_kind']['blind']:
                    print(m, file=sys.stderr)
                FAILS.append(2)
            if g['total_bad']:
                for m in g['msgs_by_kind']['total']:
                    print(m, file=sys.stderr)
                FAILS.append(6)
        # 硬门模式：只吐**豁免之外**的隐患；有 ⇒ 退出码 3（红）
        if exempt_missing:
            print('豁免基线文件不在：%s' % EXEMPT, file=sys.stderr)
            FAILS.append(2)
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
            FAILS.append(2)
        # ⚠⚠⚠ **门项正则的写法体检**（批 AX）：正则里写了 GNU grep -E **不认**的转义
        #   （`\d` / `\D`）⇒ 那条门**永远匹配不到任何东西** ⇒ **门形同虚设**。
        #   ⚠ 对 `arch_forbid` 门这是**静默**失效（forbid 本来就常年绿 ⇒ 写坏了跟没写一样）。
        rxsyn, rxunreg = check_rx_syntax()
        if rxsyn:
            print('门项正则里有 grep -E **不认**的转义（%d 条）⇒ 这些门**永远匹配不到**'
                  % len(rxsyn), file=sys.stderr)
            for lineno, kind, rx, be in rxsyn:
                print('  · %s:%d  [%s] 正则=%s  危险转义=%s'
                      % (os.path.basename(WIRING), lineno, kind, rx,
                         ','.join(t for _, t in be)), file=sys.stderr)
            print('  ⇒ 改用 POSIX 写法：`\\d` → `[0-9]`、`\\D` → `[^0-9]`', file=sys.stderr)
            FAILS.append(5)
        # ⚠⚠⚨ 批 DL · **fail closed**：有门型没登记在正则体检登记册里 ⇒
        #   那一族门项的正则**从来没被体检过** ⇒ 审计器有盲区 ⇒ 必红
        if rxunreg:
            print('有门型**没登记在正则体检登记册**（%d 种）⇒ 那一族门项的正则'
                  '**从来没被体检过**（写坏了也不会有人知道）' % len(rxunreg),
                  file=sys.stderr)
            for kind, lineno in rxunreg:
                print('  · %s:%d  门型 %s ⇒ 登记册 `RX_ARG_IDX` 里没有它'
                      % (os.path.basename(WIRING), lineno, kind), file=sys.stderr)
            print('  ⇒ 要么把它登记进去，要么**显式**登记成「本门型没有正则参数」'
                  '（`None`）⇒ 不许静默跳过', file=sys.stderr)
            FAILS.append(2)
        # ⚠⚠⚨ 批 DL · 两份门型登记册必须一致（漂移即红）
        rxmiss, rxstale = check_rx_registry()
        if rxmiss:
            print('门型清单与正则体检登记册**对不上**（漏登记 %d 种）⇒ 那族门项永远不会被体检'
                  % len(rxmiss), file=sys.stderr)
            for kind in rxmiss:
                print('  · %s' % kind, file=sys.stderr)
            print('  ⇒ 登记册必须**覆盖全部**门型（没有正则参数的显式登记成 `None`）',
                  file=sys.stderr)
            FAILS.append(9)
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
            FAILS.append(5)
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
        cntmlbad = check_count_ml_gates(cntml)
        if cntmlbad:
            print('arch_need_count_ml 期望校准（须 == **压行后**实际次数）：%d 条失准'
                  % len(cntmlbad), file=sys.stderr)
            for cmb in cntmlbad:
                print('  · ci-wiring.sh:%d  %s | %s ⇒ 期望 %d，实际 %d ⇒ %s'
                      % (cmb[0], rel(cmb[1]), cmb[2], cmb[3], cmb[4], cmb[5]),
                      file=sys.stderr)
            FAILS.append(9)
        # ⚠⚠⚨ 批 EA · **说明文字里的条数 == 期望值**（文字撒谎 ⇒ 判红）
        labelbad = check_label_count_text(cnt + cntml)
        if labelbad:
            print('门项的**说明文字里的条数**与期望值对不上（%d 条）⇒ **文字在骗人**'
                  % len(labelbad), file=sys.stderr)
            for lb in labelbad:
                print('  · ci-wiring.sh:%d  %s | %s ⇒ 期望 %d，但说明文字称「恰好 %d 处」'
                      % (lb[0], rel(lb[1]), lb[2], lb[3], lb[4]), file=sys.stderr)
            FAILS.append(9)
        cifbad = check_count_in_fn_gates(cif)
        cisbad = check_count_in_step_gates(cis)
        pairbad = check_pair_count_gates(pair)
        # ⚠⚠⚨ 批 EB · 「静默跳过」体检（零名单维护 ⇒ 扫全文件）
        #   ⇒ 审计器自己**不许**有「工具坏了 ⇒ 跳过校准」的那种写法
        #   ⇒ 报失准 ⇒ rc=2（盲区：那些门项**根本没被审**）
        skipbad = check_silent_tool_skip(AUDIT_SELF)
        if skipbad:
            print('审计器自己有「**静默略过**」的写法（%d 处）⇒ **工具坏了 ⇒ 那些门项'
                  '根本没被校准** ⇒ 判红' % len(skipbad), file=sys.stderr)
            for sb in skipbad:
                print('  · %s:%d  %s' % (os.path.basename(AUDIT_SELF), sb[0], sb[1]),
                      file=sys.stderr)
            FAILS.append(2)
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
            FAILS.append(4)
        for k in outside:
            print(k)
        # ⚠⚠⚨ 批 CQ · rc 取**最先失败**的那个（与旧行为**完全一致** ⇒
        #   门侧按 rc 分诊的文案表零改动）⇒ 差别只在「**其余失败也一并报出来**」
        # ⚠⚠⚨ 批 EB：工具用不了 ⇒ 那些次数门**没被校准** ⇒ ⇒ 判红（fail closed）
        #   ⇒ ⚠⚠⚨ **必须先跑** `tool_failure_rc()`（**无条件**）⇒ 否则
        #     `FAILS[0] if FAILS else …` 会**短路** ⇒ ⇒ 工具失败的消息**丢失**
        #     ⇒ ⇒ 实测：grep 挂掉时收口消息**根本没打印**（只印了逐条失准）
        _tool_rc = tool_failure_rc()
        return FAILS[0] if FAILS else (_tool_rc or (3 if outside else 0))

    print('门自审计：ci-wiring.sh 里的门项')
    print('  arch_need %d 条 / arch_need_ml %d 条 / arch_need_any_count %d 条 / '
          'arch_need_any_min %d 条' % (totals['need'], totals['ml'],
                                        totals['any_count'], totals['any_min']))
    print('  arch_need_count_ml %d 条（批 EF 新门型：**跨行**、**恰好** N 次）'
          % totals['count_ml'])
    print('  arch_need_count %d 条 / arch_need_count_in_fn %d 条'
          % (totals['count'], totals['count_in_fn']))
    print('  arch_need_count_in_step %d 条（批 BE 新门型：盯「标记串**还在这一步里**」）'
          % totals['count_in_step'])
    print('  arch_need_count_pair %d 条（批 BZ 新门型：盯「**报错行数 == 计数行数**」'
          '；⚠⚠⚨ 批 CS：审计器侧**逐段**核对 ⇒ 每段恰好 1 处计数）'
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
    rxsyn, rxunreg = check_rx_syntax()
    print('门项正则写法体检（grep -E 认不认）：%d 条危险' % len(rxsyn))
    for lineno, kind, rx, be in rxsyn:
        print('  · %s:%d  [%s] 正则=%s  危险转义=%s'
              % (os.path.basename(WIRING), lineno, kind, rx,
                 ','.join(t for _, t in be)))
    if rxsyn:
        print('   ⇒ 这些门**永远匹配不到**（形同虚设）⇒ 改用 POSIX 写法（`\\d` → `[0-9]`）')
    print('⚠ 没登记在正则体检登记册里的门型：%d 种' % len(rxunreg))
    for kind, lineno in rxunreg:
        print('  · %s:%d  %s' % (os.path.basename(WIRING), lineno, kind))
    rxmiss, rxstale = check_rx_registry()
    print('门型清单与正则体检登记册对不上：漏登记 %d 种 / 陈旧登记 %d 种'
          % (len(rxmiss), len(rxstale)))
    for kind in rxmiss:
        print('  · 漏登记 %s' % kind)
    for kind in rxstale:
        print('  · 陈旧登记 %s（没人用这一族门项了）' % kind)
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
    judgerep = check_judge_funcs()
    print('判定函数**被掏空**（返回字面量）：%d 处' % len(judgerep))
    for fnm, jl, jwhy in judgerep:
        print('  · %s:%d  %s  ⇒ %s'
              % (os.path.basename(os.path.abspath(__file__)), jl, fnm, jwhy))
    selfrep = check_self_test_funcs()
    print('判据脚本里的**自检函数被掏空**：%d 处' % len(selfrep))
    for fnm, fn2, jl, jwhy in selfrep:
        print('  · scripts/%s:%d  %s  ⇒ %s' % (fnm, jl, fn2, jwhy))
    guardrep = check_fail_guards()
    print('审计器自己的**失败态上报被静默关掉**：%d 处' % len(guardrep))
    for jl, jwhy in guardrep:
        print('  · ci-wiring-audit.py:%d  %s' % (jl, jwhy))
    frrep = check_fail_report_points()
    print('判据脚本的**失败态上报被静默关掉**：%d 处' % len(frrep))
    for fnm, jl, jwhy in frrep:
        print('  · scripts/%s:%d  %s' % (fnm, jl, jwhy))
    fgrep = check_fail_guard_shapes()
    print('判据脚本的**失败出口守卫被改弱**：%d 处' % len(fgrep))
    for fnm, jl, jwhy in fgrep:
        print('  · scripts/%s:%d  %s' % (fnm, jl, jwhy))
    esrep = check_extractor_self_tests()
    print('判据脚本的**抽取器没有 e2e 自检覆盖**：%d 处' % len(esrep))
    for fnm, jwhy in esrep:
        print('  · scripts/%s  %s' % (fnm, jwhy))
    dtrep = check_gate_output_shell()
    print('门型函数的**诊断输出随执行 shell 变**：%d 处' % len(dtrep))
    for fnm, jwhy in dtrep:
        print('  · scripts/%s  %s' % (fnm, jwhy))
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
    cntmlbad = check_count_ml_gates(cntml)
    print('arch_need_count_ml 期望校准（须 == **压行后**实际次数）：%d 条失准'
          % len(cntmlbad))
    for cmb in cntmlbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), cmb[0], rel(cmb[1]), cmb[2], cmb[5]))
    # ⚠⚠⚨ 批 EA · **说明文字里的条数 == 期望值**（文字撒谎 ⇒ 判红）
    labelbad = check_label_count_text(cnt + cntml)
    if labelbad:
        print('门项的**说明文字里的条数**与期望值对不上（%d 条）⇒ **文字在骗人**'
              % len(labelbad), file=sys.stderr)
        for lb in labelbad:
            print('  · ci-wiring.sh:%d  %s | %s ⇒ 期望 %d，但说明文字称「恰好 %d 处」'
                  % (lb[0], rel(lb[1]), lb[2], lb[3], lb[4]), file=sys.stderr)
    # ⚠⚠⚨ 批 EB · 「静默跳过」体检（零名单维护 ⇒ 扫全文件）
    skipbad = check_silent_tool_skip(AUDIT_SELF)
    if skipbad:
        print('审计器自己有「**静默略过**」的写法（%d 处）⇒ **工具坏了 ⇒ 那些门项'
              '根本没被校准** ⇒ 判红' % len(skipbad))
        for sb in skipbad:
            print('  · %s:%d  %s' % (os.path.basename(AUDIT_SELF), sb[0], sb[1]))
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
    print('arch_need_count_pair 期望校准（须 **报错行数 == 计数行数** == 期望'
          ' **且逐段配对**（每段恰好 1 处计数 ⇒ 批 CS））：%d 条失准'
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
    # ⚠⚠⚨ 批 EB：工具用不了 ⇒ 那些次数门**没被校准** ⇒ ⇒ 判红（fail closed）
    return tool_failure_rc() or 0


def parse_min_gates():
    """解析所有 `arch_need_min` 门项 ⇒ [(行号, 文件, 正则, 下限)]"""
    out = []
    src = read_source(WIRING)
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
# ⚠ `arch_forbid_han`（盯内容不看写法）与 `arch_forbid_text_dup`（盯重复文本）没有正则参数
#   ⇒ 批 DL 起**显式**登记为 None（见下）⇒ 「显式没有」与「漏登记」可区分。
# ⚠⚠⚨ 批 DL · 值可以是**元组** ⇒ 一个门型有**多个**正则实参时全都要体检
#   （配对门 `arch_need_count_pair` = 报错行正则 + 计数行正则）。
RX_ARG_IDX = {
    'arch_need': 1, 'arch_need_ml': 1, 'arch_need_min': 1,
    'arch_need_count': 1, 'arch_need_count_in_fn': 2,
    # ⚠⚠⚨ 批 EF 新门型：跨行、恰好 N 次（正则实参在第 2 个参数 ⇒ index 1）
    'arch_need_count_ml': 1,
    # ⚠ 批 BE 新门型：<文件> <步号> <正则> <期望次数> ⇒ 正则在第 3 个参数（index 2）
    'arch_need_count_in_step': 2,
    'arch_need_any_count': 0, 'arch_need_any_min': 0,
    'arch_forbid': 1, 'arch_forbid_ml': 1, 'arch_forbid_raw': 1,
    'arch_forbid_tree': 0,
    # ⚠⚠⚨ 批 DL · **配对门有两个正则实参**（报错行正则 + 计数行正则）
    #   ⇒ 以前登记册只支持「一个下标」⇒ 这一族**根本没被登记** ⇒
    #   ⇒ 那 14 个正则**从来没被体检过**（写坏了也不会有人知道）。
    'arch_need_count_pair': (1, 2),
    # ⚠⚠⚨ 批 DL · 本门型**没有正则参数**（盯内容不看写法）⇒ **显式**登记为 None
    #   ⇒ 「显式没有」与「漏登记」从此**可区分** ⇒ fail closed 才有意义
    #   ⇒ 否则漏登记会被误当成「这一族本来就没有正则」。
    'arch_forbid_han': None, 'arch_forbid_text_dup': None,
}
GATE_LINE = re.compile(r'^\s*(arch_[a-z_]+)\s+(.*)$')


def check_bad_escapes(rx):
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


def rx_arg_indices(kind):
    """门型 → **正则参数**的下标列表（0-based）。

    ⚠ 返回 `None` = **该门型没登记** ⇒ 调用方**必须判红**（fail closed）
    ⚠ 返回 `[]`  = **该门型显式登记为「没有正则参数」**（盯内容不看写法的门型）
    ⚠ 返回 `(i,)` / `(i, j)` = 该门型的正则参数下标（**配对门有两个**）

    ⚠⚠⚨ 批 DL · 以前这里是 `RX_ARG_IDX.get(kind)` ⇒ 取不到就 `continue`
      ⇒ **静默跳过** ⇒ 那一族门项的正则**从来没被体检过**
      ⇒ ⚠⚠⚨ **实测坐实**：删登记册一行 ⇒ 审计器 rc=0 + 接线门 rc=0
      ⇒ 一条「永远匹配不到任何东西」的门项就这么混过去了 ⇒ **假绿坐实**。
    ⇒ 现在「取不到」与「显式没有」是**两回事** ⇒ 取不到必须报出来。
    """
    if kind not in RX_ARG_IDX:
        return None
    v = RX_ARG_IDX[kind]
    if v is None:
        return []
    return tuple(v) if isinstance(v, tuple) else (v,)


def gate_kind_names():
    """审计器**认领**的门型名单（`GATE_TYPES` 的键，统一补 `arch_` 前缀）。"""
    return set('arch_' + name for name, _ in GATE_TYPES)


def check_rx_registry():
    """两份门型登记册（`GATE_TYPES` 与 `RX_ARG_IDX`）必须对得上 ⇒ (漏登记, 陈旧登记)

    ⚠⚠⚨ 批 DL · **实测坐实的洞**：两份登记册**已经漂移** ⇒
      `arch_need_count_pair`（在用 7 条门项 / **14 个**正则实参）不在 `RX_ARG_IDX` 里
      ⇒ 那 14 个正则**从来没被体检过** ⇒ 而 `RX_ARG_IDX` **全仓没有任何门在盯**
      ⇒ 删一行 ⇒ 覆盖面**静默缩小** ⇒ **假绿坐实**。
    ⚠ 漏登记 = **红**（那族门项的体检是空的 ⇒ 审计器有盲区）
    ⚠ 陈旧登记（登记了但没人用）= **只报不红**
      ⇒ 多登记 = 体检范围更广 = **安全方向** ⇒ 假红比假绿更坏 ⇒ 不判红。
    """
    want = gate_kind_names()
    have = set(RX_ARG_IDX.keys())
    return sorted(want - have), sorted(have - want)


def check_rx_syntax():
    """体检**所有**门项的正则参数 ⇒ (危险转义列表, 未登记门型列表)

    ⚠⚠⚨ 批 DL · **fail closed**：门型没登记 ⇒ **不再静默跳过**
      ⇒ 记进 `unreg` ⇒ 调用方判红（rc=2 盲区）。
    """
    bad = []
    unreg = {}
    src = read_source(WIRING)
    for i, ln in enumerate(src.split('\n'), 1):
        m = GATE_LINE.match(ln)
        if not m:
            continue
        kind, rest = m.group(1), m.group(2)
        idxs = rx_arg_indices(kind)
        if idxs is None:
            # ⚠⚠⚨ 批 DL：这一族门项的正则**从来没被体检过** ⇒ 记下来判红
            if kind not in unreg:
                unreg[kind] = i
            continue
        if not idxs:
            continue
        args = split_args(rest)
        for idx in idxs:
            if len(args) <= idx:
                continue
            rx = args[idx]
            be = check_bad_escapes(rx)
            if be:
                bad.append((i, kind, rx, be))
    return bad, sorted(unreg.items())


if __name__ == '__main__':
    sys.exit(main())
