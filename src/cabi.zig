//! Canonical ABI
const std = @import("std");

const log = std.log.scoped(.cabi);

pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;

/// Arena, typically used for allocating lowered params.
pub var arena: std.heap.ArenaAllocator = .init(gpa.allocator());

comptime {
    @export(&cabiRealloc, .{ .name = "cabi_realloc", .linkage = .weak });
}

fn cabiRealloc(ptr: [*]u8, old_n: usize, alignment: usize, new_n: usize) callconv(.c) [*]u8 {
    if (new_n == 0) return @ptrFromInt(alignment);
    return @ptrCast(arena.allocator().realloc(ptr[0..old_n], new_n) catch |err| oom(err));
}

pub fn oom(err: anytype) noreturn {
    comptime std.debug.assert(@TypeOf(err) == error{OutOfMemory});
    log.err("out of memory", .{});
    @trap();
}

pub const String = List(u8);

pub fn List(comptime T: type) type {
    return extern struct {
        ptr: [*]const T,
        len: usize,

        const Self = @This();

        pub const empty: Self = .{ .ptr = undefined, .len = 0 };

        pub fn toSlice(self: Self) []const T {
            return self.ptr[0..self.len];
        }

        pub fn fromSlice(s: []const T) Self {
            return .{ .ptr = s.ptr, .len = s.len };
        }
    };
}
