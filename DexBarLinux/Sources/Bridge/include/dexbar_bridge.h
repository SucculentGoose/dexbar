#pragma once
#include <glib.h>

// Wrapper for libsecret's variadic secret_password_*_sync APIs.
// These bridge functions let Swift avoid the C NULL-terminated variadic call.
gboolean dexbar_secret_store(const char *schema_name, const char *key, const char *value);
char    *dexbar_secret_load(const char *schema_name, const char *key);
void     dexbar_secret_delete(const char *schema_name, const char *key);
