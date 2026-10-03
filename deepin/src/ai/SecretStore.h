// SecretStore.h — API Key 安全存储（mac Keychain 的 libsecret 对位，PLAN §2.5）。
//
// schema 属性：service=cn.deepdolphin.app.ai, account=api-key，collection 默认。
// 写入先 delete（item-not-found 视为正常）再 store；三函数全查返回值。
// 调用走 QThreadPool（GLib _sync API 阻塞——本类提供同步原语，调用方自选线程）。
// key 永不进引擎/日志；错误信息脱敏。
#pragma once
#include <QString>

class SecretStore {
public:
    enum class Status { Ok, ItemNotFound, Failed };

    Status save(const QString &key, QString *errOut);
    struct LoadResult {
        Status st = Status::Failed;
        QString key;
        QString err;
    };
    LoadResult load();
    Status remove(QString *errOut);

    // libsecret/glib 错误码 → 可读中文（readableOsStatus 对位）。
    static QString readableOsStatus(int code);

private:
    // 「key 没能存进安全存储（…）—— 设置会丢失，请重试或检查钥匙串权限」
    static QString saveFailure(const QString &detail);
};
