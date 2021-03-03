const std = @import("std");
const hzzp = @import("hzzp");
const iguanatls = @import("iguanatls");
const wz = @import("wz");

const TLS = iguanatls.Client(std.net.Stream.Reader, std.net.Stream.Writer, iguanatls.ciphersuites.all, false);
const WSS = wz.base.client.BaseClient(TLS.Reader, TLS.Writer);
const HTTPS = hzzp.base.client.BaseClient(TLS.Reader, TLS.Writer);

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

fn heartbeatThread(self: *Conn) void {
    while (true) {
        std.time.sleep(self.ns_heartbeat_interval - std.time.ms_per_s * 500);
        const heartbeat =
            \\{
            \\    "op": 1,
            \\    "d": null
            \\}
        ;
        self.wss_client.writeHeader(.{ .opcode = .Text, .length = heartbeat.len }) catch return;
        self.wss_client.writeChunk(heartbeat) catch return;
    }
}

pub const Conn = struct {
    allocator: *std.mem.Allocator,
    prng: std.rand.DefaultPrng,

    gateway_url: []u8,
    intents: Intents,

    https_client: HTTPS,
    https_client_buf: [256]u8, //arbitrarily chosen; TODO: audit

    wss_client: WSS,
    wss_client_buf: [256]u8, //arbitrarily chosen; TODO: audit

    ns_heartbeat_interval: u64,
    last_sequence: std.atomic.Int(u64),
    session_id: ?[]u8,

    pub fn create(allocator: *std.mem.Allocator, token: []const u8, intents: Intents, handler: fn (*Conn, Event) void) !void {
        const self = try allocator.create(Conn);
        defer allocator.destroy(self);
        self.allocator = allocator;
        self.prng = std.rand.DefaultPrng.init(0);
        self.intents = intents;
        self.last_sequence = std.atomic.Int(u64).init(0);
        var prng = std.rand.DefaultPrng.init(0);
        const rand = &prng.random;

        //init https connection
        const http_sock = try std.net.tcpConnectToHost(self.allocator, domains.main, 443);
        var http_sock_TLS = try iguanatls.client_connect(.{
            .cert_verifier = .none,
            .reader = http_sock.reader(),
            .writer = http_sock.writer(),
            .rand = rand,
            .temp_allocator = self.allocator,
        }, domains.main);
        self.https_client = hzzp.base.client.create(
            &self.https_client_buf,
            http_sock_TLS.reader(),
            http_sock_TLS.writer(),
        );

        //ask discord for ws gateway URL
        self.gateway_url = try getGatewayURL(&self.https_client, self.allocator);
        defer self.allocator.free(self.gateway_url);

        //initialise wss connection
        const ws_sock = try std.net.tcpConnectToHost(allocator, self.gateway_url["wss://".len..], 443);
        var ws_socket_TLS = try iguanatls.client_connect(.{
            .cert_verifier = .none,
            .reader = ws_sock.reader(),
            .writer = ws_sock.writer(),
            .rand = rand,
            .temp_allocator = allocator,
        }, self.gateway_url["wss://".len..]);
        self.wss_client = wz.base.client.create(
            &self.wss_client_buf,
            ws_socket_TLS.reader(),
            ws_socket_TLS.writer(),
        );

        try self.wss_client.handshakeStart("/?v=8&encoding=json");
        try self.wss_client.handshakeAddHeaderValue("Host", self.gateway_url["wss://".len..]);
        try self.wss_client.handshakeAddHeaderValue("authorization", token);
        try self.wss_client.handshakeAddHeaderValue("User-Agent", user_agent);
        try self.wss_client.handshakeFinish();

        //skips the first header, parses the discord hello payload
        _ = (try self.wss_client.next()) orelse return error.NoHelloReceived;
        self.ns_heartbeat_interval = if (try self.wss_client.next()) |event| blk: {
            var parser = std.json.Parser.init(self.allocator, true);
            defer parser.deinit();
            var tree = try parser.parse(event.chunk.data);
            defer tree.deinit();

            const err = error.InvalidGatewayHello;
            const root_obj = switch (tree.root) {
                .Object => |root_obj| root_obj,
                else => return err,
            };

            switch (root_obj.get("op") orelse return err) {
                .Integer => |opcode| {
                    if (opcode != 10) return err;
                },
                else => return err,
            }

            break :blk switch (root_obj.get("d") orelse return err) {
                .Object => |d_obj| switch (d_obj.get("heartbeat_interval") orelse return err) {
                    .Integer => |x| @intCast(u32, x),
                    else => return err,
                },
                else => return err,
            } * @intCast(u64, std.time.ns_per_ms);
        } else return error.NoHelloReceived;

        //send identify payload
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
            .{
                token,
                @bitCast(std.meta.Int(.unsigned, @bitSizeOf(Intents)), intents),
                @tagName(std.builtin.Target.current.os.tag),
                user_agent,
                user_agent,
            },
        );
        try self.wss_client.writeHeader(.{ .opcode = .Text, .length = tmp.items.len });
        try self.wss_client.writeChunk(tmp.items);

        _ = try std.Thread.spawn(self, heartbeatThread);

        defer if (self.session_id) |s| self.allocator.free(s);

        //pass each discord event to handler
        var discord_event_buffer = std.ArrayList(u8).init(allocator);
        defer discord_event_buffer.deinit();
        var last_header: ?wz.base.client.MessageHeader = null;
        while (try self.wss_client.next()) |event| switch (event) {
            .header => |h| last_header = h,
            .chunk => |c| {
                try discord_event_buffer.appendSlice(c.data);
                if (!c.final) continue;
                defer discord_event_buffer.shrinkAndFree(0);

                if (last_header.opcode == .Close) {
                    const x = 
                    \\{
                    \\    "op": {d},
                    \\    "d": {
                    \\        "token": "{s}",
                    \\        "session_id": "{s}",
                    \\        "seq": {d}
                    \\    }
                    \\}
                    ;
                }

                var parser = std.json.Parser.init(self.allocator, true);
                defer parser.deinit();
                std.debug.print("{s}\n", .{discord_event_buffer.items});
                var tree = try parser.parse(discord_event_buffer.items);
                defer tree.deinit();

                const root_obj = switch (tree.root) {
                    .Object => |root_obj| root_obj,
                    else => return Event.err,
                };

                if (root_obj.get("s")) |s| switch (s) {
                    .Integer => |i| self.last_sequence.set(@intCast(u64, i)),
                    .Null => {},
                    else => {
                        return Event.err;
                    },
                };

                switch (switch (root_obj.get("op") orelse return Event.err) {
                    .Integer => |i| i,
                    else => return Event.err,
                }) {
                    0 => {
                        const ev = try Event.fromRaw(root_obj);
                        switch (ev) {
                            .ready => |r| {
                                self.session_id = try self.allocator.dupe(u8, r.session_id);
                            },
                            else => {},
                        }
                        handler(self, ev);
                    },
                    else => {},
                }
            },
        };
    }
};

/// caller must free returned memory
fn getGatewayURL(https: *HTTPS, allocator: *std.mem.Allocator) ![]u8 {
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

pub const Event = union(enum) {
    const err = error.InvalidEvent;
    message_create: MessageCreate,
    ready: Ready,
    unknown: std.json.ObjectMap,

    pub const MessageCreate = struct {
        id: []const u8,
        channel_id: []const u8,
        guild_id: []const u8,
        content: []const u8,
        author: struct {
            username: []const u8,
            id: []const u8,
        },
        pub fn format(
            self: MessageCreate,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print(
                \\MessageCreate{{
                \\    .id = "{s}",
                \\    .channel_id = "{s}",
                \\    .guild_id = "{s}",
                \\    .content = "{s}",
                \\    .author = {{
                \\        .username = "{s}",
                \\        .id = "{s}",
                \\    }}
                \\}}
            , .{ self.id, self.channel_id, self.guild_id, self.content, self.author.username, self.author.id });
        }
        fn parse(d: std.json.ObjectMap) !MessageCreate {
            const author = switch (d.get("author") orelse return err) {
                .Object => |o| o,
                else => return err,
            };

            return MessageCreate{
                .id = switch (d.get("id") orelse return err) {
                    .String => |s| s,
                    else => return err,
                },
                .channel_id = switch (d.get("channel_id") orelse return err) {
                    .String => |s| s,
                    else => return err,
                },
                .guild_id = switch (d.get("guild_id") orelse return err) {
                    .String => |s| s,
                    else => return err,
                },
                .content = switch (d.get("content") orelse return err) {
                    .String => |s| s,
                    else => return err,
                },
                .author = .{
                    .username = switch (author.get("username") orelse return err) {
                        .String => |s| s,
                        else => return err,
                    },
                    .id = switch (author.get("id") orelse return err) {
                        .String => |s| s,
                        else => return err,
                    },
                },
            };
        }
    };

    pub const Ready = struct {
        v: i64,
        session_id: []const u8,
        user: struct {
            username: []const u8,
            id: []const u8,
        },

        fn parse(d: std.json.ObjectMap) !Ready {
            const user = switch (d.get("user") orelse return err) {
                .Object => |o| o,
                else => return err,
            };

            return Ready{
                .v = switch (d.get("v") orelse return err) {
                    .Integer => |i| i,
                    else => return err,
                },
                .session_id = switch (d.get("session_id") orelse return err) {
                    .String => |s| s,
                    else => return err,
                },
                .user = .{
                    .username = switch (user.get("username") orelse return err) {
                        .String => |s| s,
                        else => return err,
                    },
                    .id = switch (user.get("id") orelse return err) {
                        .String => |s| s,
                        else => return err,
                    },
                },
            };
        }

        pub fn format(
            self: Ready,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print(
                \\Ready{{
                \\    .v = "{s}",
                \\    .session_id = "{s}",
                \\    .user = {{
                \\        .username = "{s}",
                \\        .id = "{s}",
                \\    }}
                \\}}
            , .{ self.v, self.session_id, self.user.username, self.user.id });
        }
    };

    fn fromRaw(root_obj: std.json.ObjectMap) !Event {
        const payload_string = switch (root_obj.get("t") orelse return err) {
            .String => |s| s,
            else => return err,
        };

        const d = switch (root_obj.get("d") orelse return err) {
            .Object => |o| o,
            else => return err,
        };

        if (std.mem.eql(u8, payload_string, "MESSAGE_CREATE"))
            return Event{ .message_create = try Event.MessageCreate.parse(d) };
        if (std.mem.eql(u8, payload_string, "READY"))
            return Event{ .ready = try Event.Ready.parse(d) };

        return Event{ .unknown = d };
    }
};

const domains = struct {
    const main = "discordapp.com";
};

const user_agent = "zigcord/0.0.1";

const endpoints = struct {
    const api = "/api";
    const gateway = api ++ "/gateway";
};
