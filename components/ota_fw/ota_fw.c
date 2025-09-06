#include "ota_fw.h"
#include "esp_ota_ops.h"
#include "http_ui.h"
#include <string.h>
void ota_mark_valid_on_boot(void){ esp_ota_mark_app_valid_cancel_rollback(); }
esp_err_t ota_handle_upload(httpd_req_t* req){ if(!http_ui_is_request_from_ap(req)) return httpd_resp_send_err(req,403,"OTA SoftAP only"); return httpd_resp_sendstr(req, "stub"); }
