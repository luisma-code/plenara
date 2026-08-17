import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image

MODULE_PATH = Path(__file__).with_name("gesture_contact_sheet.py")
SPEC = importlib.util.spec_from_file_location("gesture_contact_sheet", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ContactSheetAlphaTest(unittest.TestCase):
    def test_transparent_pixels_reveal_real_dark_ground(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "transparent.png"
            Image.new("RGBA", (1, 1), (255, 255, 255, 0)).save(path)
            composed = MODULE.composite_frame(path, size=(1, 1))
            self.assertEqual(composed.getpixel((0, 0)), MODULE.BACKGROUND)

    def test_opaque_pixels_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "opaque.png"
            Image.new("RGBA", (1, 1), (240, 120, 60, 255)).save(path)
            composed = MODULE.composite_frame(path, size=(1, 1))
            self.assertEqual(composed.getpixel((0, 0)), (240, 120, 60))


if __name__ == "__main__":
    unittest.main()
