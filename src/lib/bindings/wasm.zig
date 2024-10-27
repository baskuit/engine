const pkmn = @import("../pkmn.zig");
const std = @import("std");

const assert = std.debug.assert;

const Enum = if (@hasField(std.builtin.Type, "enum")) .@"enum" else .Enum;
const Strong = if (@hasField(std.builtin.GlobalLinkage, "strong")) .strong else .Strong;

pub const options = pkmn.options;

pub fn gen(comptime num: comptime_int) type {
    const g = @field(pkmn, "gen" ++ std.fmt.comptimePrint("{d}", .{num}));
    return struct {
        pub const CHOICES_SIZE = size(g.CHOICES_SIZE);
        pub const LOGS_SIZE = size(g.LOGS_SIZE);

        pub fn update(
            battle: *g.Battle(g.PRNG),
            c1: pkmn.Choice,
            c2: pkmn.Choice,
            options_: ?[*]u8,
        ) callconv(.C) pkmn.Result {
            return (if (options_) |o| result: {
                const buf = @as([*]u8, @ptrCast(o))[0..g.LOGS_SIZE];
                var stream: pkmn.protocol.ByteStream = .{ .buffer = buf };
                // TODO: extract out
                var opts = pkmn.battle.options(
                    pkmn.protocol.FixedLog{ .writer = stream.writer() },
                    g.chance.NULL,
                    g.calc.NULL,
                );
                break :result battle.update(c1, c2, &opts);
            } else battle.update(c1, c2, &g.NULL)) catch unreachable;
        }

        pub fn choices(
            battle: *g.Battle(g.PRNG),
            player: u8,
            request: u8,
            buf: [*]u8,
        ) callconv(.C) u8 {
            assert(player <= @field(@typeInfo(pkmn.Player), @tagName(Enum)).fields.len);
            assert(request <= @field(@typeInfo(pkmn.Choice.Type), @tagName(Enum)).fields.len);

            const n = CHOICES_SIZE;
            return battle.choices(@enumFromInt(player), @enumFromInt(request), @ptrCast(buf[0..n]));
        }
    };
}

pub fn exports() type {
    @export(gen(1).update, .{ .name = "GEN1_update", .linkage = Strong });
    @export(gen(1).choices, .{ .name = "GEN1_choices", .linkage = Strong });
    return struct {};
}

fn size(n: usize) u32 {
    return std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(n))) catch unreachable;
}
