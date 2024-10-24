/// Configured Options for the pkmn package.
pub const options = @import("common/options.zig");
/// Configures the behavior of the pkmn package.
pub const Options = options.Options;

/// The minimum size in bytes required to hold all choice options.
pub const MAX_CHOICES = gen1.MAX_CHOICES;
/// The optimal size in bytes required to hold all choice options.
/// At least as large as `MAX_CHOICES`.
pub const CHOICES_SIZE = gen1.CHOICES_SIZE;
/// The maximum number of bytes possibly logged by a single update.
pub const MAX_LOGS = gen1.MAX_LOGS;
/// The optimal size in bytes required to hold the largest amount of log data
/// possible from a single update. At least as large as `MAX_LOGS`.
pub const LOGS_SIZE = gen1.LOGS_SIZE;

/// Representation of one of the battle's participants.
pub const Player = @import("common/data.zig").Player;
/// A choice made by a player during battle.
pub const Choice = @import("common/data.zig").Choice;
/// The result of the battle - all results other than 'None' should be
/// considered terminal.
pub const Result = @import("common/data.zig").Result;

// TODO
pub const Array = @import("common/array.zig").Array;
// TODO
pub const Optional = @import("common/optional.zig").Optional;

/// Pokémon Showdown's RNG (backed by a Generation V & VI RNG).
pub const PSRNG = @import("common/rng.zig").PSRNG;

/// Namespace for helpers related to protocol message logging.
pub const protocol = if (options.internal) @import("common/protocol.zig") else struct {
    /// Logs protocol information to its `Writer` during a battle update when
    /// `options.log` is enabled.
    pub const Log = @import("common/protocol.zig").Log;
    /// Stripped down version of `std.io.FixedBufferStream` optimized for
    /// efficiently writing the individual protocol bytes. Note that the
    /// `ByteStream.Writer` is **not** a `std.io.Writer` and should not be
    /// used for general purpose writing.
    pub const ByteStream = @import("common/protocol.zig").ByteStream;
    /// `Log` type backed by the optimized `ByteStream.Writer`. Intended to be
    /// intialized with a `LOGS_SIZE`-sized buffer.
    pub const FixedLog = @import("common/protocol.zig").FixedLog;
    /// Null object pattern implementation of `Log` backed by a
    /// `std.io.null_writer`. Ignores anything sent to it, though protocol
    /// logging should additionally be turned off entirely with `options.log`.
    pub const NULL = @import("common/protocol.zig").NULL;
};

pub usingnamespace @import("common/rational.zig");

/// Namespace for cross-generation battle-related types.
pub const battle = @import("common/battle.zig");

/// Namespace for Generation I Pokémon.
pub const gen1 = struct {
    pub usingnamespace @import("gen1/data.zig");
    /// Tracks chance actions and their associated probability during a
    /// Generation I battle update when `options.chance` is enabled.
    pub const Chance = @import("gen1/chance.zig").Chance;
    /// Namespace for types associated with tracking Generation I Pokémon chance outcomes.
    pub const chance = struct {
        /// Actions taken by a hypothetical "chance player" that convey
        /// information about which RNG events were observed during a Generation
        /// I battle `update`. This can additionally be provided as input to the
        /// `update` call via the `Calc` when `options.calc` is enabled to
        /// override the normal behavior of the RNG in order to force specific
        /// outcomes.
        pub const Actions = @import("gen1/chance.zig").Actions;
        /// Information about the RNG that was observed during a Generation I
        /// battle `update` for a single player.
        pub const Action = @import("gen1/chance.zig").Action;
        /// TODO
        pub const Durations = @import("gen1/chance.zig").Durations;
        /// TODO
        pub const Duration = @import("gen1/chance.zig").Duration;
        /// Null object pattern implementation of Generation I `Chance` which
        /// does nothing, though chance tracking should additionally be turned
        /// off entirely via `options.chance`.
        pub const NULL = @import("gen1/chance.zig").NULL;
    };
    /// Allows for forcing the value of specific RNG events during a Generation I battle `update`
    /// via `overrides` and tracks `summaries` of information relevant to damage calculation.
    pub const Calc = @import("gen1/calc.zig").Calc;
    /// Namespace for types associated with supported Generation I Pokémon damage calc features.
    pub const calc = if (options.internal) @import("gen1/calc.zig") else struct {
        /// Information relevant to damage calculation that occured during a Generation I
        /// battle `update`.
        pub const Summaries = @import("gen1/calc.zig").Summaries;
        /// Information relevant to damage calculation that occured during a Generation I
        /// battle `update` for a single player.
        pub const Summary = @import("gen1/calc.zig").Summary;
        /// Null object pattern implementation of Generation I `Calc` which does nothing,
        /// though damage calculator support should additionally be turned off
        /// entirely via `options.calc`.
        pub const NULL = @import("gen1/calc.zig").NULL;
        /// TODO
        pub const MAX_FRONTIER = @import("gen1/calc.zig").MAX_FRONTIER;
        /// TODO
        pub const Rolls = @import("gen1/calc.zig").Rolls;
    };
    /// Provides helpers for initializing Generation I Pokémon battles.
    pub const helpers = @import("gen1/helpers.zig");
};

/// TODO
pub const gen2 = struct {
    pub usingnamespace @import("gen2/data.zig");
    pub const Chance = @import("gen2/chance.zig").Chance;
    pub const chance = struct {
        pub const Actions = @import("gen2/chance.zig").Actions;
        pub const Action = @import("gen2/chance.zig").Action;
        pub const Durations = @import("gen2/chance.zig").Durations;
        pub const Duration = @import("gen2/chance.zig").Duration;
        pub const NULL = @import("gen2/chance.zig").NULL;
    };
    pub const Calc = @import("gen2/calc.zig").Calc;
    pub const calc = if (options.internal) @import("gen2/calc.zig") else struct {
        pub const Summaries = @import("gen2/calc.zig").Summaries;
        pub const Summary = @import("gen2/calc.zig").Summary;
        pub const NULL = @import("gen2/calc.zig").NULL;
    };
    pub const helpers = @import("gen2/helpers.zig");
};

// Internal APIs used by other pkmn libraries, not actually part of the public API.
// NOTE: `pub usingnamespace struct { ... }` here results in a (false?) dependency loop
pub const js = if (options.internal) @import("common/js.zig") else {};
pub const bindings = if (options.internal) struct {
    pub const c = @import("bindings/c.zig");
    pub const node = @import("bindings/node.zig");
    pub const wasm = @import("bindings/wasm.zig");
} else {};
