const std = @import("std");
const Build = std.Build;
const StringList = std.ArrayList([]const u8);
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const version = std.SemanticVersion{
    .major = 5,
    .minor = 4,
    .patch = 7,
};
const lib_name = "lua";
const exe_name = lib_name ++ "_exe";
const compiler_name = "luac";

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const build_shared = b.option(bool, "shared", "build as shared library") orelse target.result.isMinGW();
    const use_readline =
        if (target.result.os.tag == .linux)
            b.option(bool, "use_readline", "readline support for linux") orelse false
        else
            null;

    const lua_src = b.dependency("lua", .{});

    const lib =
        b.addLibrary(.{
            .root_module = b.createModule(.{ .target = target }),
            .name = "lua",
            .linkage = if (build_shared) .dynamic else .static,
        });
    const exe = b.addExecutable(artifactOptions(.exe, b, .{
        .target = target,
        .optimize = optimize,
    }));
    const exec = b.addExecutable(artifactOptions(.exec, b, .{
        .target = target,
        .optimize = optimize,
    }));
    if (!target.result.isMinGW()) {
        lib.root_module.linkSystemLibrary("m", .{});
        exe.root_module.linkSystemLibrary("m", .{});
        exec.root_module.linkSystemLibrary("m", .{});
    }
    const build_targets = [_]?*Build.Step.Compile{
        lib,
        exe,
        exec,
    };
    // Common compile flags
    for (&build_targets) |tr| {
        const t = tr orelse continue;
        t.root_module.addIncludePath(lua_src.path("src"));
        t.root_module.link_libc = true;
        switch (target.result.os.tag) {
            .freebsd, .netbsd, .openbsd => {
                t.root_module.addCMacro("LUA_USE_LINUX", "");
                t.root_module.addCMacro("LUA_USE_READLINE", "");
                t.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/edit" });
                t.root_module.linkSystemLibrary("edit", .{});
            },
            .ios => {
                t.root_module.addCMacro("LUA_USE_IOS", "");
            },
            .linux => {
                t.root_module.addCMacro("LUA_USE_LINUX", "");
                t.root_module.linkSystemLibrary("dl", .{});
                if (use_readline.?) {
                    t.root_module.addCMacro("LUA_USE_READLINE", "");
                    t.root_module.linkSystemLibrary("readline", .{});
                }
            },
            .macos => {
                t.root_module.addCMacro("LUA_USE_MACOSX", "");
                t.root_module.addCMacro("LUA_USE_READLINE", "");
                t.root_module.linkSystemLibrary("readline", .{});
            },
            else => {},
        }
    }
    if (target.result.isMinGW()) {
        lib.root_module.addCMacro("LUA_BUILD_AS_DLL", "");
        exe.root_module.addCMacro("LUA_BUILD_AS_DLL", "");
    }

    lib.root_module.addCSourceFiles(.{
        .root = lua_src.path("src"),
        .files = &base_src,
        .flags = &cflags,
    });

    lib.installHeadersDirectory(
        lua_src.path("src"),
        "",
        .{ .include_extensions = &lua_inc },
    );

    exe.root_module.addCSourceFile(.{
        .file = lua_src.path("src/lua.c"),
        .flags = &cflags,
    });

    exec.root_module.addCSourceFile(.{
        .file = lua_src.path("src/luac.c"),
        .flags = &cflags,
    });

    exe.root_module.linkLibrary(lib);
    b.installArtifact(lib);

    b.installArtifact(exe);
    exec.root_module.linkLibrary(lib);
    b.installArtifact(exec);

    b.installDirectory(.{
        .source_dir = lua_src.path("doc"),
        .include_extensions = &.{".1"},
        .install_dir = .{ .custom = "man" },
        .install_subdir = "man1",
    });

    const run_step = b.step("run", "run lua interpreter");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    const unpack_step = b.step("unpack", "unpack source");
    const unpack_cmd = b.addInstallDirectory(.{
        .source_dir = lua_src.path(""),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    unpack_step.dependOn(&unpack_cmd.step);
}
const ArtifactTarget = enum {
    // True if shared options
    lib,
    exe,
    exec,
};
const ArtifactTargetOptions = struct {
    target: ResolvedTarget,
    optimize: OptimizeMode,
};
fn artifactOptions(comptime options: ArtifactTarget, b: *std.Build, opts: ArtifactTargetOptions) switch (options) {
    .exe, .exec => Build.ExecutableOptions,
    .lib => Build.LibraryOptions,
} {
    const t = opts.target.result.os.tag;
    return switch (options) {
        .lib => blk: {
            switch (t) {
                .windows => break :blk .{
                    .name = lib_name ++ "54",
                    .target = opts.target,
                    .optimize = opts.optimize,
                    .strip = true,
                },
                else => break :blk .{
                    .name = lib_name,
                    .target = opts.target,
                    .optimize = opts.optimize,
                },
            }
        },
        .exe => switch (t) {
            else => Build.ExecutableOptions{ .name = exe_name, .root_module = b.createModule(.{ .target = opts.target }) },
        },
        .exec => switch (t) {
            else => Build.ExecutableOptions{ .name = compiler_name, .root_module = b.createModule(.{ .target = opts.target }) },
        },
    };
}

const cflags = [_][]const u8{
    "-std=gnu99",
    "-Wall",
    "-Wextra",
};

const core_src = [_][]const u8{
    "lapi.c",
    "lcode.c",
    "lctype.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
};
const lib_src = [_][]const u8{
    "lauxlib.c",
    "lbaselib.c",
    "lcorolib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loadlib.c",
    "loslib.c",
    "lstrlib.c",
    "ltablib.c",
    "lutf8lib.c",
    "linit.c",
};
const base_src = core_src ++ lib_src;

const lua_inc = [_][]const u8{
    "lua.h",
    "luaconf.h",
    "lualib.h",
    "lauxlib.h",
    "lua.hpp",
};
