const std = @import("std");
const builtin = @import("builtin");

const pkmn = @import("../pkmn.zig");

const data = @import("../common/data.zig");
const protocol = @import("../common/protocol.zig");
const rng = @import("../common/rng.zig");
const util = @import("../common/util.zig");

const moves = @import("data/moves.zig");
const species = @import("data/species.zig");
const types = @import("data/types.zig");

const calc = @import("calc.zig");
const chance = @import("chance.zig");
const mechanics = @import("mechanics.zig");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

/// The minimum size in bytes required to hold all Generation I choice options.
pub const MAX_CHOICES: usize = 9; // move 1..4, switch 2..6
/// The optimal size in bytes required to hold all Generation I choice options.
/// At least as large as MAX_CHOICES.
pub const MAX_LOGS: usize = 180;

/// The maximum number of bytes possibly logged by a single Generation I update.
pub const CHOICES_SIZE = if (builtin.mode == .ReleaseSmall)
    MAX_CHOICES
else
    std.math.ceilPowerOfTwo(usize, MAX_CHOICES) catch unreachable;
/// The optimal size in bytes required to hold the largest amount of log data possible from a
/// single Generation I update. At least as large as MAX_LOGS.
pub const LOGS_SIZE = if (builtin.mode == .ReleaseSmall)
    MAX_LOGS
else
    std.math.ceilPowerOfTwo(usize, MAX_LOGS) catch unreachable;

///  Null object pattern implementation of pkmn.battle.Options for Generation I.
pub const NULL = pkmn.battle.options(protocol.NULL, chance.NULL, calc.NULL);

const Choice = data.Choice;
const ID = data.ID;
const Player = data.Player;
const Result = data.Result;

const PointerType = util.PointerType;

const showdown = pkmn.options.showdown;

/// The pseudo random number generator used by Generation I.
pub const PRNG = rng.PRNG(1);

/// Representation of a Generation I battle.
pub fn Battle(comptime RNG: anytype) type {
    return extern struct {
        const Self = @This();

        /// The sides involved in the battle.
        sides: [2]Side,
        /// The battle's current turn number.
        turn: u16 = 0,
        /// The last damage dealt by either side.
        last_damage: u16 = 0,
        /// Details about the last move selected/used by each player required to detect desyncs.
        last_moves: [2]MoveDetails = [_]MoveDetails{.{}} ** 2,
        /// The pseudo random number generator.
        rng: RNG,

        /// Returns the `Side` for the given `player`.
        pub fn side(self: anytype, player: Player) PointerType(@TypeOf(self), Side) {
            assert(@typeInfo(@TypeOf(self)).Pointer.child == Self);
            return &self.sides[@intFromEnum(player)];
        }

        /// Returns the `Side` of the opponent for the given `player`
        pub fn foe(self: anytype, player: Player) PointerType(@TypeOf(self), Side) {
            assert(@typeInfo(@TypeOf(self)).Pointer.child == Self);
            return &self.sides[@intFromEnum(player.foe())];
        }

        /// Returns an identifier for the active Pokémon of `player`.
        pub fn active(self: *const Self, player: Player) ID {
            return player.ident(@intCast(self.side(player).order[0]));
        }

        /// Returns the `MoveDetails` for the given `player`.
        pub fn lastMove(
            self: anytype,
            player: Player,
        ) PointerType(@TypeOf(self), MoveDetails) {
            assert(@typeInfo(@TypeOf(self)).Pointer.child == Self);
            return &self.last_moves[@intFromEnum(player)];
        }

        /// Returns the result of applying Player 1's choice `c1` and Player 2's choice `c2` to the
        /// battle, optionally writing protocol message logs to `options.log` if `pkmn.options.log`
        /// is enabled.
        pub fn update(self: *Self, c1: Choice, c2: Choice, options: anytype) !Result {
            return mechanics.update(self, c1, c2, options);
        }

        /// Fills in at most `out.len` possible choices for the `player` given the previous `result`
        /// of an `update` and Generation I battle state and returns the number of choices
        /// available. Note that reading values in `out` which occur at indexes > the return value
        /// of this function could result in reading potentially garbage data.
        ///
        /// This function may return 0 due to how the Transform + Mirror Move/Metronome PP error
        /// interacts with Disable, in which case there are no possible choices for the player to
        /// make (i.e. on the cartridge a soft-lock occurs).
        ///
        /// This function will always return choices > 0 if `pkmn.options.showdown` is true.
        pub fn choices(self: *const Self, player: Player, request: Choice.Type, out: []Choice) u8 {
            return mechanics.choices(self, player, request, out);
        }

        pub fn choices_no_switch(self: *const Self, player: Player, request: Choice.Type, out: []Choice) u8 {
            return mechanics.choices_no_switch(self, player, request, out);
        }
    };
}

test Battle {
    try expectEqual(384, @sizeOf(Battle(PRNG)));
}

/// Representation of one side of a Generation I Pokémon battle.
pub const Side = extern struct {
    /// The player's party in its original order
    pokemon: [6]Pokemon = [_]Pokemon{.{}} ** 6,
    /// The active Pokémon for the side, zero initialized if the battle has yet to start.
    /// Note that fainted Pokémon are still consider "active" until their replacement switches in.
    active: ActivePokemon = .{},
    /// One-based slot indexes reflecting the current order of the player's party.
    order: [6]u8 = [_]u8{0} ** 6,
    /// The last move the player selected.
    last_selected_move: Move = .None,
    /// The last move the player used.
    last_used_move: Move = .None,

    comptime {
        assert(@sizeOf(Side) == 184);
    }

    /// Returns the stored `Pokemon` corresponding to the one-indexed party `slot`.
    pub fn get(self: anytype, slot: u8) PointerType(@TypeOf(self), Pokemon) {
        assert(@typeInfo(@TypeOf(self)).Pointer.child == Side);
        assert(slot > 0 and slot <= 6);
        const id = self.order[slot - 1];
        assert(id > 0 and id <= 6);
        return &self.pokemon[id - 1];
    }

    /// Returns the stored `Pokemon` corresponding to the `active` Pokémon (slot 1).
    pub fn stored(self: anytype) PointerType(@TypeOf(self), Pokemon) {
        assert(@typeInfo(@TypeOf(self)).Pointer.child == Side);
        return self.get(1);
    }
};

/// Representation of the state for single Generation I Pokémon while active in battle.
pub const ActivePokemon = extern struct {
    /// The active Pokémon's modified stats.
    stats: Stats(u16) = .{},
    /// The active Pokémon's current species.
    species: Species = .None,
    /// The active Pokémon's current types.
    types: Types = .{},
    /// The active Pokémon's boosts.
    boosts: Boosts = .{},
    /// The active Pokémon's volatile statuses and associated data.
    volatiles: Volatiles = .{},
    /// The active Pokémon's current move slots.
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,

    comptime {
        assert(@sizeOf(ActivePokemon) == 32);
    }

    /// Returns the active Pokémon's current move slot located at the one-indexed `mslot`.
    pub fn move(self: anytype, mslot: u8) PointerType(@TypeOf(self), MoveSlot) {
        assert(@typeInfo(@TypeOf(self)).Pointer.child == ActivePokemon);
        assert(mslot > 0 and mslot <= 4);
        assert(self.moves[mslot - 1].id != .None);
        return &self.moves[mslot - 1];
    }
};

/// Representation of the state for single Generation I Pokémon while inactive in the party.
pub const Pokemon = extern struct {
    /// The Pokémon's unmodified stats.
    stats: Stats(u16) = .{},
    /// The Pokémon's original stored move slots.
    moves: [4]MoveSlot = [_]MoveSlot{.{}} ** 4,
    /// The Pokémon's current HP.
    hp: u16 = 0,
    /// The Pokémon's current status.
    status: u8 = 0,
    /// The Pokémon's original species.
    species: Species = .None,
    /// The Pokémon's original types.
    types: Types = .{},
    /// The Pokémon's level.
    level: u8 = 100,

    comptime {
        assert(@sizeOf(Pokemon) == 24);
    }

    /// Returns the Pokémon's original move slot located at the one-indexed `mslot`.
    pub fn move(self: anytype, mslot: u8) PointerType(@TypeOf(self), MoveSlot) {
        assert(@typeInfo(@TypeOf(self)).Pointer.child == Pokemon);
        assert(mslot > 0 and mslot <= 4);
        assert(self.moves[mslot - 1].id != .None);
        return &self.moves[mslot - 1];
    }
};

/// Representation of a Generation I Pokémon's move slot in a battle.
pub const MoveSlot = extern struct {
    /// The identifier for the move.
    id: Move = .None,
    /// The remaining PP of the move.
    pp: u8 = 0,

    comptime {
        assert(@sizeOf(MoveSlot) == 2);
    }
};

/// Details required to detect desyncs based on the move last selected/executed by players.
pub const MoveDetails = packed struct(if (showdown) u16 else u8) {
    /// The move slot index of the last move selected in the battle menu.
    index: if (showdown) u8 else u4 = 0,
    /// Whether the last move executed was counterable.
    counterable: if (showdown) u8 else u4 = 0,
};

/// Bitfield representation of a Generation I & II Pokémon's major status condition.
pub const Status = enum(u8) {
    // 0 and 1 bits are also used for SLP
    SLP = 2,
    PSN = 3,
    BRN = 4,
    FRZ = 5,
    PAR = 6,
    // In Generation I & II, the "badly poisoned" status is marked with Volatiles.Toxic instead of
    // being via a TOX status, however we need to use this top bit for Pokémon Showdown quirks:
    //
    //   - when combined with a valid sleep duration (or 0), it indicates that the `SLP` status was
    //     self-inflicted (required in order to implement Pokémon Showdown's "Sleep Clause Mod")
    //   - when combined with `PSN` it indicates that the Pokémon is actually badly poisoned
    //     (required in order to send the same incorrect protocol messages as Pokémon Showdown - the
    //     Toxic volatile alone is not sufficient in compatibility mode because it gets lost on
    //     switch)
    EXT = 7,

    pub const TOX = 0b10001000;

    const SLP = 0b111;

    /// Whether or not the status `num` is the same as `status`.
    pub fn is(num: u8, status: Status) bool {
        if (status == .SLP) return Status.duration(num) > 0;
        return ((num >> @intCast(@intFromEnum(status))) & 1) != 0;
    }

    /// Initializes a non-sleep `status`. Use `slp` or `slf` to initialize a sleep status.
    pub fn init(status: Status) u8 {
        assert(status != .SLP and status != .EXT);
        return @as(u8, 1) << @intCast(@intFromEnum(status));
    }

    /// Initializes a non self-inflicted sleep status with duration `dur`.
    pub fn slp(dur: u3) u8 {
        assert(dur > 0);
        return @as(u8, dur);
    }

    /// Initializes a self-inflicted sleep status with duration `dur`.
    pub fn slf(dur: u3) u8 {
        assert(dur > 0);
        return 0x80 | slp(dur);
    }

    /// Returns the duration of a sleep status.
    pub fn duration(num: u8) u3 {
        return @intCast(num & SLP);
    }

    /// Returns whether `num` reflects any status.
    pub fn any(num: u8) bool {
        return num > 0;
    }

    /// Returns a human-readable representation of the status `num`.
    pub fn name(num: u8) []const u8 {
        if (Status.is(num, .EXT)) return if (num == Status.TOX) "TOX" else "SLF";
        if (Status.is(num, .SLP)) return "SLP";
        if (Status.is(num, .PSN)) return "PSN";
        if (Status.is(num, .BRN)) return "BRN";
        if (Status.is(num, .FRZ)) return "FRZ";
        if (Status.is(num, .PAR)) return "PAR";
        return "OK";
    }
};

test Status {
    try expect(!Status.any(0));

    try expect(Status.is(Status.init(.PSN), .PSN));
    try expect(!Status.is(Status.init(.PSN), .PAR));
    try expect(Status.is(Status.init(.BRN), .BRN));
    try expect(!Status.is(Status.init(.FRZ), .SLP));
    try expect(Status.is(Status.init(.FRZ), .FRZ));

    try expect(!Status.is(0, .SLP));
    try expect(Status.is(Status.slp(5), .SLP));
    try expect(!Status.is(Status.slp(5), .EXT));
    try expect(!Status.is(Status.slp(7), .PSN));
    try expectEqual(5, Status.duration(Status.slp(5)));
    try expect(Status.is(Status.slf(2), .SLP));
    try expect(Status.is(Status.slf(2), .EXT));
    try expect(Status.is(Status.TOX, .PSN));
    try expect(Status.is(Status.TOX, .EXT));
    try expectEqual(1, Status.duration(Status.slp(1)));
}

/// Bitfield representation of volatile statuses and associated data in Generation I.
pub const Volatiles = packed struct(u64) {
    /// Whether the "Bide" volatile status is present.
    Bide: bool = false,
    /// Whether the "Thrashing" volatile status is present.
    Thrashing: bool = false,
    /// Whether the "MultiHit" volatile status is present.
    MultiHit: bool = false,
    /// Whether the "Flinch" volatile status is present.
    Flinch: bool = false,
    /// Whether the "Charging" volatile status is present.
    Charging: bool = false,
    /// Whether the "Binding" volatile status is present.
    Binding: bool = false,
    /// Whether the "Invulnerable" volatile status is present.
    Invulnerable: bool = false,
    /// Whether the "Confusion" volatile status is present.
    Confusion: bool = false,

    /// Whether the "Mist" volatile status is present.
    Mist: bool = false,
    /// Whether the "FocusEnergy" volatile status is present.
    FocusEnergy: bool = false,
    /// Whether the "Substitute" volatile status is present.
    Substitute: bool = false,
    /// Whether the "Recharging" volatile status is present.
    Recharging: bool = false,
    /// Whether the "Rage" volatile status is present.
    Rage: bool = false,
    /// Whether the "LeechSeed" volatile status is present.
    LeechSeed: bool = false,
    /// Whether the "Toxic" volatile status is present.
    Toxic: bool = false,
    /// Whether the "LightScreen" volatile status is present.
    LightScreen: bool = false,

    /// Whether the "Reflect" volatile status is present.
    Reflect: bool = false,
    /// Whether the "Transform" volatile status is present.
    Transform: bool = false,
    /// The remaining turns of confusion
    confusion: u3 = 0,
    /// The number of attacks remaining
    attacks: u3 = 0,

    /// A union of either:
    ///   - the total accumulated damage from Bide
    ///   - the overwritten accuracy of certain moves
    state: u16 = 0,
    /// The remaining HP of the Substitute.
    substitute: u8 = 0,
    /// The identity of whom the active Pokémon is transformed into.
    transform: u4 = 0,
    /// The remaining turns the move is disabled.
    disable_duration: u4 = 0,
    /// The move slot (1-4) that is disabled.
    disable_move: u3 = 0,
    /// The number of turns toxic damage has been accumulating.
    toxic: u5 = 0,
};

test Volatiles {
    var volatiles: Volatiles = .{};
    volatiles.Confusion = true;
    volatiles.confusion = 2;
    volatiles.Thrashing = true;
    volatiles.state = 235;
    volatiles.attacks = 3;
    volatiles.Substitute = true;
    volatiles.substitute = 42;
    volatiles.toxic = 4;
    volatiles.disable_move = 2;
    volatiles.disable_duration = 4;

    try expect(volatiles.Confusion);
    try expect(volatiles.Thrashing);
    try expect(volatiles.Substitute);
    try expect(!volatiles.Recharging);
    try expect(!volatiles.Transform);
    try expect(!volatiles.MultiHit);

    try expectEqual(235, volatiles.state);
    try expectEqual(42, volatiles.substitute);
    try expectEqual(2, volatiles.disable_move);
    try expectEqual(4, volatiles.disable_duration);
    try expectEqual(2, volatiles.confusion);
    try expectEqual(4, volatiles.toxic);
    try expectEqual(3, volatiles.attacks);
}

/// Representaiton of a Pokémon's stats in Generation I.
pub fn Stats(comptime T: type) type {
    return extern struct {
        hp: T = 0,
        atk: T = 0,
        def: T = 0,
        spe: T = 0,
        spc: T = 0,

        /// Computes the value of `stat` given a `base`, `dv`, stat `exp` and `level`.
        pub fn calc(comptime stat: []const u8, base: T, dv: u4, exp: u16, level: u8) T {
            assert(level > 0 and level <= 100);
            const float: f32 = @floatFromInt(exp);
            const evs: u16 = @min(255, @as(u16, @intFromFloat(@ceil(@sqrt(float)))));
            const core: u32 = (2 *% (@as(u32, base) +% dv)) +% (evs / 4);
            const factor: u32 = if (std.mem.eql(u8, stat, "hp")) level + 10 else 5;
            return @intCast(core *% @as(u32, level) / 100 +% factor);
        }
    };
}

test Stats {
    try expectEqual(5, @sizeOf(Stats(u8)));
    const stats = Stats(u16){ .atk = 2, .spe = 3 };
    try expectEqual(2, stats.atk);
    try expectEqual(0, stats.def);

    var base = Species.get(.Gyarados).stats;
    try expectEqual(127, Stats(u16).calc("hp", base.hp, 0, 5120, 38));
    base = Species.get(.Pidgeot).stats;
    try expectEqual(279, Stats(u16).calc("spe", base.spe, 15, 63001, 100));
}

/// Representation of a Pokémon's boosts in Generation I.
pub const Boosts = packed struct(u32) {
    /// A Pokémon's Attack boosts.
    atk: i4 = 0,
    /// A Pokémon's Defense boosts.
    def: i4 = 0,
    /// A Pokémon's Speed boosts.
    spe: i4 = 0,
    /// A Pokémon's Special boosts.
    spc: i4 = 0,
    /// A Pokémon's Accuracy boosts.
    accuracy: i4 = 0,
    /// A Pokémon's Evasion boosts.
    evasion: i4 = 0,

    _: u8 = 0,
};

test Boosts {
    const boosts: Boosts = .{ .spc = -6 };
    try expectEqual(0, boosts.atk);
    try expectEqual(-6, boosts.spc);
}

/// Representation of a Generation I Pokémon move.
pub const Move = moves.Move;

test Move {
    try expectEqual(2, @intFromEnum(Move.KarateChop));
    const move = Move.get(.Fissure);
    try expectEqual(Move.Effect.OHKO, move.effect);
    try expectEqual(rng.Gen12.percent(30), move.accuracy);
    try expectEqual(Type.Ground, move.type);

    try expect(!Move.Effect.onBegin(.None));
    try expect(Move.Effect.onBegin(.Confusion));
    try expect(Move.Effect.onBegin(.Transform));
    try expect(!Move.Effect.onBegin(.AccuracyDown1));

    try expect(!Move.Effect.isStatDown(.Transform));
    try expect(Move.Effect.isStatDown(.AccuracyDown1));
    try expect(Move.Effect.isStatDown(.SpeedDown1));
    try expect(!Move.Effect.isStatDown(.AttackUp1));

    try expect(!Move.Effect.onEnd(.Transform));
    try expect(Move.Effect.onEnd(.AccuracyDown1));
    try expect(Move.Effect.onEnd(.SpeedUp2));
    try expect(!Move.Effect.onEnd(.Charge));

    try expect(!Move.Effect.alwaysHappens(.SpeedUp2));
    try expect(Move.Effect.alwaysHappens(.DrainHP));
    try expect(Move.Effect.alwaysHappens(.Recoil));
    try expect(!Move.Effect.alwaysHappens(.Charge));
    try expect(!Move.Effect.alwaysHappens(.SpeedDownChance));
    try expect(Move.Effect.alwaysHappens(.Rage));

    // all considered "always happens" on cartridge
    try expect(!Move.Effect.alwaysHappens(.DoubleHit));
    try expect(!Move.Effect.alwaysHappens(.MultiHit));
    try expect(!Move.Effect.alwaysHappens(.Twineedle));

    try expect(!Move.Effect.isSpecial(.SpeedUp2));
    try expect(Move.Effect.isSpecial(.DrainHP));
    try expect(Move.Effect.isSpecial(.Rage)); // other on cartridge
    try expect(Move.Effect.isSpecial(.DoubleHit));
    try expect(Move.Effect.isSpecial(.MultiHit));
    try expect(!Move.Effect.isSpecial(.Twineedle));

    try expect(!Move.Effect.isMulti(.Thrashing));
    try expect(Move.Effect.isMulti(.DoubleHit));
    try expect(Move.Effect.isMulti(.MultiHit));
    try expect(Move.Effect.isMulti(.Twineedle));
    try expect(!Move.Effect.isMulti(.AttackDownChance));

    try expect(!Move.Effect.isStatDownChance(.Thrashing));
    try expect(Move.Effect.isStatDownChance(.AttackDownChance));
    try expect(Move.Effect.isStatDownChance(.SpecialDownChance));
    try expect(!Move.Effect.isStatDownChance(.BurnChance1));

    try expect(!Move.Effect.isSecondaryChance(.MultiHit));
    try expect(Move.Effect.isSecondaryChance(.Twineedle));
    try expect(Move.Effect.isSecondaryChance(.PoisonChance2));
    try expect(!Move.Effect.isSecondaryChance(.Disable));
}

/// Representation of a Generation I Pokémon species.
pub const Species = species.Species;

test Species {
    try expectEqual(2, @intFromEnum(Species.Ivysaur));
    try expectEqual(100, Species.get(.Mew).stats.def);
}

/// Representation of a Generation I type in Pokémon.
pub const Type = types.Type;
/// Representation of a Generation I Pokémon's typing.
pub const Types = types.Types;

/// Modifiers for the effectiveness of a type vs. another type in Pokémon.
pub const Effectiveness = enum(u8) {
    Immune = 0,
    Resisted = 5,
    Neutral = 10,
    Super = 20,

    /// Used to determine the effectiness of a neutral damage hit.
    pub const neutral: u16 =
        @intFromEnum(Effectiveness.Neutral) * @intFromEnum(Effectiveness.Neutral);
    /// Used to detect whether there is a mismatch in type effectivness (relevant for precedence).
    pub const mismatch: u16 =
        @intFromEnum(Effectiveness.Resisted) + @intFromEnum(Effectiveness.Super);

    comptime {
        assert(@sizeOf(Effectiveness) == 1);
    }
};

test Types {
    try expectEqual(14, @intFromEnum(Type.Dragon));
    try expectEqual(20, @intFromEnum(Effectiveness.Super));

    try expect(!Type.Ghost.special());
    try expect(Type.Dragon.special());

    try expectEqual(Effectiveness.Immune, Type.effectiveness(.Ghost, .Psychic));
    try expectEqual(Effectiveness.Super, Type.Water.effectiveness(.Fire));
    try expectEqual(Effectiveness.Resisted, Type.effectiveness(.Fire, .Water));
    try expectEqual(Effectiveness.Neutral, Type.effectiveness(.Normal, .Grass));

    try expectEqual(3, Type.precedence(.Water, .Water));
    try expectEqual(26, Type.precedence(.Bug, .Ghost));
    try expect(Type.precedence(.Poison, .Bug) > Type.precedence(.Poison, .Poison));

    const t: Types = .{ .type1 = .Rock, .type2 = .Ground };
    try expect(!t.immune(.Grass));
    try expect(t.immune(.Electric));

    try expect(!t.includes(.Fire));
    try expect(t.includes(.Rock));
}

/// Representation of a Generation I Pokémon's determinant values.
pub const DVs = struct {
    /// The Attack DV.
    atk: u4 = 15,
    /// The Defense DV.
    def: u4 = 15,
    /// The Speed DV.
    spe: u4 = 15,
    /// The Special DV.
    spc: u4 = 15,

    /// The computed HP DV.
    pub fn hp(self: DVs) u4 {
        return (self.atk & 1) << 3 | (self.def & 1) << 2 | (self.spe & 1) << 1 | (self.spc & 1);
    }

    /// Produces a random set of DVs given `rand`.
    pub fn random(rand: *rng.PSRNG) DVs {
        return .{
            .atk = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
            .def = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
            .spe = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
            .spc = if (rand.chance(u8, 1, 5)) rand.range(u4, 1, 15 + 1) else 15,
        };
    }
};

test DVs {
    var dvs: DVs = .{ .spc = 15, .spe = 15 };
    try expectEqual(15, dvs.hp());
    dvs = .{
        .atk = 5,
        .def = 15,
        .spe = 13,
        .spc = 13,
    };
    try expectEqual(15, dvs.hp());
    dvs = .{
        .def = 3,
        .spe = 10,
        .spc = 11,
    };
    try expectEqual(13, dvs.hp());
}
