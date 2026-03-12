#include "include/dexbar_bridge.h"
#include <libsecret/secret.h>
#include <stdlib.h>
#include <string.h>

static const SecretSchema dexbar_schema = {
    "com.dexbar.credentials",
    SECRET_SCHEMA_NONE,
    {
        { "application", SECRET_SCHEMA_ATTRIBUTE_STRING },
        { "key",         SECRET_SCHEMA_ATTRIBUTE_STRING },
        { NULL, 0 }
    }
};

static const char *APP_LABEL = "DexBar — Dexcom credentials";

gboolean dexbar_secret_store(const char *schema_name, const char *key, const char *value) {
    GError *err = NULL;
    gboolean ok = secret_password_store_sync(
        &dexbar_schema,
        SECRET_COLLECTION_DEFAULT,
        APP_LABEL,
        value,
        NULL,
        &err,
        "application", schema_name,
        "key",         key,
        NULL
    );
    if (err) g_error_free(err);
    return ok;
}

char *dexbar_secret_load(const char *schema_name, const char *key) {
    GError *err = NULL;
    char *result = secret_password_lookup_sync(
        &dexbar_schema,
        NULL,
        &err,
        "application", schema_name,
        "key",         key,
        NULL
    );
    if (err) g_error_free(err);
    return result;  // caller must call secret_password_free()
}

void dexbar_secret_delete(const char *schema_name, const char *key) {
    GError *err = NULL;
    secret_password_clear_sync(
        &dexbar_schema,
        NULL,
        &err,
        "application", schema_name,
        "key",         key,
        NULL
    );
    if (err) g_error_free(err);
}
