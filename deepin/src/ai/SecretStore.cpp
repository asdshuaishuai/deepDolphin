// ⚠️ 本头必须先于任何 Qt 头：glib/gio 的结构体有名为 `signals` 的成员，
// 而 Qt 把 `signals` 定义成宏（=public）——include 顺序错了会炸出
// 「expected unqualified-id before 'public'」。
#include <libsecret/secret.h>
#include "SecretStore.h"
#include <DLog>

DCORE_USE_NAMESPACE

namespace {
constexpr char kSchemaName[] = "cn.deepdolphin.app.ai";
constexpr char kAttrService[] = "service";
constexpr char kAttrAccount[] = "account";
constexpr char kServiceValue[] = "cn.deepdolphin.app.ai";
constexpr char kAccountValue[] = "api-key";
constexpr char kLabel[] = "deepDolphin AI API Key";

// 自建 schema（attributes：service/account，均 STRING）。
// 不用 static const 全量初始化（attributes[32] 尾部清零交给聚合初始化缺省填充）。
const SecretSchema *schema()
{
    static SecretSchema s = {};
    static bool inited = false;
    if (!inited) {
        s.name = kSchemaName;
        s.flags = SECRET_SCHEMA_NONE;
        s.attributes[0].name = kAttrService;
        s.attributes[0].type = SECRET_SCHEMA_ATTRIBUTE_STRING;
        s.attributes[1].name = kAttrAccount;
        s.attributes[1].type = SECRET_SCHEMA_ATTRIBUTE_STRING;
        inited = true;
    }
    return &s;
}
} // namespace

QString SecretStore::saveFailure(const QString &detail)
{
    return QStringLiteral("key 没能存进安全存储（%1）—— 设置会丢失，请重试或检查钥匙串权限")
        .arg(detail);
}

QString SecretStore::readableOsStatus(int code)
{
    // libsecret/glib 常见错误的可读中文
    switch (code) {
    case 1:
        return QStringLiteral("密钥环未解锁");
    case 2:
        return QStringLiteral("没有这样的条目");
    case 3:
        return QStringLiteral("已取消");
    case 4:
        return QStringLiteral("已存在同名条目");
    case 5:
        return QStringLiteral("密钥环不可用");
    case 6:
        return QStringLiteral("操作失败");
    default:
        return QStringLiteral("错误码 %1").arg(code);
    }
}

SecretStore::Status SecretStore::save(const QString &key, QString *errOut)
{
    GError *err = nullptr;
    // 写入先 delete（item-not-found 视为正常——旧值不存在也算清干净）
    secret_password_clear_sync(schema(), nullptr, &err, kAttrService, kServiceValue, kAttrAccount,
        kAccountValue, nullptr);
    if (err) {
        g_error_free(err); // 清除失败不致命：store 会覆盖同 schema+attributes 条目
        err = nullptr;
    }
    const gboolean ok = secret_password_store_sync(schema(), SECRET_COLLECTION_DEFAULT, kLabel,
        key.toUtf8().constData(), nullptr, &err, kAttrService, kServiceValue, kAttrAccount,
        kAccountValue, nullptr);
    if (!ok) {
        // 只打错误类型，不打 key 本体（日志不许出现凭据）
        dWarning() << "secret store 保存失败:" << (err ? err->message : "写入被拒绝");
        if (errOut)
            *errOut = saveFailure(err && err->message ? QString::fromUtf8(err->message)
                                                      : QStringLiteral("写入被拒绝"));
        if (err)
            g_error_free(err);
        return Status::Failed;
    }
    return Status::Ok;
}

SecretStore::LoadResult SecretStore::load()
{
    LoadResult r;
    GError *err = nullptr;
    gchar *value = secret_password_lookup_sync(schema(), nullptr, &err, kAttrService, kServiceValue,
        kAttrAccount, kAccountValue, nullptr);
    if (err) {
        r.st = Status::Failed;
        r.err = QString::fromUtf8(err->message);
        dWarning() << "secret store 读取失败:" << err->message;
        g_error_free(err);
        return r;
    }
    if (!value) {
        r.st = Status::ItemNotFound; // 还没存过 = 正常（调用方退回明文/mock 通道）
        return r;
    }
    r.st = Status::Ok;
    r.key = QString::fromUtf8(value);
    secret_password_free(value);
    return r;
}

SecretStore::Status SecretStore::remove(QString *errOut)
{
    GError *err = nullptr;
    const gboolean ok = secret_password_clear_sync(schema(), nullptr, &err, kAttrService,
        kServiceValue, kAttrAccount, kAccountValue, nullptr);
    if (!ok) {
        if (errOut)
            *errOut = err && err->message ? QString::fromUtf8(err->message)
                                          : QStringLiteral("清除失败");
        if (err)
            g_error_free(err);
        return Status::Failed;
    }
    return Status::Ok;
}
