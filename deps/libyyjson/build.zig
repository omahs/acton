const std = @import("std");
const print = @import("std").debug.print;

pub fn build(b: *std.build.Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary(.{
        .name = "yyjson",
        .target = target,
        .optimize = optimize,
    });

    const source_files = [_][]const u8{
        "yyjson.c",
    };

    lib.addCSourceFiles(&source_files, &[_][]const u8{});
    lib.linkLibC();
    b.installFile("yyjson.h", "include/yyjson.h");
    b.installArtifact(lib);
}
