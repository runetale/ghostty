const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
const posix = std.posix;
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
        .macos => macos: {
            if (build_config.artifact == .lib and
                posix.getenv("GHOSTTY_MAC_APP") != null) break :macos true;

            break :macos c.getppid() == 1;
        },

        .linux => return checkLinuxProcess(),

        .windows => false,

        .ios => true,

        else => @compileError("unsupported platform"),
    };
}

fn checkLinuxProcess() void {
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