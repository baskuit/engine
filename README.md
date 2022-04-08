<p align="center">
  <img alt="pkmn/engine" width="192" height="192" src="https://pkmn.cc/engine.svg" />
  <br />
  <br />
  <a href="https://github.com/pkmn/engine/actions/workflows/test.yml">
    <img alt="Test Status" src="https://github.com/pkmn/engine/workflows/Tests/badge.svg" />
  </a>
  <a href="#status">
    <img alt="WIP" src="https://img.shields.io/badge/status-WIP-red.svg" />
  </a>
  <a href="https://github.com/pkmn/engine/blob/master/LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-blue.svg" />
  </a>
</p>

A minimal, complete, Pokémon battle simulation engine optimized for performance and designed for
tooling, embedded systems, and [artifical intelligence](https://github.com/pkmn/0-ERROR) use cases.

## Installation

This repository hosts both the engine code (written in [Zig](https://ziglang.org/)) and driver code
(written in [TypeScript](https://www.typescriptlang.org/)).

### `libpkmn`

Binaries of the engine code can be downloaded from the
[releases](https://github.com/pkmn/engine/releases) tab on GitHub, or you can [download the source
code](https://github.com/pkmn/engine/archive/refs/heads/main.zip) directly and build it with the
latest `zig` compiler, see `zig build --help` for build options.:

```sh
$ curl https://github.com/pkmn/engine/archive/refs/heads/main.zip -o engine.zip
$ unzip engine.zip
$ cd engine
$ zig build --prefix .
```

The Zig website has [installation instructions](https://ziglang.org/learn/getting-started/) which
walk through how to install Zig on each platform - the engine code should work on Zig v0.9.0 or
greater, though tracks Zig's master branch so this may change in the future if breaking language
changes are introduced.

### `@pkmn/engine`

The driver code can be installed from [npm](https://www.npmjs.com/package/@pkmn/engine):

```sh
$ npm install @pkmn/engine
```

The driver depends on being able to find the `pkmn.node` library to be useful. By default it will
look in `node_modules/@pkmn/engine/lib` for this, and if the library cannot be found it will check
if there is a `zig` compiler with the correct version available in order to build the library and
place it in the correct location as part of its `postinstall` script. If there is not system-wide
`zig` you can either follow the instructions above to install `zig`, build the library, and move it
to the correct folder, or (recommended) **run the `install-pkmn-engine` script that is bundled with
the library:**

```sh
$ npx install-pkmn-engine
```

`install-pkmn-engine` will download and install the correct version of the  `zig` compiler locally
to `node_modules/@pkmn/engine/bin/zig` and build the `pkmn.node` file to the correct location. `npm`
should notify you with these options when you attempt to install the package.

## Usage

### C

[example code](src/examples/c)

```c
#include <pkmn.h>

Battle *battle = ....;
result_t result;
choice_t c1 = 0, c2 = 0;
while (!RESULT_TYPE(result = battle->update(c1, c2, log))) {
  if (RESULT_ERROR(result)) exit(1); // 0xFF
  c1 = choose(p1, RESULT_P1(result));
  c2 = choose(p2, RESULT_P2(result));
}
```

### JavaScript / TypeScript

[example code](src/examples/js)

```ts
import {Dex} from '@pkmn/dex';
import {Generations} from '@pkmn/data';
import {Battle} from '@pkmn/engine';

const gens = new Generations(Dex);
const battle = Battle.create(gens.get(1), team1, team2);
```

### Zig

[example code](src/examples/zig)

```zig
const std = @import("std");
const pkmn = @import("pkmn");

var random = std.rand.DefaultPrng.init(seed).random();
var options: [pkmn.MAX_OPTIONS_SIZE]pkmn.Choice = undefined;

var battle = ...

var c1 = pkmn.Choice{};
var c2 = pkmn.Choice{};

var result = try battle.update(c1, c2, null);
while (result.type == .None) : (result = try battle.update(c1, c2, null)) {
    c1 = options[random.uintLessThan(battle.choices(.P1, result.p1, options))];
    c2 = options[random.uintLessThan(battle.choices(.P2, result.p2, options))];
}

try std.debug.print("{}", result.type);
```

## Status

The simulation engine is currently expected to be developed over multiple stages:

| Stage   | Deliverables                                    |
| ------- | ----------------------------------------------- |
| **0**   | documentation, integration, benchmark, protocol |
| **1**   | RBY & GSC                                       |
| **2**   | ADV & DPP                                       |
| _**3**_ | _BW & XY & SM & SS & SV_                        |

Currently, most of the foundational work from stage 0 is done:
  
- [benchmark and integration testing](src/test) infrastructure
- [documentation](docs) about design, research, methodology, etc
- definition and implementation of the [protocol](docs/PROTOCOL.md) that will be used by the engine

**Stage 1 is currently in progress** and will see the implementation of the actual Generation I & II
battle engines, followed by Generation III & IV in stage 2. The implementation of further Pokémon
generations is in scope for the project but should not be considered as part of the immediate
roadmap (ie. exploring the options for broadening support for old generation APIs will be given
higher priority than implementing more modern generations).

Certain features will always be deemed **out of scope**:

- team/set validation or custom rule ("format") enforcement
- first-class support for "mods" to core Pokémon data and mechanics
- [battle variants](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_battle#Battle_variants)
  other than single (full) or double battles
- code for exposing the engine to users (input validation, game socket server, etc)

## License

The pkmn engine is distributed under the terms of the [MIT License](LICENSE).
