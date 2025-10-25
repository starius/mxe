# Nix Flake Design for MXE

## Key MXE Insights
- `Makefile` auto-collects every `*.mk` from `src`, `src/qt/qt6`, and activated plugins into `PKGS`; per-package metadata lives in `$(PKG)_*` variables plus optional target overrides resolved via `LOOKUP_PKG_RULE`.
- Downloads are defined through `_FILE`, `_URL`, `_CHECKSUM`, or inferred from `_GH_CONF` with helpers in `mxe.github.mk`.
- Dependencies can reference other MXE packages (`foo`) or host-scoped ones (`$(BUILD)~bar`); GNU Make normalises these before building.
- Host build requirements are enumerated once (7za, autoconf, …, wget, xz) and must be provided through Nix.

## Metadata Extraction
- Add `tools/export-mxe-metadata.py` to invoke GNU Make (via `--eval` / `gmsl-print`) and emit a machine-readable JSON snapshot of packages.
- Capture versions, archive filenames, URLs (primary + fallback), checksums, patch lists, package types, default targets, and target-specific `DEPS` / `OO_DEPS`.
- Record host-triplet data so Nix can interpret `$(BUILD)~pkg` dependencies.
- Write the generated file to `metadata/mxe-packages.json` and add a check to ensure it stays current.

## Flake Layout
- `inputs` include `nixpkgs` and `flake-utils`.
- Expose:
  - `overlay` extending `pkgs` with MXE helpers and metadata.
  - `packages.${system}.mxePackages.${target}.${pkg}` generated from metadata, plus sensible `default` aliases.
  - `devShells.default` supplying all MXE build requirements from `nixpkgs`.
  - `checks.metadata` to refresh metadata in CI.

## Builder Strategy
- Provide `lib.mkMxePackage { target; name; extraArgs ? {}; }` that:
  - Reads metadata, computes dependency closures (including host packages).
  - Prefetches source archives via `fetchurl` using recorded URLs and checksums and symlinks them into `pkg/`.
  - Invokes MXE’s `make` with `MXE_PREFIX=$out`, `MXE_TARGETS="${target}"`, `JOBS=$NIX_BUILD_CORES`, and a writable copy of the repo.
  - Leaves the MXE prefix under the derivation output.
- Treat toolchain components (`cc`, `binutils`, `gcc`, `mingw-w64`, …) like any other MXE package so existing patches and rules apply unchanged.

## Work Plan
1. Implement the metadata exporter and persist `metadata/mxe-packages.json`.
2. Add `flake.nix` scaffolding with overlay, dev shell, and helper registration.
3. Implement `mkMxePackage` to drive MXE builds from the metadata.
4. Smoke test with a small package (e.g. `zlib`) and iterate on output shaping if needed.

