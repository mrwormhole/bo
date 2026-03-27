#!/usr/bin/env python3
"""Interop test to compare bo output against tree."""

import os
import subprocess
import sys
import tempfile

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"


def build_fixture(root: str) -> None:
    """Create a deterministic directory fixture under root."""
    dirs = [
        "a",
        "a/b",
        "a/b/c",
        "empty",
        ".hidden_dir",
    ]
    files = [
        "root.txt",
        "a/a1.txt",
        "a/a2.txt",
        "a/b/b1.txt",
        "a/b/c/c1.txt",
        "a/b/c/c2.txt",
        ".hidden_file",
    ]
    for d in dirs:
        os.makedirs(os.path.join(root, d), exist_ok=True)
    for f in files:
        path = os.path.join(root, f)
        with open(path, "w") as fh:
            fh.write(f)


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout


# Each entry: (description, extra_flags)
# Flags that are stable across tree versions and don't expose machine-specific
# data (uid/gid, sizes, timestamps) are safe to compare exactly.
CASES = [
    ("basic listing",            []),
    ("dirs only (-d)",           ["-d"]),
    ("depth limit (-L 1)",       ["-L", "1"]),
    ("depth limit (-L 2)",       ["-L", "2"]),
    ("all files (-a)",           ["-a"]),
    ("full path (-f)",           ["-f"]),
    ("no indentation (-i)",      ["-i"]),
    ("JSON output (-J)",         ["-J"]),
    ("XML output (-X)",          ["-X"]),
    ("sort reverse (-r)",        ["-r"]),
    ("dirs first (--dirsfirst)", ["--dirsfirst"]),
]


def main() -> int:
    tree_bin  = sys.argv[1] if len(sys.argv) > 1 else "tree"
    bo_bin    = sys.argv[2] if len(sys.argv) > 2 else "./zig-out/bin/bo"

    failures = 0

    # Prefer /dev/shm (guaranteed RAM-backed tmpfs on Linux) so the fixture
    # never touches the real disk.  Fall back to the OS default on other platforms.
    tmpfs = "/dev/shm" if os.path.isdir("/dev/shm") else None
    with tempfile.TemporaryDirectory(dir=tmpfs) as tmp:
        build_fixture(tmp)

        for desc, flags in CASES:
            tree_out = run([tree_bin,  *flags, "--noreport", tmp])
            bo_out   = run([bo_bin,    *flags, "--noreport", tmp])

            # Normalise absolute tmp path so output is path-independent
            tree_out = tree_out.replace(tmp, "<ROOT>")
            bo_out   = bo_out.replace(tmp, "<ROOT>")

            if tree_out == bo_out:
                print(f"  {PASS}  {desc}")
            else:
                print(f"  {FAIL}  {desc}")
                tree_lines = tree_out.splitlines()
                bo_lines   = bo_out.splitlines()
                max_lines  = max(len(tree_lines), len(bo_lines))
                for i in range(max_lines):
                    tl = tree_lines[i] if i < len(tree_lines) else "<missing>"
                    bl = bo_lines[i]   if i < len(bo_lines)   else "<missing>"
                    marker = "  " if tl == bl else "!!"
                    print(f"    {marker} tree: {repr(tl)}")
                    print(f"    {marker}   bo: {repr(bl)}")
                failures += 1

    print()
    total = len(CASES)
    passed = total - failures
    print(f"{passed}/{total} tests passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
