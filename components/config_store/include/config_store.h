#pragma once
#include <stddef.h>
void config_init_defaults(void);
void config_get_str(const char* key, char* out, size_t outlen, const char* defval);
