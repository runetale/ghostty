const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
const posix = std.posix;
const internal_os = @import("main.zig");
const std = @import("std");

const log = std.log.scoped(.runetale);

comptime {
    if (builtin.target.isWasm()) {
        @compileError("runetale is not available for wasm");
    }
}

const c = if (builtin.os.tag != .windows) @cImport({
    @cInclude("unistd.h");
    @cInclude("dirent.h");
}) else {};

pub fn isLaunchedRunetale() bool {
    return switch (builtin.os.tag) {
        .macos => return checkMacProcess(),
        .linux => linux: {
             if (try checkMacProcess()) |proc| {
                std.debug.print("{}\n", .{proc});
                return true;
            }
            break :linux false;
        },

        .windows => false,

        .ios => true,

        else => @compileError("unsupported platform"),
    };
}

fn checkLinuxProcess() bool {
    var dirIter = try std.fs.cwd().openDir("/proc", .{.iterate= true});
    defer dirIter.close();
    
    var c_dir_it = dirIter.iterate();
    while (try c_dir_it.next()) |entry| {
        const commandPath = try std.fmt.allocPrint(std.heap.page_allocator, "/proc/{}/runetaled", .{entry.name});
        defer std.heap.page_allocator.free(commandPath);

        const file = try std.fs.openDirAbsolute(commandPath);
        defer file.close();

        const cmdline = try file.readAllAlloc(std.heap.page_allocator, std.math.minInt(usize, 1024));
        defer std.heap.page_allocator.free(cmdline);

        if (std.mem.indexOf(u8, cmdline, "runetaled") != null) {
            return true;
        }
    }

    return false;
}

fn checkMacProcess() !?bool {
    const allocator = std.heap.page_allocator;

    const run = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", "ps aux | grep runetaled" },
    });

    if (run.term == .Exited and run.term.Exited == 0) {
        const result = trimSpace(run.stdout);
        std.debug.print("{s}\n", .{result});
        // todo: check buf?
        // if (0 > result.len) return false;
        return true;
    }

    return false;
}

fn trimSpace(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, " \n\t");
}