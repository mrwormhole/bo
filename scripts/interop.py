#!/usr/bin/env python3
"""Interop test to compare bo output against tree."""

import os
import subprocess
import sys
import tempfile

from enum import StrEnum

class Color(StrEnum):
    RESET = "\033[0m"
    RED   = "\033[31m"
    GREEN = "\033[32m"

PASS = f"{Color.GREEN}PASS{Color.RESET}"
FAIL = f"{Color.RED}FAIL{Color.RESET}"


def build_fromfile_fixture(root: str) -> None:
    """Write paths.txt and tabs.txt for --fromfile / --fromtabfile tests."""
    paths = [
        "a",
        "a/b",
        "a/b/c",
        "a/b/c/c1.txt",
        "a/b/c/c2.txt",
        "a/b/b1.txt",
        "a/a1.txt",
        "a/a2.txt",
        "root.txt",
        "link_to_file -> a/a1.txt",
    ]
    with open(os.path.join(root, "paths.txt"), "w") as fh:
        fh.write("\n".join(paths) + "\n")

    tab_lines = [
        "a",
        "\ta1.txt",
        "\ta2.txt",
        "\tb",
        "\t\tb1.txt",
        "\t\tc",
        "\t\t\tc1.txt",
        "\t\t\tc2.txt",
        "root.txt",
    ]
    with open(os.path.join(root, "tabs.txt"), "w") as fh:
        fh.write("\n".join(tab_lines) + "\n")


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
        # Force json_encode escape branches: quote → \", backslash → \\,
        # tab → \t, DEL (0x7f stays literal but bytes < 32 hit the ctrl map).
        'a/quote"file.txt',
        'a/back\\slash.txt',
        'a/tab\tfile.txt',
    ]
    for d in dirs:
        os.makedirs(os.path.join(root, d), exist_ok=True)
    for f in files:
        path = os.path.join(root, f)
        with open(path, "w") as fh:
            fh.write(f)
    # Symlinks exercise list.zig's lnk branches: dir-link descend (-l),
    # file-link rendering, and the "recursive, not followed" path when -l
    # follows a self-loop and findino() reports the inode as already seen.
    os.symlink("a",        os.path.join(root, "link_to_dir"))
    os.symlink("a/a1.txt", os.path.join(root, "link_to_file"))
    os.symlink(".",        os.path.join(root, "link_loop"))
    # .info file exercises info.zig: # comments, pattern-then-tab-message
    # parsing, multi-line messages, multiple patterns sharing one message,
    # and orphan/empty-line handling.
    info_body = (
        "# this is a comment line and should be skipped\n"
        "\n"
        "root.txt\n"
        "\tannotation for root.txt\n"
        "\n"
        "a1.txt\n"
        "a2.txt\n"
        "\tshared annotation across two patterns\n"
        "\tsecond line of annotation\n"
    )
    with open(os.path.join(root, ".info"), "w") as fh:
        fh.write(info_body)
    # .gitignore exercises filter.zig: # comments, blank lines, plain patterns
    # (relative + absolute), trailing-space trimming, and ! negation rescue.
    # Files referenced here are created by the loop above (a1.txt, a2.txt,
    # b1.txt, c1.txt, c2.txt under a/...).
    gitignore_body = (
        "# ignore all .txt files\n"
        "\n"
        "*.txt\n"
        "!a1.txt\n"
        ".hidden_dir/\n"
    )
    with open(os.path.join(root, ".gitignore"), "w") as fh:
        fh.write(gitignore_body)


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout


# Each entry: (description, extra_flags, indent_insensitive)
# Flags that are stable across tree versions and don't expose machine-specific
# data (uid/gid, sizes, timestamps) are safe to compare exactly.
# indent_insensitive=True strips leading whitespace before comparing — used for
# JSON/XML where indentation width changed between tree 2.3.1 and 2.3.2.
CASES = [
    ("basic listing",            [],          False),
    ("dirs only (-d)",           ["-d"],      False),
    ("depth limit (-L 1)",       ["-L", "1"], False),
    ("depth limit (-L 2)",       ["-L", "2"], False),
    ("all files (-a)",           ["-a"],      False),
    ("full path (-f)",           ["-f"],      False),
    ("no indentation (-i)",      ["-i"],      False),
    ("JSON output (-J)",         ["-J"],      True),
    ("JSON dirs only (-Jd)",     ["-J", "-d"], True),
    ("JSON no indent (-Ji)",     ["-J", "-i"], True),
    ("JSON all files (-Ja)",     ["-J", "-a"], True),
    ("JSON depth limit (-JL 1)", ["-J", "-L", "1"], True),
    ("JSON reverse (-Jr)",       ["-J", "-r"], True),
    ("JSON dirsfirst",           ["-J", "--dirsfirst"], True),
    ("XML output (-X)",          ["-X"],      True),
    ("XML dirs only (-Xd)",      ["-X", "-d"], True),
    ("XML no indent (-Xi)",      ["-X", "-i"], True),
    ("XML all files (-Xa)",      ["-X", "-a"], True),
    ("XML depth limit (-XL 1)",  ["-X", "-L", "1"], True),
    ("XML reverse (-Xr)",        ["-X", "-r"], True),
    ("XML dirsfirst",            ["-X", "--dirsfirst"], True),
    ("sort reverse (-r)",        ["-r"],      False),
    ("dirs first (--dirsfirst)", ["--dirsfirst"], False),
    ("follow links (-l)",        ["-l"],      False),
    ("follow links + depth (-lL 2)", ["-l", "-L", "2"], False),
    ("JSON follow links (-Jl)",  ["-J", "-l"], True),
    ("file-type suffix (-F)",    ["-F"],      False),
    ("file-type suffix follow links (-Fl)", ["-F", "-l"], False),
    ("hyperlinks (--hyperlink)", ["--hyperlink"], False),
    ("hyperlinks + suffix",      ["--hyperlink", "-F"], False),
    ("info annotations (--info)", ["--info"], False),
    ("info + metafirst",          ["--info", "--metafirst"], False),
    ("JSON info (--info -J)",     ["--info", "-J"], True),
    ("gitignore (--gitignore)",   ["--gitignore"], False),
    ("gitignore + all (-a)",      ["--gitignore", "-a"], False),
    ("JSON gitignore",            ["--gitignore", "-J"], True),
]


# Cases that need full control over the argv (custom paths, no --noreport,
# multiple roots, etc.). args_factory builds the full argv after the binary;
# unlike CASES, the runner does not inject --noreport here.
EDGE_CASES = [
    ("with report",          lambda t: [t],                                       False),
    ("trailing slash root",  lambda t: ["--noreport", t + "/"],                   False),
    ("multiple roots",       lambda t: ["--noreport", t, t],                      False),
    ("filelimit triggers",   lambda t: ["--noreport", "--filelimit", "2", t],     False),
    ("nonexistent path",     lambda t: ["--noreport", "/__bo_no_such_dir__"],     False),
    ("JSON nonexistent",     lambda t: ["--noreport", "-J", "/__bo_no_such_dir__"], True),
]


FILE_CASES = [
    ("fromfile basic",          lambda t: ["--fromfile",    "--noreport", os.path.join(t, "paths.txt")], False),
    ("fromfile dirs only (-d)", lambda t: ["--fromfile",    "--noreport", "-d", os.path.join(t, "paths.txt")], False),
    ("fromfile all (-a)",       lambda t: ["--fromfile",    "--noreport", "-a", os.path.join(t, "paths.txt")], False),
    ("fromfile JSON (-J)",      lambda t: ["--fromfile",    "--noreport", "-J", os.path.join(t, "paths.txt")], True),
    ("fromfile fflinks",        lambda t: ["--fromfile",    "--noreport", "--fflinks", os.path.join(t, "paths.txt")], False),
    ("fromfile gitignore",      lambda t: ["--fromfile", "--noreport", "--gitignore", os.path.join(t, "paths.txt")], False),
    ("fromfile info",           lambda t: ["--fromfile", "--noreport", "--info", os.path.join(t, "paths.txt")], False),
    ("fromtabfile basic",       lambda t: ["--fromtabfile", "--noreport", os.path.join(t, "tabs.txt")], False),
    ("fromtabfile dirs only",   lambda t: ["--fromtabfile", "--noreport", "-d", os.path.join(t, "tabs.txt")], False),
    ("fromtabfile JSON",        lambda t: ["--fromtabfile", "--noreport", "-J", os.path.join(t, "tabs.txt")], True),
    ("fromtabfile gitignore",   lambda t: ["--fromtabfile", "--noreport", "--gitignore", os.path.join(t, "tabs.txt")], False),
    ("fromtabfile info",        lambda t: ["--fromtabfile", "--noreport", "--info", os.path.join(t, "tabs.txt")], False),
]


def strip_indent(output: str) -> str:
    return "\n".join(line.lstrip() for line in output.splitlines())


def compare(desc: str, tree_args: list[str], bo_args: list[str], tmp: str,
            indent_insensitive: bool, tree_bin: str, bo_bin: str) -> bool:
    tree_out = run([tree_bin, *tree_args]).replace(tmp, "<ROOT>")
    bo_out   = run([bo_bin,   *bo_args]  ).replace(tmp, "<ROOT>")

    if indent_insensitive:
        tree_out = strip_indent(tree_out)
        bo_out   = strip_indent(bo_out)

    if tree_out == bo_out:
        print(f"  {PASS}  {desc}")
        return True

    print(f"  {FAIL}  {desc}")
    tree_lines = tree_out.splitlines()
    bo_lines   = bo_out.splitlines()
    for i in range(max(len(tree_lines), len(bo_lines))):
        tl = tree_lines[i] if i < len(tree_lines) else "<missing>"
        bl = bo_lines[i]   if i < len(bo_lines)   else "<missing>"
        marker = "  " if tl == bl else "!!"
        print(f"    {marker} tree: {repr(tl)}")
        print(f"    {marker}   bo: {repr(bl)}")
    return False


def main() -> int:
    tree_bin  = sys.argv[1] if len(sys.argv) > 1 else "tree"
    bo_bin    = sys.argv[2] if len(sys.argv) > 2 else "./zig-out/bin/bo"

    failures = 0

    # Prefer /dev/shm (guaranteed RAM-backed tmpfs on Linux) so the fixture
    # never touches the real disk.  Fall back to the OS default on other platforms.
    tmpfs = "/dev/shm" if os.path.isdir("/dev/shm") else None
    with tempfile.TemporaryDirectory(dir=tmpfs) as tmp:
        build_fixture(tmp)
        build_fromfile_fixture(tmp)

        for desc, flags, indent_insensitive in CASES:
            args = [*flags, "--noreport", tmp]
            if not compare(desc, args, args, tmp, indent_insensitive, tree_bin, bo_bin):
                failures += 1

        for desc, args_factory, indent_insensitive in EDGE_CASES:
            args = args_factory(tmp)
            if not compare(desc, args, args, tmp, indent_insensitive, tree_bin, bo_bin):
                failures += 1

        for desc, args_factory, indent_insensitive in FILE_CASES:
            args = args_factory(tmp)
            if not compare(desc, args, args, tmp, indent_insensitive, tree_bin, bo_bin):
                failures += 1

    print()
    total = len(CASES) + len(EDGE_CASES) + len(FILE_CASES)
    passed = total - failures
    print(f"{passed}/{total} tests passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
