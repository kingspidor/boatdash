@'
CONFIG_HTTPD_WS_SUPPORT=y
'@ | Add-Content -Encoding ascii .\sdkconfig.defaults

idf.py defconfig      # apply defaults -> sdkconfig
