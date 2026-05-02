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

`build.zig` builds `src/main.zig` as the executable root and the rest of the Zig source files are pulled in through normal `@import` module dependencies. The executable links libc, adds the repository root as an include path so `@cInclude("tree.h")` resolves, and receives the platform preprocessor defines via `addPreprocessorDefines`.

### C/Zig interop pattern

`tree.h` is the single shared header. Every Zig module starts with:

```zig
const c = @cImport({ @cInclude("tree.h"); });
```

- **Functions still exposed through legacy C-style symbol boundaries** (e.g. `uidtoname`, `scopy`, `xmalloc`) are declared with `pub export fn`; normal Zig callers should prefer importing the owning module directly.
- Function pointer globals (`basesort`, `topsort`, `getfulltree`) still require explicit `callconv(.c)` in their Zig type signatures while they remain ABI-shaped.

### Linux struct_timespec workaround

musl's `struct_timespec` uses bitfield padding that Zig's C translator demotes to an opaque type, making `c.struct_stat` unusable from Zig on Linux. `src/linux.zig` isolates the Linux `std.os.linux.fstatat` wrapper, and callers fill `types.Info` fields manually from `std.os.linux.Stat`.

### Key source files

| File | Role |
|------|------|
| `src/main.zig` | Entry point: routes `bo man` to the embedded man page, otherwise calls `run` |
| `src/list.zig` | `emit_tree` / `listdir` — the recursive tree-printing driver |
| `src/unix.zig` | Default text-mode listing callbacks (`printinfo`, `printfile`, etc.) |
| `src/color.zig` | Terminal color and charset/linedraw support |
| `src/hash.zig` | UID/GID name caches, inode dedup table, string interning (SELinux contexts) |
| `src/filter.zig` | `.gitignore`-style pattern filtering |
| `src/info.zig` | `.info` file comments |
| `src/file.zig` | `--fromfile` / `--fromtabfile` tree builders |
| `src/util.zig` | `xmalloc`, `scopy`, `pathconcat`, `is_singleton` |
| `src/strverscmp.zig` | Version-aware string compare |
| `src/json.zig`, `src/xml.zig`, `src/html.zig` | Output format callbacks |
| `src/man.zig` | Embedded man page (generated — see `scripts/generate_full_man.py`) |

### Testing

- **Unit tests** live inside `src/*.zig` files and are aggregated via `src/tests.zig`'s `test { ... }` block. Output renderer modules are not currently imported by the unit-test root because their callbacks bind to runtime globals used by the full executable.
- **Interop tests** (`scripts/interop.py`) run `bo` and the reference `tree` binary side-by-side over a deterministic fixture directory and diff their output.
- **Man page verification** (`scripts/verify_man_page.py`) checks that `bo man` output matches the groff-formatted upstream man page.
