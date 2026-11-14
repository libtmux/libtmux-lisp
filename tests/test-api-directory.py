"""Critical checks for reading a class docstring's capability directory."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "api_directory", Path(__file__).resolve().parents[1] / "tools/api_directory.py")
api_directory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api_directory)

INTRO = "A client reaches one tmux server.\n\n#### What is on here\n\nThe groups:\n\n"


def row(title, guidance, *names):
    return f"**{title}.** {guidance}\n\n" + ", ".join(f"`libtmux:{name}`" for name in names) + "\n\n"


ROWS = [row("One", "Does one.", "a"), row("Two", "Does two.", "b", "c"),
        row("Three", "Does three.", "d")]


class CapabilityDirectory(unittest.TestCase):
    def test_three_bold_led_rows_fold_into_one_directory(self):
        runs, strays = api_directory.fold(INTRO + "".join(ROWS))
        self.assertEqual([[("One", ["libtmux:a"]), ("Two", ["libtmux:b", "libtmux:c"]),
                           ("Three", ["libtmux:d"])]], runs)
        self.assertEqual([], strays)

    def test_references_may_wrap_and_use_and(self):
        body = INTRO + ROWS[0] + ROWS[1] + "**Three.** Does three.\n\n`libtmux:d`,\n`libtmux:e` and\n`libtmux.query:f`\n"
        runs, _ = api_directory.fold(body)
        self.assertEqual(["libtmux:d", "libtmux:e", "libtmux.query:f"], runs[0][2][1])

    def test_prose_after_the_guidance_leaves_the_row_unfolded(self):
        broken = "**Two.** Does two.\n\n`libtmux:b` is also useful here.\n\n"
        runs, strays = api_directory.fold(INTRO + ROWS[0] + broken + ROWS[2])
        self.assertEqual([], runs)
        self.assertEqual(["One", "Two", "Three"], strays)

    def test_fewer_than_three_rows_stay_prose(self):
        runs, strays = api_directory.fold(INTRO + ROWS[0] + ROWS[1])
        self.assertEqual([], runs)
        self.assertEqual(["One", "Two"], strays)


if __name__ == "__main__":
    unittest.main()
