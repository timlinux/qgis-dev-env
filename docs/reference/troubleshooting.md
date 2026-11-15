<!--
SPDX-FileCopyrightText: 2026 Kartoza (Pty) Ltd <tim@kartoza.com>
SPDX-License-Identifier: MIT
-->

# Troubleshooting

Field notes from real breakages — each one is already fixed or fenced by
the tooling, but the symptoms are documented here so nobody debugs them
twice. First reflex for anything odd: `qgis-dev doctor` (`<leader>pv`).

## Build failures

### `OGRGeometry*` → `OGRGeometryH` conversion errors in `pdal_wrench`

**Symptom:** Debug builds die in `external/pdal_wrench` with
`cannot convert 'std::unique_ptr<OGRGeometry>::pointer' … to 'OGRGeometryH'`
inside PDAL's `Geometry.hpp`.

**Cause:** nixpkgs' GDAL propagates `$<$<CONFIG:DEBUG>:GDAL_DEBUG>` to all
Debug consumers; that define switches GDAL's C handles to strict opaque
types, which PDAL 2.8.4's headers don't survive. Release builds never
define it — upstream CI can't see this.

**Fence:** all Debug-config profiles pass `-UGDAL_DEBUG` (it lands after
the injected `-D`, restoring the release-style `void*` handles; no ABI
impact). If you handcraft cmake flags, keep that flag.

### Freshly built tools can't load Qt (`libQt6Xml.so.6: cannot open …`)

**Symptom:** build-time helpers (`crssync`) or the built `qgis` fail with
missing shared libraries; `readelf -d` on the binary shows a RUNPATH with
no `/nix/store/` entries.

**Cause:** linking through an *unwrapped* `mold` bypasses nix's bintools
wrapper — the component that injects store `-rpath`s (`NIX_LDFLAGS`) at
link time.

**Fence:** the devshell ships `mold-wrapped`. If you ever see storeless
RUNPATHs again, something reintroduced a bare linker; fix the toolchain,
then `qgis-dev relink`.

### crssync: `Could not open database …/build/app/share/qgis/resources/srs.db`

**Symptom:** crssync hunts for `srs.db` under the (uninstalled) install
prefix.

**Cause:** `qgisbuildpath.txt` is missing from `build/output/bin/`. QGIS
binaries use it to detect "running from a build tree"; it is written at
**configure** time, so deleting `build/output` by hand removes it and
ninja never brings it back.

**Fence:** never `rm -rf build/output` bare — use **`qgis-dev relink`**,
which clears linked artifacts, keeps every compiled object, and
reconfigures so configure-time files are regenerated. Additionally,
`qgis-dev build`/`run` now self-heal: a missing marker is rewritten
before launch.

### QGIS starts but "Couldn't load SIP module / No module named 'qgis'"

**Symptom:** the app runs, Python is disabled; the reported
`Python path` starts with `…/build/output/share/qgis/python` (install
layout) instead of `…/build/output/python` (where the bindings are).

**Cause:** running-from-build-tree detection failed (missing
`qgisbuildpath.txt`), or something forced install-layout paths —
setting `QGIS_PREFIX_PATH` does exactly that when detection fails.

**Fence:** `qgis-dev run` restores the marker automatically, reconfigures
if the `qgis.PyQt` staging is missing, and launches bare (no
`QGIS_PREFIX_PATH`). If you launch the binary by hand, do the same:
`./build/output/bin/qgis` with no prefix env.

### Configure fails: "file failed to create directory … because: File exists"

**Symptom:** cmake dies creating `build/output/python/qgis/<name>` and
`ls -la` shows `<name>` is a regular **file** where a directory belongs.

**Cause:** an interrupted/failed parallel build can race the Python
staging steps and strand a file copy at its parent directory's path.
Later configures then cannot create the directory.

**Fence:** delete the stray file(s) (`rm build/output/python/qgis/<name>`)
and reconfigure. Content is always regenerable — everything under
`build/output` is derived.

### A stale `build/` from another toolchain

Mixing objects from an older compiler generation with a new devshell
produces confusing failures. If a build tree predates your current
`flake.lock`, retire it (`rm -rf build && qgis-dev build`) — the ccache
keeps the cost honest.

### Qt runtime pieces missing (wayland platform, SVG icons, QML modules)

**Symptoms:** `Could not find the Qt platform plugin "wayland"` then a
GLX abort; blank/missing toolbar icons; or
`module "QtQuick.Controls" … not found` from the welcome screen.

**Cause:** packaged Qt apps get plugin and QML paths injected by nix's Qt
wrapper at install time; a build-tree binary only sees what the devshell
exports. Each Qt add-on lives in its own store path (qtwayland, qtsvg,
qtimageformats, qtdeclarative).

**Fence:** the devshell exports `QT_PLUGIN_PATH` roots for
qtbase/qtwayland/qtsvg/qtimageformats and `QML_IMPORT_PATH` for
qtdeclarative. If a new Qt feature complains, add its package to those
exports in `flake.nix` — and never set `QT_QPA_PLATFORM_PLUGIN_PATH`,
which restricts the platform search to a single directory.

## Environment & editor

### Neovim takes minutes to start in the checkout

lua-language-server roots at the checkout and, unfenced, crawls the whole
tree (`build/`, `.git`, `src/`, …) hunting for Lua to preload. The overlay
`.luarc.json` caps preload and ignores the heavy directories. If startup
regresses, check that symlink survived (`qgis-dev doctor`).

### No banner / no environment when entering the checkout

Silent `cd` with no direnv output at all → the direnv hook isn't installed
in your shell (`direnv status`; on NixOS: `programs.direnv.enable = true;`
plus `nix-direnv.enable = true;`). A `direnv: error … .envrc is blocked`
message → run `direnv allow` (expected whenever `.envrc` content changes —
that's the trust model working).

### Re-evaluation on entry after sidecar changes

`use flake path:…` keys on the sidecar's content hash, and `.envrc`
watches `flake.nix`, `flake.lock` and `lib/tasks.sh` — so a sidecar commit
triggers one re-evaluation on your next entry (seconds when nothing
material changed). Profiles, suppressions and the banner are read live and
need no reload.

### `Detected locale "C" … not UTF-8` spam

The devshell exports `LANG=C.UTF-8` when the environment lacks one; this
warning only survives in terminals opened before that fix loaded.
Re-enter the shell.

### Qt Multimedia grumbles about pipewire at build time

`qt.multimedia.symbolsresolver: Couldn't load pipewire-0.3` during builds
is Qt probing for audio it doesn't need there. Harmless.

### `error: 'flake.nix' is too short to be a valid store path` on `nix flake lock`/`nix flake check`

**Symptom:** this exact error, no matter how the `qgis` input is spelled
— a `path:..` url string, a Nix path literal (`type = "path"; path =
../.;`), or an attrs-form string (`path = "..";`) — and no matter
whether `--impure` is added. All three hit the identical failure at the
identical evaluation step ("while updating the flake input 'qgis'").

**Cause:** this flake is itself identified as `git+file://…` (it's a git
checkout), and a *relative* path input that crosses outside that git
tree — declared directly in `flake.nix`'s `inputs`, in any spelling —
goes through a genuinely broken resolution path on some Nix/Lix versions.
It is not a syntax problem; don't keep trying variations.

**Fence:** don't declare the local checkout as a relative input at all.
Keep `qgis.url = "github:qgis/QGIS";` committed (portable, CI-safe, no
bug), and override it at invocation time with an **absolute**
`git+file://` reference instead —
`--override-input qgis "git+file://$(git rev-parse --show-toplevel)"
--impure`. An absolute path supplied at the CLI never goes through the
relative/git-tree-escaping code path that fails above, and — bonus — it
never gets baked into the committed `flake.lock` as a machine-specific
path either. `.envrc` and the `qgis-dev`/`nix run .#<task>` wrappers
already do this for you; see [The flake](../internals/the-flake.md) and
[Activation & the devshell](../internals/activation.md).

### `lib.fileset.gitTracked: … argument is a store path within a working tree of a Git repository`

**Symptom:** this error surfaces from *inside upstream QGIS's own*
`flake.nix` evaluation, right after the `qgis` input override above
resolves successfully — i.e. you get past the first bug and hit this one
next.

**Cause:** upstream's `flake.nix` selects its build source via
`lib.fileset.gitTracked self` (or similar), which explicitly refuses a
plain directory copy — the error names the exact pattern: "a source
directory was imported into the store using a method such as
`import "${./.}"` or `path:.`". A bare `--override-input qgis
"path:<abs>"` is exactly that pattern. It doesn't reject `github:qgis/QGIS`
because GitHub fetches are git-based, not a raw copy.

**Fence:** override with `git+file://` instead of `path:` — same local
checkout, fetched through Nix's git fetcher rather than copied as a plain
directory, which is what `lib.fileset.gitTracked` actually wants (the
error message itself suggests "a fetcher such as fetchGit"). `.envrc` and
the `qgis-dev` wrappers already use `git+file://`. This also means an
actively-edited (uncommitted but tracked) QGIS checkout needs `--impure`
to fetch at all — already included — since a dirty git tree is otherwise
refused.

## Git & isolation

### `git clean -fdx` deletes the embed and your build tree

`-x` removes *ignored* files — which is exactly what the overlay and
`qgis-dev-env/` are. Plain `git clean -fd` is safe.

### Something overlay-ish shows in `git status`

That is an isolation breach — `qgis-dev doctor` names the file; unstage it
(`git restore --staged <file>`) and re-run bootstrap. The pre-push guard
would have blocked the push regardless.
