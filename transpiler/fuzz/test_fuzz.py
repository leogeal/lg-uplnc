import subprocess
import unittest

from fuzz import fuzz


class ClassifyTest(unittest.TestCase):
    def result(self, code, stderr=b""):
        return subprocess.CompletedProcess([], code, b"", stderr)

    def test_expected_compiler_error(self):
        self.assertIsNone(fuzz.classify(self.result(1, b"Error:bad input")))

    def test_leak_sanitizer_failure(self):
        stderr = b"ERROR: LeakSanitizer: detected memory leaks"
        self.assertEqual("sanitizer", fuzz.classify(self.result(1, stderr)))

    def test_leak_sanitizer_runtime_failure(self):
        stderr = b"LeakSanitizer has encountered a fatal error"
        self.assertEqual("sanitizer", fuzz.classify(self.result(1, stderr)))


if __name__ == "__main__":
    unittest.main()
