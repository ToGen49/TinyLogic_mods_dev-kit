# 8. Sharing

> Back to the [kit index](../readme.md) · Previous: [7. Limits and gotchas](07-limits.md) · Next: [9. Samples](09-samples.md)

- **In-game:** the mods panel has `publish` → *published to the mod server*.
  The game describes it as: *"make your own tools with a script or a node graph,
  and share them on the mod server."*
- Downloads are integrity-checked against the server's key; if the key changes,
  downloads are disabled until it is reviewed.
- `mods_install` expects a **bundle** (the panel's `bring in…` action).
- The panel also lists `downloads`, `likes`, `draws` for published mods.

**Handing a mod to another player, without the server:**

1. Zip the mod folder — it must contain `mod.json` at the top level:

   ```bash
   cd <kit>/mods && zip -r my-mod.zip my-mod
   ```

2. They use `bring in…` in their mods panel, or drop the folder into their own
   `<profile>/mods/<mod-id>/`.
3. `enabled: true` in `mod.json` makes it load at start; otherwise they switch
   it on in the panel.

`tools/install.sh --zip` builds that archive for you.

---

**Next:** [9. Samples worth reading](09-samples.md)
