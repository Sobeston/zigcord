const std = @import("std");
const zigcord = @import("zigcord");

fn handler(state: *zigcord.Conn, event: zigcord.Event) void {
    switch (event) {
        .message_create => |msg| {
            std.debug.print(
                \\{s}: "{s}"
                \\
            , .{msg.author.username, msg.content});
        },
        .ready => |ready| {
            std.debug.print("{s} (ID: {s}) connected\n", .{
                ready.user.username, ready.user.id
            });
        },
        else => {},
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
