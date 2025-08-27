const std = @import("std");

/// Precise ANSI 256-color palette with exact RGB values from charmbracelet/x
/// This provides the exact color values used by xterm and compatible terminals
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .r = r, .g = g, .b = b };
    }
};

/// Complete ANSI 256-color palette with exact RGB values
/// Colors 0-15: Standard ANSI colors
/// Colors 16-231: 6×6×6 color cube
/// Colors 232-255: Grayscale ramp
pub const ANSI_256_PALETTE = [256]RGBColor{
    // Standard 16 ANSI colors (0-15)
    RGBColor.init(0x00, 0x00, 0x00), //   0 - Black
    RGBColor.init(0x80, 0x00, 0x00), //   1 - Maroon
    RGBColor.init(0x00, 0x80, 0x00), //   2 - Green
    RGBColor.init(0x80, 0x80, 0x00), //   3 - Olive
    RGBColor.init(0x00, 0x00, 0x80), //   4 - Navy
    RGBColor.init(0x80, 0x00, 0x80), //   5 - Purple
    RGBColor.init(0x00, 0x80, 0x80), //   6 - Teal
    RGBColor.init(0xC0, 0xC0, 0xC0), //   7 - Silver
    RGBColor.init(0x80, 0x80, 0x80), //   8 - Gray
    RGBColor.init(0xFF, 0x00, 0x00), //   9 - Red
    RGBColor.init(0x00, 0xFF, 0x00), //  10 - Lime
    RGBColor.init(0xFF, 0xFF, 0x00), //  11 - Yellow
    RGBColor.init(0x00, 0x00, 0xFF), //  12 - Blue
    RGBColor.init(0xFF, 0x00, 0xFF), //  13 - Fuchsia
    RGBColor.init(0x00, 0xFF, 0xFF), //  14 - Aqua
    RGBColor.init(0xFF, 0xFF, 0xFF), //  15 - White

    // 6×6×6 color cube (16-231)
    RGBColor.init(0x00, 0x00, 0x00), //  16
    RGBColor.init(0x00, 0x00, 0x5F), //  17
    RGBColor.init(0x00, 0x00, 0x87), //  18
    RGBColor.init(0x00, 0x00, 0xAF), //  19
    RGBColor.init(0x00, 0x00, 0xD7), //  20
    RGBColor.init(0x00, 0x00, 0xFF), //  21
    RGBColor.init(0x00, 0x5F, 0x00), //  22
    RGBColor.init(0x00, 0x5F, 0x5F), //  23
    RGBColor.init(0x00, 0x5F, 0x87), //  24
    RGBColor.init(0x00, 0x5F, 0xAF), //  25
    RGBColor.init(0x00, 0x5F, 0xD7), //  26
    RGBColor.init(0x00, 0x5F, 0xFF), //  27
    RGBColor.init(0x00, 0x87, 0x00), //  28
    RGBColor.init(0x00, 0x87, 0x5F), //  29
    RGBColor.init(0x00, 0x87, 0x87), //  30
    RGBColor.init(0x00, 0x87, 0xAF), //  31
    RGBColor.init(0x00, 0x87, 0xD7), //  32
    RGBColor.init(0x00, 0x87, 0xFF), //  33
    RGBColor.init(0x00, 0xAF, 0x00), //  34
    RGBColor.init(0x00, 0xAF, 0x5F), //  35
    RGBColor.init(0x00, 0xAF, 0x87), //  36
    RGBColor.init(0x00, 0xAF, 0xAF), //  37
    RGBColor.init(0x00, 0xAF, 0xD7), //  38
    RGBColor.init(0x00, 0xAF, 0xFF), //  39
    RGBColor.init(0x00, 0xD7, 0x00), //  40
    RGBColor.init(0x00, 0xD7, 0x5F), //  41
    RGBColor.init(0x00, 0xD7, 0x87), //  42
    RGBColor.init(0x00, 0xD7, 0xAF), //  43
    RGBColor.init(0x00, 0xD7, 0xD7), //  44
    RGBColor.init(0x00, 0xD7, 0xFF), //  45
    RGBColor.init(0x00, 0xFF, 0x00), //  46
    RGBColor.init(0x00, 0xFF, 0x5F), //  47
    RGBColor.init(0x00, 0xFF, 0x87), //  48
    RGBColor.init(0x00, 0xFF, 0xAF), //  49
    RGBColor.init(0x00, 0xFF, 0xD7), //  50
    RGBColor.init(0x00, 0xFF, 0xFF), //  51
    RGBColor.init(0x5F, 0x00, 0x00), //  52
    RGBColor.init(0x5F, 0x00, 0x5F), //  53
    RGBColor.init(0x5F, 0x00, 0x87), //  54
    RGBColor.init(0x5F, 0x00, 0xAF), //  55
    RGBColor.init(0x5F, 0x00, 0xD7), //  56
    RGBColor.init(0x5F, 0x00, 0xFF), //  57
    RGBColor.init(0x5F, 0x5F, 0x00), //  58
    RGBColor.init(0x5F, 0x5F, 0x5F), //  59
    RGBColor.init(0x5F, 0x5F, 0x87), //  60
    RGBColor.init(0x5F, 0x5F, 0xAF), //  61
    RGBColor.init(0x5F, 0x5F, 0xD7), //  62
    RGBColor.init(0x5F, 0x5F, 0xFF), //  63
    RGBColor.init(0x5F, 0x87, 0x00), //  64
    RGBColor.init(0x5F, 0x87, 0x5F), //  65
    RGBColor.init(0x5F, 0x87, 0x87), //  66
    RGBColor.init(0x5F, 0x87, 0xAF), //  67
    RGBColor.init(0x5F, 0x87, 0xD7), //  68
    RGBColor.init(0x5F, 0x87, 0xFF), //  69
    RGBColor.init(0x5F, 0xAF, 0x00), //  70
    RGBColor.init(0x5F, 0xAF, 0x5F), //  71
    RGBColor.init(0x5F, 0xAF, 0x87), //  72
    RGBColor.init(0x5F, 0xAF, 0xAF), //  73
    RGBColor.init(0x5F, 0xAF, 0xD7), //  74
    RGBColor.init(0x5F, 0xAF, 0xFF), //  75
    RGBColor.init(0x5F, 0xD7, 0x00), //  76
    RGBColor.init(0x5F, 0xD7, 0x5F), //  77
    RGBColor.init(0x5F, 0xD7, 0x87), //  78
    RGBColor.init(0x5F, 0xD7, 0xAF), //  79
    RGBColor.init(0x5F, 0xD7, 0xD7), //  80
    RGBColor.init(0x5F, 0xD7, 0xFF), //  81
    RGBColor.init(0x5F, 0xFF, 0x00), //  82
    RGBColor.init(0x5F, 0xFF, 0x5F), //  83
    RGBColor.init(0x5F, 0xFF, 0x87), //  84
    RGBColor.init(0x5F, 0xFF, 0xAF), //  85
    RGBColor.init(0x5F, 0xFF, 0xD7), //  86
    RGBColor.init(0x5F, 0xFF, 0xFF), //  87
    RGBColor.init(0x87, 0x00, 0x00), //  88
    RGBColor.init(0x87, 0x00, 0x5F), //  89
    RGBColor.init(0x87, 0x00, 0x87), //  90
    RGBColor.init(0x87, 0x00, 0xAF), //  91
    RGBColor.init(0x87, 0x00, 0xD7), //  92
    RGBColor.init(0x87, 0x00, 0xFF), //  93
    RGBColor.init(0x87, 0x5F, 0x00), //  94
    RGBColor.init(0x87, 0x5F, 0x5F), //  95
    RGBColor.init(0x87, 0x5F, 0x87), //  96
    RGBColor.init(0x87, 0x5F, 0xAF), //  97
    RGBColor.init(0x87, 0x5F, 0xD7), //  98
    RGBColor.init(0x87, 0x5F, 0xFF), //  99
    RGBColor.init(0x87, 0x87, 0x00), // 100
    RGBColor.init(0x87, 0x87, 0x5F), // 101
    RGBColor.init(0x87, 0x87, 0x87), // 102
    RGBColor.init(0x87, 0x87, 0xAF), // 103
    RGBColor.init(0x87, 0x87, 0xD7), // 104
    RGBColor.init(0x87, 0x87, 0xFF), // 105
    RGBColor.init(0x87, 0xAF, 0x00), // 106
    RGBColor.init(0x87, 0xAF, 0x5F), // 107
    RGBColor.init(0x87, 0xAF, 0x87), // 108
    RGBColor.init(0x87, 0xAF, 0xAF), // 109
    RGBColor.init(0x87, 0xAF, 0xD7), // 110
    RGBColor.init(0x87, 0xAF, 0xFF), // 111
    RGBColor.init(0x87, 0xD7, 0x00), // 112
    RGBColor.init(0x87, 0xD7, 0x5F), // 113
    RGBColor.init(0x87, 0xD7, 0x87), // 114
    RGBColor.init(0x87, 0xD7, 0xAF), // 115
    RGBColor.init(0x87, 0xD7, 0xD7), // 116
    RGBColor.init(0x87, 0xD7, 0xFF), // 117
    RGBColor.init(0x87, 0xFF, 0x00), // 118
    RGBColor.init(0x87, 0xFF, 0x5F), // 119
    RGBColor.init(0x87, 0xFF, 0x87), // 120
    RGBColor.init(0x87, 0xFF, 0xAF), // 121
    RGBColor.init(0x87, 0xFF, 0xD7), // 122
    RGBColor.init(0x87, 0xFF, 0xFF), // 123
    RGBColor.init(0xAF, 0x00, 0x00), // 124
    RGBColor.init(0xAF, 0x00, 0x5F), // 125
    RGBColor.init(0xAF, 0x00, 0x87), // 126
    RGBColor.init(0xAF, 0x00, 0xAF), // 127
    RGBColor.init(0xAF, 0x00, 0xD7), // 128
    RGBColor.init(0xAF, 0x00, 0xFF), // 129
    RGBColor.init(0xAF, 0x5F, 0x00), // 130
    RGBColor.init(0xAF, 0x5F, 0x5F), // 131
    RGBColor.init(0xAF, 0x5F, 0x87), // 132
    RGBColor.init(0xAF, 0x5F, 0xAF), // 133
    RGBColor.init(0xAF, 0x5F, 0xD7), // 134
    RGBColor.init(0xAF, 0x5F, 0xFF), // 135
    RGBColor.init(0xAF, 0x87, 0x00), // 136
    RGBColor.init(0xAF, 0x87, 0x5F), // 137
    RGBColor.init(0xAF, 0x87, 0x87), // 138
    RGBColor.init(0xAF, 0x87, 0xAF), // 139
    RGBColor.init(0xAF, 0x87, 0xD7), // 140
    RGBColor.init(0xAF, 0x87, 0xFF), // 141
    RGBColor.init(0xAF, 0xAF, 0x00), // 142
    RGBColor.init(0xAF, 0xAF, 0x5F), // 143
    RGBColor.init(0xAF, 0xAF, 0x87), // 144
    RGBColor.init(0xAF, 0xAF, 0xAF), // 145
    RGBColor.init(0xAF, 0xAF, 0xD7), // 146
    RGBColor.init(0xAF, 0xAF, 0xFF), // 147
    RGBColor.init(0xAF, 0xD7, 0x00), // 148
    RGBColor.init(0xAF, 0xD7, 0x5F), // 149
    RGBColor.init(0xAF, 0xD7, 0x87), // 150
    RGBColor.init(0xAF, 0xD7, 0xAF), // 151
    RGBColor.init(0xAF, 0xD7, 0xD7), // 152
    RGBColor.init(0xAF, 0xD7, 0xFF), // 153
    RGBColor.init(0xAF, 0xFF, 0x00), // 154
    RGBColor.init(0xAF, 0xFF, 0x5F), // 155
    RGBColor.init(0xAF, 0xFF, 0x87), // 156
    RGBColor.init(0xAF, 0xFF, 0xAF), // 157
    RGBColor.init(0xAF, 0xFF, 0xD7), // 158
    RGBColor.init(0xAF, 0xFF, 0xFF), // 159
    RGBColor.init(0xD7, 0x00, 0x00), // 160
    RGBColor.init(0xD7, 0x00, 0x5F), // 161
    RGBColor.init(0xD7, 0x00, 0x87), // 162
    RGBColor.init(0xD7, 0x00, 0xAF), // 163
    RGBColor.init(0xD7, 0x00, 0xD7), // 164
    RGBColor.init(0xD7, 0x00, 0xFF), // 165
    RGBColor.init(0xD7, 0x5F, 0x00), // 166
    RGBColor.init(0xD7, 0x5F, 0x5F), // 167
    RGBColor.init(0xD7, 0x5F, 0x87), // 168
    RGBColor.init(0xD7, 0x5F, 0xAF), // 169
    RGBColor.init(0xD7, 0x5F, 0xD7), // 170
    RGBColor.init(0xD7, 0x5F, 0xFF), // 171
    RGBColor.init(0xD7, 0x87, 0x00), // 172
    RGBColor.init(0xD7, 0x87, 0x5F), // 173
    RGBColor.init(0xD7, 0x87, 0x87), // 174
    RGBColor.init(0xD7, 0x87, 0xAF), // 175
    RGBColor.init(0xD7, 0x87, 0xD7), // 176
    RGBColor.init(0xD7, 0x87, 0xFF), // 177
    RGBColor.init(0xD7, 0xAF, 0x00), // 178
    RGBColor.init(0xD7, 0xAF, 0x5F), // 179
    RGBColor.init(0xD7, 0xAF, 0x87), // 180
    RGBColor.init(0xD7, 0xAF, 0xAF), // 181
    RGBColor.init(0xD7, 0xAF, 0xD7), // 182
    RGBColor.init(0xD7, 0xAF, 0xFF), // 183
    RGBColor.init(0xD7, 0xD7, 0x00), // 184
    RGBColor.init(0xD7, 0xD7, 0x5F), // 185
    RGBColor.init(0xD7, 0xD7, 0x87), // 186
    RGBColor.init(0xD7, 0xD7, 0xAF), // 187
    RGBColor.init(0xD7, 0xD7, 0xD7), // 188
    RGBColor.init(0xD7, 0xD7, 0xFF), // 189
    RGBColor.init(0xD7, 0xFF, 0x00), // 190
    RGBColor.init(0xD7, 0xFF, 0x5F), // 191
    RGBColor.init(0xD7, 0xFF, 0x87), // 192
    RGBColor.init(0xD7, 0xFF, 0xAF), // 193
    RGBColor.init(0xD7, 0xFF, 0xD7), // 194
    RGBColor.init(0xD7, 0xFF, 0xFF), // 195
    RGBColor.init(0xFF, 0x00, 0x00), // 196
    RGBColor.init(0xFF, 0x00, 0x5F), // 197
    RGBColor.init(0xFF, 0x00, 0x87), // 198
    RGBColor.init(0xFF, 0x00, 0xAF), // 199
    RGBColor.init(0xFF, 0x00, 0xD7), // 200
    RGBColor.init(0xFF, 0x00, 0xFF), // 201
    RGBColor.init(0xFF, 0x5F, 0x00), // 202
    RGBColor.init(0xFF, 0x5F, 0x5F), // 203
    RGBColor.init(0xFF, 0x5F, 0x87), // 204
    RGBColor.init(0xFF, 0x5F, 0xAF), // 205
    RGBColor.init(0xFF, 0x5F, 0xD7), // 206
    RGBColor.init(0xFF, 0x5F, 0xFF), // 207
    RGBColor.init(0xFF, 0x87, 0x00), // 208
    RGBColor.init(0xFF, 0x87, 0x5F), // 209
    RGBColor.init(0xFF, 0x87, 0x87), // 210
    RGBColor.init(0xFF, 0x87, 0xAF), // 211
    RGBColor.init(0xFF, 0x87, 0xD7), // 212
    RGBColor.init(0xFF, 0x87, 0xFF), // 213
    RGBColor.init(0xFF, 0xAF, 0x00), // 214
    RGBColor.init(0xFF, 0xAF, 0x5F), // 215
    RGBColor.init(0xFF, 0xAF, 0x87), // 216
    RGBColor.init(0xFF, 0xAF, 0xAF), // 217
    RGBColor.init(0xFF, 0xAF, 0xD7), // 218
    RGBColor.init(0xFF, 0xAF, 0xFF), // 219
    RGBColor.init(0xFF, 0xD7, 0x00), // 220
    RGBColor.init(0xFF, 0xD7, 0x5F), // 221
    RGBColor.init(0xFF, 0xD7, 0x87), // 222
    RGBColor.init(0xFF, 0xD7, 0xAF), // 223
    RGBColor.init(0xFF, 0xD7, 0xD7), // 224
    RGBColor.init(0xFF, 0xD7, 0xFF), // 225
    RGBColor.init(0xFF, 0xFF, 0x00), // 226
    RGBColor.init(0xFF, 0xFF, 0x5F), // 227
    RGBColor.init(0xFF, 0xFF, 0x87), // 228
    RGBColor.init(0xFF, 0xFF, 0xAF), // 229
    RGBColor.init(0xFF, 0xFF, 0xD7), // 230
    RGBColor.init(0xFF, 0xFF, 0xFF), // 231

    // 24-step grayscale ramp (232-255)
    RGBColor.init(0x08, 0x08, 0x08), // 232
    RGBColor.init(0x12, 0x12, 0x12), // 233
    RGBColor.init(0x1C, 0x1C, 0x1C), // 234
    RGBColor.init(0x26, 0x26, 0x26), // 235
    RGBColor.init(0x30, 0x30, 0x30), // 236
    RGBColor.init(0x3A, 0x3A, 0x3A), // 237
    RGBColor.init(0x44, 0x44, 0x44), // 238
    RGBColor.init(0x4E, 0x4E, 0x4E), // 239
    RGBColor.init(0x58, 0x58, 0x58), // 240
    RGBColor.init(0x62, 0x62, 0x62), // 241
    RGBColor.init(0x6C, 0x6C, 0x6C), // 242
    RGBColor.init(0x76, 0x76, 0x76), // 243
    RGBColor.init(0x80, 0x80, 0x80), // 244
    RGBColor.init(0x8A, 0x8A, 0x8A), // 245
    RGBColor.init(0x94, 0x94, 0x94), // 246
    RGBColor.init(0x9E, 0x9E, 0x9E), // 247
    RGBColor.init(0xA8, 0xA8, 0xA8), // 248
    RGBColor.init(0xB2, 0xB2, 0xB2), // 249
    RGBColor.init(0xBC, 0xBC, 0xBC), // 250
    RGBColor.init(0xC6, 0xC6, 0xC6), // 251
    RGBColor.init(0xD0, 0xD0, 0xD0), // 252
    RGBColor.init(0xDA, 0xDA, 0xDA), // 253
    RGBColor.init(0xE4, 0xE4, 0xE4), // 254
    RGBColor.init(0xEE, 0xEE, 0xEE), // 255
};

/// 256-to-16 color mapping table from charmbracelet/x
/// Provides precise mapping from extended colors to basic ANSI colors
pub const ANSI_256_TO_16_MAP = [256]u8{
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, // 0-15 (direct mapping)
    0, 4, 4, 4, 12, 12, 2, 6, 4, 4, 12, 12, 2, 2, 6, 4, // 16-31
    12, 12, 2, 2, 2, 6, 12, 12, 10, 10, 10, 10, 14, 12, 10, 10, // 32-47
    10, 10, 10, 14, 1, 5, 4, 4, 12, 12, 3, 8, 4, 4, 12, 12, // 48-63
    2, 2, 6, 4, 12, 12, 2, 2, 2, 6, 12, 12, 10, 10, 10, 10, // 64-79
    14, 12, 10, 10, 10, 10, 10, 14, 1, 1, 5, 4, 12, 12, 1, 1, // 80-95
    1, 5, 12, 12, 1, 1, 1, 5, 12, 12, 3, 3, 3, 7, 12, 12, // 96-111
    10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14, 9, 9, 9, 9, // 112-127
    13, 12, 9, 9, 9, 9, 13, 12, 9, 9, 9, 9, 13, 12, 9, 9, // 128-143
    9, 9, 13, 12, 11, 11, 11, 11, 7, 12, 10, 10, 10, 10, 10, 14, // 144-159
    9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, // 160-175
    9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 11, 11, // 176-191
    11, 11, 11, 15, 0, 0, 0, 0, 0, 0, 8, 8, 8, 8, 8, 8, // 192-207
    7, 7, 7, 7, 7, 7, 15, 15, 15, 15, 15, 15, // 208-223
    0, 0, 0, 0, 0, 0, 8, 8, 8, 8, 8, 8, 7, 7, 7, 7, // 224-239
    7, 7, 15, 15, 15, 15, 15, 15, // 240-255
};

/// Get RGB values for any ANSI 256 color index
pub fn getRgbColor(index: u8) RGBColor {
    return ANSI_256_PALETTE[index];
}

/// Get 16-color mapping for any ANSI 256 color index
pub fn get16ColorMapping(index: u8) u8 {
    return ANSI_256_TO_16_MAP[index];
}

/// Check if a color index is in the basic 16-color range
pub fn isBasicColor(index: u8) bool {
    return index <= 15;
}

/// Check if a color index is in the 6x6x6 color cube range
pub fn isCubeColor(index: u8) bool {
    return index >= 16 and index <= 231;
}

/// Check if a color index is in the grayscale ramp range
pub fn isGrayscaleColor(index: u8) bool {
    return index >= 232 and index <= 255;
}

/// Convert 6x6x6 coordinates to color index
pub fn cubeToIndex(r: u8, g: u8, b: u8) u8 {
    std.debug.assert(r <= 5 and g <= 5 and b <= 5);
    return 16 + @as(u8, r) * 36 + @as(u8, g) * 6 + @as(u8, b);
}

/// Convert color index to 6x6x6 coordinates
pub fn indexToCube(index: u8) struct { r: u8, g: u8, b: u8 } {
    std.debug.assert(isCubeColor(index));
    const cube_index = index - 16;
    const r = cube_index / 36;
    const g = (cube_index % 36) / 6;
    const b = cube_index % 6;
    return .{ .r = @intCast(r), .g = @intCast(g), .b = @intCast(b) };
}

/// Get grayscale level (0-23) from grayscale color index
pub fn getGrayscaleLevel(index: u8) u8 {
    std.debug.assert(isGrayscaleColor(index));
    return index - 232;
}

/// Convert grayscale level (0-23) to color index
pub fn grayscaleLevelToIndex(level: u8) u8 {
    std.debug.assert(level <= 23);
    return 232 + level;
}

/// Enhanced color matching using precise palette
pub const PreciseColorMatcher = struct {
    /// Find exact color match if it exists in the palette
    pub fn findExactMatch(target: RGBColor) ?u8 {
        for (ANSI_256_PALETTE, 0..) |color, i| {
            if (color.r == target.r and color.g == target.g and color.b == target.b) {
                return @intCast(i);
            }
        }
        return null;
    }

    /// Find closest color using simple Euclidean distance
    pub fn findClosestEuclidean(target: RGBColor) struct { index: u8, distance: f64 } {
        var best_index: u8 = 0;
        var best_distance: f64 = std.math.floatMax(f64);

        for (ANSI_256_PALETTE, 0..) |color, i| {
            const dr = @as(f64, @floatFromInt(color.r)) - @as(f64, @floatFromInt(target.r));
            const dg = @as(f64, @floatFromInt(color.g)) - @as(f64, @floatFromInt(target.g));
            const db = @as(f64, @floatFromInt(color.b)) - @as(f64, @floatFromInt(target.b));
            const distance = @sqrt(dr * dr + dg * dg + db * db);

            if (distance < best_distance) {
                best_distance = distance;
                best_index = @intCast(i);
            }
        }

        return .{ .index = best_index, .distance = best_distance };
    }

    /// Advanced conversion using the charmbracelet algorithm approach
    pub fn convertRgbTo256(target: RGBColor) u8 {
        const enhanced_distance = @import("enhanced_color_distance.zig");

        // Check for exact match first
        if (findExactMatch(target)) |exact| {
            return exact;
        }

        // Use enhanced perceptual distance for best match
        const result = enhanced_distance.findClosestColor(target, &ANSI_256_PALETTE, false);
        return @intCast(result.index);
    }

    /// Convert to 16-color using precise mapping
    pub fn convertTo16Color(index_256: u8) u8 {
        return get16ColorMapping(index_256);
    }

    /// Convert RGB directly to 16-color via 256-color conversion
    pub fn convertRgbTo16(target: RGBColor) u8 {
        const index_256 = convertRgbTo256(target);
        return convertTo16Color(index_256);
    }
};

/// Color palette utilities
pub const PaletteUtils = struct {
    /// Get all basic 16 colors
    pub fn getBasic16Colors() [16]RGBColor {
        var colors: [16]RGBColor = undefined;
        for (0..16) |i| {
            colors[i] = ANSI_256_PALETTE[i];
        }
        return colors;
    }

    /// Get all colors from the 6x6x6 cube
    pub fn getCubeColors(allocator: std.mem.Allocator) ![]RGBColor {
        var colors = try allocator.alloc(RGBColor, 216); // 6^3 = 216 colors
        var idx: usize = 0;
        for (16..232) |i| {
            colors[idx] = ANSI_256_PALETTE[i];
            idx += 1;
        }
        return colors;
    }

    /// Get all grayscale colors
    pub fn getGrayscaleColors() [24]RGBColor {
        var colors: [24]RGBColor = undefined;
        var idx: usize = 0;
        for (232..256) |i| {
            colors[idx] = ANSI_256_PALETTE[i];
            idx += 1;
        }
        return colors;
    }

    /// Generate ANSI escape sequence for foreground color
    pub fn toAnsiForeground(index: u8, buf: []u8) ![]u8 {
        if (index <= 15) {
            // Basic colors use different sequences
            if (index <= 7) {
                return std.fmt.bufPrint(buf, "\x1b[{}m", .{30 + index});
            } else {
                return std.fmt.bufPrint(buf, "\x1b[{}m", .{90 + (index - 8)});
            }
        } else {
            // Extended colors use 256-color sequence
            return std.fmt.bufPrint(buf, "\x1b[38;5;{}m", .{index});
        }
    }

    /// Generate ANSI escape sequence for background color
    pub fn toAnsiBackground(index: u8, buf: []u8) ![]u8 {
        if (index <= 15) {
            // Basic colors use different sequences
            if (index <= 7) {
                return std.fmt.bufPrint(buf, "\x1b[{}m", .{40 + index});
            } else {
                return std.fmt.bufPrint(buf, "\x1b[{}m", .{100 + (index - 8)});
            }
        } else {
            // Extended colors use 256-color sequence
            return std.fmt.bufPrint(buf, "\x1b[48;5;{}m", .{index});
        }
    }
};

// Tests
const testing = std.testing;

test "palette accuracy" {
    // Test specific known colors
    const black = getRgbColor(0);
    try testing.expect(black.r == 0x00 and black.g == 0x00 and black.b == 0x00);

    const bright_red = getRgbColor(9);
    try testing.expect(bright_red.r == 0xFF and bright_red.g == 0x00 and bright_red.b == 0x00);

    const bright_white = getRgbColor(15);
    try testing.expect(bright_white.r == 0xFF and bright_white.g == 0xFF and bright_white.b == 0xFF);

    // Test first grayscale color
    const gray_start = getRgbColor(232);
    try testing.expect(gray_start.r == 0x08 and gray_start.g == 0x08 and gray_start.b == 0x08);

    // Test last grayscale color
    const gray_end = getRgbColor(255);
    try testing.expect(gray_end.r == 0xEE and gray_end.g == 0xEE and gray_end.b == 0xEE);
}

test "color range detection" {
    try testing.expect(isBasicColor(0));
    try testing.expect(isBasicColor(15));
    try testing.expect(!isBasicColor(16));

    try testing.expect(!isCubeColor(15));
    try testing.expect(isCubeColor(16));
    try testing.expect(isCubeColor(231));
    try testing.expect(!isCubeColor(232));

    try testing.expect(!isGrayscaleColor(231));
    try testing.expect(isGrayscaleColor(232));
    try testing.expect(isGrayscaleColor(255));
}

test "cube coordinate conversion" {
    // Test cube coordinate conversion
    const index = cubeToIndex(5, 5, 5); // Max values
    try testing.expect(index == 231); // Should be last cube color

    const coords = indexToCube(231);
    try testing.expect(coords.r == 5 and coords.g == 5 and coords.b == 5);

    // Test first cube color
    const first_coords = indexToCube(16);
    try testing.expect(first_coords.r == 0 and first_coords.g == 0 and first_coords.b == 0);
}

test "256-to-16 mapping" {
    // Test direct mapping for basic colors
    for (0..16) |i| {
        const mapped = get16ColorMapping(@intCast(i));
        try testing.expect(mapped == i);
    }

    // Test some extended color mappings
    const high_red = get16ColorMapping(196); // Should map to a red variant
    try testing.expect(high_red == 9); // Bright red

    const gray_mid = get16ColorMapping(244); // Mid-grayscale should map to gray
    try testing.expect(gray_mid == 8); // Gray
}

test "exact color matching" {
    const pure_red = RGBColor.init(0xFF, 0x00, 0x00);
    const exact_match = PreciseColorMatcher.findExactMatch(pure_red);

    // Should find exact match at index 9 (bright red)
    try testing.expectEqual(@as(?u8, 9), exact_match);

    // Test non-existing color
    const weird_color = RGBColor.init(0x33, 0x77, 0x99);
    const no_match = PreciseColorMatcher.findExactMatch(weird_color);
    try testing.expectEqual(@as(?u8, null), no_match);
}

test "color conversion" {
    const target_red = RGBColor.init(0xFF, 0x00, 0x00);
    const converted_256 = PreciseColorMatcher.convertRgbTo256(target_red);
    try testing.expect(converted_256 == 9); // Should match bright red

    const converted_16 = PreciseColorMatcher.convertRgbTo16(target_red);
    try testing.expect(converted_16 == 9); // Should also be bright red in 16-color
}

test "ANSI escape sequence generation" {
    var buf: [20]u8 = undefined;

    // Test basic color foreground
    const fg_red = try PaletteUtils.toAnsiForeground(1, &buf);
    try testing.expectEqualStrings("\x1b[31m", fg_red);

    // Test bright color foreground
    const fg_bright_red = try PaletteUtils.toAnsiForeground(9, buf[0..10]);
    try testing.expectEqualStrings("\x1b[91m", fg_bright_red);

    // Test 256-color foreground
    const fg_256 = try PaletteUtils.toAnsiForeground(196, &buf);
    try testing.expectEqualStrings("\x1b[38;5;196m", fg_256);

    // Test basic color background
    const bg_blue = try PaletteUtils.toAnsiBackground(4, buf[0..10]);
    try testing.expectEqualStrings("\x1b[44m", bg_blue);
}
