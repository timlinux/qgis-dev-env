# SPDX-FileCopyrightText: 2026 Kartoza (Pty) Ltd <tim@kartoza.com>
# SPDX-License-Identifier: MIT
# shellcheck shell=bash disable=SC2148,SC2034,SC2054
#
# asan-ubsan — AddressSanitizer + UndefinedBehaviorSanitizer (SRS FR-G3).
# The default tool for memory bugs: ~2x slowdown vs valgrind's 20-50x.
# 3D/WebEngine off to keep instrumented rebuilds quick. qgis-dev separates
# these objects from other profiles via CCACHE_NAMESPACE.
CMAKE_ARGS+=(
  -DCMAKE_BUILD_TYPE=Debug
  -DWITH_3D=OFF
  -DWITH_PDAL=OFF
  -DWITH_QTWEBENGINE=OFF
  -DENABLE_TESTS=ON
  -DCMAKE_LINKER_TYPE=MOLD
  -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -UGDAL_DEBUG"
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -UGDAL_DEBUG"
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
  -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined"
)
# cmd_configure sources this file and then runs cmake in the same shell, so
# this scopes to the configure step only — it does NOT reach `qgis-dev run`
# (which sets its own ASAN_OPTIONS with detect_leaks=1 separately, see
# cmd_run). Needed because CMake applies CMAKE_C/CXX_FLAGS above to its own
# try_compile/try_run probes too, not just real build targets — e.g. QGIS's
# QCA detection check loads Qt6Core + OpenSSL + several QCA provider
# plugins, and LeakSanitizer's exit-time report for the resulting pile of
# "leaked" global state can hang for hours trying to symbolize it.
# Configure-time probes only need an exit code, not a leak report.
export ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_leaks=0"
