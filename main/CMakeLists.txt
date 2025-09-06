idf_component_register(
  SRCS "app_main.c"
  INCLUDE_DIRS "."
  REQUIRES
    esp_event esp_timer esp_wifi esp_netif nvs_flash
    esp_http_server json vfs
    net_apsta http_ui ota_fw sensors_adc tach_pcnt
    relays_io config_store msg_bus ui_assets
)