// Buffer management namespace

const BufferImpl = @import("Buffer.zig");

// Re-export main types and functions
pub const CellBuffer = BufferImpl.CellBuffer;
pub const Cell = BufferImpl.Cell;
pub const Color = BufferImpl.Color;
pub const Style = BufferImpl.Style;
pub const AttrMask = BufferImpl.AttrMask;
pub const UnderlineStyle = BufferImpl.UnderlineStyle;
pub const Link = BufferImpl.Link;
pub const Rectangle = BufferImpl.Rectangle;

// Re-export utility functions
pub const defaultColor = BufferImpl.defaultColor;
pub const ansiColor = BufferImpl.ansiColor;
pub const ansi256Color = BufferImpl.ansi256Color;
pub const rgbColor = BufferImpl.rgbColor;
pub const createCell = BufferImpl.createCell;
pub const createStyledCell = BufferImpl.createStyledCell;
pub const createCellWithLink = BufferImpl.createCellWithLink;
pub const boldStyle = BufferImpl.boldStyle;
pub const colorStyle = BufferImpl.colorStyle;
pub const underlineStyle = BufferImpl.underlineStyle;

// Re-export constants
pub const BOLD = BufferImpl.BOLD;
pub const ITALIC = BufferImpl.ITALIC;
pub const REVERSE = BufferImpl.REVERSE;
pub const STRIKETHROUGH = BufferImpl.STRIKETHROUGH;
