# :ffmpeg — LGPL FFmpeg audio decoders for Cinewise

## What this module is

This Gradle library module gives the app software audio decoders for formats
that the Quest 3 cannot decode itself: Dolby Digital (AC-3), Dolby Digital Plus
(E-AC-3), DTS and DTS-HD (core), Dolby TrueHD and MLP. It also decodes AAC,
FLAC, Opus, Vorbis, MP3, ALAC, AMR-NB, AMR-WB, mu-law and A-law.

The module has two parts:

1. **Media3 FFmpeg extension (Java + JNI glue).** These are the unchanged Java
   files of the `decoder_ffmpeg` extension from
   [androidx/media](https://github.com/androidx/media), git tag `1.10.1`
   (commit `5fb306449733dd71595700c1227ad6087578c559`), package
   `androidx.media3.decoder.ffmpeg`, and the unchanged `ffmpeg_jni.cc`.
   Gradle compiles `ffmpeg_jni.cc` with CMake into `libffmpegJNI.so`.
   The app's `DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_ON` finds
   `androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer` by reflection, so no app
   code is needed to turn it on.
2. **FFmpeg shared libraries.** `libavcodec.so`, `libavutil.so` and
   `libswresample.so`, built from FFmpeg **8.1.3** for `arm64-v8a`, Android API
   34, with an LGPL-only configuration. They are in
   `src/main/jni/ffmpeg/lib/arm64-v8a/`. Their headers are in
   `src/main/jni/ffmpeg/include/`.

`libffmpegJNI.so` links to the three FFmpeg libraries **dynamically** (its ELF
header lists them as `NEEDED`). FFmpeg is not linked statically into any other
file.

This module replaces `io.github.anilbeesetti:nextlib-media3ext`, which is
GPL-3.0. Remove that dependency from the app before you add this module: both
ship a `libavcodec.so`, and Gradle stops on the duplicate file.

To use it, the app needs one line: `implementation(project(":ffmpeg"))`.

## Licences

| Part | Files | Licence |
|---|---|---|
| Media3 `decoder_ffmpeg` Java sources, `ffmpeg_jni.cc`, `proguard-rules.txt` | `src/main/java/`, `src/main/jni/ffmpeg_jni.cc` | Apache License 2.0 ([LICENSE](LICENSE)). Upstream has no NOTICE file. |
| `CMakeLists.txt` | `src/main/jni/CMakeLists.txt` | Apache License 2.0. Changed from upstream to import FFmpeg as shared libraries. The file says so in its header. |
| FFmpeg 8.1.3 libraries and headers | `src/main/jni/ffmpeg/` | GNU Lesser General Public License version 2.1 or later ([licenses/FFmpeg-COPYING.LGPLv2.1](licenses/FFmpeg-COPYING.LGPLv2.1), [licenses/FFmpeg-LICENSE.md](licenses/FFmpeg-LICENSE.md)) |
| Build script, this README, `build.gradle.kts` | | Part of Cinewise |

The FFmpeg build is LGPL only:

- `--enable-gpl`, `--enable-nonfree` and `--enable-version3` are never used.
  The build script refuses them.
- `--disable-everything` turns off every component. Then only the audio
  decoders listed below are turned on. FFmpeg also adds the `ac3` and `mlp`
  parsers, because the `eac3` and `truehd` decoders need them. These parsers
  are LGPL too. No encoders, demuxers, muxers, filters, protocols or external
  libraries are in the build (`--disable-autodetect`). The configure summary
  lists `iconv`. This is the `iconv` in Android's own C library, not an extra
  library.
- The script checks `config.h`. If `CONFIG_GPL`, `CONFIG_NONFREE` or
  `CONFIG_VERSION3` is not 0, or `FFMPEG_LICENSE` is not
  `"LGPL version 2.1 or later"`, the script stops.

[LGPL_PROOF.txt](LGPL_PROOF.txt) holds the evidence from the last build:

- the exact configure line
- the licence lines of `config.h`
- the list of enabled decoders
- the licence string inside `libavcodec.so`
- the `NEEDED` and `SONAME` entries of each library

Enabled decoders: `ac3 eac3 dca truehd mlp aac flac opus vorbis mp3 alac amrnb
amrwb pcm_mulaw pcm_alaw`. These are the audio names that Media3's
`FfmpegLibrary.getCodecName()` maps, plus `mlp`. The video decoders that
Media3 also maps (`h264`, `hevc`) are not in the build: the headset decodes
video in hardware.

### What the LGPL asks of the app

- **Offer the exact FFmpeg source.** The source is the release tarball
  `ffmpeg-8.1.3.tar.xz` from <https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz>,
  SHA-256 `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3`,
  signed by the FFmpeg release key (fingerprint
  `FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8`, signature at the same
  URL plus `.asc`). We did not change the FFmpeg source. Together with
  `build_ffmpeg_lgpl.sh` (which holds the exact configure flags), this is the
  complete corresponding source. Do not rely only on the ffmpeg.org link. Keep
  your own copy of the tarball and the script. Publish them where users can
  download them, for example on a public web page or a GitHub release. Keep
  them there for at least three years after the last app release.
- **Let users replace the libraries.** The FFmpeg code is in separate shared
  libraries with plain names (`libavcodec.so`, `libavutil.so`,
  `libswresample.so`). A user can build their own FFmpeg with the same
  interface. Then they put the new files in the APK's `lib/arm64-v8a/` folder,
  sign the APK again and install it. "The same interface" means FFmpeg 8.x
  with the same library major versions (`LIBAVCODEC_62`, `LIBAVUTIL_60`, `LIBSWRESAMPLE_6`).
  `libffmpegJNI.so` asks for its FFmpeg functions with these version tags.
- **Show the notices.** The app must tell users that it uses FFmpeg under the
  LGPL 2.1 or later, include the licence text, and say where the source is.
  The app's packaging rules remove `META-INF/LICENSE*` from the APK, so put
  this text in an "About" or "Licences" screen in the app. Also show the
  Apache 2.0 notice for Media3.
- Do not prohibit reverse engineering of the app to the extent that it is
  needed to debug changes to the LGPL libraries (LGPL 2.1 section 6). Check the
  store terms and the app EULA for this.

This README is not legal advice.

## How to rebuild FFmpeg

You need Linux (we use WSL 2 with Ubuntu 24.04), `curl`, `make`, `python3`,
`tar` and `xz`. The script downloads the Linux Android NDK r28b
(`28.1.13356709`). This is the same NDK version as in the Windows SDK. The
script also downloads the FFmpeg tarball. It checks the SHA-1 of the NDK and
the SHA-256 of the tarball.

1. Open a Linux shell.
2. Run the script. The argument is a work folder for downloads and build files
   (about 3 GB):

   ```
   bash /mnt/c/Users/lee_h/q3/movies/quest/ffmpeg/build_ffmpeg_lgpl.sh ~/cinewise-ffmpeg-lgpl
   ```

   To use an NDK that you already have, set `NDK_PATH`. To change the number
   of parallel compile jobs, set `JOBS` (default 8).
3. The script replaces `src/main/jni/ffmpeg/` and `LGPL_PROOF.txt` and copies
   the FFmpeg licence files to `licenses/`.

On the shared PC, run heavy jobs through the queue, one at a time:

```
python C:/Users/lee_h/q3/engine/tools/heavy.py --label "cinewise ffmpeg" --max-seconds 5400 -- wsl.exe -d Ubuntu -- bash /mnt/c/Users/lee_h/q3/movies/quest/ffmpeg/build_ffmpeg_lgpl.sh
```

To add a decoder, add its FFmpeg name to `DECODERS` in the script. First make
sure that the decoder is LGPL: the configure summary must still say
`License: LGPL version 2.1 or later`, and the script's licence check must pass.

## How to build the module

Gradle builds `libffmpegJNI.so` with the NDK `28.1.13356709` and CMake
`3.22.1` from the Android SDK:

```
./gradlew :ffmpeg:assembleRelease
```

The AAR in `build/outputs/aar/` contains `jni/arm64-v8a/libffmpegJNI.so`,
`libavcodec.so`, `libavutil.so` and `libswresample.so`.

## Files

| Path | What it is |
|---|---|
| `build_ffmpeg_lgpl.sh` | Downloads, checks, configures and builds FFmpeg. Writes `LGPL_PROOF.txt` |
| `LGPL_PROOF.txt` | Evidence that the last build is LGPL only |
| `src/main/java/androidx/media3/decoder/ffmpeg/` | Media3 1.10.1 Java sources (unchanged) |
| `src/main/jni/ffmpeg_jni.cc` | Media3 1.10.1 JNI glue (unchanged) |
| `src/main/jni/CMakeLists.txt` | Builds `libffmpegJNI.so`, linked to the shared FFmpeg libraries |
| `src/main/jni/ffmpeg/` | FFmpeg headers and `.so` files (output of the script) |
| `licenses/` | FFmpeg licence files from the source tarball |
| `upstream/MEDIA3_DECODER_FFMPEG_README.md` | Upstream Media3 README of the extension, for reference |
| `.work/` | Local downloads (ignored by git) |
