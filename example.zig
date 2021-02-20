const std = @import("std");
const zigcord = @import("zigcord");

fn handler(state: zigcord.Context, data: []const u8) void {
    std.debug.print("handling bytes: {s}\n", .{data});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const token_file = try std.fs.cwd().openFile(".token", .{});
    defer token_file.close();

    const token = try token_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(token);

    try zigcord.connect(allocator, token, .{ .guild_messages = true }, handler);
}
