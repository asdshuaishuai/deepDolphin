#include "SyntaxHighlight.h"

#include <QHash>

namespace SyntaxHighlight {
namespace {

/// 九种语言的关键词集（与引擎 `detectLang` 的九种语言一一对应）。
///
/// 词表来自 mac 的 `CodeSnippet.swift`（同一产品的同一份语言支持）——
/// 两端同源，改一处要改两处。
const QHash<QString, QSet<QString>> &keywordTable()
{
    static const QHash<QString, QSet<QString>> table = {
        { QStringLiteral("cangjie"),
            { QStringLiteral("package"), QStringLiteral("import"), QStringLiteral("class"),
                QStringLiteral("struct"), QStringLiteral("enum"), QStringLiteral("interface"),
                QStringLiteral("extend"), QStringLiteral("func"), QStringLiteral("let"),
                QStringLiteral("var"), QStringLiteral("const"), QStringLiteral("match"),
                QStringLiteral("case"), QStringLiteral("if"), QStringLiteral("else"),
                QStringLiteral("while"), QStringLiteral("for"), QStringLiteral("return"),
                QStringLiteral("try"), QStringLiteral("catch"), QStringLiteral("throw"),
                QStringLiteral("true"), QStringLiteral("false"), QStringLiteral("this"),
                QStringLiteral("super"), QStringLiteral("init"), QStringLiteral("override"),
                QStringLiteral("public"), QStringLiteral("private"), QStringLiteral("internal"),
                QStringLiteral("protected"), QStringLiteral("static"), QStringLiteral("abstract"),
                QStringLiteral("open"), QStringLiteral("where"), QStringLiteral("in"),
                QStringLiteral("as"), QStringLiteral("is"), QStringLiteral("spawn"),
                QStringLiteral("prop"), QStringLiteral("volatile"), QStringLiteral("unsafe"),
                QStringLiteral("mut"), QStringLiteral("ref"), QStringLiteral("final"),
                QStringLiteral("sealed"), QStringLiteral("typealias"), QStringLiteral("operator"),
                QStringLiteral("infix") } },
        { QStringLiteral("swift"),
            { QStringLiteral("import"), QStringLiteral("class"), QStringLiteral("struct"),
                QStringLiteral("enum"), QStringLiteral("protocol"), QStringLiteral("func"),
                QStringLiteral("let"), QStringLiteral("var"), QStringLiteral("if"),
                QStringLiteral("else"), QStringLiteral("guard"), QStringLiteral("while"),
                QStringLiteral("for"), QStringLiteral("return"), QStringLiteral("try"),
                QStringLiteral("catch"), QStringLiteral("throw"), QStringLiteral("true"),
                QStringLiteral("false"), QStringLiteral("self"), QStringLiteral("super"),
                QStringLiteral("init"), QStringLiteral("override"), QStringLiteral("public"),
                QStringLiteral("private"), QStringLiteral("internal"),
                QStringLiteral("fileprivate"), QStringLiteral("open"), QStringLiteral("static"),
                QStringLiteral("final"), QStringLiteral("where"), QStringLiteral("in"),
                QStringLiteral("as"), QStringLiteral("is"), QStringLiteral("extension"),
                QStringLiteral("weak"), QStringLiteral("unowned"), QStringLiteral("lazy"),
                QStringLiteral("mutating"), QStringLiteral("didSet"), QStringLiteral("willSet"),
                QStringLiteral("some"), QStringLiteral("any"), QStringLiteral("async"),
                QStringLiteral("await"), QStringLiteral("throws"), QStringLiteral("rethrows"),
                QStringLiteral("case"), QStringLiteral("switch"), QStringLiteral("default"),
                QStringLiteral("break"), QStringLiteral("continue"),
                QStringLiteral("fallthrough") } },
        { QStringLiteral("ts"),
            { QStringLiteral("import"), QStringLiteral("export"), QStringLiteral("from"),
                QStringLiteral("class"), QStringLiteral("extends"),
                QStringLiteral("implements"), QStringLiteral("interface"),
                QStringLiteral("type"), QStringLiteral("enum"), QStringLiteral("function"),
                QStringLiteral("const"), QStringLiteral("let"), QStringLiteral("var"),
                QStringLiteral("if"), QStringLiteral("else"), QStringLiteral("while"),
                QStringLiteral("for"), QStringLiteral("of"), QStringLiteral("in"),
                QStringLiteral("return"), QStringLiteral("try"), QStringLiteral("catch"),
                QStringLiteral("throw"), QStringLiteral("true"), QStringLiteral("false"),
                QStringLiteral("null"), QStringLiteral("undefined"), QStringLiteral("this"),
                QStringLiteral("super"), QStringLiteral("new"), QStringLiteral("delete"),
                QStringLiteral("typeof"), QStringLiteral("instanceof"), QStringLiteral("void"),
                QStringLiteral("async"), QStringLiteral("await"), QStringLiteral("yield"),
                QStringLiteral("static"), QStringLiteral("get"), QStringLiteral("set"),
                QStringLiteral("public"), QStringLiteral("private"), QStringLiteral("protected"),
                QStringLiteral("readonly"), QStringLiteral("abstract"), QStringLiteral("as"),
                QStringLiteral("is"), QStringLiteral("break"), QStringLiteral("continue"),
                QStringLiteral("case"), QStringLiteral("switch"), QStringLiteral("default"),
                QStringLiteral("do") } },
        { QStringLiteral("python"),
            { QStringLiteral("import"), QStringLiteral("from"), QStringLiteral("class"),
                QStringLiteral("def"), QStringLiteral("lambda"), QStringLiteral("if"),
                QStringLiteral("elif"), QStringLiteral("else"), QStringLiteral("while"),
                QStringLiteral("for"), QStringLiteral("in"), QStringLiteral("return"),
                QStringLiteral("try"), QStringLiteral("except"), QStringLiteral("finally"),
                QStringLiteral("raise"), QStringLiteral("True"), QStringLiteral("False"),
                QStringLiteral("None"), QStringLiteral("self"), QStringLiteral("super"),
                QStringLiteral("global"), QStringLiteral("nonlocal"), QStringLiteral("yield"),
                QStringLiteral("async"), QStringLiteral("await"), QStringLiteral("with"),
                QStringLiteral("as"), QStringLiteral("pass"), QStringLiteral("break"),
                QStringLiteral("continue"), QStringLiteral("and"), QStringLiteral("or"),
                QStringLiteral("not"), QStringLiteral("is"), QStringLiteral("del") } },
        { QStringLiteral("go"),
            { QStringLiteral("package"), QStringLiteral("import"), QStringLiteral("func"),
                QStringLiteral("var"), QStringLiteral("const"), QStringLiteral("type"),
                QStringLiteral("struct"), QStringLiteral("interface"), QStringLiteral("map"),
                QStringLiteral("chan"), QStringLiteral("go"), QStringLiteral("defer"),
                QStringLiteral("if"), QStringLiteral("else"), QStringLiteral("for"),
                QStringLiteral("range"), QStringLiteral("return"), QStringLiteral("switch"),
                QStringLiteral("case"), QStringLiteral("default"), QStringLiteral("true"),
                QStringLiteral("false"), QStringLiteral("nil"), QStringLiteral("break"),
                QStringLiteral("continue"), QStringLiteral("goto"),
                QStringLiteral("fallthrough"), QStringLiteral("select") } },
        { QStringLiteral("rust"),
            { QStringLiteral("fn"), QStringLiteral("let"), QStringLiteral("mut"),
                QStringLiteral("const"), QStringLiteral("struct"), QStringLiteral("enum"),
                QStringLiteral("trait"), QStringLiteral("impl"), QStringLiteral("for"),
                QStringLiteral("in"), QStringLiteral("if"), QStringLiteral("else"),
                QStringLiteral("while"), QStringLiteral("loop"), QStringLiteral("match"),
                QStringLiteral("return"), QStringLiteral("true"), QStringLiteral("false"),
                QStringLiteral("self"), QStringLiteral("Self"), QStringLiteral("super"),
                QStringLiteral("crate"), QStringLiteral("mod"), QStringLiteral("pub"),
                QStringLiteral("use"), QStringLiteral("extern"), QStringLiteral("as"),
                QStringLiteral("where"), QStringLiteral("async"), QStringLiteral("await"),
                QStringLiteral("move"), QStringLiteral("ref"), QStringLiteral("dyn"),
                QStringLiteral("type"), QStringLiteral("unsafe"), QStringLiteral("break"),
                QStringLiteral("continue") } },
        { QStringLiteral("java"),
            { QStringLiteral("package"), QStringLiteral("import"), QStringLiteral("class"),
                QStringLiteral("interface"), QStringLiteral("enum"), QStringLiteral("record"),
                QStringLiteral("extends"), QStringLiteral("implements"),
                QStringLiteral("public"), QStringLiteral("private"), QStringLiteral("protected"),
                QStringLiteral("static"), QStringLiteral("final"), QStringLiteral("abstract"),
                QStringLiteral("void"), QStringLiteral("int"), QStringLiteral("long"),
                QStringLiteral("double"), QStringLiteral("float"), QStringLiteral("boolean"),
                QStringLiteral("char"), QStringLiteral("byte"), QStringLiteral("short"),
                QStringLiteral("if"), QStringLiteral("else"), QStringLiteral("while"),
                QStringLiteral("for"), QStringLiteral("return"), QStringLiteral("try"),
                QStringLiteral("catch"), QStringLiteral("finally"), QStringLiteral("throw"),
                QStringLiteral("throws"), QStringLiteral("true"), QStringLiteral("false"),
                QStringLiteral("null"), QStringLiteral("this"), QStringLiteral("super"),
                QStringLiteral("new"), QStringLiteral("instanceof"),
                QStringLiteral("synchronized"), QStringLiteral("volatile"),
                QStringLiteral("transient"), QStringLiteral("default"),
                QStringLiteral("sealed"), QStringLiteral("permits"), QStringLiteral("var"),
                QStringLiteral("break"), QStringLiteral("continue"), QStringLiteral("do"),
                QStringLiteral("switch"), QStringLiteral("case") } },
        { QStringLiteral("kotlin"),
            { QStringLiteral("package"), QStringLiteral("import"), QStringLiteral("class"),
                QStringLiteral("object"), QStringLiteral("interface"), QStringLiteral("fun"),
                QStringLiteral("val"), QStringLiteral("var"), QStringLiteral("if"),
                QStringLiteral("else"), QStringLiteral("when"), QStringLiteral("while"),
                QStringLiteral("for"), QStringLiteral("return"), QStringLiteral("try"),
                QStringLiteral("catch"), QStringLiteral("finally"), QStringLiteral("throw"),
                QStringLiteral("true"), QStringLiteral("false"), QStringLiteral("null"),
                QStringLiteral("this"), QStringLiteral("super"), QStringLiteral("init"),
                QStringLiteral("override"), QStringLiteral("open"), QStringLiteral("abstract"),
                QStringLiteral("final"), QStringLiteral("sealed"), QStringLiteral("data"),
                QStringLiteral("companion"), QStringLiteral("internal"),
                QStringLiteral("private"), QStringLiteral("protected"),
                QStringLiteral("public"), QStringLiteral("lateinit"), QStringLiteral("lazy"),
                QStringLiteral("by"), QStringLiteral("is"), QStringLiteral("as"),
                QStringLiteral("in"), QStringLiteral("out"), QStringLiteral("reified"),
                QStringLiteral("suspend"), QStringLiteral("inline"),
                QStringLiteral("operator"), QStringLiteral("infix"),
                QStringLiteral("external"), QStringLiteral("const"), QStringLiteral("break"),
                QStringLiteral("continue"), QStringLiteral("do") } },
        { QStringLiteral("c"),
            { QStringLiteral("auto"), QStringLiteral("break"), QStringLiteral("case"),
                QStringLiteral("char"), QStringLiteral("const"), QStringLiteral("continue"),
                QStringLiteral("default"), QStringLiteral("do"), QStringLiteral("double"),
                QStringLiteral("else"), QStringLiteral("enum"), QStringLiteral("extern"),
                QStringLiteral("float"), QStringLiteral("for"), QStringLiteral("goto"),
                QStringLiteral("if"), QStringLiteral("inline"), QStringLiteral("int"),
                QStringLiteral("long"), QStringLiteral("register"), QStringLiteral("restrict"),
                QStringLiteral("return"), QStringLiteral("short"), QStringLiteral("signed"),
                QStringLiteral("sizeof"), QStringLiteral("static"), QStringLiteral("struct"),
                QStringLiteral("switch"), QStringLiteral("typedef"), QStringLiteral("union"),
                QStringLiteral("unsigned"), QStringLiteral("void"), QStringLiteral("volatile"),
                QStringLiteral("while"), QStringLiteral("class"), QStringLiteral("public"),
                QStringLiteral("private"), QStringLiteral("protected"),
                QStringLiteral("virtual"), QStringLiteral("override"), QStringLiteral("final"),
                QStringLiteral("template"), QStringLiteral("typename"),
                QStringLiteral("namespace"), QStringLiteral("using"), QStringLiteral("new"),
                QStringLiteral("delete"), QStringLiteral("nullptr"),
                QStringLiteral("constexpr"), QStringLiteral("noexcept") } },
    };
    return table;
}

bool isIdentStart(QChar c)
{
    return c.isLetter() || c == QLatin1Char('_');
}

bool isIdentChar(QChar c)
{
    return c.isLetter() || c == QLatin1Char('_') || c.isNumber();
}

/// 十六进制数字（Qt6 移除了 QChar::isHexDigit —— 自己判，省得依赖版本差异）。
bool isHexDigit(QChar c)
{
    return (c >= QLatin1Char('0') && c <= QLatin1Char('9'))
        || (c >= QLatin1Char('a') && c <= QLatin1Char('f'))
        || (c >= QLatin1Char('A') && c <= QLatin1Char('F'));
}

} // namespace

QVector<QString> languages()
{
    // 顺序 = 引擎 detectLang 的判定顺序（swift → cangjie → ts → python → go → rust →
    // java → kotlin → c），便于两边逐条比对。
    return { QStringLiteral("swift"), QStringLiteral("cangjie"), QStringLiteral("ts"),
        QStringLiteral("python"), QStringLiteral("go"), QStringLiteral("rust"),
        QStringLiteral("java"), QStringLiteral("kotlin"), QStringLiteral("c") };
}

bool supportsLanguage(const QString &lang)
{
    return keywordTable().contains(lang);
}

QSet<QString> keywords(const QString &lang)
{
    const auto &table = keywordTable();
    auto it = table.constFind(lang);
    if (it == table.constEnd())
        it = table.constFind(QStringLiteral("cangjie")); // 不认识 → 回落仓颉（mac 同款）
    return it.value();
}

QString lineCommentPrefix(const QString &lang)
{
    return lang == QLatin1String("python") ? QStringLiteral("#") : QStringLiteral("//");
}

QVector<Span> highlight(const QString &line, const QString &lang)
{
    QVector<Span> spans;
    if (line.isEmpty())
        return spans;
    const QSet<QString> kws = keywords(lang);
    const QString cmPrefix = lineCommentPrefix(lang);
    const QString trimmed = line.trimmed();

    // 整行注释 → 一整段（mac 同款：整行灰）
    if (trimmed.startsWith(cmPrefix)) {
        spans.append(Span { 0, static_cast<int>(line.size()), Kind::comment });
        return spans;
    }

    const int n = line.size();
    int i = 0;
    while (i < n) {
        const QChar c = line.at(i);
        // 字符串（含闭合引号）
        if (c == QLatin1Char('"') || c == QLatin1Char('\'')) {
            int j = i + 1;
            while (j < n && line.at(j) != c)
                ++j;
            const int end = qMin(j + 1, n);
            spans.append(Span { i, end - i, Kind::string });
            i = end;
            continue;
        }
        // 行注释（吃到行尾）
        if (i + 1 < n && c == QLatin1Char('/') && line.at(i + 1) == QLatin1Char('/')) {
            spans.append(Span { i, n - i, Kind::comment });
            break;
        }
        if (c == QLatin1Char('#') && lang == QLatin1String("python")) {
            spans.append(Span { i, n - i, Kind::comment });
            break;
        }
        // 标识符 → 关键字
        if (isIdentStart(c)) {
            int j = i;
            while (j < n && isIdentChar(line.at(j)))
                ++j;
            const QString word = line.mid(i, j - i);
            if (kws.contains(word))
                spans.append(Span { i, j - i, Kind::keyword });
            i = j;
            continue;
        }
        // 数字（十进制/十六进制/小数）
        if (c.isNumber()) {
            int j = i;
            while (j < n
                && (line.at(j).isNumber() || isHexDigit(line.at(j))
                    || line.at(j) == QLatin1Char('x') || line.at(j) == QLatin1Char('X')
                    || line.at(j) == QLatin1Char('.')))
                ++j;
            spans.append(Span { i, j - i, Kind::number });
            i = j;
            continue;
        }
        ++i;
    }
    return spans;
}

} // namespace SyntaxHighlight
