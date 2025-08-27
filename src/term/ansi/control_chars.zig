/// Control character constants based on Charmbracelet X and ISO standards
/// Provides centralized definitions for C0, C1, and ASCII control characters
/// used throughout terminal applications.

// === C0 CONTROL CHARACTERS (0x00-0x1F) ===
// Defined in ISO 646 (ASCII)
// See: https://en.wikipedia.org/wiki/C0_and_C1_control_codes

/// Null character (Caret: ^@, Char: \0)
pub const NUL = 0x00;

/// Start of Heading (Caret: ^A)
pub const SOH = 0x01;

/// Start of Text (Caret: ^B)
pub const STX = 0x02;

/// End of Text (Caret: ^C)
pub const ETX = 0x03;

/// End of Transmission (Caret: ^D)
pub const EOT = 0x04;

/// Enquiry (Caret: ^E)
pub const ENQ = 0x05;

/// Acknowledge (Caret: ^F)
pub const ACK = 0x06;

/// Bell (Caret: ^G, Char: \a)
pub const BEL = 0x07;

/// Backspace (Caret: ^H, Char: \b)
pub const BS = 0x08;

/// Horizontal Tab (Caret: ^I, Char: \t)
pub const HT = 0x09;

/// Line Feed (Caret: ^J, Char: \n)
pub const LF = 0x0A;

/// Vertical Tab (Caret: ^K, Char: \v)
pub const VT = 0x0B;

/// Form Feed (Caret: ^L, Char: \f)
pub const FF = 0x0C;

/// Carriage Return (Caret: ^M, Char: \r)
pub const CR = 0x0D;

/// Shift Out (Caret: ^N)
pub const SO = 0x0E;

/// Shift In (Caret: ^O)
pub const SI = 0x0F;

/// Data Link Escape (Caret: ^P)
pub const DLE = 0x10;

/// Device Control 1 (Caret: ^Q)
pub const DC1 = 0x11;

/// Device Control 2 (Caret: ^R)
pub const DC2 = 0x12;

/// Device Control 3 (Caret: ^S)
pub const DC3 = 0x13;

/// Device Control 4 (Caret: ^T)
pub const DC4 = 0x14;

/// Negative Acknowledge (Caret: ^U)
pub const NAK = 0x15;

/// Synchronous Idle (Caret: ^V)
pub const SYN = 0x16;

/// End of Transmission Block (Caret: ^W)
pub const ETB = 0x17;

/// Cancel (Caret: ^X)
pub const CAN = 0x18;

/// End of Medium (Caret: ^Y)
pub const EM = 0x19;

/// Substitute (Caret: ^Z)
pub const SUB = 0x1A;

/// Escape (Caret: ^[, Char: \e)
pub const ESC = 0x1B;

/// File Separator (Caret: ^\)
pub const FS = 0x1C;

/// Group Separator (Caret: ^])
pub const GS = 0x1D;

/// Record Separator (Caret: ^^)
pub const RS = 0x1E;

/// Unit Separator (Caret: ^_)
pub const US = 0x1F;

// === LOCKING SHIFT ALIASES ===

/// Locking Shift 0 (alias for SI)
pub const LS0 = SI;

/// Locking Shift 1 (alias for SO)
pub const LS1 = SO;

// === ASCII PRINTABLE BOUNDARIES ===

/// Space character
pub const SP = 0x20;

/// Delete character (Caret: ^?, Char: \x7f)
pub const DEL = 0x7F;

// === C1 CONTROL CHARACTERS (0x80-0x9F) ===
// Defined in ISO 6429 (ECMA-48)
// See: https://en.wikipedia.org/wiki/C0_and_C1_control_codes

/// Padding Character
pub const PAD = 0x80;

/// High Octet Preset
pub const HOP = 0x81;

/// Break Permitted Here
pub const BPH = 0x82;

/// No Break Here
pub const NBH = 0x83;

/// Index
pub const IND = 0x84;

/// Next Line
pub const NEL = 0x85;

/// Start of Selected Area
pub const SSA = 0x86;

/// End of Selected Area
pub const ESA = 0x87;

/// Horizontal Tab Set
pub const HTS = 0x88;

/// Horizontal Tab with Justification
pub const HTJ = 0x89;

/// Vertical Tab Set
pub const VTS = 0x8A;

/// Partial Line Forward
pub const PLD = 0x8B;

/// Partial Line Backward
pub const PLU = 0x8C;

/// Reverse Index
pub const RI = 0x8D;

/// Single Shift 2
pub const SS2 = 0x8E;

/// Single Shift 3
pub const SS3 = 0x8F;

/// Device Control String
pub const DCS = 0x90;

/// Private Use 1
pub const PU1 = 0x91;

/// Private Use 2
pub const PU2 = 0x92;

/// Set Transmit State
pub const STS = 0x93;

/// Cancel Character
pub const CCH = 0x94;

/// Message Waiting
pub const MW = 0x95;

/// Start of Guarded Area
pub const SPA = 0x96;

/// End of Guarded Area
pub const EPA = 0x97;

/// Start of String
pub const SOS = 0x98;

/// Single Graphic Character Introducer
pub const SGCI = 0x99;

/// Single Character Introducer
pub const SCI = 0x9A;

/// Control Sequence Introducer
pub const CSI = 0x9B;

/// String Terminator
pub const ST = 0x9C;

/// Operating System Command
pub const OSC = 0x9D;

/// Privacy Message
pub const PM = 0x9E;

/// Application Program Command
pub const APC = 0x9F;

// === COMMON SEQUENCE CONSTANTS ===

/// ANSI Escape Sequence Introducer (ESC [)
pub const CSI_SEQ = "\x1b[";

/// Operating System Command Introducer (ESC ])
pub const OSC_SEQ = "\x1b]";

/// Device Control String Introducer (ESC P)
pub const DCS_SEQ = "\x1bP";

/// Application Program Command Introducer (ESC _)
pub const APC_SEQ = "\x1b_";

/// String Terminator sequence (ESC \)
pub const ST_SEQ = "\x1b\\";

/// Bell as string
pub const BEL_SEQ = "\x07";

// === UTILITY FUNCTIONS ===

/// Check if a character is a C0 control character
pub fn isC0Control(ch: u8) bool {
    return ch <= 0x1F;
}

/// Check if a character is a C1 control character
pub fn isC1Control(ch: u8) bool {
    return ch >= 0x80 and ch <= 0x9F;
}

/// Check if a character is any control character (C0 or C1)
pub fn isControl(ch: u8) bool {
    return isC0Control(ch) or isC1Control(ch);
}

/// Check if a character is printable ASCII (0x20-0x7E)
pub fn isPrintableAscii(ch: u8) bool {
    return ch >= SP and ch <= 0x7E;
}

/// Check if a character is whitespace (space, tab, newline, etc.)
pub fn isWhitespace(ch: u8) bool {
    return switch (ch) {
        SP, HT, LF, VT, FF, CR => true,
        else => false,
    };
}

/// Get a human-readable name for a control character
pub fn controlCharName(ch: u8) ?[]const u8 {
    return switch (ch) {
        NUL => "NUL",
        SOH => "SOH",
        STX => "STX",
        ETX => "ETX",
        EOT => "EOT",
        ENQ => "ENQ",
        ACK => "ACK",
        BEL => "BEL",
        BS => "BS",
        HT => "HT",
        LF => "LF",
        VT => "VT",
        FF => "FF",
        CR => "CR",
        SO => "SO",
        SI => "SI",
        DLE => "DLE",
        DC1 => "DC1",
        DC2 => "DC2",
        DC3 => "DC3",
        DC4 => "DC4",
        NAK => "NAK",
        SYN => "SYN",
        ETB => "ETB",
        CAN => "CAN",
        EM => "EM",
        SUB => "SUB",
        ESC => "ESC",
        FS => "FS",
        GS => "GS",
        RS => "RS",
        US => "US",
        SP => "SP",
        DEL => "DEL",
        PAD => "PAD",
        HOP => "HOP",
        BPH => "BPH",
        NBH => "NBH",
        IND => "IND",
        NEL => "NEL",
        SSA => "SSA",
        ESA => "ESA",
        HTS => "HTS",
        HTJ => "HTJ",
        VTS => "VTS",
        PLD => "PLD",
        PLU => "PLU",
        RI => "RI",
        SS2 => "SS2",
        SS3 => "SS3",
        DCS => "DCS",
        PU1 => "PU1",
        PU2 => "PU2",
        STS => "STS",
        CCH => "CCH",
        MW => "MW",
        SPA => "SPA",
        EPA => "EPA",
        SOS => "SOS",
        SGCI => "SGCI",
        SCI => "SCI",
        CSI => "CSI",
        ST => "ST",
        OSC => "OSC",
        PM => "PM",
        APC => "APC",
        else => null,
    };
}

/// Convert a control character to its caret notation (e.g., ^A for SOH)
pub fn toCaretNotation(ch: u8, buf: *[2]u8) ?[]const u8 {
    if (ch <= 0x1F) {
        buf[0] = '^';
        buf[1] = '@' + ch; // ^@ for NUL, ^A for SOH, etc.
        return buf[0..2];
    } else if (ch == DEL) {
        buf[0] = '^';
        buf[1] = '?';
        return buf[0..2];
    }
    return null;
}

// === TESTS ===

const std = @import("std");

test "control character identification" {
    const testing = std.testing;

    // Test C0 controls
    try testing.expect(isC0Control(NUL));
    try testing.expect(isC0Control(ESC));
    try testing.expect(isC0Control(US));
    try testing.expect(!isC0Control(SP));

    // Test C1 controls
    try testing.expect(isC1Control(PAD));
    try testing.expect(isC1Control(CSI));
    try testing.expect(isC1Control(APC));
    try testing.expect(!isC1Control(0x7F));

    // Test printable ASCII
    try testing.expect(isPrintableAscii('A'));
    try testing.expect(isPrintableAscii('~'));
    try testing.expect(!isPrintableAscii(CR));
    try testing.expect(!isPrintableAscii(DEL));

    // Test whitespace
    try testing.expect(isWhitespace(SP));
    try testing.expect(isWhitespace(HT));
    try testing.expect(isWhitespace(LF));
    try testing.expect(!isWhitespace('A'));
}

test "control character names" {
    const testing = std.testing;

    // Test known control characters
    try testing.expectEqualStrings("ESC", controlCharName(ESC).?);
    try testing.expectEqualStrings("BEL", controlCharName(BEL).?);
    try testing.expectEqualStrings("CSI", controlCharName(CSI).?);

    // Test unknown character
    try testing.expect(controlCharName('A') == null);
}

test "caret notation conversion" {
    const testing = std.testing;

    var buf: [2]u8 = undefined;

    // Test C0 controls
    try testing.expectEqualStrings("^@", toCaretNotation(NUL, &buf).?);
    try testing.expectEqualStrings("^A", toCaretNotation(SOH, &buf).?);
    try testing.expectEqualStrings("^[", toCaretNotation(ESC, &buf).?);
    try testing.expectEqualStrings("^?", toCaretNotation(DEL, &buf).?);

    // Test non-control character
    try testing.expect(toCaretNotation('A', &buf) == null);
}

test "sequence constants" {
    const testing = std.testing;

    // Test sequence constants are correct
    try testing.expectEqualStrings("\x1b[", CSI_SEQ);
    try testing.expectEqualStrings("\x1b]", OSC_SEQ);
    try testing.expectEqualStrings("\x1bP", DCS_SEQ);
    try testing.expectEqualStrings("\x1b_", APC_SEQ);
    try testing.expectEqualStrings("\x1b\\", ST_SEQ);
    try testing.expectEqualStrings("\x07", BEL_SEQ);
}

test "character value correctness" {
    const testing = std.testing;

    // Verify key control characters have correct values
    try testing.expect(NUL == 0x00);
    try testing.expect(BEL == 0x07);
    try testing.expect(HT == 0x09);
    try testing.expect(LF == 0x0A);
    try testing.expect(CR == 0x0D);
    try testing.expect(ESC == 0x1B);
    try testing.expect(SP == 0x20);
    try testing.expect(DEL == 0x7F);

    // C1 characters
    try testing.expect(CSI == 0x9B);
    try testing.expect(OSC == 0x9D);
    try testing.expect(ST == 0x9C);
}
