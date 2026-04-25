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

### Build model

`build.zig` compiles each `src/*.zig` file as a **separate object** via `addZigObject`, then links them all together into the `bo` executable. Each object links libc, includes the root directory (so `@cInclude("tree.h")` resolves), and receives the platform preprocessor defines via `addPreprocessorDefines`.

### C/Zig interop pattern

`tree.h` is the single shared header. Every Zig module starts with:

```zig
const c = @cImport({ @cInclude("tree.h"); });
```

- **Functions provided by Zig** (e.g. `uidtoname`, `scopy`, `xmalloc`, `patmatch`) are declared with `export fn` so C code can call them.
- Function pointer globals (`basesort`, `topsort`, `getfulltree`) require explicit `callconv(.c)` in their Zig type signatures.

### Linux struct_timespec workaround

musl's `struct_timespec` uses bitfield padding that Zig's C translator demotes to an opaque type, making `c.struct_stat` unusable from Zig on Linux. `list.zig` works around this by calling the kernel directly via `std.os.linux.fstatat` on Linux and filling `struct__info` fields manually.

### Key source files

| File | Role |
|------|------|
| `src/main.zig` | Entry point: routes `bo man` to the embedded man page, otherwise calls `run` |
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
