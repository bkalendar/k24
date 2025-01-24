const std = @import("std");
const cabi = @import("cabi");

const cabiInfo = @extern(*const fn ([*]const u8, usize) callconv(.c) void, .{ .name = "info", .library_name = "bkalendar:k24/console" });
const cabiDebug = @extern(*const fn ([*]const u8, usize) callconv(.c) void, .{ .name = "debug", .library_name = "bkalendar:k24/console" });
const cabiWarn = @extern(*const fn ([*]const u8, usize) callconv(.c) void, .{ .name = "warn", .library_name = "bkalendar:k24/console" });
const cabiError = @extern(*const fn ([*]const u8, usize) callconv(.c) void, .{ .name = "error", .library_name = "bkalendar:k24/console" });
const cabiTrace = @extern(*const fn () callconv(.c) void, .{ .name = "trace", .library_name = "bkalendar:k24/console" });

pub fn log(comptime level: std.log.Level, msg: []const u8) void {
    const cabiLog = switch (level) {
        .info => cabiInfo,
        .debug => cabiDebug,
        .warn => cabiWarn,
        .err => cabiError,
    };
    cabiLog(msg.ptr, msg.len);
}

pub fn trace() void {
    cabiTrace();
}
