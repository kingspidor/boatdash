
idf_component_register(
SRCS "http_ui.c"
INCLUDE_DIRS "include"
REQUIRES esp_http_server vfs littlefs json
)