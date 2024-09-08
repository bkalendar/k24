const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(try std.Build.parseTargetQuery(.{ .arch_os_abi = "wasm32-freestanding" }));
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .target = target,
        .name = "mybk_app",
        .root_source_file = .{ .cwd_relative = "parser/mybk_app.zig" },
        .optimize = optimize,
    });

    exe.rdynamic = true;
    exe.entry = .disabled;

    b.installArtifact(exe);
}
