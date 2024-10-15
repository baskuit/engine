<p align="center">
  <img alt="pkmn/engine" width="192" height="192" src="https://pkmn.cc/engine.svg" />
  <br />
  <br />
  <a href="https://github.com/pkmn/engine/actions/workflows/test.yml">
    <img alt="Test Status" src="https://github.com/pkmn/engine/actions/workflows/test.yml/badge.svg" />
  </a>
  <a href="#status">
    <img alt="WIP" src="https://img.shields.io/badge/status-WIP-red.svg" />
  </a>
  <a href="https://github.com/pkmn/engine/blob/master/LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-blue.svg" />
  </a>
</p>

> [!WARNING]  
> **This project is under heavy development** and currently the `main` branch contains numerous breaking
> changes which may not work and which are not fully documented. Please **wait for the forthcoming
> initial v0.1 release** before depending on this project (code from the
> [`old`](https://github.com/pkmn/engine/releases/tag/old) tag can also be used to experiment with a
> more stable version of the codebase).

<hr />

A minimal, complete, Pokémon battle simulation engine optimized for performance and
[designed](docs/DESIGN.md) for tooling, embedded systems, and [artificial
intelligence](https://github.com/pkmn/0-ERROR) use cases. This engine aims to be a frame-accurate and
[bug-for-bug compatible](http://www.catb.org/jargon/html/B/bug-for-bug-compatible.html)
implementation of both Pokémon battles as defined by the original game code and the [Pokémon
Showdown](https://pokemonshowdown.com/)[^1] simulator which represents Pokémon battling as practically
interpreted online.

The pkmn engine is [**more than 1000× faster**](docs/TESTING.md#results) than the
[patched](docs/TESTING.md#patches) [Pokémon Showdown simulator
code](https://github.com/smogon/pokemon-showdown) when playing out supported formats in
compatibility mode and is extensively [tested](docs/TESTING.md) and [documented](docs). Note,
however, that the engine is **not a fully featured simulator** but is instead a low-level library
which can be used as a building block for more advanced use cases.

## Installation

This repository hosts both the engine code (written in [Zig](https://ziglang.org/)) and the
reference driver code (written in [TypeScript](https://www.typescriptlang.org/)).

### `libpkmn`

Binaries of the engine code can be downloaded from the
[releases](https://github.com/pkmn/engine/releases) tab on GitHub, or you can [download the source
code](https://github.com/pkmn/engine/archive/refs/heads/main.zip) directly and build it with the
latest `zig` compiler, see `zig build --help` for build options:

```sh
$ curl https://github.com/pkmn/engine/archive/refs/heads/main.zip -o engine.zip
$ unzip engine.zip
$ cd engine
$ zig build --prefix /usr/local -Doptimize=ReleaseFast
```

The Zig website has [installation instructions](https://ziglang.org/learn/getting-started/) which
walk through how to install Zig on each platform - the engine code should work on Zig v0.11.0,
though tracks Zig's master branch so this may change in the future if breaking language changes are
introduced. Note that **due to a [bug in the Zig
compiler](https://github.com/ziglang/zig/issues/17768), compiling with a version of Zig before
`0.12.0-dev.876+aaf46187a` is recommended for performance**.

`libpkmn` can be built with `-Dshowdown` to instead produce the Pokémon Showdown compatible
`libpkmn-showdown` library. Furthermore, protocol message logging can be enabled through `-Dlog`.
The `libpkmn` and `libpkmn-showdown` objects available in the binary release are both compiled with
the `-Dlog` flag by default.

### `@pkmn/engine`

The driver code can be installed from [npm](https://www.npmjs.com/package/@pkmn/engine):

```sh
$ npm install @pkmn/engine
```

The driver depends on being able to find compiled Node/WASM addons in
`node_modules/@pkmn/engine/build/lib` to be useful. When you install the package a [`postinstall`
lifecycle script](https://docs.npmjs.com/cli/v8/using-npm/scripts) runs
[`install-pkmn-engine`](src/bin/install-pkmn-engine) which checks for a compatible `zig` compiler
(see earlier regarding minimum version) and download one to `node_module/@pkmn/engine/build/bin` if
it can't find one, as well as looking for (and downloading, if necessary) the required Node headers
needed to successfully build the addons natively.

**If you have configured `npm` to `--ignore-scripts` you must either run `npx install-pkmn-engine`
directly or build the addons manually and place the artifacts in the expected paths.**

### `pkmn`

To include `pkmn`, add it as a dependency in your project's
[`build.zig.zon`](https://github.com/ziglang/zig/blob/master/doc/build.zig.zon.md) using [Zig's
Package Management
system](https://ziglang.org/download/0.11.0/release-notes.html#Package-Management):


```zig
.dependencies = .{
    .pkmn = .{
        .url = "https://github.com/pkmn/engine/archive/RELEASE.tar.gz",
    },
},
```

Replace `RELEASE` with the tag for the [release](https://github.com/pkmn/engine/releases) you wish
to use (e.g. `0.1.0` or `nightly`) or the specific hash of any commit. Next, run `zig build` and
copy the expected hash from the error message into your `build.zig.zon` alongside the `.url`:

```sh
$ zig build
error: dependency is missing hash field
            .url = "https://github.com/pkmn/engine/archive/nightly.tar.gz",
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
note: expected .hash = "122056b93b403033cb7d9bed96a02c2eb8cc1275515976167726ada6eb4207e8ef8a",
```

Note that this hash is **not** going to be the same as the commit hash. After adding the hash to
your `build.zig.zon` you will be able to import the `pkmn` package's build helpers into your
`build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    ...
    const pkmn = b.dependency("pkmn", .{ .showdown = true, .log = true });
    exe.root_module.addImport("pkmn", pkmn.module("pkmn"));
    ...
}
```

The `pkmn` package can be configured with various options such as whether or not Pokémon Showdown
compatibility mode or protocol message logging should be enabled. Alternatively, you may set options
via a `pkmn_options` [root source file
declaration](https://ziglang.org/documentation/master/#Root-Source-File). There are several
undocumented internal options that can be tweaked as well via build or root options, though these
options aren't officially supported, affect correctness, and may change meaning or behavior without
warning. Use at your own risk.

```zig
pub const pkmn_options = .{ .showdown = true, .log = true };
```

## Usage

For each Pokémon generation, the engine provides a battle structure with two functions - a function
to `update` the battle's state based on both players' choices and a function that defines which
`choices` are valid at that decision point (at the beginning of a battle both player's must "pass"
as their first choice to switch in the first member of their party). If `-Dlog` protocol logging is
enabled each update produces logs which can be decoded into a buffer (`LOGS_SIZE` constants are
provided to make it easy to allocate a buffer of the correct size). Each `update` returns a result
to indicate either that the battle has terminated or which types of choices are available for each
player.

Unlike [Pokémon Showdown's
SIM-PROTOCOL](https://github.com/smogon/pokemon-showdown/blob/master/sim/SIM-PROTOCOL.md#choice-requests)
which provides a rich request object at each decision point, the pkmn engine computes the possible
choices on demand based on the result of the previous `update` and the battle state (`CHOICES_SIZE`
is a good size to initialize the buffer passed to `choices`). **Attempting to update the battle with
a choice not present in the options returned by `choices` is undefined behavior and may corrupt
state or cause the engine to crash.**

Battles may be played out from any point but to freshly initialize a battle which is yet to start
the turn count and active Pokémon should be zeroed out (driver code should handle this for you).
Most driver code should also provide helpers to make initializing battle convenient - check the
respective documentation and examples for the bindings being used. The engine's [protocol
documentation](docs/PROTOCOL.md) goes into greater detail on the specifics of updates and the
potential logs that may result.

*The snippets below are meant to merely illustrate in broad strokes how the pkmn engine can be used
\- the [`examples`](examples) directory contains fully commented and runnable code.*

### C

[`pkmn.h`](src/include/pkmn.h) exports the C API for `libpkmn`. Symbols are all prefixed with
`pkmn_` to avoid name collisions. If `-Dlog` is enabled and logging throws an error then the error
is encoded in the `pkmn_result` and can be checked with `pkmn_error`.

```c
#include <pkmn.h>

pkmn_battle_options options;
pkmn_gen1_battle_options_set(&options, ...);
pkmn_battle battle = ...;

pkmn_result result;
pkmn_choice c1 = 0, c2 = 0;
while (!pkmn_result_type(result = pkmn_battle_update(&battle, c1, c2, &options))) {
  c1 = choose(PKMN_PLAYER_P1, pkmn_result_p1(result));
  c2 = choose(PKMN_PLAYER_P2, pkmn_result_p2(result));
  pkmn_gen1_battle_options_set(&options, ...);
}
if (pkmn_error(result)) exit(1);
```

[(full code)](examples/c/example.c)

The C API doesn't export any helpers for creating or accessing the opaque battle objects - it's
instead intended to be used as the foundation for more ergonomic bindings in [other
languages](#other) (the lack of namespaces and bit fields having an implementation-defined layout in
C are the main contributing factors to the sparseness of what `libpkmn` chooses to expose).

### JavaScript / TypeScript

`@pkmn/engine` depends on the [`@pkmn/data`](https://www.npmjs.com/package/@pkmn/data) package which
requires a `Dex` implementation to be provided as well. The `Battle.create` function can be used to
initialize a `Battle` from the beginning, or `Battle.restore` can be used to re-instantiate a battle
which is already in progress. If logging is enabled the output can be turned into Pokémon Showdown
protocol via `Log.parse`.

```ts
import {Dex} from '@pkmn/dex';
import {Generations} from '@pkmn/data';
import {Battle, Choice} from '@pkmn/engine';

const gens = new Generations(Dex);
const battle = Battle.create(...);

const choose = (choices: Choice[]) =>
  choices[Math.floor(Math.random() * choices.length)];

let result: Result;
let c1: Choice, c2: Choice;
while (!(result = battle.update(c1, c2)).type) {
  c1 = choose(battle.choices('p1', result));
  c2 = choose(battle.choices('p2', result));
}

console.log(result);
```

[(full code)](examples/js/example.ts)

By default, the `@pkmn/engine` package compiles the engine with `-Dshowdown`, though by running
`install-pkmn-engine` directly and passing in `--options` you can override this default and build
different configurations of the extension for the driver to use. The driver can support
configurations both with and without Pokémon Showdown compatibility simultaneously if present. On
update, the post-install script attempts to rebuild whichever extensions it finds with the same
configuration parameters that were originally used meaning updating to the newest version of the
library should be seamless.

Despite relying on the native engine code, the `@pkmn/engine` code is designed to also work in
browsers which support [WebAssembly](https://webassembly.org/). Running `npm run start:web` from the
[`examples`](examples/js) directory starts a server that can be used to demonstrate the engine
running in the browser.

### Zig

The `pkmn` Zig package exposes helper methods to simplify state instantiation and any `Writer` can
be used when logging is enabled to allow for easily printing e.g. to standard out or a buffer.

```zig
const std = @import("std");
const pkmn = @import("pkmn");

var random = std.Random.DefaultPrng.init(seed).random();
var choices: [pkmn.CHOICES_SIZE]pkmn.Choice = undefined;

var battle = ...
var options = pkmn.battle.options(...);

var c1 = pkmn.Choice{};
var c2 = pkmn.Choice{};

var result = try battle.update(c1, c2, &options);
while (result.type == .None) : (result = try battle.update(c1, c2, &options)) {
    c1 = choices[random.uintLessThan(u8, battle.choices(.P1, result.p1, &choices))];
    c2 = choices[random.uintLessThan(u8, battle.choices(.P2, result.p2, &choices))];
}

std.debug.print("{}\n", .{result.type});
```

[(full code)](examples/zig/example.zig)

The Zig package also supports some APIs which are difficult to expose elsewhere such as the
`FixedRNG` which allows you to fully specify the exact RNG frames (which can be useful for ensuring
certain outcomes/effects always occur) for a battle, though doing so changes the size of the
`Battle` object.

### Other

Developers who wish to use the engine in other languages should find writing bindings against
[`libpkmn`](#libpkmn) relatively straightforward based on the existing documentation, though to
simplify the process even further [`src/data`](src/data) contains JSON dumps of all of the Pokémon
data, structure sizes and offsets, and protocol information used by the reference driver code. The
following is a list of known `libpkmn` bindings written by developers outside of the [pkmn
organization](https://github.com/pkmn) that may be helpful (though note that these projects may not
necessarily be up-to-date/complete/correct - inclusion in this list doesn't imply endorsement):

| Language   | License   | URL                                  |
| ---------- | --------- | ------------------------------------ |
| **C++**    | `BSL-1.0` | https://github.com/pasyg/wrapsire    |
| **Python** | `MIT`     | https://github.com/AnnikaCodes/PyKMN |


#### `pkmn-debug`

The [`@pkmn/engine`](#pkmnengine) package ships with a `pkmn-debug` tool which exists to decode the
binary data structures and protocols used by the engine and to output a [standalone
webpage](https://pkmn.cc/debug.html) that can be used for debugging. To use this tool in a folder
that has the `@pkmn/engine` package installed locally you can use `npx pkmn-debug`, though you may
also wish to install the package globally to be able to use this tool anywhere without
[`npx`](https://docs.npmjs.com/cli/v7/commands/npx):

```sh
$ npm install --global @pkmn/engine
```

By default, `pkmn-debug` expects to read [binary debug protocol](docs/PROTOCOL.md#debugging) from
[standard input](https://en.wikipedia.org/wiki/Standard_streams) and output HTML to standard output:

```sh
$ <cmd> | pkmn-debug > index.html
```

Alternatively, if a single filename argument is passed to the `pkmn-debug` it reads from that
instead:

```sh
$ pkmn-debug <file> > index.html
```

## Status

The engine is currently expected to be developed over multiple stages:

| Stage   | Deliverables                                    |
| ------- | ----------------------------------------------- |
| **0**   | documentation, integration, benchmark, protocol |
| **1**   | RBY & GSC                                       |
| **2**   | ADV & DPP                                       |
| ***3*** | *modern generations*                            |

Currently, most of the foundational work from stage 0 is done:
  
- [benchmark and integration testing](src/test) infrastructure
- [documentation](docs) about design, research, methodology, etc
- definition and implementation of the [protocol](docs/PROTOCOL.md) that's used by the engine

**Stage 1 is currently in progress** and involves the implementation of the actual Generation I & II
battle engines, followed by Generation III & IV in stage 2. The implementation of further Pokémon
generations is in scope for the project but shouldn't be considered part of the immediate roadmap
(i.e. exploring the options for broadening support for old generation APIs is given higher priority
than implementing more modern generations). Furthermore, implementation of modern generations is
soft-blocked on the [availability of high quality
decompilations](https://github.com/orgs/pret/repositories) of the original games in question.

Certain features will always be deemed **out of scope**:

- team/set validation or custom rule ("format") enforcement
- first-class support for "mods" to core Pokémon data and mechanics
- [battle variants](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_battle#Battle_variants)
  other than single (full) or double battles
- code for exposing the engine to users (input validation, game socket server, etc)

## License

The pkmn engine is distributed under the terms of the [MIT License](LICENSE).

[^1]: In the case of Pokémon Showdown, only bugs which stem from a misimplementation of specific
  effects are reproduced in the engine, bugs which are the result of a misunderstanding of the
  fundamental mechanics of Pokémon or which simply arise due to specific Pokémon Showdown
  implementation details that aren't replicable without making the same (incorrect) architectural
  choices aren't. Furthermore, the "Pokémon Showdown" code referenced by this project includes
  several [patches](docs/TESTING.md#patches) to improve accuracy and smooth over some of the more
  egregious implementation issues. In practical terms, the vast majority of games played out in the
  pkmn engine's compatibility mode and on this patched Pokémon Showdown simulator are the same,
  it's only in a well defined and documented set of circumstances where the two implementations
  diverge.
