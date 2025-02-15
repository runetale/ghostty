const std = @import("std");

const key = @import("key.zig");
const Config = @import("Config.zig");
const Color = Config.Color;
const Key = key.Key;
const Value = key.Value;

/// Get a value from the config by key into the given pointer. This is
/// specifically for C-compatible APIs. If you're using Zig, just access
/// the configuration directly.
///
/// The return value is false if the given key is not supported by the
/// C API yet. This is a fixable problem so if it is important to support
/// some key, please open an issue.
pub fn get(config: *const Config, k: Key, ptr_raw: *anyopaque) bool {
    @setEvalBranchQuota(10_000);
    switch (k) {
        inline else => |tag| {
            const value = fieldByKey(config, tag);
            return getValue(ptr_raw, value);
        },
    }
}

/// Get the value anytype and put it into the pointer. Returns false if
/// the type is not supported by the C API yet or the value is null.
fn getValue(ptr_raw: *anyopaque, value: anytype) bool {
    switch (@TypeOf(value)) {
        ?[:0]const u8 => {
            const ptr: *?[*:0]const u8 = @ptrCast(@alignCast(ptr_raw));
            ptr.* = if (value) |slice| @ptrCast(slice.ptr) else null;
        },

        bool => {
            const ptr: *bool = @ptrCast(@alignCast(ptr_raw));
            ptr.* = value;
        },

        u8, u32 => {
            const ptr: *c_uint = @ptrCast(@alignCast(ptr_raw));
            ptr.* = @intCast(value);
        },

        f32, f64 => |Float| {
            const ptr: *Float = @ptrCast(@alignCast(ptr_raw));
            ptr.* = @floatCast(value);
        },

        else => |T| switch (@typeInfo(T)) {
            .Optional => {
                // If an optional has no value we return false.
                const unwrapped = value orelse return false;
                return getValue(ptr_raw, unwrapped);
            },

            .Enum => {
                const ptr: *[*:0]const u8 = @ptrCast(@alignCast(ptr_raw));
                ptr.* = @tagName(value);
            },

            .Struct => |info| {
                // If the struct implements c_get then we call that
                if (@hasDecl(@TypeOf(value), "c_get")) {
                    value.c_get(ptr_raw);
                    return true;
                }

                // Packed structs that are less than or equal to the
                // size of a C int can be passed directly as their
                // bit representation.
                if (info.layout != .@"packed") return false;
                const Backing = info.backing_integer orelse return false;
                if (@bitSizeOf(Backing) > @bitSizeOf(c_uint)) return false;

                const ptr: *c_uint = @ptrCast(@alignCast(ptr_raw));
                ptr.* = @intCast(@as(Backing, @bitCast(value)));
            },

            else => return false,
        },
    }

    return true;
}

/// Get a value from the config by key.
fn fieldByKey(self: *const Config, comptime k: Key) Value(k) {
    const field = comptime field: {
        const fields = std.meta.fields(Config);
        for (fields) |field| {
            if (@field(Key, field.name) == k) {
                break :field field;
            }
        }

        unreachable;
    };

    return @field(self, field.name);
}

test "u8" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.@"font-size" = 24;

    var cval: f32 = undefined;
    try testing.expect(get(&c, .@"font-size", &cval));
    try testing.expectEqual(@as(f32, 24), cval);
}

test "enum" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.@"window-theme" = .dark;

    var cval: [*:0]u8 = undefined;
    try testing.expect(get(&c, .@"window-theme", @ptrCast(&cval)));

    const str = std.mem.sliceTo(cval, 0);
    try testing.expectEqualStrings("dark", str);
}

test "color" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();
    c.background = .{ .r = 255, .g = 0, .b = 0 };

    var cval: c_uint = undefined;
    try testing.expect(get(&c, .background, @ptrCast(&cval)));
    try testing.expectEqual(@as(c_uint, 255), cval);
}

test "optional" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var c = try Config.default(alloc);
    defer c.deinit();

    {
        c.@"unfocused-split-fill" = null;
        var cval: c_uint = undefined;
        try testing.expect(!get(&c, .@"unfocused-split-fill", @ptrCast(&cval)));
    }

    {
        c.@"unfocused-split-fill" = .{ .r = 255, .g = 0, .b = 0 };
        var cval: c_uint = undefined;
        try testing.expect(get(&c, .@"unfocused-split-fill", @ptrCast(&cval)));
        try testing.expectEqual(@as(c_uint, 255), cval);
    }
}
