# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build (debug)
zig build

# Build with optimization
zig build -Doptimize=ReleaseFast

# Run unit tests
zig build test --summary all

# Run a single test file directly
zig test src/util.zig --test-filter "pathconcat"

# Check formatting
zig fmt --check .

# Auto-format
zig fmt .

# Run the binary
zig build run -- -L 2
zig build run -- --version
zig build run -- man

# Cross-compile (binary lands in zig-out/bin/)
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-macos

# Interop test (requires `tree` installed)
zig build && ./scripts/interop.py tree ./zig-out/bin/bo

# Matrix cross-compile across all supported targets
./matrix-build.sh
```

## Architecture

This project is a gradual port of the C `tree` utility to Zig. The repository holds a **hybrid C+Zig build**: `tree.c` (the last remaining C file) is compiled directly by Zig's C compiler, while every other original C file has been replaced by a `.zig` counterpart.

### Build model

`build.zig` compiles each `src/*.zig` file as a **separate object** via `addZigObject`, then links them all together with `tree.c` into the `bo` executable. Each object links libc, includes the root directory (so `@cInclude("tree.h")` resolves), and receives the platform preprocessor defines via `addPreprocessorDefines`.

### C/Zig interop pattern

`tree.h` is the single shared header. Every Zig module starts with:

```zig
const c = @cImport({ @cInclude("tree.h"); });
```

- **Globals defined in `tree.c`** (e.g. `flag`, `outfile`, `dirs`, `pattern`, `basesort`) are accessed in Zig files as `extern var`.
- **Functions provided by Zig** (e.g. `uidtoname`, `scopy`, `xmalloc`, `patmatch`) are declared with `export fn` so C code can call them.
- Function pointer globals (`basesort`, `topsort`, `getfulltree`) require explicit `callconv(.c)` in their Zig type signatures.

### Linux struct_timespec workaround

musl's `struct_timespec` uses bitfield padding that Zig's C translator demotes to an opaque type, making `c.struct_stat` unusable from Zig on Linux. `list.zig` works around this by calling the kernel directly via `std.os.linux.fstatat` on Linux and filling `struct__info` fields manually, while non-Linux paths delegate to C's `stat2info`.

### Key source files

| File | Role |
|------|------|
| `tree.c` | Last remaining C file — globals, CLI arg parsing, directory reading, sorting, pattern matching, formatting helpers |
| `src/main.zig` | Entry point: routes `bo man` to the embedded man page, otherwise calls `tree_main` from C |
| `src/list.zig` | `emit_tree` / `listdir` — the recursive tree-printing driver |
| `src/unix.zig` | Default text-mode listing callbacks (`unix_printinfo`, `unix_printfile`, etc.) |
| `src/color.zig` | Terminal color and charset/linedraw support |
| `src/hash.zig` | UID/GID name caches, inode dedup table, string interning (SELinux contexts) |
| `src/filter.zig` | `.gitignore`-style pattern filtering |
| `src/info.zig` | `.info` file comments |
| `src/file.zig` | `--fromfile` / `--fromtabfile` tree builders |
| `src/util.zig` | `xmalloc`, `scopy`, `pathconcat`, `is_singleton` |
| `src/strverscmp.zig` | Version-aware string compare (linked as a separate object, always available to C) |
| `src/json.zig`, `src/xml.zig`, `src/html.zig` | Output format callbacks |
| `src/man.zig` | Embedded man page (generated — see `scripts/generate_full_man.py`) |

### Testing

- **Unit tests** live inside `src/*.zig` files and are aggregated via `src/main.zig`'s `test { ... }` block. `json.zig` is intentionally excluded from the test binary because its exports bind to globals only present when the full C runtime is linked.
- **Interop tests** (`scripts/interop.py`) run `bo` and the reference `tree` binary side-by-side over a deterministic fixture directory and diff their output.
- **Man page verification** (`scripts/verify_man_page.py`) checks that `bo man` output matches the groff-formatted upstream man page.

### Ongoing port

`tree.c` is the only remaining C file. When porting a function from it to Zig:
1. Add an `export fn` in a `src/tree.zig` (or appropriate existing module).
2. Remove the C implementation and its prototype from `tree.h` (or keep the prototype pointing to the Zig export).
3. Move any global variable definitions from `tree.c` to `tree.zig` as `export var`; all other modules already declare them as `extern var`.
4. Once `tree.c` is empty, remove it from the `sources` slice in `build.zig`.
