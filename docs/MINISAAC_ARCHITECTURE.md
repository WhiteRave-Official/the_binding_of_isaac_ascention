# Mini Isaac combat in Ascention

`scripts/minisaac/incubus_router.lua` now creates one invisible Incubus per
Mini Isaac when `zhlAscention.dll` is loaded. Its aim is selected independently
of the player's input. `native/src/MiniIsaacWeapon.cpp` drives the Incubus's
native `Weapon::Fire` and suppresses normal player-input firing for managed
proxies. This avoids the timing failure of `MC_INPUT_ACTION`.

`scripts/minisaac/combat.lua` remains the fallback route without the DLL. Vanilla Mini
Isaac AI handles movement; Spirit Sword alone adjusts velocity toward melee
range. `scripts/minisaac/formation.lua` builds its multishot formation.

`scripts/golden_eye_weapon_adapter.lua` remains specific to Golden Eye. Native
Mini Isaac damage and size are scaled by `scripts/minisaac/native_weapon_adapter.lua`.
`scripts/minisaac/charge_visuals.lua` renders Mini Isaac costumes.

The native route discards the vanilla Mini Isaac tear. In fallback mode,
`combat.lua` replaces it with the selected weapon attack.

If Dynamic Minisaacs Forever is loaded, Ascention's combat dispatcher yields
to it rather than changing its callbacks. Disable Dynamic to test the new
implementation. The old compat files remain in the repository for comparison
but are not loaded by `main.lua`.

## In-game validation

- Normal tears and 20/20, Inner Eye, Mutant Spider: exact shot count, small
  visuals, no recursive split tears.
- Brimstone, Technology, Tech X, and their combinations: direction, beam/ring
  variant, damage, and no extra vanilla tear.
- Monstro's Lung alone and with lasers: spread, firing rate, and performance.
- Mom's Knife and Spirit Sword: visible weapon, contact damage, return/cleanup,
  and melee pursuit without changing the Mini Isaac skin.
- Dr. Fetus: bomb ownership, explosion damage, and modifiers.
- Several Mini Isaacs, co-op, and room transitions: independent ownership and
  deterministic output.

Build and install on Windows with matching REPENTOGON sources:

```powershell
.\scripts\build-native.ps1
.\scripts\install-native.ps1
```

The DLL belongs in the active game's `repentogon` directory, not the Workshop
mod folder. `install-native.ps1 -GameDirectory <path>` supports another game
location. Compilation does not prove charged weapons work with direct `Fire`;
test idle-player firing, all charged synergies, co-op, and room transitions in game.
