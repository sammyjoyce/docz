//! JSON reflection utilities barrel.
//! Import via this barrel; do not deep-import subfiles.

pub const json_reflection = @import("json_reflection.zig");
pub const generateJsonMapper = json_reflection.generateJsonMapper;
pub const generateJsonDeserializer = json_reflection.generateJsonDeserializer;
pub const generateJsonSerializer = json_reflection.generateJsonSerializer;
pub const fieldNameToJson = json_reflection.fieldNameToJson;
