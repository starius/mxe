#!/usr/bin/env python3
"""
Export MXE package metadata into a machine-readable JSON file.
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys
from typing import Dict, List

DELIM = "\x1f"
DEFAULT_CROSS_TARGETS = [
    "i686-w64-mingw32.static",
    "i686-w64-mingw32.shared",
    "x86_64-w64-mingw32.static",
    "x86_64-w64-mingw32.shared",
]
REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = REPO_ROOT / "metadata" / "mxe-packages.json"


def _unique(sequence: List[str]) -> List[str]:
    seen = {}
    result: List[str] = []
    for item in sequence:
        if item not in seen:
            seen[item] = True
            result.append(item)
    return result


def run_metadata_dump() -> str:
    """Invoke the helper makefile and return its stdout."""
    env = os.environ.copy()
    env.setdefault("MXE_TARGETS", " ".join(DEFAULT_CROSS_TARGETS))
    target_arg = "MXE_TARGETS=" + " ".join(env["MXE_TARGETS"].split())

    cmd = [
        "make",
        "-s",
        "-f",
        str(REPO_ROOT / "tools" / "export-mxe-metadata.mk"),
        target_arg,
        "metadata-dump",
    ]
    try:
        res = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stdout)
        sys.stderr.write(exc.stderr)
        raise
    # Some informational lines may appear on stderr (e.g. GCC warnings).
    if res.stderr:
        sys.stderr.write(res.stderr)
    return res.stdout


def parse_lines(raw: str) -> Dict:
    """Convert the delimited dump into structured metadata."""
    globals_section: Dict[str, str] = {}
    packages: Dict[str, Dict] = {}

    for line in raw.splitlines():
        if DELIM not in line:
            continue
        parts = line.split(DELIM)
        kind = parts[0]

        if kind == "global" and len(parts) >= 3:
            key = parts[1]
            value = parts[2] if len(parts) > 2 else ""
            globals_section[key] = value
            continue

        if kind == "pkg" and len(parts) >= 4:
            pkg = parts[1]
            raw_field = parts[2]
            field = {
                "url-2": "url2",
                "file-deps": "fileDeps",
            }.get(raw_field, raw_field)
            value = parts[3] if len(parts) > 3 else ""
            pkg_entry = packages.setdefault(pkg, {"fields": {}, "targets": {}})
            pkg_entry["fields"][field] = value
            continue

        if kind == "target" and len(parts) >= 5:
            pkg = parts[1]
            target = parts[2]
            raw_field = parts[3]
            field = {"url-2": "url2"}.get(raw_field, raw_field)
            value = parts[4] if len(parts) > 4 else ""
            pkg_entry = packages.setdefault(pkg, {"fields": {}, "targets": {}})
            target_entry = pkg_entry["targets"].setdefault(target, {})

            if field == "oo-deps":
                items = [item for item in value.split() if item]
                target_entry["ooDeps"] = items
            elif field == "deps":
                items = [item for item in value.split() if item]
                target_entry[field] = items
            elif field == "build":
                target_entry[field] = (value == "yes")
            else:
                target_entry[field] = value
            continue

    host = globals_section.get("host", "")
    ignore_oo_deps = {"mxe-conf", "ccache"}
    if host:
        ignore_oo_deps.update(
            {
                f"{host}~autotools",
                f"{host}~cmake-conf",
            }
        )

    # Post-process package fields for convenience.
    for pkg_name, pkg_entry in packages.items():
        fields = pkg_entry["fields"]

        patches_raw = fields.pop("patches", "")
        patch_paths = [item for item in patches_raw.split() if item]
        rel_patches = []
        for patch in patch_paths:
            path = pathlib.Path(patch)
            try:
                rel_path = path.relative_to(REPO_ROOT)
            except ValueError:
                rel_path = pathlib.Path(os.path.relpath(path, REPO_ROOT))
            rel_patches.append(str(rel_path))
        pkg_entry["patches"] = _unique(rel_patches)

        targets_raw = fields.pop("targets", "")
        declared_targets = [item for item in targets_raw.split() if item]
        pkg_entry["declaredTargets"] = _unique(declared_targets)

        primary_url = fields.get("url", "")
        secondary_url = fields.get("url2", "")

        for key in list(fields.keys()):
            value = fields[key]
            if isinstance(value, str) and value == "":
                del fields[key]

        for target, target_meta in pkg_entry["targets"].items():
            if target_meta.get("file") == fields.get("file"):
                target_meta.pop("file", None)
            if target_meta.get("url") == primary_url:
                target_meta.pop("url", None)
            if target_meta.get("url2") == secondary_url:
                target_meta.pop("url2", None)
            if target_meta.get("message") == "":
                target_meta.pop("message", None)

            if host:
                if "deps" in target_meta:
                    target_meta["deps"] = [
                        dep.replace("$(BUILD)", host) for dep in target_meta["deps"]
                    ]
                if "ooDeps" in target_meta:
                    target_meta["ooDeps"] = [
                        dep.replace("$(BUILD)", host) for dep in target_meta["ooDeps"]
                    ]

            if "ooDeps" in target_meta:
                filtered_oo = [
                    dep for dep in target_meta["ooDeps"] if dep not in ignore_oo_deps
                ]
                filtered_oo = _unique(filtered_oo)
                if filtered_oo:
                    target_meta["ooDeps"] = filtered_oo
                else:
                    target_meta.pop("ooDeps")

            if "deps" in target_meta:
                target_meta["deps"] = _unique(target_meta["deps"])

            for key in ("file", "url", "url2"):
                if key in target_meta and target_meta[key] == "":
                    target_meta.pop(key, None)

        target_map = pkg_entry["targets"]
        profile_lookup = {}
        for target_name in sorted(target_map.keys()):
            meta = target_map[target_name]
            norm_key = json.dumps(meta, sort_keys=True, separators=(",", ":"))
            bucket = profile_lookup.setdefault(
                norm_key,
                {
                    "meta": json.loads(json.dumps(meta, sort_keys=True)),
                    "targets": [],
                },
            )
            bucket["targets"].append(target_name)

        target_profiles = []
        for bucket in profile_lookup.values():
            profile = bucket["meta"]
            profile["targets"] = sorted(bucket["targets"])
            target_profiles.append(profile)

        target_profiles.sort(key=lambda p: p["targets"])
        pkg_entry["targetProfiles"] = target_profiles
        del pkg_entry["targets"]

    mxe_targets_raw = globals_section.get("mxe-targets", "")
    mxe_targets = [item for item in mxe_targets_raw.split() if item]

    return {
        "host": globals_section.get("host", ""),
        "gitHead": globals_section.get("git-head", ""),
        "mxeTargets": mxe_targets,
        "packages": packages,
    }


def write_output(data: Dict, output_path: pathlib.Path, pretty: bool) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        if pretty:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        else:
            json.dump(data, handle, separators=(",", ":"), sort_keys=True)


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-o",
        "--output",
        type=pathlib.Path,
        default=DEFAULT_OUTPUT,
        help=f"Path to write metadata JSON (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Write compact JSON (no pretty indentation).",
    )
    args = parser.parse_args(argv)

    raw = run_metadata_dump()
    data = parse_lines(raw)
    write_output(data, args.output, pretty=not args.compact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
