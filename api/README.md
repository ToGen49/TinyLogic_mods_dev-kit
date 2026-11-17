# api/api.json

A verbatim copy of the game's own API reference:

```text
<install>/assets/mods/api.json
```

- **Version:** `0.2-beta` (matches `tl.version`)
- **Contents:** every group (`core`, `mods`, `board`, `sim`, `elec`, `draw`,
  `ui`, `input`, `sound`, `store`, `camera`, `graph`) with, for each item, its
  `name`, `sig`, `returns` and `doc`.

It is the **source of truth** for this kit:

- [`docs/04-api.md`](../docs/04-api.md) is a human-readable rendering of it.
- [`tools/validate.py`](../tools/validate.py) reads it to flag `tl.*` names that
  do not exist, so the checker stays correct even if this kit's prose lags behind.

## Refreshing after a game update

```bash
<kit>/tools/sync-api.sh --install <path-to-game-install>
```

Or point it at the game and let it search:

```bash
<kit>/tools/sync-api.sh --auto
```

Then re-run `tools/validate.py` over `examples/` and `template/` to confirm
nothing was renamed out from under the kit.
