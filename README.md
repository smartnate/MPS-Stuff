# chain.lol — Facility build

The chain.lol UI rebuilt on the [Facility](https://github.com/FacilityHUB/UI-Facility) library.

- **`chain_facility.lua`** — the full script. Load it in your executor; it fetches Facility and its addons itself.
- Every feature, default, keybind and config from the original is preserved — see the header comment for the full old-to-new API map and the few documented incompatibilities.
- **Reach tab** uses a nested tree sidebar (Attacking / Playmaking / Defending groups with tree-branch lines, expandable) that filters the per-move pages; the rest of the menu uses full-width multisections, split columns and per-toggle ⚙ gear popups.
- The character preview is a themed `Library:Panel` docked next to the window.
- Verified with a 4-scenario runtime harness (desktop / mobile / MMP / VEF), 891 assertions, all passing.
