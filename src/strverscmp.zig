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
//! - Original C implementation: https://chromium.googlesource.com/native_client/nacl-gcc/+/455063d/libiberty/strverscmp.c

const std = @import("std");
const testing = std.testing;

// States for the version comparison state machine
const S_N: u8 = 0x0; // Normal: comparing non-digit characters
const S_I: u8 = 0x4; // Integral: comparing integral numeric parts
const S_F: u8 = 0x8; // Fractional: comparing fractional numeric parts (start with 0)
const S_Z: u8 = 0xC; // Zeroes: comparing fractional parts with only leading zeroes

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

// Result types for comparison
const CMP: i8 = 2; // Return character difference
const LEN: i8 = 3; // Compare by length of numeric sequences

// Result types lookup table
// Indexed by: (state << 2) | c2_symbol_type
// Returns: CMP (2), LEN (3), or direct result (-1, 0, +1)
// For each state (S_N, S_I, S_F, S_Z), there are 16 combinations of (c1_type, c2_type)
const result_types = [_]i8{
    // S_N
    CMP, CMP, CMP, CMP, CMP, LEN, CMP, CMP,
    CMP, CMP, CMP, CMP, CMP, CMP, CMP, CMP,
    // S_I
    CMP, -1,  -1,  CMP, 1,   LEN, LEN, CMP,
    1,   LEN, LEN, CMP, CMP, CMP, CMP, CMP,
    // S_F
    CMP, CMP, CMP, CMP, CMP, LEN, CMP, CMP,
    CMP, CMP, CMP, CMP, CMP, CMP, CMP, CMP,
    // S_Z
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
pub fn strverscmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int {
    // Identical pointers
    if (s1 == s2) return 0;

    var p1: [*:0]const u8 = s1;
    var p2: [*:0]const u8 = s2;

    var c1 = p1[0];
    var c2 = p2[0];
    var diff: i32 = @as(i32, c1) - @as(i32, c2);

    // Make state based on first character
    var state: u8 = S_N | getSymbolType(c1);

    p1 += 1;
    p2 += 1;

    // Continue while characters are equal and not at end
    while (diff == 0 and c1 != 0) {
        // Transition to next state
        // state is the combined value (state_bits | symbol_type)
        state = next_state[state];

        // Read next characters
        c1 = p1[0];
        c2 = p2[0];
        diff = @as(i32, c1) - @as(i32, c2);

        // Update state with c1
        state |= getSymbolType(c1);

        p1 += 1;
        p2 += 1;
    }

    // Determine result based on final state and c2 type
    const c2_type = getSymbolType(c2);
    const index = (state << 2) | c2_type;
    const result = result_types[index];

    if (result == CMP) { // return character difference
        return diff;
    } else if (result == LEN) { // compare by length of numeric sequences
        while (std.ascii.isDigit(p1[0])) {
            if (!std.ascii.isDigit(p2[0])) return 1;
            p1 += 1;
            p2 += 1;
        }
        return if (std.ascii.isDigit(p2[0])) -1 else @intCast(diff);
    }
    return result;
}

test "identical strings" {
    try testing.expect(strverscmp("test", "test") == 0);
    try testing.expect(strverscmp("", "") == 0);
    try testing.expect(strverscmp("123", "123") == 0);
    try testing.expect(strverscmp("no digit", "no digit") == 0);
    try testing.expect(strverscmp("a", "a") == 0);
}

test "no digits behaves like strcmp" {
    try testing.expect(strverscmp("abc", "abd") < 0);
    try testing.expect(strverscmp("abd", "abc") > 0);
}

test "numeric comparison" {
    try testing.expect(strverscmp("item#99", "item#100") < 0);
    try testing.expect(strverscmp("file99.txt", "file100.txt") < 0);
    try testing.expect(strverscmp("9", "10") < 0);
    try testing.expect(strverscmp("99", "100") < 0);
}

test "fractional vs integral" {
    try testing.expect(strverscmp("alpha1", "alpha001") > 0);
    try testing.expect(strverscmp("file1", "file01") > 0);
}

test "fractional parts" {
    try testing.expect(strverscmp("part1_f012", "part1_f01") > 0);
    try testing.expect(strverscmp("0.123", "0.12") > 0);
}

test "leading zeroes only" {
    try testing.expect(strverscmp("foo.009", "foo.0") < 0);
    try testing.expect(strverscmp("foo.0009", "foo.009") < 0);
}

test "empty strings" {
    try testing.expect(strverscmp("a", "") > 0);
    try testing.expect(strverscmp("", "a") < 0);
}

test "one character" {
    try testing.expect(strverscmp("a", "b") < 0);
    try testing.expect(strverscmp("b", "a") > 0);
}

test "real-world filenames" {
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

test "pointer equality fast path" {
    const s = "test";
    try testing.expect(strverscmp(s, s) == 0);
}

test "pure leading zeros (S_Z state)" {
    try testing.expect(strverscmp("foo.0", "foo.00") > 0);
    try testing.expect(strverscmp("foo.000", "foo.0") < 0);
    try testing.expect(strverscmp("a0", "a00") > 0);
    try testing.expect(strverscmp("a00", "a0") < 0);
    try testing.expect(strverscmp("test.0000", "test.000") < 0);
}

test "numbers at string start" {
    try testing.expect(strverscmp("123abc", "124abc") < 0);
    try testing.expect(strverscmp("99start", "100start") < 0);
    try testing.expect(strverscmp("0123", "0124") < 0);
    try testing.expect(strverscmp("1", "2") < 0);
    try testing.expect(strverscmp("9xyz", "10xyz") < 0);
}

test "explicit length difference (LEN case)" {
    try testing.expect(strverscmp("num123", "num1234") < 0);
    try testing.expect(strverscmp("num1234", "num123") > 0);
    try testing.expect(strverscmp("123", "1234") < 0);
    try testing.expect(strverscmp("1234", "123") > 0);
    try testing.expect(strverscmp("x99999", "x999999") < 0);
}

test "pure fractional numbers" {
    try testing.expect(strverscmp("01", "02") < 0);
    try testing.expect(strverscmp("001", "002") < 0);
    try testing.expect(strverscmp("0", "00") > 0); // S_Z: shorter wins
    try testing.expect(strverscmp("00", "0") < 0); // S_Z: longer loses
    try testing.expect(strverscmp("012", "013") < 0);
}

test "state transition boundaries" {
    try testing.expect(strverscmp("a1b0c", "a1b0d") < 0);
    try testing.expect(strverscmp("x1y01z", "x1y01z") == 0);
    try testing.expect(strverscmp("m9n08p", "m9n08q") < 0);
    try testing.expect(strverscmp("a1b2c3", "a1b2c3") == 0);
    try testing.expect(strverscmp("a1b2c3", "a1b2c4") < 0);
}

test "zero vs non-zero digit at transition" {
    try testing.expect(strverscmp("test1x", "test01x") > 0);
    try testing.expect(strverscmp("test01x", "test1x") < 0);
    try testing.expect(strverscmp("a0b", "a00b") > 0);
    try testing.expect(strverscmp("prefix1", "prefix01") > 0);
}

test "very long numbers" {
    try testing.expect(strverscmp("12345678901234567890", "12345678901234567891") < 0);
    try testing.expect(strverscmp("999999999", "1000000000") < 0);
    try testing.expect(strverscmp("123456789012345", "123456789012345") == 0);
    try testing.expect(strverscmp("99999999999999999", "100000000000000000") < 0);
}

test "fractional with different zero prefixes" {
    try testing.expect(strverscmp("x001", "x01") < 0);
    try testing.expect(strverscmp("x0001", "x001") < 0);
    try testing.expect(strverscmp("x01", "x001") > 0);
    try testing.expect(strverscmp("ver0012", "ver012") < 0);
}

test "single digit edge cases" {
    try testing.expect(strverscmp("0", "1") < 0);
    try testing.expect(strverscmp("9", "0") > 0);
    try testing.expect(strverscmp("0", "0") == 0);
    try testing.expect(strverscmp("1", "9") < 0);
    try testing.expect(strverscmp("5", "5") == 0);
}

test "mixed integral and fractional sequences" {
    try testing.expect(strverscmp("1.01", "1.1") < 0);
    try testing.expect(strverscmp("10.001", "10.01") < 0);
    try testing.expect(strverscmp("01a2b", "01a10b") < 0);
}

test "numbers at string end" {
    try testing.expect(strverscmp("test99", "test100") < 0);
    try testing.expect(strverscmp("end1", "end2") < 0);
    try testing.expect(strverscmp("suffix001", "suffix1") < 0);
}

test "repeated zero patterns" {
    try testing.expect(strverscmp("a00b", "a0b") < 0);
    try testing.expect(strverscmp("0a0b", "0a00b") > 0);
    try testing.expect(strverscmp("x000y", "x0000y") > 0);
}
