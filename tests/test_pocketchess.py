import csv
from pathlib import Path
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
                self.assertEqual(game.play(game, moves[-1].uci()), "finished")
        self.assertEqual(features, {
            "en passant", "kingside castling", "queenside castling", "promotion", "underpromotion",
        })

    def test_compiler_rejects_illegal_line(self):
        row = dict(PuzzleId="abcde", FEN=chess.STARTING_FEN, Moves="e2e4 e8e6", Rating="900")
        with self.assertRaisesRegex(ValueError, "illegal move"):
            build_puzzles.compile_puzzle(row)


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
                        "pocketchess_session.lua", "pocketchess_study.lua", "COPYING", "NOTICES.md"}
            expected.update(f"pieces/{color}{piece}.svg" for color in "bw" for piece in "KQRBNP")
            self.assertEqual(set(archive.namelist()), {f"pocketchess.koplugin/{name}" for name in expected})


if __name__ == "__main__":
    unittest.main()
