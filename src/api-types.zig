pub const String = []const u8;
pub const UInt = u53;
pub const Unknown = u8;
pub const Snowflake = String;
pub const Timestamp = i32;

pub const Hello = struct {
    t: ?String,
    s: ?UInt,
    op: u53,
    d: struct {
        heartbeat_interval: u53,
        _trace: [][]u8,
    },
};

pub const Identify = struct {
    op: UInt = 2,
    d: struct {
        token: String,
        properties: struct {
            @"$os": String,
            @"$browser": String,
            @"$device": String,
        },
        compress: ?bool = null,
        large_threshold: ?UInt = null,
        guild_subscriptions: ?bool = null,
        shard: ?[2]UInt = null,
        presence: ?struct {
            game: struct {
                name: String,
                @"type": UInt, 
            },
            status: String,
            since: UInt,
            afk: bool,
        } = null,
        intents: ?UInt = null,
    },
};

// pub const GuildCreate = struct {
//     t: String,
//     s: UInt,
//     op: UInt, 
//     d: struct {
//         id: Snowflake,
//         name: String,
//     },
// };

/// not an actual discord api type
pub const Stub = struct {
    t: ?String,
    s: ?UInt,
};

pub const MessageCreate = struct {
    t: String,
    s: UInt,
    op: UInt,
    d: struct {
        content: String,
        channel_id: String,
        guild_id: String,
        id: String,
    },
};

pub const GuildCreate = struct {
    t: String,
    s: UInt,
    op: UInt,
    d: struct {
        id: Snowflake,
        name: String,
        // icon: ?String,
        // splash: ?String,
        // discovery_splash: ?String,
        // owner_id: String,
        // permissions: UInt,
        // region: String,
        // afk_channel_id: ?Snowflake,
        // afk_timeout: UInt,
        // verification_level: UInt,
        // default_message_notifications: UInt,
        // explicit_content_filter: UInt,
        // roles: []Role,
        // emojis: []User,
        // features: []GuildFeature,
        // mfa_level: UInt,
        // application_id: ?Snowflake,
        // system_channel_id: ?Snowflake,
        // system_channel_flags: UInt,
        // rules_channel_id: ?Snowflake,
        // joined_at: Timestamp,
        // large: bool,
        // unavailable: bool,
        // member_count: bool,
        // voice_states: []VoiceState,
        // members: []GuildMember,
        // channels: []Channel,
        // presences: []Presence,
        // vanity_url_code: ?String,
        // description: ?String,
        // banner: ?String,
        // premium_tier: UInt,
        // premium_subscription_count: ?UInt,
        // preferred_locale: String,
        // public_updates_channel_id: ?Snowflake,
        // max_video_channel_users: UInt,
    },
};

pub const User = struct {};
pub const Channel = struct {};
pub const Presence = struct {};

pub const GuildFeature = []const u8;

pub const Role = struct {
    id: Snowflake,
    name: String,
    color: UInt,
    hoist: bool,
    position: UInt,
    permissions: UInt,
    managed: bool,
    mentionable: bool,
};

pub const Emoji = struct {
    id: ?Snowflake,
    name: ?String,
};

pub const GuildMember = struct {
    user: struct {
        username: String,
    },
    nick: ?String,
    roles: []Snowflake,
    joined_at: Timestamp,
    deaf: bool,
    mute: bool,
};

pub const VoiceState = struct {

};