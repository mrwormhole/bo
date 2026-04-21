Port color.c → src/color.zig                                                                                                                                                                                                                                                          
                                                                                                                                                                                                                                                                                     
 Context

 The repo is mid-migration from C to Zig. file.c, html.c, json.c, xml.c, list.c, unix.c, info.c, filter.c, and the remaining formatters have already been ported; only tree.c and color.c remain in build.zig's C sources list. Porting color.c continues that migration: everything
 in it (dir-colors parsing, the color() selector, fancy() markup, getcharset(), and initlinedraw() with its 16-entry charset table) moves into Zig while keeping the exact same C ABI so tree.c, src/unix.zig, and src/info.zig keep linking unchanged. The interop test
 (scripts/interop.py) and the matrix-build.sh cross-compile must keep passing.

 Public ABI contract (must be preserved)

 From tree.h:168-174 and the grep of callers:

 Functions (all export fn in Zig):
 - parse_dir_colors() — tree.c:578, 641
 - color(mode_t, const char*, bool, bool) -> bool — unix.zig:58, 60, 79
 - endcolor() — unix.zig:66, 81
 - fancy(FILE*, char*) — tree.c:646, 664, 710
 - getcharset() -> const char* — tree.c:128
 - initlinedraw(bool help) — tree.c:92, 101, 579, 642

 Globals that leak outside color.c:
 - linedraw: const struct linedraw* — read from tree.c:1335–1336 and src/info.zig:18, 194–201. Must be export var so both C and Zig link against it.
 - color_code[] and ext — grep confirms they are only touched inside color.c. Keep module-private in Zig (plain var, no export).

 Porting approach

 Mirror the style established by src/html.zig and src/file.zig:

 - @cImport({ @cInclude("tree.h"); }) for all C types (struct_Flags, struct_linedraw, struct_extensions, mode_t, FILE, S_IF* macros, etc.).
 - extern var flag: c.struct_Flags;, extern var outfile: ?*c.FILE;, extern var charset: [*c]const u8; (pattern from html.zig:7–18).
 - Reuse C memory helpers via @cImport: c.xmalloc, c.xrealloc, c.scopy, c.strtok, c.strchr, c.strcmp, c.strcasecmp, c.strlen, c.getenv, c.fputs, c.fputc, c.fprintf, c.sprintf, c.isatty, c.strncpy. No Zig allocator — existing ports don't introduce one.
 - export fn for the six public functions. Signatures must match the C prototypes byte-for-byte (use [*c]u8 / [*c]const u8 / c_int / bool / c.mode_t / ?*c.FILE).
 - Private helpers (split, cmd, print_color) become plain (non-export) fns.
 - The ERROR / CMD_* / COL_* / DOT_EXTENSION and MCOL_* enums: port as Zig const ints (or a const enum { … } block with @intFromEnum). Keep identifiers identical so the code reads the same.
 - color_code[DOT_EXTENSION+1] → var color_code: [DOT_EXTENSION + 1]?[*c]u8 = @splat(null); module-private.
 - ext → var ext: ?*c.struct_extensions = null; module-private.
 - linedraw → export var linedraw: [*c]const c.struct_linedraw = null; (matches info.zig's extern declaration at info.zig:18).
 - The large cstable[] charset array in initlinedraw: translate as a module-level const cstable = [_]c.struct_linedraw{ … }; with the same 17 entries. Each name pointer list becomes a module-level const ansi = [_:null][*c]const u8{ "ANSI" }; (null-sentinel) — or simplest: an
 array of [*c]const u8 with a trailing null, then @ptrCast its &[0] to [*c][*c]const u8 to match the C field type. Inspect the C struct layout via @cImport and match it (the field is const char **name).
 - S_IFDOOR is only defined on Solaris/illumos. Guard with if (@hasDecl(c, "S_IFDOOR")) or a comptime branch keyed off builtin.os.tag, mirroring how file.zig:26–32 handles stdin/__stdinp platform differences.

 Comments to preserve verbatim

 Port as Zig // or /* */ comments (match the style already used in the ported files — most carry the C comments over as //).

 - Top GPL block (color.c:1–17).
 - "Hacked in DIR_COLORS support for linux." block (color.c:20–38).
 - Commented-out vgacolor[] / colortable[] block (color.c:60–69) — keep as a block comment; it documents historical intent.
 - "You must free the pointer that is allocated by split()…" (color.c:74–77).
 - "/* Probably can't happen */" (color.c:110).
 - "/* Keep this one last, sets the size of the color_code array: */" (color.c:45).
 - "/* Should never actually be used */" (color.c:173).
 - "Make sure at least reset (not normal) is defined…" (color.c:186–189).
 - "It's probably safe to assume short-circuit evaluation, but we'll do it this way:" (color.c:251).
 - "/* not a directory, link, special device, etc, so check for extension match */" (color.c:285).
 - "/* colorize just normal files too */" (color.c:296).
 - "Charsets provided by Kyosuke Tokoro…" credit (color.c:302–304).
 - "Assume if they need ansilines, then they're probably stuck with a vt100:" (color.c:479).
 - Add a file-level //! Color / charset support ported from color.c. module doc (matches html.zig:1 and file.zig:1).

 Files to modify

 - Create src/color.zig — ~500 lines, 1:1 port of color.c.
 - Delete color.c.
 - Edit build.zig:
   - Remove "color.c" from sources (build.zig:19).
   - Add addZigObject(b, exe, target, optimize, "color", .{}); to the addZigObject block (build.zig:49–59). Order: any position is linker-fine; placing it alphabetically (between list and unix, or after filter) matches the loose convention.
 - No edit to tree.h — the prototypes and struct defs stay; they describe the ABI both sides agree on.
 - No edit to src/unix.zig or src/info.zig — their extern declarations resolve to the new Zig exports transparently.
 - No edit to src/main.zig — its test { _ = … } block lists modules whose tests run under zig build test; only add color there if I add test { … } blocks inside color.zig. Initial port will skip Zig-level unit tests (consistent with html.zig / json.zig / file.zig, which are
 also not wired in — per the comment at main.zig:11–14, behavioral coverage lives in scripts/interop.py).

 Verification

 Run end-to-end, matching what CI (.github/workflows/main.yaml) runs:

 1. Format: zig fmt --check . — must be clean.
 2. Unit tests: zig build test --summary all — must pass (no new tests added, but the build must still compose).
 3. Native build: zig build — links with the new Zig object replacing color.c.
 4. Matrix cross-compile: ./matrix-build.sh — covers x86_64/aarch64 for linux/macos/freebsd at -Doptimize=ReleaseFast. The S_IFDOOR guard and any platform-specific header behavior shakes out here.
 5. Interop test: install reference tree 2.3.2, then zig build && ./scripts/interop.py tree ./zig-out/bin/bo. This exercises color() / endcolor() (through -l, normal listings), fancy() (through usage/version text), getcharset() + initlinedraw() (through the default and explicit
  --charset paths), and parse_dir_colors() (when LS_COLORS / TREE_CHARSET are set). All 55+ cases in CASES, EDGE_CASES, FILE_CASES must pass.
 6. Manual sanity: LS_COLORS="di=01;34:ex=01;32:*.zig=01;33" ./zig-out/bin/bo src/ to eyeball ANSI output; ./zig-out/bin/bo --charset=UTF-8 . and ./zig-out/bin/bo --charset=ANSI . to exercise initlinedraw; ./zig-out/bin/bo --help to exercise fancy() markup.

 If any step fails, the most likely culprits are (a) cstable[] layout mismatch — verify c.struct_linedraw field order via zig build-obj error output, and (b) S_IFDOOR visibility on Solaris — guard with @hasDecl.

 Critical reference files

 - color.c (491 lines) — the source of truth for the port.
 - tree.h:109–122 — struct extensions, struct linedraw.
 - tree.h:168–174 — the six prototypes the port must match.
 - src/html.zig — the closest stylistic template (extern vars, export fns, @cImport, preserved comments).
 - src/file.zig:20–42 — template for platform-guarded externs and "mirrors C's static" pattern.
 - src/info.zig:18, 194–201 — consumer of the exported linedraw symbol; format must match.
 - build.zig:17–62 — where color.c is removed and color.zig wired in.
 - scripts/interop.py — the end-to-end gate.
 - .github/workflows/main.yaml:24–45 — the exact command sequence CI runs.