import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "helpers"))

import storage

SAMPLE = "\n".join([
    "29 1 0:27 /@ / rw,relatime shared:1 - btrfs /dev/mapper/root rw,subvol=/@",
    "40 29 0:30 / /mnt/my\\040data rw master:4 shared:2 - ext4 /dev/sd\\134b1 rw",
    "41 29 0:31 / /plain rw - tmpfs tmpfs rw",
    "malformed line",
    "42 29 0:32 / /short rw -",
])


class MountinfoTests(unittest.TestCase):
    def test_variable_optional_fields(self):
        entries = storage.parse_mountinfo(SAMPLE)
        self.assertEqual([entry["mount"] for entry in entries], ["/", "/mnt/my data", "/plain"])
        self.assertEqual(entries[0]["fs"], "btrfs")

    def test_escapes_are_decoded(self):
        self.assertEqual(storage.parse_mountinfo(SAMPLE)[1]["source"], "/dev/sd\\b1")

    def test_invalid_escape_is_preserved(self):
        self.assertEqual(storage.decode_field("a\\9zz"), "a\\9zz")

    def test_matches_live_system(self):
        with open("/proc/self/mountinfo") as stream:
            self.assertIn("/", [entry["mount"] for entry in storage.parse_mountinfo(stream.read())])


if __name__ == "__main__":
    unittest.main()
