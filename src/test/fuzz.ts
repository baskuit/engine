import 'source-map-support/register';

import {execFile} from 'child_process';
import {promisify} from 'util';

import {Generation, Generations} from '@pkmn/data';
import {Dex} from '@pkmn/sim';

import {Battle, Choice, Info, Log, ParsedLine, Result, SideInfo} from '../pkg';
import * as addon from '../pkg/addon';
import {Data, LAYOUT, LE, Lookup} from '../pkg/data';
import * as gen1 from '../pkg/gen1';

import {Frame, display} from './display';

const run = promisify(execFile);

const usage = (msg?: string): void => {
  if (msg) console.error(msg);
  console.error('Usage: fuzz <pkmn|showdown> <GEN> <DURATION> <SEED?>');
  process.exit(1);
};

class SpeciesNames implements Info {
  gen: Generation;
  battle!: Battle;

  constructor(gen: Generation) {
    this.gen = gen;
  }

  get p1() {
    const [p1] = Array.from(this.battle.sides);
    const team = Array.from(p1.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => ({species: p.stored.species}));
    return new SideInfo(this.gen, {name: 'Player 1', team});
  }

  get p2() {
    const [, p2] = Array.from(this.battle.sides);
    const team = Array.from(p2.pokemon)
      .sort((a, b) => a.position - b.position)
      .map(p => ({species: p.stored.species}));
    return new SideInfo(this.gen, {name: 'Player 2', team});
  }
}

(async () => {
  if (process.argv.length < 4 || process.argv.length > 6) usage(process.argv.length.toString());
  const mode = process.argv[2];
  if (mode !== 'pkmn' && mode !== 'showdown') {
    usage(`Mode must be either 'pkmn' or 'showdown', received '${mode}'`);
  }
  const showdown = mode === 'showdown';

  const gens = new Generations(Dex as any);
  const gen = gens.get(process.argv[3]);
  const lookup = Lookup.get(gen);
  const size = LAYOUT[gen.num - 1].sizes.Battle;
  const names = new SpeciesNames(gen);
  const log = new Log(gen, lookup, names);
  const deserialize = (buf: number[]): Battle => {
    // We don't care about the native addon, we just need to load it so other checks don't fail
    void addon.supports(true);
    switch (gen.num) {
    case 1: return new gen1.Battle(lookup, Data.view(buf), {showdown});
    default: throw new Error(`Unsupported gen: ${gen.num}`);
    }
  };

  const args = ['build', 'fuzz', '-Dtrace'];
  if (showdown) args.push('-Dshowdown');
  args.push('--', gen.num.toString(), process.argv[4]);
  if (process.argv.length > 5) args.push(process.argv[5].toString());

  try {
    await run('zig', args, {encoding: 'buffer'});
  } catch (err: any) {
    const {stdout, stderr} = err as {stdout: Buffer; stderr: Buffer};
    const raw = stderr.toString('utf8');
    const panic = raw.indexOf('panic: ');
    const error = raw.slice(panic);

    console.error(raw);

    const data = Array.from(stdout);
    if (!data.length) process.exit(1);

    const view = Data.view(data);

    const head = 8 + 1;
    const seed = view.getBigUint64(0, LE);
    const end = view.getUint8(8);

    const frames: Frame[] = [];
    for (let offset = head + end; offset < data.length; offset += (3 + size)) {
      const result = Result.decode(data[offset]);
      const c1 = Choice.decode(data[offset + 1]);
      const c2 = Choice.decode(data[offset + 2]);
      const battle = deserialize(data.slice(offset + 3, offset + size + 3));
      names.battle = battle;

      const parsed: ParsedLine[] = [];
      const it = log.parse(Data.view(data.slice(offset + size + 3)))[Symbol.iterator]();
      let r = it.next();
      while (!r.done) {
        parsed.push(r.value);
        r = it.next();
      }
      offset += r.value;
      frames.push({result, c1, c2, battle, parsed});
    }

    console.log(display(gen, showdown, error, seed, frames, {
      parsed: end > 0
        ? Array.from(log.parse(Data.view(data.slice(head, head + end))))
        : undefined,
    }));

    process.exit(1);
  }
})().catch(err => {
  console.error(err);
  process.exit(1);
});