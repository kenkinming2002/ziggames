const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    for ([_][]const u8{
        "ibreakout",
        "npong",
    }) |name| {
        const root_source_file = b.path(b.fmt("src/{s}.zig", .{name}));
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        });

        exe.linkLibC();
        exe.addIncludePath(b.path("./raylib-5.5_linux_amd64/include"));
        exe.addLibraryPath(b.path("./raylib-5.5_linux_amd64/lib"));
        exe.linkSystemLibrary("raylib");

        b.installArtifact(exe);
    }
}
