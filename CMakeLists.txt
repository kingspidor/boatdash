cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(boatdash)
get_filename_component(configName "${CMAKE_BINARY_DIR}" NAME)
list(APPEND EXTRA_COMPONENT_DIRS "${CMAKE_SOURCE_DIR}/.pio/libdeps/${configName}/esp_littlefs")

littlefs_create_partition_image(littlefs littlefs FLASH_IN_PROJECT)