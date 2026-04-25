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

## Utility Macros

| Macro | Definition | Purpose |
|-------|------------|---------|
| `MAXPATH` | `64*1024` | Custom max path (64KB) |
| `SIXMONTHS` | `(6*31*24*60*60)` | Time constant (6 months) |
| `MINIT` | `30` | Initial dir entry allocation |
| `MINC` | `20` | Allocation increment |
| `UNUSED(x)` | `((void)x)` | Suppress unused variable warnings |
