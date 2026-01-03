# Preprocessor Macros Reference

## Platform Detection

| Macro | Purpose | Location |
|-------|---------|----------|
| `__ANDROID__` / `__ANDROID` | Android platform detection | tree.h |
| `__linux__` | Linux platform detection | tree.h, tree.c |

## File Type Detection (Solaris Legacy)

| Macro | Purpose | Location |
|-------|---------|----------|
| `S_IFDOOR` | Solaris door files (IPC mechanism) | tree.c:42, tree.c:1397, color.c |
| `S_IFPORT` | Solaris event ports (/dev/*poll) | tree.c:42 |

## System Configuration

| Macro | Purpose | Default Value | Location |
|-------|---------|---------------|----------|
| `PATH_MAX` | Maximum path length | 4096 | tree.h |
| `INFO_PATH` | Default info file path | "/usr/share/finfo/global_info" | tree.h |
| `MB_CUR_MAX` | Max bytes in multibyte char | (system) | tree.c |
| `__USE_FILE_OFFSET64` | Large file support (64-bit offsets) | - | json.c, xml.c, tree.c |
| `_GNU_SOURCE` | Enable GNU extensions | - | tree.h |

## Utility Macros

| Macro | Definition | Purpose |
|-------|------------|---------|
| `MAXPATH` | `64*1024` | Custom max path (64KB) |
| `HASH(x)` | `((x)&255)` | Hash function |
| `inohash(x)` | `((x)&255)` | Inode hash |
| `SIXMONTHS` | `(6*31*24*60*60)` | Time constant (6 months) |
| `scopy(x)` | `strcpy(xmalloc(strlen(x)+1),(x))` | String copy helper |
| `MINIT` | `30` | Initial dir entry allocation |
| `MINC` | `20` | Allocation increment |
| `UNUSED(x)` | `((void)x)` | Suppress unused variable warnings |

## strverscmp.c (GNU Version Sorting)

| Macro | Value | Purpose |
|-------|-------|---------|
| `S_N` | `0x0` | State: N (number) |
| `S_I` | `0x4` | State: I (identifier) |
| `S_F` | `0x8` | State: F (fractional) |
| `S_Z` | `0xC` | State: Z (zero) |
| `CMP` | `2` | Comparison result |
| `LEN` | `3` | Length comparison |
