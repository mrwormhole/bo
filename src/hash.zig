//! UID/GID name caches and inode deduplication table.

const std = @import("std");
const testing = std.testing;

const Uid = std.c.uid_t;
const Gid = std.c.gid_t;
const Ino = std.posix.ino_t;
const Dev = std.posix.dev_t;

const InodeKey = struct { inode: Ino, dev: Dev };

var utable: std.AutoHashMapUnmanaged(Uid, [:0]const u8) = .{};
var gtable: std.AutoHashMapUnmanaged(Gid, [:0]const u8) = .{};
var itable: std.AutoHashMapUnmanaged(InodeKey, void) = .{};
// strhash is Linux-only (#ifdef __linux__ in tree.h)
var strtable: std.StringHashMapUnmanaged([:0]const u8) = .{};

// Process is short-lived so we intentionally leak, same as the C original.
const allocator = std.heap.page_allocator;

// POSIX-only
export fn uidtoname(uid: Uid) [*:0]const u8 {
    if (utable.get(uid)) |name| return name.ptr;

    const pw = std.c.getpwuid(uid);
    const name: [:0]const u8 = if (pw) |p| if (p.name) |n|
        allocator.dupeZ(u8, std.mem.span(n)) catch unreachable
    else
        std.fmt.allocPrintSentinel(allocator, "{d}", .{uid}, 0) catch unreachable else std.fmt.allocPrintSentinel(allocator, "{d}", .{uid}, 0) catch unreachable;

    utable.put(allocator, uid, name) catch unreachable;
    return name.ptr;
}

// POSIX-only
export fn gidtoname(gid: Gid) [*:0]const u8 {
    if (gtable.get(gid)) |name| return name.ptr;

    const gr = std.c.getgrgid(gid);
    const name: [:0]const u8 = if (gr) |g| if (g.name) |n|
        allocator.dupeZ(u8, std.mem.span(n)) catch unreachable
    else
        std.fmt.allocPrintSentinel(allocator, "{d}", .{gid}, 0) catch unreachable else std.fmt.allocPrintSentinel(allocator, "{d}", .{gid}, 0) catch unreachable;

    gtable.put(allocator, gid, name) catch unreachable;
    return name.ptr;
}

// POSIX-only
export fn saveino(inode: Ino, device: Dev) void {
    itable.put(allocator, .{ .inode = inode, .dev = device }, {}) catch unreachable;
}

// POSIX-only
export fn findino(inode: Ino, device: Dev) bool {
    return itable.contains(.{ .inode = inode, .dev = device });
}

// Linux-only, strhash interns strings to avoid duplicate allocations (guarded by #ifdef __linux__ in tree.h).
export fn strhash(str: [*:0]const u8) [*:0]const u8 {
    const s = std.mem.sliceTo(str, 0);
    if (strtable.get(s)) |interned| return interned.ptr;
    const copy = allocator.dupeZ(u8, s) catch unreachable;
    strtable.put(allocator, copy, copy) catch unreachable;
    return copy.ptr;
}

test "uidtoname returns same pointer on cache hit" {
    const uid: Uid = @intCast(std.os.linux.getuid());
    const first = uidtoname(uid);
    const second = uidtoname(uid);
    try testing.expect(first == second);
    try testing.expect(std.mem.len(first) > 0);
}

test "uidtoname resolves current uid to a non-numeric name" {
    const uid: Uid = @intCast(std.os.linux.getuid());
    const name = std.mem.span(uidtoname(uid));
    // A real passwd entry exists for the current user; the result must not be
    // a plain decimal number (i.e. the getpwuid branch was taken).
    for (name) |c| {
        if (std.ascii.isDigit(c)) continue;
        return; // found a non-digit character — it's a real username
    }
    return error.TestUnexpectedResult;
}

test "gidtoname returns same pointer on cache hit" {
    const gid: Gid = @intCast(std.os.linux.getgid());
    const first = gidtoname(gid);
    const second = gidtoname(gid);
    try testing.expect(first == second);
    try testing.expect(std.mem.len(first) > 0);
}

test "gidtoname resolves current gid to a non-numeric name" {
    const gid: Gid = @intCast(std.os.linux.getgid());
    const name = std.mem.span(gidtoname(gid));
    for (name) |c| {
        if (std.ascii.isDigit(c)) continue;
        return;
    }
    return error.TestUnexpectedResult;
}

test "findino returns false before saveino, true after" {
    try testing.expect(!findino(999, 1));
    saveino(999, 1);
    try testing.expect(findino(999, 1));
}

test "saveino is idempotent" {
    saveino(42, 7);
    saveino(42, 7);
    try testing.expect(findino(42, 7));
}

test "findino distinguishes different (inode, dev) pairs" {
    saveino(1, 1);
    try testing.expect(findino(1, 1));
    try testing.expect(!findino(1, 2));
    try testing.expect(!findino(2, 1));
}

test "strhash returns same pointer for identical strings" {
    const a = strhash("hello");
    const b = strhash("hello");
    try testing.expect(a == b);
}

test "strhash returns different pointers for different strings" {
    const a = strhash("foo");
    const b = strhash("bar");
    try testing.expect(a != b);
}

test "strhash content matches input" {
    const result = strhash("hello");
    try testing.expectEqualStrings("hello", std.mem.span(result));
}

test "uidtoname unknown uid returns numeric string" {
    // uid 0xFFFFFF is extremely unlikely to exist on any test system
    const result = uidtoname(0xFFFFFF);
    try testing.expectEqualStrings("16777215", std.mem.span(result));
}

test "gidtoname unknown gid returns numeric string" {
    const result = gidtoname(0xFFFFFF);
    try testing.expectEqualStrings("16777215", std.mem.span(result));
}

test "uidtoname returns different pointers for different uids" {
    const a = uidtoname(0xFFFFFD);
    const b = uidtoname(0xFFFFFE);
    try testing.expect(a != b);
}

test "gidtoname returns different pointers for different gids" {
    const a = gidtoname(0xFFFFFD);
    const b = gidtoname(0xFFFFFE);
    try testing.expect(a != b);
}
