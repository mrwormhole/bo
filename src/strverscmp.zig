//! strverscmp - Version string comparison
//!
//! This is a Zig re-implementation of the GNU libiberty strverscmp function.
//! It compares strings containing version numbers naturally, so that:
//!   "file99" < "file100" (not "file99" > "file100" like strcmp)
//!
//! Algorithm:
//! - Compares strings character by character normally
//! - When encountering digits, enters special numeric comparison mode
//! - Handles integral parts (e.g., "123") and fractional parts (e.g., "0123")
//! - Fractional parts beginning with '0' have special comparison rules
//!
//! References:
//! - Original C implementation: libiberty/strverscmp.c
//! - GNU C Library documentation

const std = @import("std");
const testing = std.testing;

// States for the version comparison state machine
const S_N: u8 = 0x0; // Normal: comparing non-digit characters
const S_I: u8 = 0x4; // Integral: comparing integral numeric parts
const S_F: u8 = 0x8; // Fractional: comparing fractional numeric parts (start with 0)
const S_Z: u8 = 0xC; // Zeroes: comparing fractional parts with only leading zeroes

// Result types for comparison
const CMP: i8 = 2; // Return character difference
const LEN: i8 = 3; // Compare by length of numeric sequences

// State transition table (1D array indexed by combined state|symbol value)
// Symbol encoding: (c == '0') + (isdigit(c) != 0)
//   non-digit → 0 (other)
//   digit 1-9 → 1 (digit)
//   '0' → 2 (zero)
//   padding → 3 (unused)
// Combined index: state_bits (0x0, 0x4, 0x8, 0xC) | symbol_type (0, 1, 2, 3)
const next_state = [16]u8{
    // state x    d    0    -
    // S_N (0x0)
    S_N, S_I, S_Z, S_N,
    // S_I (0x4)
    S_N, S_I, S_I, S_I,
    // S_F (0x8)
    S_N, S_F, S_F, S_F,
    // S_Z (0xC)
    S_N, S_F, S_Z, S_Z,
};

// Result type lookup table
// Indexed by: (state << 2) | c2_symbol_type
// Returns: CMP (2), LEN (3), or direct result (-1, 0, +1)
// For each state (S_N, S_I, S_F, S_Z), there are 16 combinations of (c1_type, c2_type)
const result_type = [_]i8{
    // S_N (state bits 00)
    CMP, CMP, CMP, CMP, CMP, LEN, CMP, CMP,
    CMP, CMP, CMP, CMP, CMP, CMP, CMP, CMP,
    // S_I (state bits 01)
    CMP, -1,  -1,  CMP, 1,   LEN, LEN, CMP,
    1,   LEN, LEN, CMP, CMP, CMP, CMP, CMP,
    // S_F (state bits 10)
    CMP, CMP, CMP, CMP, CMP, LEN, CMP, CMP,
    CMP, CMP, CMP, CMP, CMP, CMP, CMP, CMP,
    // S_Z (state bits 11)
    CMP, 1,   1,   CMP, -1,  CMP, CMP, CMP,
    -1,  CMP, CMP, CMP,
};

/// Get symbol type for a character
/// Returns: 0 (other), 1 (digit 1-9), 2 (zero)
/// Matches C: (c == '0') + (isdigit(c) != 0)
inline fn getSymbolType(c: u8) u8 {
    const is_zero: u8 = if (c == '0') 1 else 0;
    const is_digit: u8 = if (std.ascii.isDigit(c)) 1 else 0;
    return is_zero + is_digit;
}

/// Compare two version strings
///
/// Returns:
///   < 0 if s1 < s2
///   = 0 if s1 == s2
///   > 0 if s1 > s2
///
/// Examples:
///   strverscmp("no digit", "no digit") == 0
///   strverscmp("item#99", "item#100") < 0
///   strverscmp("alpha1", "alpha001") > 0
///
/// Exported with C calling convention for interop with C code
export fn strverscmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int {
    // Fast path: identical pointers
    if (s1 == s2) return 0;

    var p1: [*:0]const u8 = s1;
    var p2: [*:0]const u8 = s2;

    var c1 = p1[0];
    var c2 = p2[0];
    p1 += 1;
    p2 += 1;

    // Initialize state based on first character
    // state = S_N | ((c1 == '0') + (isdigit(c1) != 0))
    var state: u8 = S_N | getSymbolType(c1);

    // Main comparison loop: continue while characters are equal and not at end
    var diff: i32 = @as(i32, c1) - @as(i32, c2);
    while (diff == 0 and c1 != 0) {
        // Transition to next state
        // In C: state = next_state[state]
        // state is the combined value (state_bits | symbol_type)
        state = next_state[state];

        // Read next characters
        c1 = p1[0];
        c2 = p2[0];
        p1 += 1;
        p2 += 1;

        // Update state with c1 type for next iteration
        state |= getSymbolType(c1);

        diff = @as(i32, c1) - @as(i32, c2);
    }

    // Determine result based on final state and c2 type
    // In C: state = result_type[state << 2 | (((c2 == '0') + (isdigit (c2) != 0)))]
    const c2_type = getSymbolType(c2);
    const result_idx = (state << 2) | c2_type;
    const result = result_type[result_idx];

    // Process result
    if (result == CMP) {
        // CMP: return character difference
        return @intCast(diff);
    } else if (result == LEN) {
        // LEN: compare by length of numeric sequences
        while (std.ascii.isDigit(p1[0])) {
            if (!std.ascii.isDigit(p2[0])) return 1;
            p1 += 1;
            p2 += 1;
        }
        return if (std.ascii.isDigit(p2[0])) -1 else @intCast(diff);
    } else {
        // Direct result: -1, 0, or +1
        return result;
    }
}

test "identical strings" {
    try testing.expectEqual(@as(c_int, 0), strverscmp("test", "test"));
    try testing.expectEqual(@as(c_int, 0), strverscmp("", ""));
    try testing.expectEqual(@as(c_int, 0), strverscmp("123", "123"));
}

test "no digits behaves like strcmp" {
    try testing.expectEqual(@as(c_int, 0), strverscmp("no digit", "no digit"));
    try testing.expect(strverscmp("abc", "abd") < 0);
    try testing.expect(strverscmp("abd", "abc") > 0);
}

test "numeric comparison" {
    // 99 < 100
    try testing.expect(strverscmp("item#99", "item#100") < 0);
    try testing.expect(strverscmp("file99.txt", "file100.txt") < 0);
    try testing.expect(strverscmp("9", "10") < 0);
    try testing.expect(strverscmp("99", "100") < 0);
}

test "fractional vs integral" {
    // Integral > fractional (leading zero)
    try testing.expect(strverscmp("alpha1", "alpha001") > 0);
    try testing.expect(strverscmp("file1", "file01") > 0);
}

test "fractional parts" {
    // Two fractional parts
    try testing.expect(strverscmp("part1_f012", "part1_f01") > 0);
    try testing.expect(strverscmp("0.123", "0.12") > 0);
}

test "leading zeroes only" {
    // Leading zeroes only: longer is less
    try testing.expect(strverscmp("foo.009", "foo.0") < 0);
    try testing.expect(strverscmp("foo.0009", "foo.009") < 0);
}

test "empty strings" {
    try testing.expectEqual(@as(c_int, 0), strverscmp("", ""));
    try testing.expect(strverscmp("a", "") > 0);
    try testing.expect(strverscmp("", "a") < 0);
}

test "one character" {
    try testing.expectEqual(@as(c_int, 0), strverscmp("a", "a"));
    try testing.expect(strverscmp("a", "b") < 0);
    try testing.expect(strverscmp("b", "a") > 0);
}

test "real-world filenames" {
    // Common version sorting scenarios
    try testing.expect(strverscmp("file1.txt", "file2.txt") < 0);
    try testing.expect(strverscmp("file9.txt", "file10.txt") < 0);
    try testing.expect(strverscmp("file10.txt", "file9.txt") > 0);
    try testing.expect(strverscmp("v1.2.3", "v1.2.10") < 0);
    try testing.expect(strverscmp("v2.0.0", "v1.9.9") > 0);
    try testing.expect(strverscmp("v1.0.0", "v1.0.0") == 0);
}

test "complex version numbers" {
    try testing.expect(strverscmp("1.001.9", "1.002.0") < 0);
    // Fractional parts with non-zero digits compare character-by-character
    // "010" vs "09": '0' == '0', then '1' < '9', so "010" < "09"
    try testing.expect(strverscmp("1.010", "1.09") < 0);
    try testing.expect(strverscmp("1.09", "1.010") > 0);
}

test "mixed alphanumeric" {
    try testing.expect(strverscmp("a1b2c3", "a1b2c10") < 0);
    try testing.expect(strverscmp("test-1.2.3", "test-1.2.10") < 0);
    try testing.expect(strverscmp("prefix99suffix", "prefix100suffix") < 0);
}
