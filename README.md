# Pocket Chess Studies v0.1

An offline chess tactics trainer for KOReader, sized for the Kobo Libra Colour.
The starter pack contains 20 CC0 Lichess puzzles with player moves that include
kingside and queenside castling, en passant, queen promotion and knight underpromotion.

## Install on Kobo

1. Download [Pocket-Chess-Studies-v0.1.zip](dist/Pocket-Chess-Studies-v0.1.zip)
   and extract it on your computer.
2. Connect the Kobo by USB. Show hidden folders if needed and copy the extracted
   `pocketchess.koplugin` folder into `.adds/koreader/plugins/`. The installed
   entry point should be `.adds/koreader/plugins/pocketchess.koplugin/main.lua`.
3. Eject the Kobo. If KOReader is running, exit and reopen KOReader once to
   discover the plugin. Open the main menu and choose **Tools → More tools →
   Pocket Chess Studies**. If the entry is hidden, check **Plugin management**.
4. Use **Close** to return to the file browser or the book you were reading.

## Solve puzzles

The solver's pieces start at the bottom. Tap one of your pieces to see dots on
its legal destinations, including dots in the corner of squares you can
capture. Then tap the destination. For castling, tap the king and then its
destination two files away.
Promotion opens a choice of queen, rook, bishop or knight. When you find a
solution move, the plugin plays the opponent's reply automatically. A legal
move outside the recorded solution leaves the position unchanged.

- **Hint** outlines the moving piece, then becomes **Reveal** for that turn.
  Tap **Reveal** to see the remaining line and final position. An unsolved
  puzzle stays unsolved when revealed.
- **Retry** returns to the starting position and keeps any previously earned solved mark.
- **Refresh** flashes the full screen to clear e-ink ghosting while preserving
  the current position and selection.
- **Previous** and **Next** also respond to KOReader's normal page keys and
  Left/Right key events while the puzzle view is open. A Bluetooth page-turner
  can use mappings that already deliver these events to KOReader.

Solved marks, partial lines and the current puzzle are stored in KOReader's
`settings/pocketchess-progress.txt`. The plugin validates the file and starts
with fresh progress if the contents are damaged. Updates use a temporary file
and rename so a failed replacement can leave the previous save available.

## Data and rules

The checked-in [source records](data/lichess-v0.1.csv) retain Lichess puzzle IDs,
game URLs, ratings and themes. Record `00sO1` comes from Lichess's official
[export-format sample][sample]. The other 19 come from a pinned
[mirror of the Lichess puzzle CSV][mirror]. Lichess publishes its
[puzzle database][database] under CC0 1.0. Ratings are from those snapshots.
The starter pack includes one puzzle rated 1722 to demonstrate kingside castling.
It contains no book studies.

[python-chess](https://github.com/niklasf/python-chess) validates every recorded
move and generates the position, complete legal move set and SAN for each
player turn along the line. The plugin uses that generated data offline and
does not need Python, Stockfish, networking or a device-side engine. v0.1
covers the bundled puzzle lines. It does not provide free play or evaluate
alternative lines. The pack excludes positions with an alternate immediate mate.

The planned 20,000-puzzle pack and later roughly 1.95 million puzzles rated
80–1500 will need indexed, on-demand loading. The bundled Lua table is sized
for v0.1. Progress uses Lichess puzzle IDs so it survives pack reordering.

See [notices](pocketchess.koplugin/NOTICES.md) for the chess piece artwork.
The plugin structure, menu registration and ZIP layout follow patterns from
[Focus Reader](https://github.com/tvventykeys/focusreader.koplugin).

## Build and test

With Python 3.12:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-dev.txt
python scripts/build_puzzles.py --check
python -m unittest discover -s tests -v
python scripts/build_release.py
```

After editing the source records, run `python scripts/build_puzzles.py`
without `--check`, then rebuild the ZIP before running the tests. The suite
replays all 20 lines, tests illegal and off-line moves, promotion controls,
hints, reveal, navigation, progress recovery, plugin startup and archive contents.

The [native smoke test](tests/koreader_smoke.lua) runs in KOReader's Linux SDL
emulator. Install the ZIP into a disposable KOReader Linux distribution's
`plugins/`. Use a fresh `KO_HOME`, put the smoke test in its `patches/` folder
as `2-pocketchess-smoke.lua`, and put this in its `settings.reader.lua`:

```lua
return { color_rendering = true, sdl_window = { width = 1264, height = 1680 } }
```

From the distribution directory containing `reader.lua`, run
`SDL_VIDEODRIVER=dummy KO_HOME=/path/to/test-profile ./reader.lua /path/to/empty-directory`.
The script drives KOReader's file-manager menu, tap and page-key dispatch,
progress reload and screen close. It exits nonzero on failure. The Libra
Colour's e-ink rendering and a physical Bluetooth clicker require device testing.

[database]: https://database.lichess.org/#puzzles
[sample]: https://github.com/lichess-org/database/blob/400f124a43200857be9f78ca781ebbbba01b4ced/web/index.html.tpl#L156-L166
[mirror]: https://github.com/rodolfoinfantini/JS-Chess-Stockfish-Puzzles/blob/68c6ab51ec8585a3a92f4e70f41c3272931cbeb4/puzzlesDataBase2.js
