#
# Copyright 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# MODIFIED for Cinewise (2026): based on androidx/media tag 1.10.1,
# libraries/decoder_ffmpeg/src/main/jni/CMakeLists.txt. The change: FFmpeg is
# imported as SHARED libraries (libavcodec.so, libavutil.so, libswresample.so)
# instead of static archives, so that libffmpegJNI.so links to them dynamically
# and a user can replace the LGPL libraries. Headers and .so files come from
# ../../../build_ffmpeg_lgpl.sh.
#

cmake_minimum_required(VERSION 3.21.0 FATAL_ERROR)

# Enable C++11 features.
set(CMAKE_CXX_STANDARD 11)

project(libffmpegJNI C CXX)

set(ffmpeg_location "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg")
set(ffmpeg_binaries "${ffmpeg_location}/lib/${ANDROID_ABI}")

foreach(ffmpeg_lib avutil swresample avcodec)
    set(ffmpeg_lib_file_path ${ffmpeg_binaries}/lib${ffmpeg_lib}.so)
    if(NOT EXISTS ${ffmpeg_lib_file_path})
        message(FATAL_ERROR "Missing ${ffmpeg_lib_file_path}. Run build_ffmpeg_lgpl.sh first.")
    endif()
    add_library(
            ${ffmpeg_lib}
            SHARED
            IMPORTED)
    set_target_properties(
            ${ffmpeg_lib} PROPERTIES
            IMPORTED_LOCATION
            ${ffmpeg_lib_file_path})
endforeach()

include_directories(${ffmpeg_location}/include)
find_library(android_log_lib log)

add_library(ffmpegJNI
            SHARED
            ffmpeg_jni.cc)

target_link_libraries(ffmpegJNI
                      PRIVATE android
                      PRIVATE swresample
                      PRIVATE avcodec
                      PRIVATE avutil
                      PRIVATE ${android_log_lib})

# Additional flags needed for "arm64-v8a" from NDK 23.1.7779620 and above.
# See https://github.com/google/ExoPlayer/issues/9933#issuecomment-1029775358.
if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_link_options(ffmpegJNI PRIVATE "-Wl,-Bsymbolic")
endif()

# Enable 16 KB ELF alignment.
target_link_options(ffmpegJNI
                    PRIVATE "-Wl,-z,max-page-size=16384")
