# VideoProcessor FL35 libplacebo fork

Branch `vp-fl35` of https://github.com/vmcpherson2012-dev/libplacebo is the
libplacebo that VideoProcessor's FL35 Beta renderer ships as
`libplacebo-377.dll` (`3rdparty/libplacebo-beta` in the VideoProcessor tree).

## Base

- Bill Slack's VP fork: https://github.com/billslack2/libplacebo, branch
  `codex/vp-master-beta`, commit `8bccd6578c9e845f77205cec9e85fdb97bf36ed7`
  (API 377).
- That commit's upstream base: `1dd022687b9ac1dd996855b51433bf770ae76aab`
  (https://code.videolan.org/videolan/libplacebo).
- Submodule pins are unchanged from the base (see `git ls-tree HEAD 3rdparty`).

## FL35 patches (one commit each, in order)

1. `colorspace: use the luma limits for all channels of limited range RGB`:
   limited-range RGB gave G/B the chroma limit (240), so the output clamp let
   G/B exceed white while R stopped at 235 and super-whites turned cyan.
2. `colorspace: keep footroom and headroom in the limited range output clamp`:
   the final integer clamp now stops at the legal codes (8-bit 1-254, 10-bit
   4-1019) on all channels instead of 16-235/240, keeping BTB/WTW.
3. `renderer: optional rgba32f FBOs (output pass, or all)`: fork-only
   `pl_render_params.output_fbo_float32` / `fbo_float32` (default false =
   upstream behaviour) for a float output pass or float intermediates.
4. `custom_mpv: caller textures for declared textures`: new export
   `pl_mpv_user_shader_set_texture` (define `PL_VP_MPV_USER_SHADER_SET_TEXTURE`)
   points a user shader's own `//!TEXTURE` at a caller texture, such as
   VP's de-judder vector field (VPVEC), and restores it before destroy.

Any libplacebo rebuild for VP must carry all four.

## Windows build (MSYS2 MINGW64)

`tools/build-windows.sh` reproduces the shipped build from a clean checkout
(run it in an MSYS2 MINGW64 shell, or through `tools/build-windows.ps1` from
PowerShell). The same script runs in CI (`.github/workflows/build-windows.yml`,
on every push to `vp-fl35` and on manual dispatch; the bundle is the run's
artifact).

Packages (MINGW64): `mingw-w64-x86_64-{gcc,binutils,meson,ninja,pkgconf,python,
shaderc,spirv-cross,lcms2,libdovi}` plus `git`. Jinja and MarkupSafe come from
the `3rdparty` submodules; libdovi is the MSYS2 package (no cargo-c needed).
The known-good versions are pinned in `tools/windows-toolchain.txt`; the script
compares, records them in the manifest and warns on drift (`--strict` fails).

```sh
tools/build-windows.sh -j 4          # or: powershell -File toolsuild-windows.ps1 -Jobs 4
```

It runs, in order:

```sh
git submodule update --init --recursive
meson setup build-release --buildtype=release --default-library=shared   -Dd3d11=enabled -Dshaderc=enabled -Dglslang=disabled -Dlcms=enabled   -Ddovi=enabled -Dlibdovi=enabled -Dvulkan=disabled -Dopengl=disabled   -Ddemos=false -Dtests=true
meson compile -C build-release -j 4
meson test -C build-release --print-errorlogs
```

and collects `dist/`: `bin/libplacebo-377.dll` with its transitive MinGW
runtime DLLs (libdovi, lcms2, shaderc, spirv-cross, libstdc++, libgcc_s_seh,
libwinpthread), `include/libplacebo` (public headers + generated `config.h`),
`lib/libplacebo-377.def`, `lib/libplacebo-377.lib` when MSVC `lib.exe` is
found, `exports.txt`, `BUILD-MANIFEST.txt` (commit, submodules, options,
toolchain, tests) and `SHA256SUMS`.

The suite has 13 library tests, including `d3d11.c` (needs a D3D11 device or
WARP; it passes on the GitHub Windows runner). Meson adds the `libav.c` and
`dav1d.c` header tests when the FFmpeg and dav1d development packages happen
to be installed (15 tests on the local workstation). All must pass.
By default `pl_version()` is the plain `v7.377.0`, as in the shipped DLL
(which was built from a source archive); `--git-version` embeds `git describe`.
VP's `vulkan-1.dll` in `3rdparty/libplacebo-beta/bin` is not a dependency of
this build (Vulkan is disabled) and is not collected.

Reproduction check (2026-10-17, local, toolchain exactly as pinned): the
rebuilt `vp-fl35` DLL has the same 514 exports, the same 185 imported
symbols, a byte-identical .def (513 names), and byte-identical `.rdata`,
`.data`, `.pdata`, `.xdata` and `.reloc` sections and an equal-size `.text`
compared with the shipped DLL (SHA256 `15809853...b5509220`). It is not
byte-identical: the PE/export timestamps and checksum, the version resource,
and the order of the import descriptors (`api-ms-win-crt-math-l1-1-0.dll`
first in the shipped DLL, last here) differ, and the import-address shift
changes about 1.5 KB of RIP-relative operands in `.text`. The MSVC `.lib`
differs only by its member timestamps. The bundled runtime DLLs are those of
the current toolchain; VP's shipped libgcc/libstdc++/winpthread/shaderc/
spirv-cross DLLs are older copies carried over from the 7.360.1 bundle.

## MSVC import library

VP links with MSVC against `lib/libplacebo-377.lib`, generated from
`lib/libplacebo-377.def`, not from the MinGW import library. The DLL exports
**514** names; the .def lists **513**: every export except the internal
`memcpy_layout`, which it leaves out on purpose. The script writes the .def
from the DLL's export table, so fork exports (patch 4:
`pl_mpv_user_shader_set_texture`) are included automatically and checked.
`tools/build-windows.ps1` (and CI) also run `lib.exe`; otherwise, from a
Visual Studio developer prompt:

```bat
lib.exe /nologo /def:libplacebo-377.def /machine:x64 /out:libplacebo-377.lib
```

Copy `include/libplacebo` to VP's `include/libplacebo`.

## Rebasing onto a new upstream release

Not done yet; this is the plan.

### The API-number collision

- Bill's base (`8bccd657`) sits on upstream `1dd02268` (API 375) and claims
  two API numbers of its own: **376** (VP analysis crop and optional dynamic
  target) and **377** (VP optional smooth color-volume compression). The DLL
  is therefore `libplacebo-377.dll` and the log entry point
  `pl_log_create_377`.
- Upstream master (checked 2026-10-17: `0df80ae5`, 18 commits past
  `1dd02268`) has since used **376** itself (`pl_color_repr_decode_ex`,
  `pl_color_decode_args.primaries`, `pl_shader_encode_color_ex`). Upstream's
  376 and Bill's 376/377 mean different things, so a rebased tree cannot keep
  Bill's numbers: `PL_API_VER >= 376/377` would be true for builds lacking the
  features the number promises.
- Rebasing the VP patches on top keeps them after upstream's 376, so the
  result must be at least **378**: `libplacebo-378.dll`, `pl_log_create_378`,
  `PL_API_VER 378`, unless Bill's two bumps are folded together.

### Recommended approach

1. Rebase onto a tagged upstream release (or master), not onto Bill's branch,
   carrying Bill's VP patches as commits here (`git rebase --onto <upstream>
   1dd02268`), and **fold Bill's two API bumps into one VP bump** placed after
   upstream's latest: API **378** = "VP analysis crop, dynamic target and
   smooth color-volume compression". One number for the whole VP ABI keeps the
   DLL name change to a single step and avoids burning two numbers that would
   collide again on the next upstream bump.
2. Keep the FL35 patches 0001-0004 as separate commits on top; they add no
   API number of their own (0003 appends fields to `pl_render_params`; 0004
   is detected with `PL_VP_MPV_USER_SHADER_SET_TEXTURE`). Both change the
   ABI, which the single VP number in step 1 covers.
3. If upstream has moved further by then (377+), take
   `max(upstream) + 1` in the same way; never reuse an upstream number.
4. Ask Bill to adopt the same number on his branch if he rebases too, so the
   two forks do not diverge on the meaning of 378.
5. Rebuild with `tools/build-windows.sh`, run the tests, regenerate the .def
   and import library (the name changes with the API), compare exports
   (expect upstream's new exports in addition to the 514), and run VP's Beta
   GPU tests before shipping.

### What VP must change for a 378 DLL

- `PL_API_VER >= 377` checks: `src/VideoProcessor-Lib/vprenderer/`
  `LibplaceboVideoRenderer.cpp`, `LibplaceboRenderParameters.cpp`,
  `OptionalRendererLayout.h`, `OutputEncodingRepair.cpp` (the
  OutputEncodingRepair-off switch), and `VideoProcessor-Test/`
  `LibplaceboPluginProxyTests.cpp`. Re-check each condition rather than
  bumping the number blindly: upstream's own 376 changes
  (`pl_color_repr_decode_ex`, encode/decode args) may need code too.
- The DLL/import-library name `libplacebo-377` in
  `src/VideoProcessor-VPRenderer/VideoProcessor-VPRendererBeta.vcxproj`,
  `src/VideoProcessor-BetaTests/VideoProcessor-BetaTests*.vcxproj`,
  `packaging/release-manifest.json`, `tools/package_release.ps1`,
  `tools/test_libplacebo_variants.py`, and the docs
  (`docs/libplacebo-beta.md`, `docs/BUILD-STATUS.md`).
- `3rdparty/libplacebo-beta`: new DLL, headers, `.def`/`.lib` names, README.

## Licence

LGPL-2.1-or-later, as libplacebo (see `LICENSE`). The FL35 patches are under
the same licence.

## Base fork notes (Bill's VP-FORK.md, unchanged)


Branch: `codex/vp-master-beta` (experimental). Upstream pinned to
`1dd022687b9ac1dd996855b51433bf770ae76aab` (API 375).
The VP fork uses API 377 to give its extended structures and DLL a distinct ABI.

VP patches:
- Analysis crop for peak detection, including master scene-average/maxRGB
  measurements used by dynamic target. Excluded pixels do not affect statistics.
- D3D11 timer allocation and diagnostic suspension controls, recovered from
  the exact shipped release source archive.
- `pl_color_map_params.dynamic_target` / `dynamic_target=yes|no` option.
  Defaults to enabled. Disabling bypasses virtual target/exposure adaptation;
  peak detection, film response and physical display luminance stay independent.

- `pl_color_map_params.vp_gamut_compression` / `vp_gamut_compression=yes|no`.
  Defaults to disabled: the original master mapping path is unchanged. When
  enabled during tone mapping (excluding inverse tone mapping), a continuous
  residual correction follows the complete selected original gamut stage.
  Physical target RGB is normalized by its nominal black and peak. Positive
  overflow uses a common gain with a saturation-dependent 2% shoulder reserve;
  negative channels receive a common neutral lift with a continuous cap at the
  positive original luminance. This avoids creating light from negative-Y input.
  Legal interior pixels bypass the additional transform exactly. Near-boundary
  saturated colors may move by up to about 0.586% of target range. Color and
  brightness tradeoffs remain, particularly for negative-channel blues.
  This replaces the earlier fixed-Y color-volume LUT experiment. No additional
  texture/LUT or environment switch is used; original gamut choices remain active.
  Physical P3 inside a BT.2020 signal container is handled with explicit matrices.
  Alpha, tone curve and dynamic-target controls remain independent. The option
  does not govern later calibration/custom LUT output. Default-on, real-content,
  temporal, physical swapchain/dither and performance qualification remain open.

  Research validation: 105 matched D3D11 linear cases at 50/100/500 nits plus
  nine actual PQ-output controls; exact original/off restoration, no material
  target-bound violations or nominal exposure-Y reversals. Source-code-neighbor
  and negative-luminance controls are included. Small GPU floating-point errors
  require a numerical tolerance; these results are not a universal quality claim.

Sibling branch `codex/vp-release-7.360.1` reconstructs the full shipped release
source (analysis crop plus timers); the VP stable binary remains unchanged.

### Windows build

Use MSYS2 mingw64 gcc, shaderc, spirv-cross, lcms2 and libdovi. Initialize
submodules with `git submodule update --init --recursive`.

```sh
meson setup build-release --buildtype=release --default-library=shared \
  -Dd3d11=enabled -Dshaderc=enabled -Dglslang=disabled -Dlcms=enabled \
  -Ddovi=enabled -Dlibdovi=enabled -Dtests=true -Ddemos=false \
  -Dvulkan=disabled -Dopengl=disabled
meson compile -C build-release
meson test -C build-release --print-errorlogs
```

GPU tests cover cropped luminance/maxRGB, timer controls, and actual rendered
HDR output with dynamic target on/off/on (including reused LUT state).
Scene fixtures and visual gamut qualification are separate from these tests.
