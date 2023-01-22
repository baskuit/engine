// TODO: actually use @pkmn/engine
// - feed input from rawBattleStream.rawInputLog into @pkmn/engine & compare
// - add buf to output if doesn't compare
// - verify binary protocol round trip
// - handle invalid choices by RandomPlayerAI

import {Generations, Generation, GenerationNum} from '@pkmn/data';
import {PRNG, PRNGSeed, BattleStreams, ID} from '@pkmn/sim';
import {
  AIOptions, ExhaustiveRunner, ExhaustiveRunnerOptions,
  ExhaustiveRunnerPossibilites, RunnerOptions,
} from '@pkmn/sim/tools';

import {PatchedBattleStream, patch} from '../showdown/common';

import blocklistJSON from '../blocklist.json';

const BLOCKLIST = blocklistJSON as {[gen: number]: Partial<ExhaustiveRunnerPossibilites>};

class Runner {
  private readonly format: string;
  private readonly prng: PRNG;
  private readonly p1options?: AIOptions;
  private readonly p2options?: AIOptions;

  constructor(options: RunnerOptions) {
    this.format = options.format;

    this.prng = (options.prng && !Array.isArray(options.prng))
      ? options.prng : new PRNG(options.prng);

    this.p1options = options.p1options;
    this.p2options = options.p2options;
  }

  async run() {
    const rawBattleStream = new RawBattleStream(this.format);
    const streams = BattleStreams.getPlayerStreams(rawBattleStream);

    const spec = {formatid: this.format, seed: this.prng.seed};
    const p1spec = {name: 'Bot 1', ...this.p1options};
    const p2spec = {name: 'Bot 2', ...this.p2options};

    const p1 = this.p1options!.createAI(streams.p2, {
      seed: this.newSeed(), move: 0.7, mega: 0.6, ...this.p1options!,
    }).start();
    const p2 = this.p2options!.createAI(streams.p1, {
      seed: this.newSeed(), move: 0.7, mega: 0.6, ...this.p2options!,
    }).start();

    await Promise.all([streams.omniscient.write(
      `>start ${JSON.stringify(spec)}\n` +
      `>player p1 ${JSON.stringify(p1spec)}\n` +
      `>player p2 ${JSON.stringify(p2spec)}`
    ), p1, p2]);

    const buf = [];
    for await (const chunk of streams.omniscient) {
      buf.push(chunk);
    }

    // BUG: streams.p2.writeEnd ?
  }

  // Same as PRNG#generatedSeed, only deterministic.
  // NOTE: advances this.prng's seed by 4.
  newSeed(): PRNGSeed {
    return [
      this.prng.next(0x10000),
      this.prng.next(0x10000),
      this.prng.next(0x10000),
      this.prng.next(0x10000),
    ];
  }
}

class RawBattleStream extends PatchedBattleStream {
  readonly format: string;
  readonly rawInputLog: string[];

  constructor(format: string) {
    super();
    this.format = format;
    this.rawInputLog = [];
  }

  _write(message: string) {
    this.rawInputLog.push(message);
    super._write(message);
  }
}

const FORMATS = [
  'gen1customgame',
  'gen2customgame',
  // 'gen3customgame', 'gen3doublescustomgame',
  // 'gen4customgame', 'gen4doublescustomgame',
  // 'gen5customgame', 'gen5doublescustomgame',
  // 'gen6customgame', 'gen6doublescustomgame',
  // 'gen7customgame', 'gen7doublescustomgame',
  // 'gen8customgame', 'gen8doublescustomgame',
  // 'gen9customgame', 'gen9doublescustomgame',
];

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

export async function run(gens: Generations, options: Options) {
  const opts: ExhaustiveRunnerOptions = {
    cycles: 1, maxFailures: 1, log: false, ...options,
    runner: o => new Runner(o).run(), format: '',
  };

  let failures = 0;
  const start = Date.now();
  do {
    for (const format of FORMATS) {
      const gen = gens.get(format.charAt(3));
      if (options.gen && gen.num !== options.gen) continue;
      patch.generation(gen);
      opts.format = format;
      opts.possible = possibilities(gen);
      failures += await (new ExhaustiveRunner(opts).run());
      if (opts.log) process.stdout.write('\n');
      if (failures >= opts.maxFailures!) return failures;
    }
  } while (Date.now() - start < (options.duration || 0));

  return failures;
}