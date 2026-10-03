# Dynamic Minisaacs synergy audit

Audited against `Dynamic Minisaacs Forever` (`minisaacs_inherit_weapons_3388446591`) and the Ascention compatibility layer.

## Supported weapon replacements

- Normal tears: copies `GetTearHitParams`, tear variant, color and tear flags.
- Brimstone: charged short Brimstone beam.
- Technology: thin Technology laser.
- Dr. Fetus / bomb weapon: small sticky bomb.
- Mom's Knife: persistent Mini Isaac knife with throw behavior.
- C Section / fetus weapon: fetus tear and supported fetus flags.
- Tech X: charged Tech X ring.
- Epic Fetus / rocket weapon: targeted rocket marker and impact.
- Spirit Sword: Mini Isaac sword swing and projectile every second swing.
- Monstro's Lung: charged ten-projectile burst.
- Monstro's Lung + Technology: chained Technology laser burst.
- Monstro's Lung + Brimstone: short Brimstone beam barrage.
- Monstro's Lung + Tech X: Tech X ring barrage.
- Brimstone + Technology: Brim-Tech beam.
- Brimstone + Tech X: Brimstone Tech X ring.

## Explicit combined synergies

- Chocolate Milk modifies charge counters and attack scaling in Dynamic Minisaacs.
- BFFS is recognized by Dynamic Minisaacs.
- Bone weapon + Brimstone creates the small Brimstone ball/beam effect.
- Bone weapon + Technology or Tech X creates a Technology ring.
- C Section inherits Tech X, Spirit Sword, Mom's Knife, Dr. Fetus and Technology fetus flags.
- Spirit Sword + Technology or Tech X uses the technological sword variant and ring.
- Tear-based attacks inherit ordinary tear flags and status effects through `GetTearHitParams`.

## Ascention normalization

- Attack interval follows `round(player.MaxFireDelay + 1)`.
- Attack damage is normalized to 15% of current player damage.
- Brimstone, Technology and Tech X lasers use 65% visual scale.
- Tech X rings fired by Mini Isaacs use 65% of Dynamic Minisaacs' original radius.
- Player-spawned Dynamic outputs are associated back to the Mini Isaac that created them.

## Missing or incomplete synergy families

- Ludovico Technique has no dedicated Mini Isaac weapon behavior.
- Anti-Gravity has no stored Mini Isaac volley behavior.
- Eye of the Occult and Marked do not provide cursor-controlled Mini Isaac attacks.
- Tiny Planet, My Reflection, Continuum, Pop!, Flat Stone and Rubber Cement rely only on inherited tear flags; special weapons do not reproduce their native movement consistently.
- Haemolacria, Cricket's Body, Parasite and Compound Fracture have no dedicated split handling for non-tear weapons.
- Trisagion, Godhead, Sacred Heart and Jacob's Ladder have no dedicated laser/knife/bomb implementations beyond inherited flags where applicable.
- Ipecac interactions with bombs, lasers and knives are not normalized.
- Dr. Fetus and Epic Fetus modifier inheritance is partial.
- Brimstone + Tech X is handled by the Ascention combo controller and fires reduced Tech X rings.
- Monstro's Lung + Technology, Brimstone and Tech X are handled by the Ascention combo controller.
- Multishot is supplied by the Ascention REPENTOGON compatibility layer for tears, lasers, Tech X rings, bombs, knives, Spirit Sword, C Section and Monstro's Lung outputs.
- Incubus/Twisted Pair ownership is outside this mod's Mini Isaac handling.

## Structural risks found

- The upstream mod uses separate damage formulas for every weapon and compensates damage using inverse fire delay.
- Several spawned entities incorrectly use the player as spawner, losing Mini Isaac ownership.
- Several RNG calls use the player's DropRNG repeatedly instead of a per-attack stream.
- Epic Fetus stores damage in an effect-specific `DamageSource` field with an extreme custom multiplier.
- Some weapon combinations are selected through numeric weapon IDs and duplicated condition lists, making future weapon additions fragile.
## Multishot compatibility layer

The Ascention layer consumes the final REPENTOGON `MultiShotParams` instead of checking collectible IDs. This covers:

- 20/20, The Inner Eye and Mutant Spider;
- Conjoined and The Wiz multi-eye formations;
- Bookworm's rolled extra shot;
- Mom's Eye and Loki's Horns backward/side shots;
- Eye Sore random-direction shots;
- stacked multishot combinations;
- modded items that modify `MC_EVALUATE_MULTI_SHOT_PARAMS`.

The exact native lane offsets and spread are obtained from `GetMultiShotPositionVelocity`, with offsets reduced to 40% for Mini Isaac proportions. Formation size is capped at 16 primary lanes per generated attack for online performance; backward, sideways and random-direction shots are appended separately. Monstro's Lung uses one aggregate barrage per active eye, respects `MultiEyeAngle`, and adds 2.4 pellets per extra lane instead of recursively multiplying every pellet. Clones preserve tear flags, colors, scale, laser properties, bomb properties and knife properties.
