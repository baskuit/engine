//! Code generated by `tools/generate` - manual edits will be overwritten.

const gen1 = @import("../../gen1/data.zig");
const std = @import("std");

const assert = std.debug.assert;
const Effectiveness = gen1.Effectiveness;

const S = Effectiveness.Super;
const N = Effectiveness.Neutral;
const R = Effectiveness.Resisted;
const I = Effectiveness.Immune;

/// Representation of a Generation II type in Pokémon.
pub const Type = enum(u8) {
    Ground,
    Rock,
    Steel,
    Normal,
    Fighting,
    Flying,
    Poison,
    Bug,
    Ghost,
    @"???",
    Fire,
    Water,
    Grass,
    Electric,
    Psychic,
    Ice,
    Dragon,
    Dark,

    const CHART: [18][18]Effectiveness = .{
        [_]Effectiveness{ N, S, S, N, N, I, S, R, N, N, S, N, R, S, N, N, N, N }, // Ground
        [_]Effectiveness{ R, N, R, N, R, S, N, S, N, N, S, N, N, N, N, S, N, N }, // Rock
        [_]Effectiveness{ N, S, R, N, N, N, N, N, N, N, R, R, N, R, N, S, N, N }, // Steel
        [_]Effectiveness{ N, R, R, N, N, N, N, N, I, N, N, N, N, N, N, N, N, N }, // Normal
        [_]Effectiveness{ N, S, S, S, N, R, R, R, I, N, N, N, N, N, R, S, N, S }, // Fighting
        [_]Effectiveness{ N, R, R, N, S, N, N, S, N, N, N, N, S, R, N, N, N, N }, // Flying
        [_]Effectiveness{ R, R, I, N, N, N, R, N, R, N, N, N, S, N, N, N, N, N }, // Poison
        [_]Effectiveness{ N, N, R, N, R, R, R, N, R, N, R, N, S, N, S, N, N, S }, // Bug
        [_]Effectiveness{ N, N, R, I, N, N, N, N, S, N, N, N, N, N, S, N, N, R }, // Ghost
        [_]Effectiveness{ N, N, N, N, N, N, N, N, N, N, N, N, N, N, N, N, N, N }, // ???
        [_]Effectiveness{ N, R, S, N, N, N, N, S, N, N, R, R, S, N, N, S, R, N }, // Fire
        [_]Effectiveness{ S, S, N, N, N, N, N, N, N, N, S, R, R, N, N, N, R, N }, // Water
        [_]Effectiveness{ S, S, R, N, N, R, R, R, N, N, R, S, R, N, N, N, R, N }, // Grass
        [_]Effectiveness{ I, N, N, N, N, S, N, N, N, N, N, S, R, R, N, N, R, N }, // Electric
        [_]Effectiveness{ N, N, R, N, S, N, S, N, N, N, N, N, N, N, R, N, N, I }, // Psychic
        [_]Effectiveness{ S, N, R, N, N, S, N, N, N, N, R, R, S, N, N, R, S, N }, // Ice
        [_]Effectiveness{ N, N, R, N, N, N, N, N, N, N, N, N, N, N, N, N, S, N }, // Dragon
        [_]Effectiveness{ N, N, R, N, R, N, N, N, S, N, N, N, N, N, S, N, N, R }, // Dark
    };

    const PRECEDENCE = [_]u8{
        9, // Ground
        13, // Rock
        17, // Steel
        1, // Normal
        7, // Fighting
        10, // Flying
        8, // Poison
        12, // Bug
        14, // Ghost
        0, // ???
        2, // Fire
        3, // Water
        5, // Grass
        4, // Electric
        11, // Psychic
        6, // Ice
        15, // Dragon
        16, // Dark
    };

    const INDEXES = [_]u8{
        4, // Ground
        5, // Rock
        9, // Steel
        0, // Normal
        1, // Fighting
        2, // Flying
        3, // Poison
        7, // Bug
        8, // Ghost
        19, // ???
        20, // Fire
        21, // Water
        22, // Grass
        23, // Electric
        24, // Psychic
        25, // Ice
        26, // Dragon
        27, // Dark
    };

    const CONVERSION_2 = [_]Type{
        .Normal,
        .Fighting,
        .Flying,
        .Poison,
        .Ground,
        .Rock,
        .@"???", // placeholder
        .Bug,
        .Ghost,
        .Steel,
    };

    const HIDDEN_POWER = [_]Type{
        .Fighting,
        .Flying,
        .Poison,
        .Ground,
        .Rock,
        .Bug,
        .Ghost,
        .Steel,
        .Fire,
        .Water,
        .Grass,
        .Electric,
        .Psychic,
        .Ice,
        .Dragon,
        .Dark,
    };

    /// Order of Pokémon Showdown's types.
    pub const SHOWDOWN = [_]Type{
        .Fire,
        .Ice,
        .Steel,
        .Electric,
        .Ghost,
        .Grass,
        .Dark,
        .Bug,
        .Dragon,
        .Fighting,
        .Flying,
        .Ground,
        .Normal,
        .Poison,
        .Psychic,
        .Rock,
        .Water,
        .@"???",
    };

    comptime {
        assert(@bitSizeOf(Type) == 8);
        assert(@sizeOf(@TypeOf(CHART)) == 324);
        assert(@sizeOf(@TypeOf(PRECEDENCE)) == 18);
        assert(@sizeOf(@TypeOf(INDEXES)) == 18);
        assert(@sizeOf(@TypeOf(CONVERSION_2)) == 10);
        assert(@sizeOf(@TypeOf(HIDDEN_POWER)) == 16);
        assert(@sizeOf(@TypeOf(SHOWDOWN)) == 18);
    }

    /// The number of types in this generation.
    pub const size = 18;

    /// Whether or not this type is considered to be special as opposed to physical.
    pub fn special(self: Type) bool {
        return @intFromEnum(self) >= @intFromEnum(Type.Fire);
    }

    /// The `Effectiveness` of type `t2` vs. type `t1`.
    pub fn effectiveness(t1: Type, t2: Type) Effectiveness {
        return CHART[@intFromEnum(t1)][@intFromEnum(t2)];
    }

    /// The precedence order of Type `t1` vs. Type `t2`.
    pub fn precedence(t1: Type, t2: Type) u8 {
        // The Ice vs. Fire matchup is out of order - return a higher
        // number than anything else so that it sorts last correctly
        if (t1 == .Ice and t2 == .Fire) return 18;
        return PRECEDENCE[@intFromEnum(t2)];
    }

    /// The internal index of this Type used by Present.
    pub fn present(self: Type) u8 {
        return INDEXES[@intFromEnum(self)];
    }

    /// The Type corresponding to a random roll of `num` for Conversion 2.
    pub fn conversion2(num: u8) Type {
        assert(num != 6);
        assert(num < 10 or num >= 20);
        assert(num <= 27);
        return if (num < 10) CONVERSION_2[num] else @enumFromInt(num - 10);
    }

    /// The Type corresponding to a Hidden Power `index`.
    pub fn hiddenPower(index: u8) Type {
        return HIDDEN_POWER[index];
    }
};

/// Representation of a Pokémon's typing.
pub const Types = extern struct {
    /// A Pokémon's primary type.
    type1: Type = .Normal,
    /// A Pokémon's secondary type (may be identical to its primary type).
    type2: Type = .Normal,

    comptime {
        assert(@sizeOf(Types) == 2);
    }

    /// Whether this typing is immune to type `t`.
    pub fn immune(self: Types, t: Type) bool {
        return t.effectiveness(self.type1) == I or t.effectiveness(self.type2) == I;
    }

    /// Whether this typing includes type `t`.
    pub fn includes(self: Types, t: Type) bool {
        return self.type1 == t or self.type2 == t;
    }

    /// Whether this typing is immune to damage from Sandstorm.
    pub fn sandstormImmune(self: Types) bool {
        return @intFromEnum(self.type1) <= @intFromEnum(Type.Steel) or
            @intFromEnum(self.type2) <= @intFromEnum(Type.Steel);
    }
};
