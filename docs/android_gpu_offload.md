# Android GPU/NPU offload — determination and path

_Last verified: 2026-07-13, against the fllama checkout in use
(`~/.pub-cache/git/fllama-3b1351a…`, llama.cpp drop dated June 2026)._

## Determination

**Confirmed: on-device inference on Android runs CPU-only today, and this is a
limitation of fllama's build wrapper, not of the underlying llama.cpp.**

- fllama's `src/CMakeLists.txt` enables a GPU backend only for Apple
  (`GGML_METAL`, line ~64) and Windows (`LLAMA_VULKAN` under `if(WIN32)`,
  line ~57). The `if(ANDROID)` branch configures CPU-only optimizations
  (ARM64 dotprod + KleiDiAI, llamafile/OpenMP off).
- `numGpuLayers: 99` in `AiService` is therefore silently ignored on Android.
  It is left in place so it takes effect the moment a GPU-enabled build exists.
- **The vendored llama.cpp already ships every relevant backend's source**:
  `ggml/src/ggml-opencl/` (Qualcomm's Adreno-optimized OpenCL backend),
  `ggml/src/ggml-vulkan/`, and `ggml/src/ggml-hexagon/` (Qualcomm Hexagon
  NPU). They are compiled out because the corresponding `GGML_*` options
  default to OFF and fllama never sets them for Android.

## What was done this pass (CPU, available now)

- **Thread count fix** (`lib/core/services/ai_service.dart`): fllama's chat
  path hard-defaults to **2 inference threads** and `fllamaChat()` provides no
  way to change it (`OpenAiRequest` has no `numThreads`). `rawChat` now builds
  the `FllamaInferenceRequest` directly — byte-for-byte what `fllamaChat`
  builds, plus `numThreads` sized to the device's core count (cores − 2,
  clamped to [2, 6]). On a Snapdragon-class big.LITTLE CPU this is the largest
  available CPU-side lever; 2 threads leaves most performance cores idle.
- No fork of fllama was needed for this; the fix is app-side only.

## Latency numbers

**No physical Android device was attached this session** (`flutter devices`:
macOS + Chrome only), so there are no real before/after numbers. Prior
sessions' latency claims remain architectural reasoning. The thread-count fix
above is the kind of change that must be measured on hardware — do that first
thing when a device is available (time `extract()` end-to-end before/after by
toggling `_numThreads` to 2).

## Scoped path to actual GPU/NPU offload (requires a fork of fllama)

fllama is consumed as a git dependency; enabling a backend means editing its
`src/CMakeLists.txt`, so a fork (or a vendored copy — the package is ~330 MB,
which is why it was not vendored into this repo) is unavoidable. In order of
recommended attempt for this project (Qualcomm hardware target):

1. **OpenCL backend (Adreno GPU) — recommended first attempt.**
   Qualcomm contributed and maintains this backend specifically for Adreno.
   Changes: in the fork's `src/CMakeLists.txt` add
   `set(GGML_OPENCL ON CACHE BOOL "" FORCE)` under `if(ANDROID)`;
   build the Khronos `OpenCL-Headers` and `OpenCL-ICD-Loader` for Android and
   install them into the NDK sysroot (llama.cpp's
   `docs/backend/OPENCL.md` documents the exact steps); kernels embed via
   `GGML_OPENCL_EMBED_KERNELS=ON` (already the default). At runtime the ICD
   loader picks up the device's `libOpenCL.so`.
2. **Hexagon NPU backend — highest ceiling for this hackathon, more moving
   parts.** `ggml-hexagon` targets the Snapdragon NPU; needs the Hexagon SDK
   toolchain at build time and is quantization-format sensitive. Scope only if
   OpenCL lands and more headroom is needed.
3. **Vulkan backend — fallback if OpenCL misbehaves on the target device.**
   Needs `glslc`/shaderc at build time (host-side shader compilation step);
   more universal across Android GPUs, generally less tuned for Adreno than
   the OpenCL backend.

No alternative maintained Flutter binding was found that ships Android GPU
support out of the box, so the fork path is the real path.

**Current blockers to even compile-testing a fork's Android build from this
repo:** the `mwdat-*` Maven dependencies no longer resolve (credentials were
scrubbed from `plugins/flutter_meta_wearables_dat/android/build.gradle` — see
the security notes), so `flutter build apk` fails before reaching native
compilation unless the owner supplies `GITHUB_ACTOR`/`GITHUB_TOKEN` via
environment or `~/.gradle/gradle.properties`. And verifying the backend
actually initializes (vs. silently falling back to CPU) requires a physical
device — check llama.cpp's startup log lines for `OpenCL` device enumeration.
