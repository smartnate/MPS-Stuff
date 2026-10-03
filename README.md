# chain.lol — Facility build

The chain.lol UI rebuilt on the [Facility](https://github.com/FacilityHUB/UI-Facility) library.

- **`chain_facility.lua`** — the full script. Load it in your executor; it fetches Facility and its addons itself.
- Every feature, default, keybind and config from the original is preserved — see the header comment for the full old-to-new API map and the few documented incompatibilities.
- Verified with a 4-scenario runtime harness (desktop / mobile / MMP / VEF), 870 assertions, all passing.
