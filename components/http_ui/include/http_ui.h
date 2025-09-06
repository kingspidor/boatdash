#pragma once
#include <stdbool.h>
#include <stddef.h>
#include "esp_http_server.h"
void http_ui_start(void);
void http_ui_broadcast_json(const char* json, size_t len);
bool http_ui_is_request_from_ap(httpd_req_t* req);
