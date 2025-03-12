import 'source-map-support/register';

import {CommonExecOptions, execFileSync, execSync} from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import minimist from 'minimist';
import semver from 'semver';

const ROOT = path.resolve(__dirname, '..', '..');

const argv = minimist(process.argv.slice(2), {boolean: ['prod', 'dryRun']});

type Options = Omit<CommonExecOptions, 'encoding'> & {bypass?: boolean; silent?: boolean};
const sh = (cmd: string, args?: string[], options: Options = {}) => {
  const cwd = (options.cwd ?? process.cwd()).toString();
  const env = {...process.env, ...options.env};
  const e = options.env
    ? `${Object.entries(options.env).map(([k, v]) => `${k}=${v!}`).join(' ')} ` : '';
  const run = args ? `${e}${cmd} ${args.join(' ')}` : `${e}${cmd}`;

  if (!options.silent) {
    if (cwd !== process.cwd()) {
      console.log(`$(cd ${path.relative(process.cwd(), cwd)}; ${run})`);
    } else {
      console.log(run);
    }
  }

  if (argv.dryRun && !options.bypass) return '';
  if (args) {
    return execFileSync(cmd, args, {...options, env, cwd, encoding: 'utf8'});
  } else {
    return execSync(cmd, {...options, env, cwd, encoding: 'utf8'});
  }
};

const TARGETS = [
  {label: 'Windows - x86_64', triple: 'x86_64-windows-gnu', mcpu: 'baseline'},
  {label: 'Windows - ARM64', triple: 'aarch64-windows-gnu', mcpu: 'baseline'},
  {label: 'macOS - x86_64', triple: 'x86_64-macos-none', mcpu: 'baseline'},
  {label: 'macOS - ARM64', triple: 'aarch64-macos-none', mcpu: 'apple_a14'},
  {label: 'Linux - x86_64', triple: 'x86_64-linux-musl', mcpu: 'baseline'},
  {label: 'Linux - ARM64', triple: 'aarch64-linux-musl', mcpu: 'baseline'},
];

// TODO: not actually prod-only, but can't detect patched Zig currently`
if (argv.prod && semver.gt(sh('zig', ['version'], {bypass: true}), '0.12.0-dev.866+3a47bc715')) {
  // TODO: ziglang/zig#17768
  console.error('Releases must only be built with a Zig compiler before v0.12.0-dev.866+3a47bc715');
  process.exit(1);
}

try {
  sh('gh', ['auth', 'token'], {stdio: 'ignore'});
} catch {
  console.error('Unable to publish a release without being logged into GitHub.');
  process.exit(1);
}

if (sh('git', ['status', '--porcelain'])) {
  console.error('Cowardly refusing to cut a release with untracked changes.');
  process.exit(1);
}

let tmp = '';
try {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pkmn-'));
} catch (err) {
  console.error('Unable to create temporary directory', err);
  process.exit(1);
}

sh('make', ['clean']);

const release = path.join(ROOT, 'release');
const relative = path.relative(process.cwd(), release);
try {
  console.log(`rm -rf ${relative} && mkdir -p ${relative}`);
  fs.rmSync(release, {force: true, recursive: true});
  fs.mkdirSync(release, {recursive: true});
} catch (err: any) {
  if (err.code !== 'EEXIST') throw err;
}

const debug = (files: string[]) => {
  if (files.includes('src/lib/common/debug.zig')) return true;
  try {
    sh('git', ['grep', '@import.*debug\\.zig']);
  } catch {
    return false;
  }
  return true;
};

// eslint-disable-next-line
const json = require(path.join(ROOT, 'package.json'));
let version: string = json.version;
if (argv.prod) {
  if (debug(json.files)) {
    console.error('Refusing to produce a release containing debug logic');
    process.exit(1);
  }
} else {
  const HEAD = sh('git', ['rev-parse', 'HEAD'], {bypass: true}).slice(0, 8);
  version = `${version}-dev+${HEAD}`;
}

const build = () => {
  for (const {triple, mcpu} of TARGETS) {
    for (const showdown of ['true', 'false']) {
      sh('zig', [
        'build',
        '-Doptimize=ReleaseFast',
        '-Dstrip',
        `-Dtarget=${triple}`,
        `-Dcpu=${mcpu}`,
        `-Dshowdown=${showdown}`,
        '-Dlog',
        '-Dchance',
        '-Dcalc',
        '-p',
        `release/${triple}`,
      ]);
    }
    let archive: string;
    if (triple.includes('windows')) {
      archive = `libpkmn-${triple}-${version}.zip`;
      sh('7z', ['a', archive, `${triple}/`], {cwd: release});
    } else {
      archive = `libpkmn-${triple}-${version}.tar.xz`;
      const options = {cwd: release, env: {XZ_OPT: '-9'}};
      // --sort=name fails on macOS because not GNU...
      sh('tar', ['cJf', `libpkmn-${triple}-${version}.tar.xz`, `${triple}/`], options);
    }
    console.log(`rm -rf ${path.join(relative, triple)}`);
    fs.rmSync(path.join(release, triple), {force: argv.dryRun, recursive: true});
    if (argv.prod) sh(`echo | minisign -Sm ${archive}`, undefined, {cwd: release, stdio: 'ignore'});
  }
  sh('npm', ['run', 'build']);
};

const next = version.replace('+', '.');
if (argv.prod) {
  build();
  sh('npm', ['publish']);
  sh('git', ['tag', `v${version}`]);
  sh('git', ['push', '--tags', 'origin', 'main']);
} else {
  const info = JSON.parse(sh('npm', ['show', '--json', '@pkmn/engine@dev'], {bypass: true}));
  const old = info.version;
  if (old === next) {
    console.log(`Version v${version} already exists, exiting as there is nothing to do`);
    process.exit(0);
  }
  if (info.deprecated) {
    console.log(`Version v${old} is already deprecated.`);
  } else {
    sh('npm', ['deprecate', `@pkmn/engine@${old}`,
      'This dev version has been deprecated automatically as a newer version exists.']);
  }
  build();
  fs.copyFileSync(path.join(ROOT, 'package.json'), path.join(tmp, 'package.json'));
  try {
    json.version = next;
    fs.writeFileSync(path.join(ROOT, 'package.json'), JSON.stringify(json, null, 2));
    sh('npm', ['publish', '--tag=dev']);
  } finally {
    fs.copyFileSync(path.join(tmp, 'package.json'), path.join(ROOT, 'package.json'));
  }
}

const preamble = argv.prod ? 'Official release of' : 'Automated nightly release of developer';
const npm = 'The corresponding release of the reference TypeScript driver code can be found on ' +
  `the [npm registry](https://www.npmjs.com/package/@pkmn/engine/v/${next}).`;
const key = 'RWQJbSYgSRvYHXIqYwkOzpuV4eQW6roHp8PqUXcQAUk3suFmclEUZZff';
const sign = argv.prod
  ? 'These archives have been signed with [Minisign](https://jedisct1.github.io/minisign/) with ' +
    `https:/pkmn.cc/minisign.pub, reproduced below for convenience:\n\n    ${key}`
  : '';
const notes = `${preamble} version **\`v${version}\`** for` +
  '`libpkmn` and `libpkmn-showdown` (`-Dshowdown`). This release offers only stripped static ' +
  '`-OReleaseFast` versions of these libraries built for popular architectures and baseline CPU ' +
  `features with \`-Dlog\`, \`-Dchance\`, and \`-Dcalc\` all enabled. ${npm} ${sign}\n\n` +
  '*[Manually building](https://github.com/pkmn/engine#libpkmn) these libraries from source ' +
  'on your own system is likely to result in better performance when optimized for the native ' +
  'architecture and allows you to tweak exactly which features you need (including support for ' +
  'dynamic libraries or more niche systems)*';

fs.writeFileSync(path.join(tmp, 'notes'), notes);

const args = ['release', 'create'];
if (!argv.prod) {
  args.push('nightly', '--prerelease', '--title', 'Nightly');
  sh('gh', ['release', 'delete', 'nightly', '--yes'], {stdio: 'ignore'});
  sh('git', ['push', 'origin', ':nightly']);
} else {
  args.push(version, '--title', version, '--verify-tag');
}
args.push('--notes-file', path.join(tmp, 'notes'));
const artifacts = fs.readdirSync(release).map(f => {
  const file = path.join(release, f);
  const triple = f.split('-').slice(1, 4).join('-');
  const label = TARGETS.find(t => t.triple === triple)!.label;
  return f.endsWith('.sig') ? `${file}#${label} (signature)` : `${file}#${label}`;
});
console.log(`gh ${args.join(' ')} ${artifacts.map(a => `'${a}'`).join(' ')}`);
args.push(...artifacts);
sh('gh', args, {silent: true});
