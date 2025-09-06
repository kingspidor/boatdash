#include "config_store.h"
#include "nvs_flash.h"
#include "nvs.h"
#include <string.h>
static const char *NS = "cfg";
void config_init_defaults(void){ nvs_handle_t h; nvs_open(NS, NVS_READWRITE, &h); nvs_set_str(h, "ap_psk", "BoatDash1234"); nvs_commit(h); nvs_close(h); }
void config_get_str(const char* key, char* out, size_t outlen, const char* defval){ nvs_handle_t h; size_t sz=outlen; if(nvs_open(NS, NVS_READONLY,&h)==ESP_OK && nvs_get_str(h,key,out,&sz)==ESP_OK){ nvs_close(h); return; } strncpy(out, defval, outlen); }
