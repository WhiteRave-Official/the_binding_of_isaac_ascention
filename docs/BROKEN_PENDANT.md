# Broken Pendant

`scripts/broken_pendant.lua` softens net stat losses by 20% per trinket multiplier.
It records each player's initial damage, fire rate, movement speed, and range.
Positive changes only raise the reference when a collectible is added, using
the raw stat difference before and after the pickup. Ordinary cache evaluations
never raise the reference, so a temporary boost such as Dead Eye does not leave
behind a permanent bonus when it expires. Shot speed and luck are excluded.
There is no hardcoded item registry.

When a collectible is removed, its cache flags identify which of those four
stats must be reset to the player's initial reference. Other stats keep their
references. This conservative reset also discards reference gains from other
collectibles affecting the same stat, but avoids capturing a temporary boost
that happens to be active when an item is removed.

Losses from any source, including pills and cards, can be softened when the
result is below the reference. Their positive effects do not raise it. A penalty
fully masked by bonuses cannot be distinguished from a positive net stat and
receives no refund. A penalty already present in the first evaluated stats
becomes part of the initial reference.
