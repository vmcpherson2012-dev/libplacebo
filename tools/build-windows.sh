#!/usr/bin/env bash
# Reproducible Windows x64 build of the VP FL35 libplacebo fork.
#
# Run from an MSYS2 MINGW64 shell (or through tools/build-windows.ps1).
# Produces, under the output directory (default: dist/):
#   bin/libplacebo-<API>.dll   plus every non-system DLL it needs (transitively)
#   include/libplacebo/        public headers + generated config.h
#   lib/libplacebo-<API>.def   MSVC .def (all exports except internal memcpy_layout)
#   lib/libplacebo-<API>.dll.a MinGW import library (VP does NOT link this)
#   lib/libplacebo-<API>.lib   only if MSVC lib.exe is found (see below)
#   exports.txt                every name the DLL exports
#   BUILD-MANIFEST.txt         source commit, submodules, options, toolchain, tests
#   SHA256SUMS                 sha256 of every file in the bundle
#
# VP links with MSVC against an import library made from the .def:
#   lib.exe /nologo /def:libplacebo-<API>.def /machine:x64 /out:libplacebo-<API>.lib
# (from a Visual Studio developer prompt; tools/build-windows.ps1 does this
# automatically when Visual Studio is installed).
#
# Options:
#   -j N          parallel jobs for ninja and meson test (default 4)
#   -o DIR        output bundle directory (default <src>/dist)
#   -b DIR        build directory (default <src>/build-release)
#   --strict      fail if the installed toolchain differs from tools/windows-toolchain.txt
#   --no-tests    skip the library tests (not for release bundles)
#   --no-submodules  do not run git submodule update
#   --keep-build  reuse an existing build directory instead of wiping it
#   --git-version embed `git describe` in pl_version()/the DLL version resource
#                 (default: the plain release version, e.g. v7.377.0, as the
#                 shipped DLL was built from a source archive without .git)
set -euo pipefail

JOBS=4
STRICT=0
RUN_TESTS=1
SUBMODULES=1
KEEP_BUILD=0
GIT_VERSION=0
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT=""
BUILD=""

while [ $# -gt 0 ]; do
    case "$1" in
        -j) JOBS="$2"; shift 2 ;;
        -j*) JOBS="${1#-j}"; shift ;;
        -o) OUT="$2"; shift 2 ;;
        -b) BUILD="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        --no-tests) RUN_TESTS=0; shift ;;
        --no-submodules) SUBMODULES=0; shift ;;
        --keep-build) KEEP_BUILD=1; shift ;;
        --git-version) GIT_VERSION=1; shift ;;
        --) shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
OUT="${OUT:-$SRC/dist}"
BUILD="${BUILD:-$SRC/build-release}"

die() { echo "build-windows: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[ "${MSYSTEM:-}" = "MINGW64" ] || die "run in an MSYS2 MINGW64 shell (MSYSTEM=${MSYSTEM:-unset})"
MINGW_BIN="${MINGW_PREFIX:-/mingw64}/bin"
export LC_ALL=C

for tool in gcc meson ninja objdump pkgconf sha256sum git; do
    command -v "$tool" >/dev/null || die "missing tool: $tool"
done

# ---------------------------------------------------------------- toolchain
PINS="$SRC/tools/windows-toolchain.txt"
TOOLCHAIN_REPORT=""
DRIFT=0
if [ -f "$PINS" ]; then
    while read -r pkg want; do
        want="${want%$'\r'}"
        case "$pkg" in ''|'#'*) continue ;; esac
        have="$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')" || true
        have="${have:-MISSING}"
        mark="ok"
        if [ "$have" != "$want" ]; then mark="DRIFT (pinned $want)"; DRIFT=1; fi
        TOOLCHAIN_REPORT+="  $pkg $have  $mark"$'\n'
    done < "$PINS"
fi
if [ "$DRIFT" = 1 ]; then
    echo "$TOOLCHAIN_REPORT"
    if [ "$STRICT" = 1 ]; then die "toolchain differs from $PINS (--strict)"; fi
    echo "warning: toolchain differs from $PINS; the DLL will not be byte-identical" >&2
fi

# ---------------------------------------------------------------- source
cd "$SRC"
if [ "$SUBMODULES" = 1 ]; then
    log "submodules"
    git submodule update --init --recursive
fi
COMMIT="$(git rev-parse HEAD)"
DESCRIBE="$(git describe --always --dirty --tags 2>/dev/null || echo "$COMMIT")"
DIRTY=""
git diff --quiet HEAD -- . ':!dist' ':!build-release' 2>/dev/null || DIRTY=" (working tree modified)"

# Fixed timestamps where the tools honour them.
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"

MESON_OPTS=(
    --buildtype=release
    --default-library=shared
    -Dd3d11=enabled
    -Dshaderc=enabled
    -Dglslang=disabled
    -Dlcms=enabled
    -Ddovi=enabled
    -Dlibdovi=enabled
    -Dvulkan=disabled
    -Dopengl=disabled
    -Ddemos=false
    -Dtests=true
)

# ---------------------------------------------------------------- build
if [ "$KEEP_BUILD" = 0 ] && [ -d "$BUILD" ]; then
    log "removing old build directory $BUILD"
    rm -rf "$BUILD"
fi
if [ ! -f "$BUILD/build.ninja" ]; then
    log "meson setup"
    meson setup "$BUILD" "${MESON_OPTS[@]}"
fi
# src/version.py embeds `git describe --dirty` when it finds a repository.
# Hide the repository from it (only) unless --git-version was given.
if [ "$GIT_VERSION" = 1 ]; then
    log "meson compile -j $JOBS (git describe version)"
    meson compile -C "$BUILD" -j "$JOBS"
else
    log "meson compile -j $JOBS (plain release version)"
    GIT_DIR=/nonexistent-git-dir meson compile -C "$BUILD" -j "$JOBS"
fi

TEST_SUMMARY="not run"
if [ "$RUN_TESTS" = 1 ]; then
    log "meson test"
    if [ "$GIT_VERSION" = 1 ]; then
        meson test -C "$BUILD" --num-processes "$JOBS" --print-errorlogs
    else
        GIT_DIR=/nonexistent-git-dir meson test -C "$BUILD" --num-processes "$JOBS" --print-errorlogs
    fi
    TEST_SUMMARY="$(grep -E '^(Ok|Expected Fail|Fail|Unexpected Pass|Skipped|Timeout):' \
        "$BUILD/meson-logs/testlog.txt" | tr '\n' ' ')"
    ok="$(grep -E '^Ok:' "$BUILD/meson-logs/testlog.txt" | awk '{print $2}')"
    log "tests: $TEST_SUMMARY"
    [ "${ok:-0}" -ge 13 ] || die "expected at least 13 passing library tests, got ${ok:-0}"
fi

# ---------------------------------------------------------------- collect
DLL="$(ls "$BUILD"/src/libplacebo-*.dll | head -n1)"
[ -f "$DLL" ] || die "no libplacebo DLL in $BUILD/src"
DLLNAME="$(basename "$DLL")"
STEM="${DLLNAME%.dll}"
API="$(sed -n 's/^#define PL_API_VER \([0-9]*\).*/\1/p' "$BUILD/src/include/libplacebo/config.h")"

log "collecting $DLLNAME (API $API) into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/include"
cp "$DLL" "$OUT/bin/"

# Transitive non-system dependencies resolved from the MinGW prefix.
declare -A SEEN=()
deps_of() { objdump -p "$1" | sed -n 's/^\s*DLL Name: //p' | tr -d '\r'; }
queue=("$DLL")
while [ ${#queue[@]} -gt 0 ]; do
    cur="${queue[0]}"; queue=("${queue[@]:1}")
    for dep in $(deps_of "$cur"); do
        key="${dep,,}"
        [ -n "${SEEN[$key]:-}" ] && continue
        SEEN[$key]=1
        if [ -f "$MINGW_BIN/$dep" ]; then
            cp "$MINGW_BIN/$dep" "$OUT/bin/"
            queue+=("$MINGW_BIN/$dep")
        fi
    done
done

cp -r "$SRC/src/include/libplacebo" "$OUT/include/"
cp "$BUILD/src/include/libplacebo/config.h" "$OUT/include/libplacebo/"
IMPA="$(ls "$BUILD"/src/*.dll.a 2>/dev/null | head -n1 || true)"
[ -n "$IMPA" ] && cp "$IMPA" "$OUT/lib/$STEM.dll.a"

# Export table -> exports.txt and the MSVC .def (CRLF, sorted, without the
# internal memcpy_layout, matching VP's lib/libplacebo-<API>.def).
objdump -p "$DLL" | awk '
    /\[Ordinal\/Name Pointer\] Table/ { f = 1; next }
    f && /^[ \t]*\[/ { print $NF; next }
    f && NF == 0 { exit }' | tr -d '\r' | sort > "$OUT/exports.txt"
NEXPORTS="$(wc -l < "$OUT/exports.txt")"
{
    printf 'LIBRARY %s\r\nEXPORTS\r\n' "$DLLNAME"
    grep -vx 'memcpy_layout' "$OUT/exports.txt" | sed 's/$/\r/'
} > "$OUT/lib/$STEM.def"
NDEF="$(grep -vxc 'memcpy_layout' "$OUT/exports.txt")"
grep -qx 'pl_mpv_user_shader_set_texture' "$OUT/exports.txt" \
    || die "fork export pl_mpv_user_shader_set_texture is missing (patch 0004?)"

# Optional: MSVC import library, if lib.exe is reachable (LIB_EXE or PATH).
LIBEXE="${LIB_EXE:-$(command -v lib.exe 2>/dev/null || true)}"
IMPLIB_NOTE="not generated here; run: lib.exe /nologo /def:$STEM.def /machine:x64 /out:$STEM.lib"
if [ -n "$LIBEXE" ] && [ -x "$LIBEXE" ]; then
    (cd "$OUT/lib" && MSYS2_ARG_CONV_EXCL='*' "$LIBEXE" /nologo "/def:$STEM.def" /machine:x64 "/out:$STEM.lib") \
        && rm -f "$OUT/lib/$STEM.exp" \
        && IMPLIB_NOTE="generated by $LIBEXE"
fi

# ---------------------------------------------------------------- manifest
{
    echo "libplacebo VP FL35 Windows x64 build"
    echo "Source: $(git remote get-url origin 2>/dev/null || echo unknown)"
    echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "Commit: $COMMIT$DIRTY"
    echo "Describe: $DESCRIBE"
    echo "API: $API ($DLLNAME)"
    echo "pl_version string: $(sed -n 's/.*BUILD_VERSION *"\(.*\)".*/\1/p' "$BUILD/src/version.h")"
    echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)  SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
    echo "Submodules:"
    git submodule status --recursive | sed 's/^/ /'
    echo "Meson options: ${MESON_OPTS[*]}"
    echo "Tests: $TEST_SUMMARY"
    echo "Exports: $NEXPORTS names in the DLL; $NDEF in $STEM.def (memcpy_layout excluded)"
    echo "Import library: $IMPLIB_NOTE"
    echo "Toolchain:"
    echo "  $(gcc --version | head -n1)"
    echo "  meson $(meson --version); ninja $(ninja --version); $(objdump --version | head -n1)"
    echo "  MSYS2 package versions (vs tools/windows-toolchain.txt):"
    printf '%s' "$TOOLCHAIN_REPORT"
    echo "Runtime DLLs bundled in bin/ (resolved from $MINGW_BIN):"
    for f in "$OUT"/bin/*.dll; do
        b="$(basename "$f")"
        own="$(pacman -Qqo "$MINGW_BIN/$b" 2>/dev/null || true)"
        [ "$b" = "$DLLNAME" ] && own="(this build)"
        echo "  $b ${own:+$own }$(pacman -Q "$own" 2>/dev/null | awk '{print $2}')"
    done
} > "$OUT/BUILD-MANIFEST.txt"

(cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | sort | xargs -d '\n' sha256sum) > "$OUT/SHA256SUMS"

log "done"
echo "  DLL:     $OUT/bin/$DLLNAME"
echo "  sha256:  $(sha256sum "$OUT/bin/$DLLNAME" | awk '{print $1}')"
echo "  exports: $NEXPORTS (def: $NDEF)"
echo "  tests:   $TEST_SUMMARY"
echo "  implib:  $IMPLIB_NOTE"
