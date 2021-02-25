const std = @import("std");
const zigcord = @import("zigcord");

fn handler(state: *zigcord.Conn, event: zigcord.Event) void {
    switch (event) {
        .message_create => |msg| {
            std.debug.print("{}\n", .{msg});
        },
        .unknown => |unk| {
            std.debug.print("unknown event:\n{s}\n", .{unk});
        },
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const token_file = try std.fs.cwd().openFile(".token", .{});
    defer token_file.close();

    const token = try token_file.readToEndAlloc(allocator, 1024);
    defer allocator.free(token);

    try zigcord.Conn.create(allocator, token, .{ .guild_messages = true }, handler);
}
