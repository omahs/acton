const std = @import("std");
const print = @import("std").debug.print;
const ArrayList = std.ArrayList;

pub fn build(b: *std.build.Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const syspath_include = b.option([]const u8, "syspath_include", "") orelse "";

    const dep_libargp = b.anonymousDependency("deps/libargp", @import("deps/libargp/build.zig"), .{
        .target = target,
        .optimize = optimize,
    });

    const dep_libnetstring = b.anonymousDependency("deps/libnetstring", @import("deps/libnetstring/build.zig"), .{
        .target = target,
        .optimize = optimize,
    });

    const dep_libprotobuf_c = b.anonymousDependency("deps/libprotobuf_c", @import("deps/libprotobuf_c/build.zig"), .{
        .target = target,
        .optimize = optimize,
    });

    const dep_libuuid = b.anonymousDependency("deps/libuuid", @import("deps/libuuid/build.zig"), .{
        .target = target,
        .optimize = optimize,
    });

    const dep_libyyjson = b.anonymousDependency("deps/libyyjson", @import("deps/libyyjson/build.zig"), .{
        .target = target,
        .optimize = optimize,
    });

    const libactondb_sources = [_][]const u8 {
        "comm.c",
        "hash_ring.c",
        "queue_callback.c",
        "db.c",
        "queue.c",
        "queue_groups.c",
//        "log.c",
        "skiplist.c",
        "txn_state.c",
        "txns.c",
        "client_api.c",
        "failure_detector/db_messages.pb-c.c",
        "failure_detector/cells.c",
        "failure_detector/db_queries.c",
        "failure_detector/fd.c",
        "failure_detector/vector_clock.c",
    };

    const libactondb_cflags: []const []const u8 = &.{
        "-fno-sanitize=undefined",
    };

    const libactondb = b.addStaticLibrary(.{
        .name = "ActonDB",
        .target = target,
        .optimize = optimize,
    });
    libactondb.addCSourceFiles(&libactondb_sources, libactondb_cflags);
    libactondb.defineCMacro("LOG_USER_COLOR", "");
    libactondb.addIncludePath(syspath_include);
    libactondb.linkLibC();
    b.installArtifact(libactondb);

    const actondb = b.addExecutable(.{
        .name = "actondb",
        .target = target,
        .optimize = optimize,
    });
    actondb.addCSourceFile("actondb.c", &[_][]const u8{
        "-fno-sanitize=undefined",
    });
    actondb.addCSourceFile("log.c", &[_][]const u8{});
    actondb.addIncludePath(syspath_include);
    actondb.addLibraryPath("../lib");
    actondb.linkLibrary(libactondb);
    actondb.linkLibrary(dep_libargp.artifact("argp"));
    actondb.linkLibrary(dep_libnetstring.artifact("netstring"));
    actondb.linkLibrary(dep_libprotobuf_c.artifact("protobuf-c"));
    actondb.linkLibrary(dep_libuuid.artifact("uuid"));
    actondb.linkLibrary(dep_libyyjson.artifact("yyjson"));
    actondb.linkLibC();
    b.installArtifact(actondb);
}