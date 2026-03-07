Sprite asset layout for WordGrinder monster work.

- `candidates/`: Raw source PNGs for monsters you are evaluating. These are the large originals you drop into the repo before generating pixel-art variants.
- `generated/8x8/`, `generated/16x16/`, `generated/32x32/`, `generated/48x48/`, `generated/64x64/`: Generated PNG variants for review in the future sprite viewer. These are working files, not the canonical in-game assets.
- `official/`: The single selected PNG for each monster that should be treated as the canonical in-game sprite source.
- `formatted_sprites.lua`: Generated Lua palette table used by the current text-mode sprite renderer. Rebuild it from `official/` with `extras/sprite-converter`.

Current workflow:

1. Drop new monster source art into `candidates/`.
2. Run `extras/generate-sprite-variants` to generate review variants into the `generated/` size folders.
3. Manually copy the chosen sprite PNG into `official/`.
4. Run `extras/sprite-converter` to rebuild `formatted_sprites.lua` from the contents of `official/`.

This layout keeps raw art, generated review assets, and final selected sprites separate while WordGrinder still uses the Lua sprite table as its runtime format.

Transition note:

- The checked-in `formatted_sprites.lua` still matches the older sample source art so the current program output stays unchanged. Re-run `extras/sprite-converter` when you want the runtime sprite table to switch over to the contents of `official/`.

Generator notes:

- `extras/generate-sprite-variants` reads from `candidates/` by default and writes centered square PNGs into the `generated/<size>x<size>/` folders.
- It uses the sibling `image_to_pixel_art_wasm` project. If `target/release/pixelate-cli` already exists there, it uses that binary directly; otherwise it falls back to `cargo run --release --features native-bin --bin pixelate-cli`.
- The default sizes are `8,16,32,48,64`, and the default palette mode is `--palette-source self`, which keeps each monster's generated sizes on the same palette.

Overlay notes:

- The Sprite Viewer UI uses Cool Retro Term's OSC 99 image overlay and expects the terminal's sprite directory to point at this `extras/sprites/` tree.
- The local `cool-retro-term` build now supports `CRT_SPRITE_DIRECTORY=/absolute/path/to/wordgrinder/extras/sprites`.
- If you launch Cool Retro Term from the `writing-env` root with `--workdir`, it will also auto-detect `wordgrinder/extras/sprites` and use that as the overlay sprite directory.
