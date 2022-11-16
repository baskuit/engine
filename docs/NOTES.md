## Adding a new Generation

1. **[Research](./RESEARCH.md)** the data structures and code flow
2. Add a `data.zig` file with **basic data types** (`Battle`, `Side`, `Pokemon`, ...) and fields
   - unoptimized - exact layout tweaked in step 11
3. **[Generate](../src/tools/generate.ts) data** files
   - reorder enums for performance
   - update [`Lookup`](../src/pkg/data.ts) if necessary
4. **[Generate](../src/tools/generate.ts) test** files
   - reorganize logically and to match previous generations
   - add in cases for known Pokémon Showdown bugs and cartridge glitches
5. **Copy over shared code/files**
   - copy over `README.md` for new generation
   - copy over imports and public function skeletons in `mechanics.zig`
   - copy `Test` infrastructure and rolls into `test.zig`
   - copy over `helpers.zig`
6. Implement **unit [tests](../src/test/showdown/) against Pokémon Showdown** behavior
   - update Bugs section of generation documentation as bugs are discovered
7. Implement **mechanics** in `mechanics.zig` based on cartridge research
   - update [protocol](../src/lib/common/protocol.zig) as necessary, also updating
     [documentation](PROTOCOL.md), [driver](../src/pkg/protocol.ts), and tests
   - [generate](../src/tools/protocol.zig) updated [`protocol.json`](../src/pkg/data/protocol.json)
8. Adjust **mechanics for Pokémon Showdown** compatability
   - track RNG differences and update [tool](../src/tools/rng.zig) and generation documentation
   - ensure all bugs are tracked in documentation
   - [blocklist](../src/test/blocklist.json) any unimplementable effects
9. **Unit test the engine** in both cartridge and Pokémon Showdown compatability mode
10. Implement a **`MAX_LOGS` unit test**
    - document in [`PROTOCOL.md`](PROTOCOL.md)
    - validate with [`max_logs.py`](../src/tools/max_logs.py)
11. **Optimize data structures**
    - [generate](../src/tools/protocol.zig) updated [`layout.json`](../src/pkg/data/layout.json) and
     [`offsets.json`](../src/pkg/data/offsets.json)
12. Implement **driver serialization/deserialization** and writes tests
13. **Expose API** for new generation
    - update [`pkmn.zig`](../src/lib/pkmn.zig) and [bindings](../src/lib/bindings)
    - update [`index.ts`](../src/pkg/index.ts)
14. Write **`helper.zig`** and implement **`choices`** method
    - matching code required in [benchmark helpers](../src/tools/benchmark)
15. Ensure **[fuzz tests](../src/test/benchmark.zig)** pass
    - update [`fuzz.ts`](../src/tools/fuzz.ts) and [`display.ts`](../src/test/display.ts)
16. Ensure **[integration tests](../src/test/integration.test.ts)** pass
17. **[Benchmark](../src/test/benchmark.zig)** new generation
18. Finalize **documentation** for generation