# from project root
ni partitions.csv -Value @"
# Name,Type,SubType,Offset,Size
nvs,data,nvs,,64K
otadata,data,ota,,8K
phy_init,data,phy,,4K
factory,app,factory,,1M
ota_0,app,ota_0,,6M
ota_1,app,ota_1,,6M
littlefs,data,littlefs,,2M
"@

mkdir littlefs; Set-Content littlefs\index.html '<!doctype html><h1>OK</h1>'

idf.py menuconfig   # pick the CSV; set Flash size=16MB; enable HTTP WS
idf.py set-target esp32s3
idf.py reconfigure build
