const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm32 = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });

    const cabi_mod = b.createModule(.{
        .root_source_file = b.path("src/cabi.zig"),
        .target = wasm32,
        .optimize = optimize,
    });

    const console_mod = b.createModule(.{
        .root_source_file = b.path("src/console.zig"),
        .target = wasm32,
        .optimize = optimize,
    });
    console_mod.addImport("cabi", cabi_mod);

    const parser_mod = b.createModule(.{
        .root_source_file = b.path("src/parser/main_k24.zig"),
        .target = wasm32,
        .optimize = optimize,
    });
    parser_mod.addImport("cabi", cabi_mod);
    parser_mod.addImport("console", console_mod);

    const parser_exe = b.addExecutable(.{
        .name = "parser",
        .root_module = parser_mod,
    });
    parser_exe.rdynamic = true;
    parser_exe.entry = .disabled;

    b.installArtifact(parser_exe);

    const run_embed = b.addSystemCommand(&.{
        "wasm-tools",
        "component",
        "embed",
        "-w",
        "parser",
    });
    run_embed.addFileArg(b.path("wit/k24.wit"));
    run_embed.addArtifactArg(parser_exe);

    const run_component = b.addSystemCommand(&.{
        "wasm-tools",
        "component",
        "new",
    });
    run_component.addFileArg(run_embed.captureStdOut());

    const component_file = run_component.captureStdOut();

    b.getInstallStep().dependOn(&b.addInstallBinFile(component_file, "parser.component.wasm").step);

    const run_jco = b.addSystemCommand(&.{
        "deno",
        "run",
        "-A",
        "npm:@bytecodealliance/jco",
        "transpile",
        "--name",
        "parser",
        "--no-nodejs-compat",
        "-Iasync",
    });
    run_jco.addFileArg(component_file);
    run_jco.addArg("-o");
    const out_js_dir = run_jco.addOutputDirectoryArg("transpiled");

    b.getInstallStep().dependOn(
        &b.addInstallDirectory(.{
            .source_dir = out_js_dir,
            .install_dir = .prefix,
            .install_subdir = "js",
        }).step,
    );
}
