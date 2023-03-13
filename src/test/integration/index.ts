import 'source-map-support/register';

import * as fs from 'fs';
import * as path from 'path';
import * as tty from 'tty';
import * as assert from 'assert/strict';

import minimist from 'minimist';

import {Generations, Generation, GenerationNum} from '@pkmn/data';
import {Protocol} from '@pkmn/protocol';
import {Dex, PRNG, PRNGSeed, Battle, BattleStreams, ID, Streams, Teams} from '@pkmn/sim';
import {
  AIOptions, ExhaustiveRunner, ExhaustiveRunnerOptions,
  ExhaustiveRunnerPossibilities, RunnerOptions,
} from '@pkmn/sim/tools';

import * as engine from '../../pkg';
import * as addon from '../../pkg/addon';
import {Frame, ShowdownFrame, display, displayShowdown} from '../display';
import {Choices, patch, FILTER, formatFor} from '../showdown';

import blocklistJSON from '../showdown/blocklist.json';

const ROOT = path.resolve(__dirname, '..', '..', '..');
const ANSI = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g;

const CWD = process.env.INIT_CWD || process.env.CWD || process.cwd();

const BLOCKLIST = blocklistJSON as {[gen: number]: Partial<ExhaustiveRunnerPossibilities>};

class Runner {
  private readonly gen: Generation;
  private readonly format: string;
  private readonly prng: PRNG;
  private readonly p1options: AIOptions & {team: string};
  private readonly p2options: AIOptions & {team: string};

  constructor(gen: Generation, options: RunnerOptions) {
    this.gen = gen;
    this.format = options.format;

    this.prng = (options.prng && !Array.isArray(options.prng))
      ? options.prng : new PRNG(options.prng);

    this.p1options = fixTeam(gen, options.p1options!);
    this.p2options = fixTeam(gen, options.p2options!);
  }

  run() {
    const seed = this.prng.seed.slice() as PRNGSeed;
    const create = (o: AIOptions) => (s: Streams.ObjectReadWriteStream<string>) =>
      o.createAI(s, {seed: newSeed(this.prng), move: 0.7, mega: 0.6, ...o});

    return Promise.resolve(play(
      this.gen,
      {formatid: this.format, seed},
      {spec: {name: 'Bot 1', ...this.p1options}, create: create(this.p1options)},
      {spec: {name: 'Bot 2', ...this.p2options}, create: create(this.p2options)},
    ));
  }
}

interface PlayerOptions {
  spec: {name: string; team: string};
  create?: (s: Streams.ObjectReadWriteStream<string>) => BattleStreams.BattlePlayer;
}

// THIS PLACE IS NOT A PLACE OF HONOR... NO HIGHLY ESTEEMED DEED IS COMMEMORATED
// HERE... NOTHING VALUED IS HERE. WHAT IS HERE IS DANGEROUS AND REPULSIVE TO
// US. THIS MESSAGE IS A WARNING ABOUT DANGER.
//
// Attempts to play out a Pokémon Showdown battle in lockstep with a
// @pkmn/engine (-Dshowdown -Dtrace) battle via the ExhaustiveRunner and
// confirms that the engine produces the same chunks of output given the same
// input... only a lot of black magic and subterfuge is required to make this
// happen. First, we support both replaying from a past input log (which must
// contain "pass" choices - these cannot simply be implied) as well as playing
// out a battle from a seed. To get the latter to work we have to jump through a
// number of hoops:
//
//   - we need to patch Pokémon Showdown to make its speed ties sane (patch)
//   - we need to ensure the ExhaustiveRunner doesn't generate teams with moves
//     that are too broken for the engine to be able to match (possibilities)
//     and we need to massage the teams it produces to ensure they are legal for
//     the generation in question (fixTeam)
//   - we can't use the ExhaustiveRunner/CoordinatedPlayerAI as Pokémon Showdown
//     intended because its BattleStream abstract is broken by design and the
//     data races will cause our test fail. Instead, we manually call the AI
//     player directly and spy on its choices (which is guaranteed not to race
//     because all calls involved are synchronous) to be able to actually commit
//     them at the same time with Battle.makeChoices
//   - the CoordinatedPlayerAI can make "unavailable" choices, so we need to
//     first check whether the choice it chose was valid or not before saving it
//     (if its invalid we need to call Side.choose knowing that it will fail in
//     order for the activeRequest to be updated)
//   - Pokémon Showdown's output contains a bunch of protocol messages which are
//     redundant that need to filter out. Furthermore, we also only want to
//     compare parsed output because the raw output produced by Pokémon Showdown
//     needs to get parsed first anyway (compare)
//
// Along the way we keep track of all the relevant information to be able to
// display the full history of the battle in case of failure, writing the output
// to the logs/ directory for ease of debugging
function play(
  gen: Generation,
  {seed, formatid}: {formatid: string; seed: PRNGSeed},
  p1options: PlayerOptions,
  p2options: PlayerOptions,
  input?: string[],
) {
  const frames: {pkmn: Frame[]; showdown: ShowdownFrame[]} = {pkmn: [], showdown: []};

  let c1 = engine.Choice.pass();
  let c2 = engine.Choice.pass();

  const partial: {pkmn: Partial<Frame>; showdown: Partial<ShowdownFrame>} =
    {pkmn: {c1, c2}, showdown: {c1, c2}};

  // We can't pass p1/p2 via BattleOptions because that would cause the battle to
  // start before we could patch it, desyncing the PRNG due to spurious advances
  const control = new Battle({formatid: formatid as ID, seed, strictChoices: false});
  patch.battle(control, true);
  control.setPlayer('p1', p1options.spec);
  control.setPlayer('p2', p2options.spec);
  partial.showdown.result = toResult(control, p1options.spec.name);
  partial.showdown.seed = control.prng.seed.slice() as PRNGSeed;

  const chunk = control.getDebugLog();
  partial.showdown.chunk = chunk;
  control.log.length = 0;
  frames.showdown.push(partial.showdown as ShowdownFrame);
  partial.showdown = {};

  const players = input ? undefined : {
    p1: p1options.create!(null! as any),
    p2: p2options.create!(null! as any),
  };

  const choices = {p1: 'pass', p2: 'pass'};
  if (players) {
    players.p1.choose = c => { choices.p1 = c; };
    players.p2.choose = c => { choices.p2 = c; };
  }

  let decision = 0;
  const makeChoices = (): [engine.Choice, engine.Choice] => {
    if (input) {
      // First 3 lines are start and both players teams
      choices.p1 = input[decision + 3].slice(4);
      choices.p2 = input[decision + 4].slice(4);
      decision++;
    } else {
      for (const id of ['p1', 'p2'] as const) {
        const player = players![id];
        const request = control[id]!.activeRequest;
        if (!request || request.wait) {
          choices[id] = 'pass';
        } else {
          player.receiveRequest(request);
          while (!Choices.get(gen)(control, id).includes(choices[id])) {
            // making the unavailable request forces activeRequest to get updated
            assert.ok(!control[id].choose(choices[id]));
            player.receiveRequest(control[id]!.activeRequest!);
          }
        }
      }
    }
    control.makeChoices(choices.p1, choices.p2);
    return [engine.Choice.parse(choices.p1), engine.Choice.parse(choices.p2)];
  };

  try {
    const options = {
      p1: {name: p1options.spec.name, team: Teams.unpack(p1options.spec.team)!},
      p2: {name: p2options.spec.name, team: Teams.unpack(p2options.spec.team)!},
      seed, showdown: true, log: true,
    };
    const battle = engine.Battle.create(gen, options);
    const log = new engine.Log(gen, engine.Lookup.get(gen), options);

    let result = battle.update(c1, c2);
    partial.pkmn.result = result;
    partial.pkmn.battle = battle.toJSON();
    assert.equal(result.type, undefined);

    const parsed = Array.from(log.parse(battle.log!));
    partial.pkmn.parsed = parsed;
    frames.pkmn.push(partial.pkmn as Frame);
    partial.pkmn = {};

    compare(gen, chunk, parsed);

    const valid = (id: engine.Player, choice: engine.Choice) =>
      battle.choices(id, result).some(c => c.type === choice.type && c.data === choice.data);

    while (!control.ended) {
      assert.equal(result.type, undefined);
      assert.deepEqual(battle.prng, control.prng.seed);

      [c1, c2] = makeChoices();
      partial.pkmn.c1 = partial.showdown.c1 = c1;
      partial.pkmn.c2 = partial.showdown.c1 = c1;
      const request = partial.showdown.result = toResult(control, p1options.spec.name);
      partial.showdown.seed = control.prng.seed.slice() as PRNGSeed;

      const chunk = control.getDebugLog();
      partial.showdown.chunk = chunk;
      control.log.length = 0;
      frames.showdown.push(partial.showdown as ShowdownFrame);
      partial.showdown = {};

      assert.ok(valid('p1', c1));
      assert.ok(valid('p2', c2));
      result = battle.update(c1, c2);
      partial.pkmn.result = result;
      partial.pkmn.battle = battle.toJSON();

      const parsed = Array.from(log.parse(battle.log!));
      partial.pkmn.parsed = parsed;
      frames.pkmn.push(partial.pkmn as Frame);
      partial.pkmn = {};

      assert.deepEqual(result, request);
      compare(gen, chunk, parsed);
    }

    assert.notEqual(result.type, undefined);
    assert.deepEqual(battle.prng, control.prng.seed);
  } catch (err: any) {
    if (!input) {
      try {
        console.error('');
        dump(
          gen,
          err.stack.replace(ANSI, ''),
          toBigInt(seed),
          control.inputLog,
          frames,
          partial,
        );
      } catch (e) {
        console.error(e);
      }
    }
    throw err;
  }
}

function toResult(battle: Battle, name: string) {
  return {
    type: battle.ended
      ? battle.winner === '' ? 'tie' : battle.winner === name ? 'win' : 'lose'
      : undefined,
    p1: battle.p1.requestState || 'pass',
    p2: battle.p1.requestState || 'pass',
  } as engine.Result;
}

function dump(
  gen: Generation,
  error: string,
  seed: bigint,
  input: string[],
  frames: {pkmn: Frame[]; showdown: ShowdownFrame[]},
  partial: {pkmn: Partial<Frame>; showdown: Partial<ShowdownFrame>}
) {
  const color = (s: string) => tty.isatty(2) ? `\x1b[36m${s}\x1b[0m` : s;
  const box = (s: string) =>
    `╭${'─'.repeat(s.length + 2)}╮\n│\u00A0${s}\u00A0│\n╰${'─'.repeat(s.length + 2)}╯`;
  const pretty = (file: string) => color(path.relative(CWD, file));

  const dir = path.join(ROOT, 'logs');
  try {
    fs.mkdirSync(dir, {recursive: true});
  } catch (err: any) {
    if (err.code !== 'EEXIST') throw err;
  }

  const hex = `0x${seed.toString(16).toUpperCase()}`;
  let file = path.join(dir, `${hex}.input.log`);
  let link = path.join(dir, 'input.log');
  fs.writeFileSync(file, input.join('\n'));
  symlink(file, link);
  console.error(box(`npm run integration ${path.relative(CWD, file)}`));

  file = path.join(dir, `${hex}.pkmn.html`);
  link = path.join(dir, 'pkmn.html');
  fs.writeFileSync(file, display(gen, true, error, seed, frames.pkmn, partial.pkmn));
  console.error(' ◦ @pkmn/engine:', pretty(symlink(file, link)), '->', pretty(file));

  file = path.join(dir, `${hex}.showdown.html`);
  link = path.join(dir, 'showdown.html');
  fs.writeFileSync(file, displayShowdown(error, seed, frames.showdown, partial.showdown));
  console.error(' ◦ Pokémon Showdown:', pretty(symlink(file, link)), '->', pretty(file), '\n');
}

function symlink(from: string, to: string) {
  fs.rmSync(to, {force: true});
  fs.symlinkSync(from, to);
  return to;
}

type Writeable<T> = { -readonly [P in keyof T]: T[P] };

// Compare Pokémon Showdown vs. @pkmn/engine output, after parsing the protocol
// and filtering out redundant messages / smoothing over any differences
//
//   - Pokémon Showdown includes `[of]` on `|-damage|` messages for status
//     damage but the engine doesn't keep track of this as its redundant
//     information that requires additional state to support
//   - Pokémon Showdown protocol includes the `tox` status even in generations
//     where Toxic is not actually a status. This is only relevant in the
//     initial `|-status|` message as the text formatter uses this to decide
//     whether to output "poisoned" vs. "badly poisoned", though this is
//     possible to accomplish by simply tracking the prior `|move|` message so
//     isn't necessary
//   - Similarly, when a Pokémon which was previously badly poisoned switches
//     back in, a `|-status|IDENT|psn|[silent]` message will be logged. This is
//     incorrect as Toxic is not actually a status in Gen 1 and the Toxic
//     volatile gets removed on switch *out* not switch *in*, and as such the
//     engine does not attempt to reproduce this. If we receive one of these
//     messages we just verify that its for the scenario we expect and ignore it
//   - The engine cannot always infer `[from]` on `|move|` and so if we see that
//     the engine's output is missing it we also need to remove it from Pokémon
//     Showdown's (we can't just always indiscriminately remove it because we
//     want to ensure that it matches when present)
//
// TODO: can we always infer done/start/upkeep?
function compare(gen: Generation, chunk: string, actual: engine.ParsedLine[]) {
  const buf: engine.ParsedLine[] = [];
  let i = 0;
  for (const {args, kwArgs} of Protocol.parse(chunk)) {
    if (FILTER.has(args[0])) continue;
    const a = args.slice() as Writeable<Protocol.ArgType>;
    const kw = {...kwArgs} as Protocol.KWArgType;
    switch (args[0]) {
    case 'move': {
      const keys = kwArgs as Protocol.KWArgs['|move|'];
      if (keys.from && !(actual[i].kwArgs as Protocol.KWArgs['|move|']).from) {
        delete (kw as any).from;
      }
      break;
    }
    case 'switch': {
      a[3] = fixHPStatus(gen, args[3]);
      break;
    }
    case '-heal':
    case '-damage': {
      a[2] = fixHPStatus(gen, args[2]);
      const keys = kwArgs as Protocol.KWArgs['|-heal|' | '|-damage|'];
      if (keys.from && !['drain', 'Recoil'].includes(keys.from)) {
        delete (kw as any).of;
      }
      break;
    }
    case '-status':
    case '-curestatus': {
      if (args[0] === '-status') {
        const keys = kwArgs as Protocol.KWArgs['|-status|'];
        if (keys.silent) {
          assert.equal(args[2], 'psn');
          continue;
        }
      }
      a[2] = args[2] === 'tox' ? 'psn' : args[2];
      break;
    }
    }
    assert.deepEqual(actual[i], {args: a, kwArgs: kw});
    i++;
  }
  return buf;
}

function fixHPStatus(gen: Generation, hpStatus: Protocol.PokemonHPStatus) {
  return (gen.num < 3 && hpStatus.endsWith('tox')
    ? `${hpStatus.slice(0, -3)}psn` as Protocol.PokemonHPStatus
    : hpStatus);
}

// The ExhaustiveRunner does not do a good job at ensuring the sets it generates
// are legal for old generations - these would usually be corrected by the
// TeamValidator but custom games bypass this so we need to massage the faulty
// set data ourselves
function fixTeam(gen: Generation, options: AIOptions) {
  for (const pokemon of options.team!) {
    const species = gen.species.get(pokemon.species)!;
    if (gen.num <= 1) {
      pokemon.ivs.hp = gen.stats.getHPDV(pokemon.ivs);
      pokemon.ivs.spd = pokemon.ivs.spa;
      pokemon.evs.spd = pokemon.evs.spa;
    }
    if (gen.num <= 2) {
      delete pokemon.shiny;
      pokemon.nature = '';
      if (gen.num > 1) {
        pokemon.gender = species.gender ??
          gen.stats.toDV(pokemon.ivs.atk) >= species.genderRatio.F * 16 ? 'M' : 'F';
      }
    }
  }
  return {...options, team: Teams.pack(options.team!)!} as AIOptions & {team: string};
}

// This is a fork of the possibilities function (which is used to build up the
// various "pools" of effects to proc during testing) from @pkmn/sim that has
// been extended to also enforce the engine's BLOCKLIST
function possibilities(gen: Generation) {
  const blocked = BLOCKLIST[gen.num] || {};
  const pokemon = Array.from(gen.species).filter(p => !blocked.pokemon?.includes(p.id as ID) &&
    (p.name !== 'Pichu-Spiky-eared' && p.name.slice(0, 8) !== 'Pikachu-'));
  const items = gen.num < 2
    ? [] : Array.from(gen.items).filter(i => !blocked.items?.includes(i.id as ID));
  const abilities = gen.num < 3
    ? [] : Array.from(gen.abilities).filter(a => !blocked.abilities?.includes(a.id as ID));
  const moves = Array.from(gen.moves).filter(m => !blocked.moves?.includes(m.id as ID) &&
    (!['struggle', 'revivalblessing'].includes(m.id) &&
      (m.id === 'hiddenpower' || m.id.slice(0, 11) !== 'hiddenpower')));
  return {
    pokemon: pokemon.map(p => p.id as ID),
    items: items.map(i => i.id as ID),
    abilities: abilities.map(a => a.id as ID),
    moves: moves.map(m => m.id as ID),
  };
}

type Options = Pick<ExhaustiveRunnerOptions, 'log' | 'maxFailures' | 'cycles'> & {
  prng: PRNG | PRNGSeed;
  gen?: GenerationNum;
  duration?: number;
};

export async function run(gens: Generations, options: string | Options) {
  if (!addon.supports(true, true)) throw new Error('engine must be built with -Dshowdown -Dtrace');
  if (typeof options === 'string') {
    const file = path.join(ROOT, 'logs', `${options}.input.log`);
    if (fs.existsSync(file)) options = file;
    const log = fs.readFileSync(path.resolve(CWD, options), 'utf8');
    const gen = gens.get(log.charAt(23));
    patch.generation(gen);

    const lines = log.split('\n');
    const spec = JSON.parse(lines[0].slice(7)) as {formatid: string; seed: PRNGSeed};
    const p1 = {spec: JSON.parse(lines[1].slice(10)) as {name: string; team: string}};
    const p2 = {spec: JSON.parse(lines[2].slice(10)) as {name: string; team: string}};
    play(gen, spec, p1, p2, lines.slice(3));
    return 0;
  }

  const opts: ExhaustiveRunnerOptions = {
    cycles: 1, maxFailures: 1, log: false, ...options, format: '',
    cmd: (cycles: number, format: string, seed: string) =>
      `npm run integration -- --cycles=${cycles} --gen=${format[3]} --seed=${seed}`,
  };

  let failures = 0;
  const start = Date.now();
  do {
    for (const gen of gens) {
      if (gen.num > 1) break;
      if (options.gen && gen.num !== options.gen) continue;
      patch.generation(gen);
      opts.format = formatFor(gen);
      opts.possible = possibilities(gen);
      failures +=
        await (new ExhaustiveRunner({...opts, runner: o => new Runner(gen, o).run()}).run());
      if (failures >= opts.maxFailures!) return failures;
    }
  } while (Date.now() - start < (options.duration || 0));

  return failures;
}

export const newSeed = (prng: PRNG) => [
  prng.next(0x10000), prng.next(0x10000), prng.next(0x10000), prng.next(0x10000),
] as PRNGSeed;

export const toBigInt = (seed: PRNGSeed) =>
  ((BigInt(seed[0]) << 48n) | (BigInt(seed[1]) << 32n) |
   (BigInt(seed[2]) << 16n) | BigInt(seed[3]));


if (require.main === module) {
  (async () => {
    const gens = new Generations(Dex as any);
    // minimist tries to parse all number-like things into numbers which doesn't work because the
    // seed is actually a bigint, meaning we need to special case this without calling minimist
    if (process.argv.length === 3 && process.argv[2][0] !== '-') {
      process.exit(await run(gens, process.argv[2]));
    }
    const argv = minimist(process.argv.slice(2), {default: {maxFailures: 1}});
    const unit =
      typeof argv.duration === 'string' ? argv.duration[argv.duration.length - 1] : undefined;
    const duration =
      unit ? +argv.duration.slice(0, -1) * {s: 1e3, m: 6e4, h: 3.6e6}[unit]! : argv.duration;
    argv.cycles = argv.cycles ?? duration ? 1 : 10;
    const seed = argv.seed ? argv.seed.split(',').map((s: string) => Number(s)) : null;
    const options = {prng: new PRNG(seed), log: process.stdout.isTTY, ...argv, duration};
    process.exit(await run(gens, options));
  })().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
