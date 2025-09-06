#include "net_apsta.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_mac.h"
#include <string.h>
static void on_ip(void* arg, esp_event_base_t base, int32_t id, void* data){ /* start SNTP here */ }
void net_start_apsta(const char* ap_psk,const char* sta_ssid,const char* sta_psk){
  esp_netif_init(); esp_event_loop_create_default();
  esp_netif_create_default_wifi_ap(); esp_netif_create_default_wifi_sta();
  wifi_init_config_t cfg=WIFI_INIT_CONFIG_DEFAULT(); esp_wifi_init(&cfg);
  wifi_config_t ap={0}; ap.ap.authmode=WIFI_AUTH_WPA2_PSK; ap.ap.max_connection=4; ap.ap.channel=1;
  uint8_t mac[6]; esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
  snprintf((char*)ap.ap.ssid, sizeof(ap.ap.ssid), "BOATDASH-%02X%02X", mac[4], mac[5]);
  strlcpy((char*)ap.ap.password, ap_psk, sizeof(ap.ap.password));
  wifi_config_t st={0}; st.sta.threshold.authmode=WIFI_AUTH_WPA2_PSK;
  if(sta_ssid && *sta_ssid){ strlcpy((char*)st.sta.ssid, sta_ssid, sizeof(st.sta.ssid)); strlcpy((char*)st.sta.password, sta_psk?"":sta_psk, sizeof(st.sta.password)); }
  esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &on_ip, NULL);
  esp_wifi_set_mode(WIFI_MODE_APSTA); esp_wifi_set_config(WIFI_IF_AP, &ap); if(*st.sta.ssid) esp_wifi_set_config(WIFI_IF_STA, &st);
  esp_wifi_start(); if(*st.sta.ssid) esp_wifi_connect();
}
