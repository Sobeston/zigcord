const std = @import("std");
const hzzp = @import("hzzp");
const iguanatls = @import("iguanatls");
const wz = @import("wz");

const TLS = iguanatls.Client(std.net.Stream.Reader, std.net.Stream.Writer, iguanatls.ciphersuites.all, false);
const WSS = wz.base.client.BaseClient(TLS.Reader, TLS.Writer);
pub const HTTPS = hzzp.base.client.BaseClient(TLS.Reader, TLS.Writer);

pub const Intents = packed struct {
    guilds: bool = false,
    guild_members: bool = false,
    guild_bans: bool = false,
    guild_emojis: bool = false,
    guild_integrations: bool = false,
    guild_webhooks: bool = false,
    guild_invites: bool = false,
    guild_voice_Contexts: bool = false,
    guild_presences: bool = false,
    guild_messages: bool = false,
    guild_message_reactions: bool = false,
    guild_message_typing: bool = false,
    direct_messages: bool = false,
    direct_message_reactions: bool = false,
    direct_message_typing: bool = false,
};

pub const Context = struct {
    https: *HTTPS,
    allocator: *std.mem.Allocator,
};

pub fn connect(
    allocator: *std.mem.Allocator,
    token: []const u8,
    intents: Intents,
    handler: fn (Context, []const u8) void,
) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rand = &prng.random;

    const http_sock = try std.net.tcpConnectToHost(allocator, domains.main, 443);
    var https_socket = try iguanatls.client_connect(.{
        .cert_verifier = .none,
        .reader = http_sock.reader(),
        .writer = http_sock.writer(),
        .rand = rand,
        .temp_allocator = allocator,
    }, domains.main);

    var https_buf: [256]u8 = undefined;
    var https = hzzp.base.client.create(
        &https_buf,
        https_socket.reader(),
        https_socket.writer(),
    );

    const gatewayURL = try getGatewayURL(&https, allocator);

    const ws_sock = try std.net.tcpConnectToHost(allocator, gatewayURL["wss://".len..], 443);
    var wss_socket = try iguanatls.client_connect(.{
        .cert_verifier = .none,
        .reader = ws_sock.reader(),
        .writer = ws_sock.writer(),
        .rand = rand,
        .temp_allocator = allocator,
    }, gatewayURL["wss://".len..]);

    var wss_buf: [256]u8 = undefined;
    var wss = wz.base.client.create(
        &wss_buf,
        wss_socket.reader(),
        wss_socket.writer(),
    );

    try wss.handshakeStart("/?v=8&encoding=json");
    try wss.handshakeAddHeaderValue("Host", gatewayURL["wss://".len..]);
    try wss.handshakeAddHeaderValue("authorization", token);
    try wss.handshakeAddHeaderValue("User-Agent", user_agent);
    try wss.handshakeFinish();

    var got_hello = false;
    var heartbeat_ms: usize = undefined;
    var time_since_last_heartbeat: std.time.Timer = undefined;
    _ = (try wss.next()).?;
    if (try wss.next()) |ev| {
        const chunk = ev.chunk;
        var parser = std.json.Parser.init(allocator, true);
        defer parser.deinit();
        var tree = try parser.parse(chunk.data);
        defer tree.deinit();
        if (tree.root != .Object) return error.InvalidHelloReceived;
        if (tree.root.Object.get("op")) |op| {
            if (op != .Integer) return error.InvalidHelloReceived;
            if (op.Integer != 10) return error.InvalidHelloReceived;
        } else return error.InvalidHelloReceived;
        if (tree.root.Object.get("d")) |d| {
            if (d != .Object) return error.InvalidHelloReceived;
            if (d.Object.get("heartbeat_interval")) |beat_interval| {
                if (beat_interval != .Integer) return error.InvalidHelloReceived;
                heartbeat_ms = @intCast(u32, beat_interval.Integer);
                time_since_last_heartbeat = std.time.Timer.start() catch unreachable;
                got_hello = true;
            } else return error.InvalidHelloReceived;
        } else return error.InvalidHelloReceived;
    }
    if (!got_hello) return error.NoHelloReceived;

    var tmp = std.ArrayList(u8).init(allocator);
    defer tmp.deinit();
    try tmp.writer().print(
        \\{{
        \\  "op":2,
        \\  "d":{{
        \\      "token":"{s}",
        \\      "intents":{d},
        \\      "properties":{{
        \\          "$os":"{s}",
        \\          "$browser":"{s}",
        \\          "$device":"{s}"
        \\      }}
        \\  }}
        \\}}
    ,
        .{ token, @bitCast(std.meta.Int(.unsigned, @bitSizeOf(Intents)), intents),  @tagName(std.builtin.Target.current.os.tag), user_agent, user_agent },
    );

    try wss.writeHeader(.{ .opcode = .Text, .length = tmp.items.len });
    try wss.writeChunk(tmp.items);

    var discord_event_buffer = std.ArrayList(u8).init(allocator);
    defer discord_event_buffer.deinit();
    while (try wss.next()) |event| {
        switch (event) {
            .header => {},
            .chunk => |c| {
                try discord_event_buffer.appendSlice(c.data);
                if (c.final) {
                    handler(.{ .https = &https, .allocator = allocator }, discord_event_buffer.items);
                    discord_event_buffer.shrinkAndFree(0);
                }
            },
        }
    }
}

/// caller must free returned memory
fn getGatewayURL(https: *HTTPS, allocator: *std.mem.Allocator) ![]const u8 {
    var gateway: []const u8 = &[_]u8{};
    try https.writeStatusLine("GET", endpoints.gateway);
    try https.writeHeader(.{ .name = "Host", .value = domains.main });
    try https.finishHeaders();
    try https.writePayload(null);
    while (try https.next()) |event| switch (event) {
        .payload => |pl| {
            var parser = std.json.Parser.init(allocator, true);
            defer parser.deinit();
            var tree = try parser.parse(pl.data);
            defer tree.deinit();
            if (tree.root != .Object) return error.InvalidGatewayResponse;
            if (tree.root.Object.get("url")) |url| {
                if (url != .String) return error.InvalidGatewayResponse;
                return allocator.dupe(u8, url.String);
            } else return error.InvalidGatewayResponse;
        },
        .end => break,
        else => continue,
    };
    return error.NoGatewayResponse;
}

const domains = struct {
    const main = "discordapp.com";
};

const user_agent = "zigcord/0.0.1";

const endpoints = struct {
    const api = "/api";
    const gateway = api ++ "/gateway";
};
