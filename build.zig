const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ziggames",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addIncludePath(b.path("./raylib-5.5_linux_amd64/include"));
    exe.addLibraryPath(b.path("./raylib-5.5_linux_amd64/lib"));
    exe.linkSystemLibrary("raylib");

    b.installArtifact(exe);
}
