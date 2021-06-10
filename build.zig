const std = @import("std");
const deps = @import("deps.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("trax_viewer", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    // c and system libraries
    exe.linkLibC();
    exe.linkSystemLibrary("freeglut");
    exe.linkSystemLibrary("glfw3");
    exe.linkSystemLibrary("GL");
    // add zigmod-managed packages
    deps.addAllTo(exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
