const std = @import("std");
const zigcord = @import("zigcord");
const token = "Bot " ++ "";

fn handler(session: *zigcord.Session, event: zigcord.Event) !void {
    switch (event.data) {
        .message_create => |msg| {
            if (std.mem.eql(u8, msg.content, "ping")) {
                try session.sendMessage(msg.channel_id, "pong!");
            }
        },
        else => {},
    }
}

pub fn main() !void {
    var discord = try zigcord.Session.init(
        std.heap.page_allocator,
        @embedFile("../discordgg.pem"),
        @embedFile("../discordappcom.pem"),
    );
    try discord.connect();
    try discord.listen(token, handler);
}