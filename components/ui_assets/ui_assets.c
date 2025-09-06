#include "ui_assets.h"
#include "esp_littlefs.h"
esp_err_t ui_fs_mount(void){
  esp_vfs_littlefs_conf_t conf = { .base_path = "/littlefs", .partition_label = "littlefs", .format_if_mount_failed = true };
  return esp_vfs_littlefs_register(&conf);
}
