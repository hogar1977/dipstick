import argparse
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "helpers"))

import janitor
import tmpscan


def age(path, seconds):
    moment = time.time() - seconds
    os.utime(path, (moment, moment), follow_symlinks=False)


def request(**values):
    defaults = {"dry_run": False, "all_stale": False, "category": None, "ids": None}
    return argparse.Namespace(**{**defaults, **values})


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = os.path.realpath(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def records(self):
        return {record["name"]: record for record in tmpscan.scan(self.root)[0]}

    def test_recent_metadata_change_blocks_stale(self):
        os.mkdir(self.path("unpacked"))
        with open(self.path("unpacked", "file"), "w") as stream:
            stream.write("data")
        age(self.path("unpacked", "file"), 259200)
        age(self.path("unpacked"), 259200)
        self.assertEqual(self.records()["unpacked"]["status"], "recent")

    def test_working_directory_is_active(self):
        os.mkdir(self.path("busy"))
        process = subprocess.Popen(["sleep", "20"], cwd=self.path("busy"))
        try:
            time.sleep(0.1)
            self.assertEqual(self.records()["busy"]["status"], "active")
        finally:
            process.kill()
            process.wait()

    def test_named_pipe_does_not_hang(self):
        os.mkfifo(self.path("trap.so"))
        self.assertEqual(self.records()["trap.so"]["status"], "protected")

    def test_lookalike_gets_generic_grace(self):
        os.mkdir(self.path("electron-project"))
        self.assertEqual(self.records()["electron-project"]["category"], "directories")

    def test_sparse_file_counts_allocated_space(self):
        with open(self.path("sparse"), "w") as stream:
            stream.truncate(1073741824)
        self.assertLess(self.records()["sparse"]["size"], 1048576)

    def test_hard_links_count_once(self):
        with open(self.path("one"), "wb") as stream:
            stream.write(b"x" * 65536)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(self.path("one"), self.path("two"))
        records = self.records()
        self.assertEqual(sorted([records["one"]["size"] > 0, records["two"]["size"] > 0]), [False, True])

    def test_dry_run_deletes_nothing(self):
        with open(self.path("item"), "w") as stream:
            stream.write("data")
        identity = self.records()["item"]["id"]
        result = janitor.clean(request(dry_run=True, ids=[identity]), self.root)
        self.assertEqual(result["removedCount"], 1)
        self.assertTrue(os.path.exists(self.path("item")))

    def test_changed_item_is_skipped(self):
        with open(self.path("item"), "w") as stream:
            stream.write("data")
        identity = self.records()["item"]["id"]
        os.unlink(self.path("item"))
        with open(self.path("item"), "w") as stream:
            stream.write("replacement")
        result = janitor.clean(request(ids=[identity]), self.root)
        self.assertEqual(result["removedCount"], 0)
        self.assertTrue(os.path.exists(self.path("item")))

    def test_symlink_target_survives(self):
        with tempfile.TemporaryDirectory() as outside:
            target = os.path.join(outside, "keep")
            with open(target, "w") as stream:
                stream.write("data")
            os.mkdir(self.path("holder"))
            os.symlink(outside, self.path("holder", "link"))
            identity = self.records()["holder"]["id"]
            result = janitor.clean(request(ids=[identity]), self.root)
            self.assertEqual(result["removedCount"], 1)
            self.assertTrue(os.path.exists(target))
            self.assertFalse(os.path.lexists(self.path("holder")))

    def test_bulk_clean_leaves_recent_items(self):
        with open(self.path("fresh"), "w") as stream:
            stream.write("data")
        result = janitor.clean(request(all_stale=True), self.root)
        self.assertEqual(result["removedCount"], 0)
        self.assertTrue(os.path.exists(self.path("fresh")))


if __name__ == "__main__":
    unittest.main()
