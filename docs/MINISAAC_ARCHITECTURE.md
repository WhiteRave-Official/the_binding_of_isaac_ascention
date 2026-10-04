# Mini Isaac combat in Ascention

`scripts/minisaac/incubus_router.lua` now creates one invisible Incubus per
Mini Isaac when `zhlAscention.dll` is loaded. Its aim is selected independently
of the player's input. `native/src/MiniIsaacWeapon.cpp` drives the proxy's
weapon through `Weapon::Fire` and blocks engine-driven `Shoot()` for managed
proxies. An input override is scoped to this weapon call. It invokes `Shoot()`
once when a charged attack is released, not every tick.

`scripts/minisaac/combat.lua` remains the fallback route without the DLL. Vanilla Mini
Isaac AI handles movement; Spirit Sword alone adjusts velocity toward melee
range. `scripts/minisaac/formation.lua` builds its multishot formation.

`scripts/golden_eye_weapon_adapter.lua` remains specific to Golden Eye. Native
Mini Isaac damage and size are scaled by `scripts/minisaac/native_weapon_adapter.lua`.
`scripts/minisaac/charge_visuals.lua` renders Mini Isaac costumes.

The native route discards the vanilla Mini Isaac tear. In fallback mode,
`combat.lua` replaces it with the selected weapon attack.

## Native tear route and failure modes

- `incubus_router.lua` creates and registers an invisible Incubus proxy for each
  Mini Isaac. Its selected target is stored in `AscentionMiniIsaacAim`.
- `MC_FAMILIAR_UPDATE` calls `native.TickProxy` for ordinary tears. Do not
  return `true` from the proxy's `MC_PRE_FAMILIAR_UPDATE` while it has a target:
  that suppressed all native tear emission in the in-game test. The current
  idle-only guard returns `true` when no target exists, preventing the player
  from firing the hidden Incubus before combat. This guard is not yet tested.
  Calling `Incubus.Shoot()` manually after `Weapon::Fire` did not restore the observed
  behavior. Both experimental changes were removed to restore the last
  user-confirmed working ordinary-tear path.
- `Weapon::Fire` advances the shot state, but ordinary tear emission also
  depends on Incubus AI. These tears do **not**
  pass through `Entity_Familiar::FireProjectile` or
  `MC_POST_FAMILIAR_FIRE_PROJECTILE`. A nonzero `GetNumFired()` is not proof that
  either of those hooks ran. Observed tears had the proxy as `SpawnerEntity` and
  the player as `Parent`.
- `native_weapon_adapter.lua` redirects those tears in `MC_POST_TEAR_INIT`.
  It uses the first raw tear velocity per proxy/frame as the source direction,
  preserving relative multishot spread. The size is reduced there to avoid a
  visible full-size frame. Damage is scaled on the first tear update, after
  the engine has finalized it.
- Do not gate `MC_POST_TEAR_INIT` on the C++ `firingProxy` flag: in the tested
  build it was already false when Lua saw tear initialization, and all
  redirection stopped. A 72-pixel proximity gate also stopped redirection;
  the initial position is not a reliable discriminator at that callback.
- Split children may keep the proxy as `SpawnerEntity`. The new
  `split_tears.lua` registers before `native_weapon_adapter.lua`, snapshots
  their pre-aim position/velocity/scale, and restores them in
  `MC_POST_FIRE_SPLIT_TEAR` at the source tear's impact point. It marks the
  child so the adapter will not redirect it again on the first update. This
  isolated fix is not yet tested in game.

Last user-confirmed result: ordinary tears worked with the ungated init
redirect, while split children appeared in wrong locations and idle proxies
could still follow player input. The current idle guard and split module need
in-game validation; they do not change native shot timing or the primary
tear redirect.

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
location. Compilation does not prove all synergies work; test idle-player
firing, charged releases, co-op, and room transitions in game. Brimstone keeps
the shoot button released for 25 ticks after a full charge so its beam can finish.
