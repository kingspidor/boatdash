#pragma once
#include "esp_http_server.h"
esp_err_t ota_handle_upload(httpd_req_t* req);
void ota_mark_valid_on_boot(void);
