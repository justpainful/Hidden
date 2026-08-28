# The shuffle engine

A queue is a **permutation** of the pool, so the guarantees are structural:

- **No repeat** until the pool is exhausted — nothing to bookkeep, nothing to get wrong.
- **Previous works**: it is simply the previous index of the queue.
- **Seeded**: the same seed over the same pool recreates the same sequence (SplitMix64,
  shared with the random library sort). Resume/replay are literal.
- **Weighted (rediscovery)**: exponential-sort weighted sampling without replacement.
  Weights bias away from recently-viewed, frequently-viewed and over-exposed items, and
  gently towards old and never-seen media. True Random is a separate mode with no weights.
- **Mix rules**: optional no-two-videos-consecutively rearrangement that preserves relative
  order per kind and never silently drops media.
- **Limits**: count-limited and duration-limited sessions (photos cost the configured photo
  duration; videos their own length).
- **Persistence**: queue identifiers, position and seed survive relaunch; identifiers that
  no longer resolve are skipped on resume.

All of the above is enforced by unit tests, including at 20,000 items.
