const pkmn = @import("pkmn");
const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Choice = pkmn.Choice;
const protocol = pkmn.protocol;
const Rational = pkmn.Rational;

pub const pkmn_options = pkmn.Options{ .advance = false, .ebc = false, .key = true };

const gen1 = struct {
    const Actions = pkmn.gen1.chance.Actions;
    const Battle = pkmn.gen1.data.Battle;
    const Calc = pkmn.gen1.Calc;
    const Chance = pkmn.gen1.Chance;
    const Durations = pkmn.gen1.chance.Durations;
    const PRNG = pkmn.gen1.data.PRNG;
    const Rolls = pkmn.gen1.calc.Rolls;

    pub fn transitions(
        battle: Battle(.PRNG),
        c1: Choice,
        c2: Choice,
        allocator: Allocator,
        durations: ?Durations,
    ) !void {
        const cap = true; // FIXME

        var seen = std.AutoHashMap(Actions, void).init(allocator);
        defer seen.deinit();
        var frontier = std.ArrayList(Actions).init(allocator);
        defer frontier.deinit();

        const d = durations orelse .{};

        var opts = pkmn.battle.options(
            protocol.NULL,
            Chance(Rational(u128)){ .probability = .{}, .durations = d },
            Calc{},
        );

        var b = battle;
        _ = try b.update(c1, c2, &opts);

        const p1 = b.side(.P1);
        const p2 = b.side(.P2);

        var p: Rational(u128) = .{ .p = 0, .q = 1 };
        try frontier.append(opts.chance.actions);

        // zig fmt: off
        var i: usize = 0;
        while (i < frontier.items.len) : (i += 1) {
            const f = frontier.items[i];

            var a: Actions = .{
                .p1 = .{ .duration = f.p1.duration },
                .p2 = .{ .duration = f.p2.duration },
            };

            for (Rolls.speedTie(f.p1)) |tie| { a.p1.speed_tie = tie; a.p2.speed_tie = tie;
            for (Rolls.sleep(f.p1, d.p1)) |p1_slp| { a.p1.sleep = p1_slp;
            for (Rolls.sleep(f.p2, d.p2)) |p2_slp| { a.p2.sleep = p2_slp;
            for (Rolls.disable(f.p1, d.p1, p1_slp)) |p1_dis| { a.p1.disable = p1_dis;
            for (Rolls.disable(f.p2, d.p2, p2_slp)) |p2_dis| { a.p2.disable = p2_dis;
            for (Rolls.attacking(f.p1, d.p1, p1_slp)) |p1_atk| { a.p1.attacking = p1_atk;
            for (Rolls.attacking(f.p2, d.p2, p2_slp)) |p2_atk| { a.p2.attacking = p2_atk;
            for (Rolls.confusion(f.p1, d.p1, p1_atk, p1_slp)) |p1_cfz| { a.p1.confusion = p1_cfz;
            for (Rolls.confusion(f.p2, d.p2, p2_atk, p2_slp)) |p2_cfz| { a.p2.confusion = p2_cfz;
            for (Rolls.confused(f.p1, p1_cfz)) |p1_cfzd| { a.p1.confused = p1_cfzd;
            for (Rolls.confused(f.p2, p2_cfz)) |p2_cfzd| { a.p2.confused = p2_cfzd;
            for (Rolls.paralyzed(f.p1, p1_cfzd)) |p1_par| { a.p1.paralyzed = p1_par;
            for (Rolls.paralyzed(f.p2, p2_cfzd)) |p2_par| { a.p2.paralyzed = p2_par;
            for (Rolls.binding(f.p1, d.p1, p1_par)) |p1_bind| { a.p1.binding = p1_bind;
            for (Rolls.binding(f.p2, d.p2, p2_par)) |p2_bind| { a.p2.binding = p2_bind;
            for (Rolls.hit(f.p1, p1_par)) |p1_hit| { a.p1.hit = p1_hit;
            for (Rolls.hit(f.p2, p2_par)) |p2_hit| { a.p2.hit = p2_hit;
            for (Rolls.psywave(f.p1, p1, p1_hit)) |p1_psywave| { a.p1.psywave = p1_psywave;
            for (Rolls.psywave(f.p2, p2, p2_hit)) |p2_psywave| { a.p2.psywave = p2_psywave;
            for (Rolls.moveSlot(f.p1, p1_hit)) |p1_slot| { a.p1.move_slot = p1_slot;
            for (Rolls.moveSlot(f.p2, p2_hit)) |p2_slot| { a.p2.move_slot = p2_slot;
            for (Rolls.multiHit(f.p1, p1_hit)) |p1_multi| { a.p1.multi_hit = p1_multi;
            for (Rolls.multiHit(f.p2, p2_hit)) |p2_multi| { a.p2.multi_hit = p2_multi;
            for (Rolls.secondaryChance(f.p1, p1_hit)) |p1_sec| { a.p1.secondary_chance = p1_sec;
            for (Rolls.secondaryChance(f.p2, p2_hit)) |p2_sec| { a.p2.secondary_chance = p2_sec;
            for (Rolls.criticalHit(f.p1, p1_hit)) |p1_crit| { a.p1.critical_hit = p1_crit;
            for (Rolls.criticalHit(f.p2, p2_hit)) |p2_crit| { a.p2.critical_hit = p2_crit;

            var p1_dmg = Rolls.damage(f.p1, p1_hit);
            while (p1_dmg.min < p1_dmg.max) : (p1_dmg.min += 1) {
                a.p1.damage = @intCast(p1_dmg.min);

                var p2_dmg = Rolls.damage(f.p2, p2_hit);

                const p1_min: u9 = p1_dmg.min;
                const p2_min: u9 = p2_dmg.min;

                while (p2_dmg.min < p2_dmg.max) : (p2_dmg.min += 1) {
                    a.p2.damage = @intCast(p2_dmg.min);

                    if (seen.contains(a)) continue;

                    opts.calc.overrides = a;
                    opts.calc.summaries = .{};
                    opts.chance = .{ .probability = .{}, .durations = d };
                    const q = &opts.chance.probability;

                    b = battle;
                    _ = try b.update(c1, c2, &opts);

                    const summaries = &opts.calc.summaries;
                    const p1_max: u9 = if (p2_dmg.min != p2_min)
                        p1_dmg.min
                    else
                        try Rolls.coalesce(.P1, @as(u8, @intCast(p1_dmg.min)), summaries, cap);
                    const p2_max: u9 =
                        try Rolls.coalesce(.P2, @as(u8, @intCast(p2_dmg.min)), summaries, cap);

                    if (opts.chance.actions.matches(f)) {
                        if (!opts.chance.actions.relax().eql(a)) {
                            p1_dmg.min = p1_max;
                            p2_dmg.min = p2_max;
                            continue;
                        }

                        for (p1_min..p1_max + 1) |p1d| {
                            for (p2_dmg.min..p2_max + 1) |p2d| {
                                var acts = opts.chance.actions;
                                acts.p1.damage = @intCast(p1d);
                                acts.p2.damage = @intCast(p2d);
                                assert(!try seen.getOrPut(acts).found_existing);
                            }
                        }
                        if (p1_max != p1_min) try q.update(p1_max - p1_min + 1, 1);
                        if (p2_max != p2_dmg.min) try q.update(p2_max - p2_dmg.min + 1, 1);

                        q.reduce();
                        try p.add(q);
                        p.reduce();
                    } else if (!opts.chance.actions.matchesAny(frontier.items, i)) {
                        try frontier.append(opts.chance.actions);
                    }

                    p1_dmg.min = p1_max;
                    p2_dmg.min = p2_max;
                }

            }}}}}}}}}}}}}}}}}}}}}}}}}}}}
        }
        frontier.shrinkRetainingCapacity(1);
        // zig fmt: on

        p.reduce();
    }
};
