# Testing

In addition to [unit tests](#unit), the code in [`src/test`](../src/test) contains harnesses for
[integration testing](#integration) and [benchmarking](#benchmark) against Pokémon Showdown.

## Unit

Due to the various build options (e.g. `-Dshowdown` or `-Dlog`) and the stochastic nature of Pokémon
as a game, testing the pkmn engine requires a little extra work. Helper functions exist to remove
the majority of the boilerplate from the library's unit tests:

- `Test`: the main helper type for testing, a test can be initialized with `Test(rolls).init(p1,
  p2)` (`Test.deinit()` should be `defer`-ed immediately after initialization to free resources),
  expected updates and logs can be tracked on the `expected` fields and finally the `actual` state
  can be `verify`-ed at the end of the test. `expectProbability` can be used to check probabilities
  when `-Dchance` is enabled, and if `-Dcalc` is also enabled each update gets rerun on the original
  state with the chance actions from the original update used as overrides to ensure all RNG is
  accounted for.
- `Battle.fixed`: under the hood, `Test` uses this helper to create a battle with a `FixedRNG` that
  returns a fixed sequence of results ("rolls") - this provides complete control over whether or not
  events should occur. One problem is that `-Dshowdown` Pokemon Showdown compatibility mode requires
  a different number and order of rolls, meaning both must be specified. Furthermore, at the end of
  the test it's important to verify that all of the rolls provided were actually required with `try
  expect(battle.rng.exhausted())` - unexpectedly unused rolls could point to bugs (`Test.verify()`
  automatically checks that the `rng` is exhausted).

### Patches

The pkmn engine aims to match Pokémon Showdown when run in `-Dshowdown` compatibility mode, but
unfortunately it's impossible to match Pokémon Showdown's behavior without also duplicating its
incorrect architecture and event/handler/action system due to how this architecture results in many
artificial "speed ties" which cause RNG frame advances. This is deemed to be out of scope for the
pkmn engine, as it seeks to match Pokémon Showdown purely for practical reasons (to leverage for
integration testing purposes/to provide more "accurate" playouts for AI applications built to play
on Pokémon Showdown) only, and adding the byzantine logic and fields required to be able to
perfectly replicate Pokémon Showdown's bugs simply distracts from the goal of building an optimal
Pokémon battle engine.

In order to reconcile this, the pkmn engine instead aims to match a *patched* version of Pokémon
Showdown, where minimal changes have been made to Pokémon Showdown to improve correctness and
eliminate unnecessary nondeterministic elements:

- `Battle#eachEvent` and `Battle#fieldEvent` have been changed to not perform a
  `Battle#speedSort` in Generation I and II, which should result in events being executed in the
  order they're added, ultimately resulting in Player 1's events occurring before Player 2's
  regardless of speed, effectively recreating the cartridge's default "host" ordering semantics
- `BattleQueue#insertChoice` is patched to also obey "host" ordering in Generation I and II
- "priorities" have been added to various handler functions to break speed ties and ensure that
  there either no unnecessary rolls or events deterministically get resolved in the order they're
  resolved on the cartridge

These patches do **not** fix Pokémon Showdown implementation bugs beyond a subset of speed tie
semantics, and do **not** fix all issues regarding unnecessary RNG frame advances from speed ties
(e.g. moves with a `beforeTurnCallback` on Pokémon Showdown still potentially result in speed tie
rolls), they simply aim to make minimally intrusive changes that allow for Pokémon Showdown behavior
to be reproduced by the pkmn engine. These patches should also strictly result in a performance
improvement compared to vanilla Pokémon Showdown, as they cause Pokémon Showdown to perform less
sorting and RNG frame advances than it otherwise would, which effectively
["steelmans"](https://en.wikipedia.org/wiki/Straw_man#Steelmanning) the implementation for
benchmarking purposes.

### `showdown`

In order to verify Pokémon Showdown's behavior, many of the pkmn engine's unit tests are mirrored in
the [`showdown`](../src/test/showdown/) directory. It should be emphasized that these are tests
against [patched](#patches) Pokémon Showdown, **not** the pkmn engine (engine code isn't being
tested). Pokémon Showdown's own unit tests are inadequate for the pkmn engine's purposes as they
mostly cover the latest generation, don't use a fixed RNG, and don't verify logs (both of which
are crucial for matching Pokémon Showdown's RNG and output).

### Guidelines

The following guidelines should be taken into consideration when adding new unit tests:

1. Support should be added to the [`generate`](../src/tools/generate.ts) tool for the generation in
  question - `npm run generate  -- tests <GEN>` is used to first generate stubs for all of the
  effects that need to be tested (the generated stubs need to be massaged quite a bit, but serve as
  a good first rough draft).
2. Tests should be ordered such that they match the order from previous generations as closely as
   possible, and new effects should be grouped with similar effects. General engine/battle flow test
   cases should also be preserved from past generations where applicable.
3. Effects should have all of the behavior outlined in their descriptions on
   [Bulbapedia](https://bulbapedia.bulbagarden.net) and [Smogon](https://smogon.com/dex) tested
   (though these sources shouldn't be assumed to be correct). Additionally, any reported Pokémon
   Showdown bugs and all documented cartridge glitches should be tested.
4. Copy as much as possible from previous generations' test cases - preserving the original test
   makes it easier to see how much of the behavior has changed vs. remained over the generations. If
   the behavior has significantly diverged then coming up with a brand new test case might be
   preferable.
5. Ideally, every species, item, move, ability, etc should show up at least once in the test file -
   try to use as diverse a range of options as possible, though prefer movesets which are "natural"
   (choose similarly tiered species using moves that occur in their movesets, prefer that
   "signature" [moves](https://bulbapedia.bulbagarden.net/wiki/Signature_move) and
   [abilities](https://bulbapedia.bulbagarden.net/wiki/Signature_Ability) are present on the
   correct evolutionary lines, etc).
6. If creating a test for a Pokémon Showdown bug or a video demonstrating a glitch, prefer to match
   the original reproduction's setup.
7. Prefer most tests use the "default" stats (level 100, full stat experience in Generation I & II
   and no Effort Values in Generation III+, etc).
8. Long test cases that demonstrate the majority of an effects behavior are preferable to
   individually scoped testing (this is contrary to most testing best practices, but minimizing the
   amount of setup necessary is deemed preferable to the alternative).
9. For complex effects which interact with a wide variety of other effects (e/g. Substitute, Baton
   Pass), prefer to test just the "base" functionality in the complex effect's test case and its
   various interactions with other effects in the test case demonstrating the other effect's
   behavior.
10. Avoid unnecessary rolls and log messages. Fall back on moves like Splash where reasonable and
    avoid test setups involving speed ties unless speed ties are specifically being tested.
11. Avoid performing artificial alterations of the battle state mid-test unless required. Tests
    which require status should acquire it as part of the test (Pokémon Showdown's cleric clause
    means starting the battle with status is difficult), and HP/PP should ideally be manipulated
    before the test begins.
12. Minimize the number of sub-tests that are created - they should only be necessary if they
    involve a vastly different setup than the primary test case.
13. If behavior differs in single vs. double battle styles, test both. Otherwise choose a mix of
    single and double battles for testing.

## Integration

The [integration test](../src/test/integration.test.ts) exists to ensure the pkmn engine compiled in
Pokémon Showdown compatibility mode with `-Dshowdown` produces comparable output to
[patched](#patches) Pokémon Showdown. For each supported generation, both Pokémon Showdown and the
pkmn engine are run with an
[`ExhaustiveRunner`](https://github.com/smogon/pokemon-showdown/blob/master/sim/tools/exhaustive-runner.ts)
that attempts to use as many different effects as possible in the battles it randomly simulates and
the results are collected. While Pokémon Showdown always produces its text protocol streams, pkmn
must be built specially to opt-in to introspection support (`-Dlog`).

The pkmn [binary protocol](PROTOCOL.md) isn't expected to be equivalent to Pokémon Showdown for
several reasons:

- pkmn doesn't have any notion of a
  ['format'](https://github.com/smogon/pokemon-showdown/blob/master/config/formats.ts) or [custom
  'rules'](https://github.com/smogon/pokemon-showdown/blob/master/config/CUSTOM-RULES.md)
- the ordering of keyword arguments in Pokémon Showdown isn't strictly defined
- several of Pokémon Showdown's protocol messages are redundant/implementation specific
- pkmn always returns a single "stream" and always includes exact HP (i.e. Pokémon Showdown's
  "omniscient" stream) - other streams of information must be computed from this
- [despite what it may claim](https://pokemonshowdown.com/pages/rng), Pokémon Showdown does **not**
  implement the correct pseudo-random number generator for each format (it implements the Generation
  V & VI PRNG and applies it to all generations and performs a different amount of calls, with
  different arguments and in different order than the cartridge)

The integration test contains logic to configure Pokémon Showdown to produce the correct results and
for massaging the output from the pkmn engine into something which can be compared to Pokémon
Showdown. Care is taken to ensure that where they disagree the actual cartridge decompilations are
used as the arbiter of correctness, but it's still possible that since Pokémon Showdown and the
pkmn engine are both independent implementations of the actual Pokémon cartridge logic  despite
being in agreement **they may both be incorrect** when it comes to the actual cartridge[^1].

Most integration test failures result in new unit tests being added, though the failing logs are
also saved as [fixtures](../src/test/regression/fixtures) which can then be replayed to protect
against [regressions](../src/test/regression/). The integration test also supports being run in
standalone mode for various durations, e.g. `npm run integration -- --duration=15m` which can be
useful for [fuzzing](#fuzz) purposes.

[^1]: A stretch goal for the project is to be able to run integration tests against the actual
    cartridge code.
    [Examples](https://github.com/jsettlem/elo_world_pokemon_red/blob/master/battle_x_as_y.py) exist
    of scripting battles to run on the cartridge via an emulator, though the fact that integration
    testing the engine properly requires support for "link" battling and the ability to detect
    desyncs makes such a goal decidedly nontrivial.

### Unimplementable

Some of Pokémon Showdown's bugs are too convoluted to be implemented in the pkmn engine, even after
[patches](#patches) are applied. The engine tries its best to reproduce the behavior of even the
most misunderstood and broken mechanics of Pokémon Showdown, but in the same way that implementing
the cartridge behavior correctly is difficult starting from Pokémon Showdown's architecture,
implementing Pokémon Showdown's mechanics is also difficult starting from an architecture that
mirrors the cartridge.

For the purposes of the [benchmark](#benchmark) one could simply choose to not generate any sets
with problematic Pokémon / Items / Abilities / Moves, but for integration testing purposes it makes
sense to add some complexity to be able to test as much as possible (teams are validated before
starting a battle to ensure a battle isn't started with moves that have issues when used together,
and during a battle if Pokémon Showdown is observed to be in an undesirable state it simply aborts
and move to the next battle).

## Benchmark

Benchmarking the pkmn engine vs. Pokémon Showdown is slightly more complicated than simply using a
tool like [`hyperfine`](https://github.com/sharkdp/hyperfine) due to the need to account for the
runtime overhead and warmup period required by V8 (`hyperfine --warmup` is intended to help with
disk caching, not JIT warmup). As such, a [custom benchmark tool](../src/test/benchmark.ts) exists
which can be used to run the benchmark. The benchmark measures how long it takes to play out N
randomly generated battles, excluding any set up time and time spent warming up the JS
configurations. This benchmark scenario is useful for approximating the [Monte Carlo tree
search](https://en.wikipedia.org/wiki/Monte_Carlo_tree_search) use case where various battles are
played out each turn to the end numerous times to determine the best course of action.

Notably, the benchmark doesn't attempt to measure the performance of Pokémon Showdown via either its
`BattleStream` abstraction or the `pokemon-showdown` binary. The `BattleStream` isn't that difficult
to use (though you need to use a special `RandomPlayerAI` that directly inspects the `Battle` to
avoid making unavailable choices and matches the AI used by all of the other configuration in
addition to directly accessing the `BattleStream`s internal `Battle` object to more easily be able
to grab the turn count and also to [patch fix various speed ties](#patches).), the main concern is
that due to Pokémon Showdown's poor handling of promises internally it's fairly trivial to encounter
race conditions that desync the benchmark. Pokémon Showdown's root `pokemon-showdown` binary is
technically the blessed approach to using the simulator, but `BattleStream` is effectively the same
thing but without the (sizeable) I/O overhead. Attempting to use the actual `pokemon-showdown`
binary is deemed too difficult as there would then be no way to inspect the `Battle` to avoid making
unavailable choices[^2], meaning it would be difficult to keep in sync with the other
configurations.

Before running the benchmark, care needs to be taken to set up the environment to be as stable as
possible, e.g. [disabling CPU performance scaling, Intel Turbo Boost,
etc](https://easyperf.net/blog/2019/08/02/Perf-measurement-environment-on-Linux). The benchmark tool
measures 3 different configurations:

- **`DirectBattle`**: this configuration introduces the concept of a `DirectBattle` which
  overrides the Pokémon Showdown `Battle` class to strip out unused functionality:

    1. methods which add to the battle log are overridden to drop any messages immediately
    2. `sendUpdates` is overridden to not send any updates
    3. `makeRequest` avoids serializing the request for each side

  The `DirectBattle` is then used synchronously as opposed to via the async `BattleStream` which is
  about 10% faster and obviates needing to care about races. This configuration minimizes string
  processing overhead and unnecessary delays due to `async` calls and is as close to as fast as
  Pokémon Showdown can be run (there is room for further optimization by simplifying choice parsing
  to not perform any verification, though this is significantly less trivial than the aforementioned
  optimizations). This is closer to how the pkmn engine runs without `-Dlog`. Finally,
  `DirectBattle` is [patched](#patches) to eliminate unnecessary as covered earlier.

- **`@pkmn/engine`**: this configuration uses the `@pmn/engine` driver package to run battles with
  the pkmn engine.

- **`libpkmn`**: this configuration runs battles directly with the `libpkmn` library and doesn't
  interface with JS at all. The benchmark runner invokes
  [`benchmark.zig`](../src/test/benchmark.zig) to directly run the benchmark and report the results.

Both pkmn engine configurations are intended to be used `-Dshowdown` build option but with all other
build options turned off. Both of the Pokémon Showdown configurations are run beforehand for a warmup
period to ensure the measured duration is representative of the actual best case runtime.

In order to ensure all configurations are testing the same thing, one must ensure that the exact
same battles are generated, the same sequence of moves are chosen, and the battle results are match.
As such, all benchmarks are run with the same PRNGs that have been initialized with the same seeds,
and the logic for generating battles/randomly choosing moves is duplicated across  both the Zig and
TypeScript implementations. Finally, in addition to total duration, the benchmarking tool tracks and
compares the total number of turns across all battles and the final RNG seed to serve as a
"checksum" and verify that all of the configurations are in agreement - Pokémon Showdown requires
that one:

- serialize the player's teams passed to the `Battle` constructor, as Pokémon Showdown mutates
  them
- drive both players with separate PRNGs from each other and from the `Battle`, as there is no
  guarantee around the order of operations (Pokémon Showdown has numerous races and
  [unpleasantries](https://github.com/smogon/pokemon-showdown/issues/8546))

Note that how long a given battle takes is heavily dependent on the teams in question. The benchmark
runs on teams that have effectively been generated using ["Challenge
Cup"](https://bulbapedia.bulbagarden.net/wiki/Challenge_Cup) semantics, and because this includes
numerous sub-optimal moves (e.g. Thunder Shock in addition to Thunderbolt, instead of just the
latter) it's expected to take substantially longer than more traditional ["Random Battle"
sets](https://github.com/pkmn/randbats) or handcrafted teams. **Experimentally the random sets used
by the benchmark are expected to be roughly 2-3× slower than what would be typical in practice.**

[^2]: It's possible to remain in sync between configurations which can inspect `Battle` and those
that can't by always saving the raw result returned by the last RNG call and reapplying it to the
next request in the event of an "[Unavailable choice]" error (e.g. call the RNG and get back `r`,
attempt to choose the `r % N`-th choice, get rejected, on the next request don't generate a new `r`
but instead now make the `r % M`-th choice where `M` is the actual available choices post
rejection). Since it isn't especially important to demonstrate how much slower the (already slow)
async `BattleStream` API when you introduce syscall overhead into the mix, this workaround is left
as an exercise to the reader.

### Results

The results for the table below come from running the benchmarks against
[pkmn/engine@9ce6e379](https://github.com/pkmn/engine/commit/9ce6e379) on an `n2d-standard-48` Google
Cloud Compute Engine machine with 192 GB of memory and an AMD EPYC 7B12 CPU running 64-bit x86 Linux
which has undergone the pre-benchmark tuning detailed below via the command `npm run benchmark --
--battles=10000`:

| Generation | `libpkmn` | `@pkmn/engine` | `DirectBattle` |
| ---------- | --------- | -------------- | -------------- |
| **RBY**    | 195 ms    | 737 ms (3.78×) | 618 s (3167×)  |

*It's important to note that the relative performance differences between the various
configurations depend on the exact choice of machine used for testing (though the orders of
magnitude seen here are expected to hold).*

<details><summary>CPU Details</summary><pre>
Architecture:            x86_64
  CPU op-mode(s):        32-bit, 64-bit
  Address sizes:         48 bits physical, 48 bits virtual
  Byte Order:            Little Endian
CPU(s):                  48
  On-line CPU(s) list:   0-47
Vendor ID:               AuthenticAMD
  Model name:            AMD EPYC 7B12
    CPU family:          23
    Model:               49
    Thread(s) per core:  2
    Core(s) per socket:  12
    Socket(s):           2
    Stepping:            0
    BogoMIPS:            4499.99
    Flags:               fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cp
                         uid extd_apicid tsc_known_freq pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand hypervisor lahf_lm cmp_legacy cr8_legacy abm sse4a misalignsse 3dnowprefet
                         ch osvw topoext ssbd ibrs ibpb stibp vmmcall fsgsbase tsc_adjust bmi1 avx2 smep bmi2 rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 clzero xsaveerptr arat npt nrip_save um
                         ip rdpid
Virtualization features:
  Hypervisor vendor:     KVM
  Virtualization type:   full
Caches (sum of all):
  L1d:                   768 KiB (24 instances)
  L1i:                   768 KiB (24 instances)
  L2:                    12 MiB (24 instances)
  L3:                    96 MiB (6 instances)
NUMA:
  NUMA node(s):          2
  NUMA node0 CPU(s):     0-11,24-35
  NUMA node1 CPU(s):     12-23,36-47
Vulnerabilities:
  Itlb multihit:         Not affected
  L1tf:                  Not affected
  Mds:                   Not affected
  Meltdown:              Not affected
  Spec store bypass:     Mitigation; Speculative Store Bypass disabled via prctl
  Spectre v1:            Mitigation; usercopy/swapgs barriers and __user pointer sanitization
  Spectre v2:            Mitigation; Retpolines, IBPB conditional, IBRS_FW, STIBP conditional, RSB filling
  Srbds:                 Not affected
  Tsx async abort:       Not affected
</pre></details>
<details><summary>Setup</summary>

Provision a [spot](https://cloud.google.com/compute/docs/instances/spot) Google Cloud Compute Engine
instance with a [Minimal Ubuntu LTS](https://wiki.ubuntu.com/Minimal) image that's deleted after
after 30 minutes using the [`gcloud` command-line tool](https://cloud.google.com/sdk/gcloud) and SSH
into it:

```sh
# Configure to auto-terminate for safety; when done we can also manually run:
#
#    $ gcloud compute instances stop pkmn-engine-benchmark
#    $ gcloud compute instances delete pkmn-engine-benchmark
#
gcloud beta compute instances create pkmn-engine-benchmark \
	--zone=us-central1-a \
	--machine-type=n2d-standard-48 \
	--image-project=ubuntu-os-cloud \
	--image-family=ubuntu-minimal-2204-lts \
	--max-run-duration=30m \
	--provisioning-model=SPOT \
	--instance-termination-action=DELETE

# Need to wait a bit before SSH will succeed...
sleep 15
gcloud compute ssh pkmn-engine-benchmark
```

On the VM, install dependencies:

```sh
# Install system packages
sudo apt update
sudo apt --assume-yes install git cpuset
# Shallow clone the pkmn engine code
git clone -–depth 1 https://github.com/pkmn/engine.git
cd engine
# Set up Node
curl -fsSL https://raw.githubusercontent.com/tj/n/master/bin/n | sudo bash -s lts
# Install package dependencies + put the locally installed Zig on the PATH
npm install
export PATH="$(pwd)/build/bin/zig:$PATH"
```

The tuning script can then be run as root to perform the benchmark:

```sh
sudo --preserve-env=PATH env ./benchmark.sh
```
</details>
<details><summary>Tuning</summary>

```sh
#!/bin/bash

function cleanup() {
    # Turn back on hyperthreading
    for cpu in {1..47}
    do
      echo 1 > /sys/devices/system/cpu/cpu$cpu/online
    done

    # remove CPU shielding
    cset shield --reset >/dev/null 2>&1
}
trap cleanup EXIT

# Turn off hyperthreading based on /sys/devices/system/cpu/cpu*/topology/thread_siblings
for cpu in {24..47}
do
  echo 0 > /sys/devices/system/cpu/cpu$cpu/online
done

# Sadly we are unable to disable CPU boosting or change the CPU governor to performance

# Set up a shield and move all threads (including kernel threads) out
cset shield -c 1-9 -k on >/dev/null 2>&1

# Drop filesystem cache
echo 3 > /proc/sys/vm/drop_caches
sync

# Run benchmark command within shield at highest possible priority
# (can add '--battles=100000 --iterations=50' flags to execute regression benchmark)
cset shield --exec -- nice -n -19 node build/test/benchmark
```
</details>

### Regression

In addition to being used to compare the pkmn engine to Pokémon Showdown, the [benchmark
tool](../src/test/benchmark.ts) has an alternative mode that allows it to better detect regressions
in the engine's performance. When the `--iterations` flag is used the tool instead runs multiple
iterations of battle playouts from the same seed against the engine and outputs a TSV with the
results. These results can then be fed back into the script to determine how performance changed:

```sh
npm --silent run benchmark -- --iterations=50 > logs/before.tsv
# <make changes>
npm --silent run benchmark -- --iterations=50 logs/before.tsv
```

Alternatively, a text or JSON `--summary` can be produced - in order to minimize noise, the mean of
all the iterations is reported after outliers have been removed.

## Fuzz

The [integration](#integration) tests and a standalone [fuzz](../src/test/fuzz.zig) are also used
for [fuzzing](https://en.wikipedia.org/wiki/Fuzzing). A [GitHub
workflow](../.github/workflows/fuzz.yml) exists to run these tests on a schedule from random seeds
for various durations to attempt to uncover latent bugs. The fuzz tests differ from the benchmark in
that they run for predefined time durations as opposed to a given number of battles and enable the
[unimplementable](#unimplementable) effects that are usually excluded in `-Dshowdown` compatibility
mode. When run with the `-Dlog` flag, additional binary data is dumped on crashes to allow for
debugging with the help of [`fuzz.ts`](./fuzz.ts) and the [debug UI](https://pkmn.cc/debug.html)
rendered by [`debug.ts`](../src/tools/debug.ts). If `-Dchance` and `-Dcalc` are enabled the fuzz
test also ensures a `transitions` function can correctly detect all valid transitions without
crashing.

To run the fuzz tool locally use:

    $ npm run --silent fuzz  --  <pkmn|showdown> <GEN> <DURATION> <SEED?>
