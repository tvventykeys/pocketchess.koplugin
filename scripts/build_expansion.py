"""Build the read-only Lichess expansion from an official CSV or pinned CSV mirror."""
import argparse
from contextlib import closing
import csv
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import tempfile

from build_puzzles import AlternateMate, ROOT, SOURCE, compile_puzzle

OUTPUT = ROOT / "pocketchess.koplugin" / "lichess-expansion.sqlite3"
MIRROR_FIELDS = (
    "PuzzleId", "FEN", "Moves", "Rating", "RatingDeviation", "Popularity",
    "NbPlays", "Themes", "GameUrl",
)


def build(source, output, limit, mirror_js=False):
    with SOURCE.open(newline="", encoding="utf-8") as starter:
        seen = {row["PuzzleId"] for row in csv.DictReader(starter)}
    with source.open(newline="", encoding="utf-8") as stream:
        if mirror_js:
            raw = stream.read()
            prefix, content, suffix = raw.split("`")
            if prefix.strip() != "let puzzlesCsv =" or suffix.strip().strip(";"):
                raise ValueError("Unexpected mirror format")
            rows = csv.DictReader(io.StringIO(content), fieldnames=MIRROR_FIELDS)
        else:
            rows = csv.DictReader(stream)
        with tempfile.TemporaryDirectory(dir=output.parent) as temp:
            staged = Path(temp) / output.name
            with closing(sqlite3.connect(staged)) as db, db:
                db.execute("PRAGMA user_version=1")
                db.execute("""CREATE TABLE puzzles (
                    position INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL,
                    rating INTEGER NOT NULL, themes TEXT NOT NULL,
                    stage_count INTEGER NOT NULL, steps TEXT NOT NULL
                )""")
                count = 0
                for row in rows:
                    if not 80 <= int(row["Rating"]) <= 1500 or int(row["Popularity"]) < 40 or int(row["NbPlays"]) < 10:
                        continue
                    if row["PuzzleId"] in seen:
                        continue
                    try:
                        puzzle = compile_puzzle(row, reject_alternate_mates=True)
                    except AlternateMate:
                        continue
                    count += 1
                    seen.add(puzzle["id"])
                    steps = puzzle["steps"]
                    db.execute("INSERT INTO puzzles VALUES (?, ?, ?, ?, ?, ?)", (
                        count, puzzle["id"], puzzle["rating"], puzzle["themes"],
                        len(steps), json.dumps(steps, separators=(",", ":")),
                    ))
                    if count == limit:
                        break
                if count != limit:
                    raise ValueError(f"Only {count} eligible puzzles found")
            staged.replace(output)
    with output.open("rb") as archive:
        digest = hashlib.file_digest(archive, "sha256").hexdigest()
    print(f"{count:,} puzzles · {output.stat().st_size:,} bytes · SHA-256 {digest}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--mirror-js", action="store_true")
    parser.add_argument("--count", type=int, default=20_000)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    build(args.source, args.output, args.count, args.mirror_js)


if __name__ == "__main__":
    main()
