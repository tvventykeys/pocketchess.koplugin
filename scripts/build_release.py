"""Build the deterministic Kobo installation archive."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "pocketchess.koplugin"
OUTPUT = ROOT / "dist" / "Pocket-Chess-Studies-v0.2.zip"


def build(output):
    files = sorted(
        list(PLUGIN.glob("*.lua"))
        + list((PLUGIN / "pieces").glob("*.svg"))
        + [PLUGIN / "COPYING", PLUGIN / "NOTICES.md", PLUGIN / "lichess-expansion.sqlite3"]
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for file in files:
            entry = ZipInfo(file.relative_to(ROOT).as_posix())
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, file.read_bytes(), ZIP_DEFLATED, 9)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    build(args.output)
    print(args.output)


if __name__ == "__main__":
    main()
