const std = @import("std");

const test_tmpl = @import("tmpl.templates.test");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const test_data = &[_][]const i32{
        &.{ 0, 1, 2, 3, 4 },
        &.{ 5, 6, 7, 8, 9 },
        &.{ 0, 1, 2, 3, 4 },
        &.{ 5, 6, 7, 8, 9 },
        &.{ 0, 1, 2, 3, 4 },
        &.{ 5, 6, 7, 8, 9 },
        &.{ 0, 1, 2, 3, 4 },
        &.{ 5, 6, 7, 8, 9 },
        &.{ 0, 1, 2, 3, 4 },
        &.{ 5, 6, 7, 8, 9 },
    };

    for (test_data) |stuff| {
        for (stuff) |i| {
            _ = i;
        }
    }

    try test_tmpl.exec(allocator, buffer.writer().any(), test_data);

    std.debug.print("Result:\n{s}\n", .{buffer.items});
}
