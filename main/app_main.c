#include <stdio.h>
#include "nvs_flash.h"
#include "esp_event.h"
#include "esp_timer.h"
#include "esp_log.h"
#include "net_apsta.h"
#include "http_ui.h"
#include "ota_fw.h"
#include "sensors_adc.h"
#include "tach_pcnt.h"
#include "relays_io.h"
#include "config_store.h"
#include "msg_bus.h"
#include "ui_assets.h"
#include "esp_littlefs.h"


static const char *TAG = "app";

void app_main(void) {
  ESP_ERROR_CHECK(nvs_flash_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());

  config_init_defaults();
  ui_fs_mount();

  char ap_psk[65]={0}, sta_ssid[33]={0}, sta_psk[65]={0};
  config_get_str("ap_psk", ap_psk, sizeof ap_psk, "BoatDash1234");
  config_get_str("sta_ssid", sta_ssid, sizeof sta_ssid, "");
  config_get_str("sta_psk", sta_psk, sizeof sta_psk, "");
  net_start_apsta(ap_psk, sta_ssid, sta_psk);

  http_ui_start();
  sensors_start();
  tach_start();
  relays_init();

  ota_mark_valid_on_boot();
  ESP_LOGI(TAG, "BoatDash up");
}
