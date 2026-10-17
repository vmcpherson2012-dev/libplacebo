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

Install the mingw-w64-x86_64 gcc, meson, ninja, shaderc, spirv-cross, lcms2
and libdovi packages, then:

```sh
git submodule update --init --recursive
meson setup build-release --buildtype=release --default-library=shared \
  -Dd3d11=enabled -Dshaderc=enabled -Dglslang=disabled -Dlcms=enabled \
  -Ddovi=enabled -Dlibdovi=enabled -Dtests=true -Ddemos=false \
  -Dvulkan=disabled -Dopengl=disabled
meson compile -C build-release
meson test -C build-release --print-errorlogs
```

D3D11, shaderc, lcms2 and libdovi enabled; Vulkan and OpenGL disabled. All
13 library tests must pass. The DLL is `build-release/src/libplacebo-377.dll`.
The runtime DLLs it needs (libdovi, lcms2, shaderc, spirv-cross, gcc/stdc++/
winpthread) ship next to it in VP's `bin`.

## MSVC import library

VP links with MSVC against `lib/libplacebo-377.lib`, generated from
`lib/libplacebo-377.def` (in the VideoProcessor tree), not from the MinGW
import library. **Every fork export must be listed in `libplacebo-377.def`**
(patch 4: `pl_mpv_user_shader_set_texture`), or VP's Beta renderer will not
link. After changing the .def, regenerate the import library from a Visual
Studio developer prompt:

```bat
lib.exe /nologo /def:libplacebo-377.def /machine:x64 /out:libplacebo-377.lib
```

Compare the DLL's export table with the .def after every rebuild. The DLL
also exports the internal `memcpy_layout`, which the .def leaves out on purpose.
Copy the public headers from `src/include/libplacebo` plus the generated
`build-release/src/include/libplacebo/config.h` to VP's `include/libplacebo`.

## Rebasing onto a new upstream release

```sh
git remote add upstream https://code.videolan.org/videolan/libplacebo.git
git fetch upstream --tags
git fetch https://github.com/billslack2/libplacebo.git codex/vp-master-beta
git switch -c vp-fl35-<version> vp-fl35
git rebase --onto <new base> 8bccd6578c9e845f77205cec9e85fdb97bf36ed7
```

`<new base>` is either Bill's branch once rebased onto the new upstream, or the
upstream tag (`v7.xxx.x`) if Bill's patches are carried here too (then rebase
from `1dd02268` to bring them along). Resolve conflicts patch by patch, keep
each FL35 change a separate commit, re-check the API version (`meson.build`)
and the DLL name, rebuild, run the tests, update the .def/import library,
then update this file and VP's `3rdparty/libplacebo-beta/README.txt`.

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
