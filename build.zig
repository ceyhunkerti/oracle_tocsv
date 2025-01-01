const std = @import("std");
const builtin = @import("builtin");

comptime {
    // This is the required Zig version for building this project. We allow
    // any patch version but the major and minor must match exactly.
    const required_zig = "0.14.0";

    // Fail compilation if the current Zig version doesn't meet requirements.
    const current_vsn = builtin.zig_version;
    const required_vsn = std.SemanticVersion.parse(required_zig) catch unreachable;
    if (current_vsn.major != required_vsn.major or
        current_vsn.minor != required_vsn.minor)
    {
        @compileError(std.fmt.comptimePrint(
            "Your Zig version v{} does not meet the required build version of v{}",
            .{ current_vsn, required_vsn },
        ));
    }
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.append("-std=c99");
    const c_flags = flags.items;

    const exe = b.addExecutable(.{
        .name = "ox",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFile(.{
        .file = b.path("lib/odpi/embed/dpi.c"),
        .flags = c_flags,
    });
    exe.addIncludePath(b.path("lib/odpi/include"));
    exe.linkLibC();

    const zdt = b.dependency("zdt", .{
        .target = target,
        .optimize = optimize,
    });
    const argz = b.dependency("argz", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zdt", zdt.module("zdt"));
    exe.root_module.addImport("argz", argz.module("argz"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.addCSourceFile(.{
        .file = b.path("lib/odpi/embed/dpi.c"),
        .flags = c_flags,
    });
    exe_unit_tests.addIncludePath(b.path("lib/odpi/include"));
    exe_unit_tests.linkLibC();
    exe_unit_tests.root_module.addImport("zdt", zdt.module("zdt"));
    exe_unit_tests.root_module.addImport("argz", argz.module("argz"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
