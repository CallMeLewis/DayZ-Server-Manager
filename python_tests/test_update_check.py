import unittest

from dayz_manager.update_check import compare_versions, parse_version


class ParseVersionTests(unittest.TestCase):
    def test_parses_plain_semver(self) -> None:
        self.assertEqual(parse_version("1.2.3"), (1, 2, 3))

    def test_strips_leading_v_prefix(self) -> None:
        self.assertEqual(parse_version("v1.2.3"), (1, 2, 3))

    def test_strips_trailing_prerelease(self) -> None:
        self.assertEqual(parse_version("1.2.3-rc.1"), (1, 2, 3))

    def test_rejects_non_numeric_components(self) -> None:
        with self.assertRaises(ValueError):
            parse_version("1.two.3")

    def test_rejects_missing_components(self) -> None:
        with self.assertRaises(ValueError):
            parse_version("1.2")


class CompareVersionsTests(unittest.TestCase):
    def test_newer_patch_is_greater(self) -> None:
        self.assertEqual(compare_versions("1.1.0", "1.1.1"), -1)

    def test_equal_versions_compare_zero(self) -> None:
        self.assertEqual(compare_versions("1.1.0", "1.1.0"), 0)

    def test_older_major_is_less(self) -> None:
        self.assertEqual(compare_versions("2.0.0", "1.9.9"), 1)

    def test_accepts_v_prefix_on_either_side(self) -> None:
        self.assertEqual(compare_versions("v1.1.0", "1.1.0"), 0)
