<!--
SPDX-FileCopyrightText: 2026 Kartoza (Pty) Ltd <tim@kartoza.com>
SPDX-License-Identifier: MIT
-->

# The flake

`flake.nix` is the spine. It pins the world, composes the devshell, and
exposes every task as a runnable app.

![Flake inputs and outputs](../assets/uml/flake.svg){ .no-lightbox }

## Inputs

| Input | Role |
|---|---|
| `qgis` (`github:qgis/QGIS`) | Upstream's own flake — we consume its **packages**, which carry the complete QGIS dependency set |
| `nixpkgs` | `follows` the QGIS input's nixpkgs, so our extra tools match upstream's library versions |
| `nix-vim` (`github:timlinux/nix-vim`) | The standard team editor, pinned independently so it behaves as released |
| `clang-tools-pin` (nixpkgs-unstable) | clang-format / clang-tidy at the QGIS-pinned major (v21); the toolchain nixpkgs only carries LLVM 19, and formatting must match CI (FR-Q4) |

Because inputs are content-addressed and locked in `flake.lock`, every
colleague resolves the identical toolchain by default — and this default
(the github pin) is what CI, a standalone clone, and `devShells.tooling`
always evaluate. It's deliberately **not** declared as a local path: a
relative path input that crosses outside this repo's own git tree hits a
real Nix bug on some versions — `nix flake lock`/`nix flake check` fail
with `error: 'flake.nix' is too short to be a valid store path`,
regardless of whether the input is spelled as a `path:..` url string, a
Nix path literal, or an attrs-form string. Every spelling goes through
the same buggy resolution code once the input actually gets locked or
fetched.

Local embedded tracking (SRS C2, FR-N1) — so the devshell always matches
whatever QGIS revision you *actually* have checked out, not this pin —
happens entirely at invocation time instead, via
`--override-input qgis "git+file://<absolute qgis root>" --impure`.
`git+file:`, not a bare `path:`: upstream's own `flake.nix` selects its
source via `lib.fileset.gitTracked`, which refuses a plain directory
copy outright and wants a git-fetched source — exactly what `git+file:`
gives it (the same kind of fetch the `github:` pin above already
succeeds with). `--impure` is also what lets this fetch an
actively-edited (uncommitted) checkout, not just a clean one. `.envrc`
and the `qgis-dev`/`nix run .#<task>` app wrappers both supply this
(resolved from the real checkout path, never a relative one), so it never
touches the committed `flake.lock` and never hits the bug above. See
[Activation & the devshell](activation.md) for where this is wired up.

## devShells

`devShells.default` is composed with `inputsFrom = [ qgis.packages…qgis
qgis…unwrapped ]` — i.e. **upstream's packages, not their devShell**. That
distinction matters: pulling their `devShell` would inherit their
`dev-help` banner and shell hook; pulling their *packages* gives us the
exact same dependency closure while we own the activation experience (our
Kartoza banner). On top we add ccache, mold-wrapped, clangd, the LSP
servers, the QA tools, `nix-vim` and the `qgis-dev` binary.

`devShells.tooling` is the lighter shell for hacking on the sidecar itself:
mkdocs, plantuml, shellcheck, bats, gitleaks, reuse, nixfmt, stylua.

## apps

Every task is also `nix run .#<task>` (`configure`, `build`, `run`,
`test`, `report`, `doctor`, …) — each is a one-liner that enters the
devshell and calls `qgis-dev`. Plus `bootstrap`, the docs apps
(`handbook`, `handbook-build`, `handbook-pdf`) and `diagrams`. This is what
gives terminal / editor / CI the same capabilities (FR-N4).

The task apps' generated script is where the local-checkout override from
the Inputs section above actually happens: it resolves the QGIS root from
`git rev-parse --show-toplevel` (the same technique `qgis-dev`'s own
`init()` uses) and runs its inner `nix develop --impure --override-input
qgis "git+file://$qgis_root" …` — invisibly, so the outer `nix run
.#<task>` itself needs no extra flags.

## checks & formatter

`nix flake check` builds `checks.tests` (the bats suite, shebang-patched
for the sandbox) and `checks.shellcheck`. `formatter` is nixfmt. CI runs
exactly these against the plain github-pinned `qgis` input — no QGIS
checkout required, since CI never applies the local override.

!!! note "No code embedded in Nix"
    Per the project's rules, the flake never inlines shell or lua. It
    references real dotfiles — `lib/tasks.sh`, `lib/shell-motd.sh`,
    `lib/report.gnuplot`, `overlay/*` — and, where a runtime store path is
    needed (the report template), exports it as an env var.
