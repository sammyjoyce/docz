const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;
const JsonBuilder = @import("json_builder.zig").JsonBuilder;

pub const TemplateRequest = struct {
    template: []const u8,
    variables: ?std.json.ObjectMap = null,
    options: ?toolsMod.Template.ProcessOptions = null,
};

pub const TemplateResponse = struct {
    success: bool,
    result: []const u8 = "",
    error_message: ?[]const u8 = null,
    variables_used: [][]const u8 = &.{},
    variables_missing: [][]const u8 = &.{},
};

pub fn executeTemplateProcessing(allocator: std.mem.Allocator, json_input: std.json.Value) toolsMod.ToolError!std.json.Value {
    const MapperReq = toolsMod.JsonReflector.mapper(TemplateRequest);
    const reqp = MapperReq.fromJson(allocator, json_input) catch return toolsMod.ToolError.InvalidInput;
    defer reqp.deinit();
    const req = reqp.value;

    const opts = req.options orelse toolsMod.Template.ProcessOptions{};

    var tr = toolsMod.Template.processWithMap(allocator, req.template, req.variables, opts) catch |err| {
        const error_msg = std.fmt.allocPrint(allocator, "Template processing failed: {}", .{err}) catch "processing error";
        defer allocator.free(error_msg);
        return JsonBuilder.buildTemplateResponse(allocator, false, "", error_msg, &.{}, &.{});
    };
    defer tr.deinit();

    return JsonBuilder.buildTemplateResponse(allocator, true, tr.result, null, tr.variables_used, tr.variables_missing);
}
