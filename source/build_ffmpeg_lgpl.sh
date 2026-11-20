#!/usr/bin/env bash
#
# Build LGPL-only FFmpeg shared libraries for the Cinewise :ffmpeg module.
#
# Target: Android arm64-v8a, API 34 (Meta Quest 3, Horizon OS = Android 14).
# Output: libavcodec.so, libavutil.so, libswresample.so and their headers,
#         copied into src/main/jni/ffmpeg/ next to this script, plus
#         LGPL_PROOF.txt and the FFmpeg licence files.
#
# Run it on Linux (we use WSL Ubuntu 24.04):
#   bash build_ffmpeg_lgpl.sh [WORK_DIR]
# WORK_DIR defaults to $HOME/cinewise-ffmpeg-lgpl. It holds the downloads, the
# Android NDK, the FFmpeg source and the build tree. It is not part of the repo.
#
# Environment (optional):
#   NDK_PATH  use an existing Linux NDK r28b instead of downloading one
#   JOBS      make -j value (default 8)
#
# This file is part of Cinewise. The FFmpeg it builds is LGPL-2.1-or-later.
set -euo pipefail

# ---- Pinned inputs -----------------------------------------------------------
FFMPEG_VERSION="8.1.3"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SHA256="7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"

NDK_RELEASE="r28b"                       # = 28.1.13356709, same as the Windows SDK
NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_RELEASE}-linux.zip"
NDK_SHA1="f574d3165405bd59ffc5edaadac02689075a729f"   # from Google repository2-3.xml

ANDROID_API=34
ABI="arm64-v8a"

# Audio decoders only. All are LGPL in FFmpeg. These are the names that
# Media3's FfmpegLibrary.getCodecName() asks for (plus mlp, which shares the
# TrueHD decoder source). h264/hevc are left out on purpose (video is decoded
# by the headset's MediaCodec).
DECODERS=(ac3 eac3 dca truehd mlp aac flac opus vorbis mp3 alac amrnb amrwb pcm_mulaw pcm_alaw)

JOBS="${JOBS:-8}"
# -----------------------------------------------------------------------------

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${1:-$HOME/cinewise-ffmpeg-lgpl}"
DL_DIR="${WORK_DIR}/dl"
SRC_DIR="${WORK_DIR}/src/ffmpeg-${FFMPEG_VERSION}"
BUILD_DIR="${WORK_DIR}/build-${ABI}"
INSTALL_DIR="${WORK_DIR}/install-${ABI}"
OUT_DIR="${MODULE_DIR}/src/main/jni/ffmpeg"
PROOF="${MODULE_DIR}/LGPL_PROOF.txt"

mkdir -p "${DL_DIR}" "${WORK_DIR}/src"

# ---- 1. FFmpeg source tarball ------------------------------------------------
TARBALL="${DL_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"
if [[ ! -f "${TARBALL}" ]]; then
  curl -fL --retry 3 -o "${TARBALL}.part" "${FFMPEG_URL}"
  mv "${TARBALL}.part" "${TARBALL}"
fi
echo "${FFMPEG_SHA256}  ${TARBALL}" | sha256sum -c -

# ---- 2. Android NDK (Linux) --------------------------------------------------
if [[ -z "${NDK_PATH:-}" ]]; then
  NDK_PATH="${WORK_DIR}/android-ndk-${NDK_RELEASE}"
  if [[ ! -x "${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]]; then
    NDK_ZIP="${DL_DIR}/android-ndk-${NDK_RELEASE}-linux.zip"
    if [[ ! -f "${NDK_ZIP}" ]]; then
      curl -fL --retry 3 -o "${NDK_ZIP}.part" "${NDK_URL}"
      mv "${NDK_ZIP}.part" "${NDK_ZIP}"
    fi
    echo "${NDK_SHA1}  ${NDK_ZIP}" | sha1sum -c -
    rm -rf "${NDK_PATH}"
    # No 'unzip' on a stock WSL Ubuntu: extract with Python, keeping the
    # executable bits and the symbolic links that are stored in the zip.
    python3 -I - "${NDK_ZIP}" "${WORK_DIR}" <<'PY'
import os, stat, sys, zipfile
zip_path, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path) as z:
    for info in z.infolist():
        target = os.path.join(dest, info.filename)
        mode = info.external_attr >> 16
        if info.is_dir():
            os.makedirs(target, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if stat.S_ISLNK(mode):
            link = z.read(info).decode()
            if os.path.lexists(target):
                os.remove(target)
            os.symlink(link, target)
            continue
        with z.open(info) as src, open(target, "wb") as dst:
            while True:
                chunk = src.read(1 << 20)
                if not chunk:
                    break
                dst.write(chunk)
        if mode:
            os.chmod(target, stat.S_IMODE(mode))
PY
  fi
fi
TC="${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin"
CC="${TC}/aarch64-linux-android${ANDROID_API}-clang"
[[ -x "${CC}" ]] || { echo "No compiler at ${CC}" >&2; exit 1; }
NDK_REVISION="$(grep Pkg.Revision "${NDK_PATH}/source.properties" | cut -d= -f2 | tr -d ' ')"

# ---- 3. Fresh source tree ----------------------------------------------------
rm -rf "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}"
tar -xJf "${TARBALL}" -C "${WORK_DIR}/src"
mkdir -p "${BUILD_DIR}"

# ---- 4. Configure (LGPL only: no --enable-gpl, no --enable-nonfree) ----------
CONFIGURE_FLAGS=(
  --prefix="${INSTALL_DIR}"
  --target-os=android
  --arch=aarch64
  --cpu=armv8-a
  --enable-cross-compile
  --cross-prefix="${TC}/aarch64-linux-android${ANDROID_API}-"
  --cc="${CC}"
  --cxx="${CC}++"
  --nm="${TC}/llvm-nm"
  --ar="${TC}/llvm-ar"
  --ranlib="${TC}/llvm-ranlib"
  --strip="${TC}/llvm-strip"
  --extra-ldflags="-Wl,-z,max-page-size=16384"
  --enable-shared
  --disable-static
  --disable-doc
  --disable-programs
  --disable-autodetect
  --enable-pthreads
  --disable-everything
  --disable-avdevice
  --disable-avformat
  --disable-swscale
  --disable-avfilter
  --disable-network
  --disable-symver
  --disable-vulkan
  --disable-v4l2-m2m
  --enable-swresample
)
for d in "${DECODERS[@]}"; do
  CONFIGURE_FLAGS+=(--enable-decoder="${d}")
done

for f in "${CONFIGURE_FLAGS[@]}"; do
  case "$f" in
    --enable-gpl|--enable-nonfree|--enable-version3)
      echo "Refusing licence flag $f" >&2; exit 1 ;;
  esac
done

cd "${BUILD_DIR}"
"${SRC_DIR}/configure" "${CONFIGURE_FLAGS[@]}" | tee "${BUILD_DIR}/configure.out"

# ---- 5. Licence gate ---------------------------------------------------------
check_zero() {
  grep -qx "#define $1 0" config.h || { echo "LICENCE GATE FAILED: $1 is not 0" >&2; exit 1; }
}
check_zero CONFIG_GPL
check_zero CONFIG_NONFREE
! grep -qx '#define CONFIG_GPLV3 1' config.h || { echo "LICENCE GATE FAILED: GPLv3" >&2; exit 1; }
check_zero CONFIG_VERSION3
grep -qx '#define FFMPEG_LICENSE "LGPL version 2.1 or later"' config.h \
  || { echo "LICENCE GATE FAILED: FFMPEG_LICENSE is not LGPL 2.1+" >&2; exit 1; }

# ---- 6. Build and install ----------------------------------------------------
make -j"${JOBS}"
make install-libs install-headers

# ---- 7. Copy outputs into the Gradle module ----------------------------------
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/lib/${ABI}" "${OUT_DIR}/include"
for lib in avcodec avutil swresample; do
  cp -L "${INSTALL_DIR}/lib/lib${lib}.so" "${OUT_DIR}/lib/${ABI}/lib${lib}.so"
done
cp -r "${INSTALL_DIR}/include/." "${OUT_DIR}/include/"
mkdir -p "${MODULE_DIR}/licenses"
cp "${SRC_DIR}/COPYING.LGPLv2.1" "${MODULE_DIR}/licenses/FFmpeg-COPYING.LGPLv2.1"
cp "${SRC_DIR}/LICENSE.md" "${MODULE_DIR}/licenses/FFmpeg-LICENSE.md"

# ---- 8. Proof file -----------------------------------------------------------
{
  echo "LGPL proof for the Cinewise :ffmpeg module"
  echo "Generated by build_ffmpeg_lgpl.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Build host: $(uname -srm); $(. /etc/os-release && echo "${PRETTY_NAME}")"
  echo
  echo "== Source =="
  echo "FFmpeg version : ${FFMPEG_VERSION}"
  echo "Tarball URL    : ${FFMPEG_URL}"
  echo "SHA-256        : ${FFMPEG_SHA256}"
  echo "Signature      : ${FFMPEG_URL}.asc (FFmpeg release signing key,"
  echo "                 fingerprint FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8)"
  echo "Android NDK    : ${NDK_RELEASE} (${NDK_REVISION}), ${NDK_URL}, sha1 ${NDK_SHA1}"
  echo "Target         : ${ABI}, Android API ${ANDROID_API}"
  echo
  echo "== Exact configure line =="
  echo "configure \\"
  for f in "${CONFIGURE_FLAGS[@]}"; do echo "  $f \\"; done | sed '$ s/ \\$//'
  echo
  echo "(Paths: TC=${TC}, prefix=${INSTALL_DIR})"
  echo
  echo "== config.h licence lines =="
  grep -E '^#define (CONFIG_GPL|CONFIG_GPLV3|CONFIG_NONFREE|CONFIG_VERSION3|CONFIG_LGPLV3) ' config.h || true
  grep -E '^#define FFMPEG_LICENSE ' config.h
  echo
  echo "== config.h FFMPEG_CONFIGURATION (embedded in the libraries) =="
  grep -E '^#define FFMPEG_CONFIGURATION ' config.h
  echo
  echo "== Enabled decoders (config_components.h CONFIG_*_DECODER 1) =="
  grep -E '^#define CONFIG_[A-Z0-9_]+_DECODER 1' config_components.h | sed -E 's/#define CONFIG_(.*)_DECODER 1/\1/' | tr 'A-Z' 'a-z'
  echo
  echo "== Enabled parsers / encoders / demuxers / muxers / filters / protocols / hwaccels / bsfs (count; the ac3 and mlp parsers are selected by the eac3 and truehd decoders, so expect 2) =="
  grep -cE '^#define CONFIG_[A-Z0-9_]+_(PARSER|ENCODER|DEMUXER|MUXER|FILTER|PROTOCOL|HWACCEL|BSF) 1' config_components.h || true
  echo
  echo "== External libraries enabled in config.h (CONFIG_LIB*, expect none) =="
  grep -E '^#define CONFIG_LIB[A-Z0-9_]+ 1' config.h || echo "(none)"
  echo
  echo "== Licence string inside the built libavcodec.so (what avcodec_license() returns) =="
  strings "${OUT_DIR}/lib/${ABI}/libavcodec.so" | grep -E 'license: |LGPL|GPL' | sort -u
  echo
  echo "== Configure summary (stdout of configure) =="
  cat "${BUILD_DIR}/configure.out"
  echo
  echo "== Shared library dynamic sections =="
  for lib in avcodec avutil swresample; do
    echo "--- lib${lib}.so ($(stat -c %s "${OUT_DIR}/lib/${ABI}/lib${lib}.so") bytes, sha256 $(sha256sum "${OUT_DIR}/lib/${ABI}/lib${lib}.so" | cut -d' ' -f1))"
    "${TC}/llvm-readelf" -d "${OUT_DIR}/lib/${ABI}/lib${lib}.so" | grep -E 'NEEDED|SONAME'
  done
} > "${PROOF}"

echo
echo "Done. Libraries in ${OUT_DIR}/lib/${ABI}; proof in ${PROOF}"
