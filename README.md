# bo (The Bodhi Tree)

[![Version](https://img.shields.io/github/tag/mrwormhole/bo.svg)](https://github.com/mrwormhole/bo/tags)
[![CI](https://github.com/mrwormhole/bo/actions/workflows/main.yaml/badge.svg)](https://github.com/mrwormhole/bo/actions/workflows/main.yaml)
[![License](https://img.shields.io/github/license/mrwormhole/bo)](https://github.com/mrwormhole/bo/blob/main/LICENSE)

This is a UNIX utility to display a tree view of directories. The original tree (written in C) can be found [here](http://oldmanprogrammer.net/source.php?dir=projects/tree)

bo (The Bodhi Tree) is Zig (v0.15.2) version of this UNIX utility where C implementation is moved to Zig implementation gradually to make cross-platform dead easy and improve the safety without performance loss. It is also an educational project to test drive Zig. Everyone is welcome here via PRs

You can grab the binary from [the releases here](https://github.com/mrwormhole/bo/releases)

## Build Your Own Binary

**Fully Supported:**

- Linux (x86_64, ARM64), macOS (x86_64, Apple Silicon), FreeBSD (x86_64, ARM64), Android (via NDK)

**Not Supported :**

- Windows (requires full Zig re-write)

```bash
zig build # Debug build (default)
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseFast
```

The compiled binary will be located at `zig-out/bin/`. It is super easy to build for any platform from any platform:

```bash
zig build -Dtarget=aarch64-linux    
zig build -Dtarget=x86_64-macos    
zig build -Dtarget=aarch64-macos   
zig build -Dtarget=x86_64-freebsd
```

## Run Without Installing

```bash
zig build run -- --version
zig build run -- -L 2
zig build run -- man
```

## C → Zig Porting Notes

Since this is an educational project, here is what porting C to Zig teaches you about the type system.

### Strings: The Biggest Surprise

C has one string type: `char *`. Zig has four, each encoding different guarantees in the type system.

| C | Zig | What it guarantees |
|---|-----|--------------------|
| `char *` | `[*c]u8` | C-compatible, nullable, no length, no sentinel |
| `const char *` | `[*c]const u8` | same, read-only |
| `const char *` (NUL-terminated) | `[*:0]const u8` | pointer to NUL-terminated data, not nullable |
| slice (pointer + len) | `[]u8` / `[]const u8` | no C equivalent |
| NUL-terminated slice | `[:0]const u8` | pointer + length + sentinel, Zig-native |

The rule: use `[*c]` when crossing the C boundary. Use `[*:0]` when you control the Zig side and know the pointer is non-null and NUL-terminated. Use `[]` slices everywhere inside pure Zig.

### Pointer Nullability Is Encoded in the Type

In C, every pointer is implicitly nullable. Zig separates them:

- `*T` — non-null, single item
- `?*T` — nullable (optional pointer), equivalent to C's `T *`
- `[*]T` — non-null, multi-item (pointer arithmetic allowed)
- `[*c]T` — C-compatible: nullable AND allows arithmetic

`?*T` is unwrapped with if-let, making null pointer dereferences a compile error:

```zig
if (file) |f| {
    // f is *T here, guaranteed non-null
}
```

### No Implicit Integer Conversions

C silently converts between integer types. Zig never does. Every conversion is an explicit builtin:

| C | Zig |
|---|-----|
| `(int)x` | `@intCast(x)` — checked at runtime in debug |
| `(u32)x` | `@as(u32, x)` — asserts the type, no truncation |
| `(void *)p` | `@ptrCast(p)` |
| `(uintptr_t)p` | `@intFromPtr(p)` |
| `(T *)int` | `@ptrFromInt(int)` |

### `void *` → `*anyopaque`

C's `void *` becomes `*anyopaque` (or `?*anyopaque` if nullable). `orelse` on an optional is the idiomatic `if (ptr == NULL)` replacement and is an expression, not a statement:

```zig
export fn xmalloc(size: usize) *anyopaque {
    return std.c.malloc(size) orelse { std.process.exit(1); };
}
```

### Globals: `extern var` and `export var`

In a mixed Zig/C project:

- C defines it, Zig accesses it → `extern var` in Zig
- Zig defines it, C accesses it → `export var` in Zig (C sees it like a normal global)

### Function Pointers Need `callconv(.c)`

C function pointers use the C calling convention. Zig's default is its own convention. When storing or calling a function pointer that crosses the C boundary, annotate it:

```zig
extern var topsort: ?*const fn ([*c][*c]c.struct__info, [*c][*c]c.struct__info) callconv(.c) c_int;
```

### Comptime: Cross-Platform Code Without the Preprocessor

C uses `#ifdef`. Zig uses `comptime` — evaluated at compile time but in the same language, with full type checking on every branch. `@hasField` lets you query whether a C struct has a field by platform:

```zig
if (comptime @hasField(c.struct_stat, "st_atimespec")) {
    lstat_info.atime = st.st_atimespec.tv_sec; // macOS
} else {
    lstat_info.atime = st.st_atim.tv_sec;      // Linux / FreeBSD
}
```

The dead branch is completely eliminated; the live branch is fully type-checked.

### Initializers

| C | Zig |
|---|-----|
| `struct Foo x = {0}` | `std.mem.zeroes(Foo)` |
| `struct Foo x;` (uninitialized) | `var x: Foo = undefined;` |
| `struct Foo x = {.a = 1, .b = 2}` | `Foo{ .a = 1, .b = 2 }` |

`undefined` means "I promise to write before I read" — the compiler catches violations in debug/safe builds.

### The One-Sentence Summary

Zig's type system forces you to state your intent explicitly: is this pointer nullable? Does it own a length? Is it NUL-terminated? Is this cast checked? In C you assume all of that silently; in Zig you write it once, and the compiler enforces it forever.

## Old Todos of Tree

Should do:

- [ ] Use stdint.h and inttypes.h to standardize the int sizes and format strings.
  Not sure how cross-platform this would be.

- [ ] Add --DU option to fully report disk usage, taking into account files that
  are not displayed in the output.

- [ ] Make wide character support less of a hack.

- [ ] Fully support HTML colorization properly and allow for an external stylesheet.

- [ ] Might be nice to prune files by things like type, mode, access/modify/change
  time, uid/gid, etc. ala find.

- [ ] Just incorporate the stat structure into _info, since we now need most of
  the structure anyway.

- [ ] Move as many globals into a struct or structs to reduce namespace pollution.

- [ ] Add support for more xattr attributes, such as user.xdg.*, trusted.mimetype,
  etc.

Maybe do:

- [ ] With the addition of TREE_COLORS, add some custom options to perhaps colorize
  metadata like the permissions, date, username, etc, and change the color of
  the tree lines and so on.

- [ ] Refactor color.c.

- [ ] Output BSON on stddata instead of JSON.
