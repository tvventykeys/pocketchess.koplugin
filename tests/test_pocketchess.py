import csv
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from zipfile import ZipFile

import chess
from lupa.luajit21 import LuaRuntime

from scripts import build_puzzles, build_release

ROOT = Path(__file__).resolve().parents[1]


def lua_runtime():
    lua = LuaRuntime()
    lua.globals().plugin_dir = str(build_release.PLUGIN)
    lua.execute('package.path = plugin_dir .. "/?.lua;" .. package.path')
    return lua


class PuzzleTests(unittest.TestCase):
    def test_pack_matches_source_and_contains_special_moves(self):
        self.assertEqual(build_puzzles.render(build_puzzles.SOURCE), build_puzzles.OUTPUT.read_text())
        with build_puzzles.SOURCE.open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 20)
        self.assertEqual(len({row["PuzzleId"] for row in rows}), 20)

        lua = lua_runtime()
        puzzles = lua.eval('require("pocketchess_puzzles")')
        session = lua.eval('require("pocketchess_session")')
        features = set()
        for index, row in enumerate(rows, 1):
            with self.subTest(puzzle=row["PuzzleId"]):
                state = lua.table(current=row["PuzzleId"], entries=lua.table())
                game = session.new(puzzles, state)
                self.assertEqual(game.index, index)
                board = chess.Board(row["FEN"])
                moves = [chess.Move.from_uci(uci) for uci in row["Moves"].split()]
                board.push(moves[0])
                for ply in range(1, len(moves), 2):
                    move = moves[ply]
                    self.assertEqual(game.step.fen, board.fen())
                    self.assertEqual(set(game.step.legal.split()), {m.uci() for m in board.legal_moves})
                    for square in board.piece_map():
                        source = chess.square_name(square)
                        destinations = {chess.square_name(m.to_square)
                                        for m in board.legal_moves if m.from_square == square}
                        self.assertEqual(set(game.legalDestinations(game, source).keys()), destinations)
                    self.assertEqual(game.hint(game), chess.square_name(move.from_square))
                    if board.is_en_passant(move):
                        features.add("en passant")
                    if board.is_kingside_castling(move):
                        features.add("kingside castling")
                    if board.is_queenside_castling(move):
                        features.add("queenside castling")
                    if move.promotion:
                        features.add("promotion" if move.promotion == chess.QUEEN else "underpromotion")
                        options = game.promotions(game, move.uci()[:2], move.uci()[2:4])
                        self.assertEqual(set(options.values()), set("qrbn"))
                    expected_san = board.san(move)
                    board.push(move)
                    reply = moves[ply + 1] if ply + 1 < len(moves) else None
                    expected_reply = board.san(reply) if reply else None
                    if reply:
                        board.push(reply)
                    self.assertEqual(game.play(game, move.uci()), ("correct", expected_san, expected_reply))
                    pieces = {chess.square_name(square): p.symbol() for square, p in board.piece_map().items()}
                    self.assertEqual(dict(game.pieces.items()), pieces)
                    self.assertEqual(game.side, "w" if board.turn else "b")
                self.assertTrue(game.solved)
                self.assertEqual(list(game.legalDestinations(game, "a1").keys()), [])
                self.assertEqual(game.play(game, moves[-1].uci()), "finished")
        self.assertEqual(features, {
            "en passant", "kingside castling", "queenside castling", "promotion", "underpromotion",
        })

    def test_compiler_rejects_illegal_line(self):
        row = dict(PuzzleId="abcde", FEN=chess.STARTING_FEN, Moves="e2e4 e8e6", Rating="900")
        with self.assertRaisesRegex(ValueError, "illegal move"):
            build_puzzles.compile_puzzle(row)

    def test_expansion_contents_and_replay(self):
        path = build_release.PLUGIN / "lichess-expansion.sqlite3"
        with sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True) as db:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT COUNT(*), COUNT(DISTINCT id) FROM puzzles").fetchone(),
                             (20_000, 20_000))
            for theme in ("mate", "fork", "pin", "endgame", "middlegame"):
                for low, high in ((80, 1199), (1200, 1399), (1400, 1500)):
                    self.assertIsNotNone(db.execute(
                        "SELECT 1 FROM puzzles WHERE instr(themes, ?) > 0 AND rating BETWEEN ? AND ? LIMIT 1",
                        (f" {theme} ", low, high),
                    ).fetchone())
            for puzzle, rating, count, raw in db.execute(
                "SELECT id, rating, stage_count, steps FROM puzzles ORDER BY position"
            ):
                self.assertTrue(80 <= rating <= 1500, puzzle)
                steps = json.loads(raw)
                self.assertEqual(len(steps), count, puzzle)
                for step, following in zip(steps, steps[1:]):
                    board = chess.Board(step["fen"])
                    move = chess.Move.from_uci(step["move"])
                    self.assertEqual(set(step["legal"].split()), {m.uci() for m in board.legal_moves}, puzzle)
                    self.assertIn(move, board.legal_moves, puzzle)
                    self.assertEqual(board.san(move), step["san"], puzzle)
                    board.push(move)
                    if reply := step.get("reply"):
                        board.push_san(reply)
                    self.assertEqual(board.fen(), following["fen"], puzzle)


class LuaTests(unittest.TestCase):
    def run_lua(self, name):
        with tempfile.TemporaryDirectory() as temp:
            lua = lua_runtime()
            lua.globals().test_dir = temp
            lua.execute((ROOT / "tests" / name).read_text())

    def test_moves_and_actions(self):
        self.run_lua("moves.lua")

    def test_progress_and_corruption_recovery(self):
        self.run_lua("progress.lua")

    def test_plugin_startup_and_touch(self):
        self.run_lua("startup.lua")


class ReleaseTests(unittest.TestCase):
    def test_zip_matches_sources(self):
        committed = build_release.OUTPUT
        with tempfile.TemporaryDirectory() as temp:
            rebuilt = Path(temp) / "plugin.zip"
            build_release.build(rebuilt)
            self.assertEqual(rebuilt.read_bytes(), committed.read_bytes())
        with ZipFile(committed) as archive:
            self.assertIsNone(archive.testzip())
            expected = {"main.lua", "_meta.lua", "pocketchess_progress.lua", "pocketchess_puzzles.lua",
                        "pocketchess_session.lua", "pocketchess_study.lua", "pocketchess_browse.lua",
                        "pocketchess_expansion.lua", "lichess-expansion.sqlite3", "COPYING", "NOTICES.md"}
            expected.update(f"pieces/{color}{piece}.svg" for color in "bw" for piece in "KQRBNP")
            self.assertEqual(set(archive.namelist()), {f"pocketchess.koplugin/{name}" for name in expected})


if __name__ == "__main__":
    unittest.main()
