# bo (The Bodhi Tree)

[![Version](https://img.shields.io/github/tag/mrwormhole/bo.svg)](https://github.com/mrwormhole/bo/tags)
[![CI](https://github.com/mrwormhole/bo/actions/workflows/main.yaml/badge.svg)](https://github.com/mrwormhole/bo/actions/workflows/main.yaml)
[![License](https://img.shields.io/github/license/mrwormhole/bo)](https://github.com/mrwormhole/bo/blob/main/LICENSE)

This is a UNIX utility to display a tree view of directories. The original tree (written in C) can be found [here](http://oldmanprogrammer.net/source.php?dir=projects/tree)

bo (The Bodhi Tree) is Zig version of this UNIX utility where C implementation is moved to Zig implementation gradually to make cross-platform dead easy and improve the safety without performance loss. It is also an educational project to test drive Zig. Everyone is welcome here via PRs

You can grab the binary from [the releases here](https://github.com/mrwormhole/bo/releases)

## Build Your Own Binary

**Fully Supported:**

- Linux (x86_64, ARM64), macOS (x86_64, Apple Silicon), FreeBSD (x86_64, ARM64), Android (via NDK)

**Requires POSIX Environment:**

- Windows (requires Cygwin, not native Windows, working on it to make non-POSIX dependent with full Zig re-write)

Requirement is to have Zig v0.15.2

```bash
zig build # Debug build (default)
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseFast
```

The compiled binary will be located at `zig-out/bin/`. It is super easy to build for any platform from any platform:

```bash
zig build -Dtarget=x86_64-windows   # Build Windows binary (requires Cygwin)
zig build -Dtarget=aarch64-linux    # Build ARM64 Linux binary
zig build -Dtarget=x86_64-macos     # Build macOS binary
zig build -Dtarget=aarch64-macos    # Build Apple Silicon binary
zig build -Dtarget=x86_64-freebsd   # Build FreeBSD binary
```

## Run Without Installing

```bash
zig build run -- --version
zig build run -- -L 2
zig build run -- man
```

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

Maybe do:

- [ ] With the addition of TREE_COLORS, add some custom options to perhaps colorize
  metadata like the permissions, date, username, etc, and change the color of
  the tree lines and so on.

- [ ] Refactor color.c.

- [ ] Output BSON on stddata instead of JSON.
