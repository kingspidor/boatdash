cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(boatdash)

littlefs_create_partition_image(littlefs littlefs FLASH_IN_PROJECT)