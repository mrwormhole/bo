# hash.c → hash.zig Migration Plan

## What hash.c does

Three independent hash tables, all using `x & 255` (low 8 bits) as the bucket index
with sorted linked-list chaining:

| Table | Key | Value | Purpose |
|---|---|---|---|
| `utable[256]` | `uid_t` | `char *name` | UID → username cache |
| `gtable[256]` | `gid_t` | `char *name` | GID → group name cache |
| `itable[256]` | `(ino_t, dev_t)` | — | Seen-inode set (symlink loop guard) |
| `strtable[256]` | DJB2 hash | `char *string` | String interning — Linux only, one caller in tree.c |

## Zig design

Replace manual hash tables with `std.AutoHashMap`:

```zig
var utable: std.AutoHashMap(u32, [:0]const u8) = undefined;
var gtable: std.AutoHashMap(u32, [:0]const u8) = undefined;

const InodeKey = struct { inode: std.posix.ino_t, dev: std.posix.dev_t };
var itable: std.AutoHashMap(InodeKey, void) = undefined;

// Linux only
var strtable: std.StringHashMap([:0]const u8) = undefined;
```

Use a module-level `std.heap.ArenaAllocator` backed by the page allocator — mirrors
the C code's intentional leak, keeps all allocations together.

## Windows portability

`uid_t`/`gid_t` do not exist on Windows. Windows `stat()` always returns 0 for
`st_uid`/`st_gid`. Use a `comptime` branch:

- **POSIX** (Linux, macOS, FreeBSD, Android): look up via `getpwuid()`/`getgrgid()`
- **Windows**: return numeric string `"0"` always

All callers of `uidtoname`/`gidtoname` are guarded by `flag.u` and `flag.g`, so
without `-u`/`-g` flags these functions are never called. With `-u`/`-g` on Windows,
every file shows `0` — technically correct since the concept doesn't exist there.

## Exported symbols

Must match `tree.h` declarations exactly:

```zig
export fn init_hashes() void
export fn uidtoname(uid: u32) [*:0]const u8
export fn gidtoname(gid: u32) [*:0]const u8
export fn saveino(inode: std.c.ino_t, device: std.c.dev_t) void
export fn findino(inode: std.c.ino_t, device: std.c.dev_t) bool
// Linux only:
export fn strhash(str: [*:0]const u8) [*:0]const u8
```

`strhash` wrapped in `comptime if (builtin.os.tag == .linux)`.

## Sorting behaviour change

The C linked lists are insertion-sorted for early-exit lookup performance. With
`std.AutoHashMap` lookup is O(1) so the sort can be dropped entirely.

## Steps

1. Write `src/hash.zig` with the design above, tests included
2. Add `hash.zig` as an object in `build.zig` (same pattern as `strverscmp_obj`)
3. Remove `hash.c` from `common_sources` and decrement the buffer size
4. Update `tree.h` — put `strhash` declaration inside `#ifdef __linux__` guard
5. Build + test — run `zig build test`, smoke test with `bo -ug`
6. Delete `hash.c`

## Tests to write in hash.zig

- `uidtoname` returns consistent pointer for repeated calls with same uid (cache hit)
- `gidtoname` same
- `findino` returns false before `saveino`, true after
- `saveino` is idempotent (calling twice doesn't duplicate)
- `strhash` returns the same pointer for identical strings (interning)
