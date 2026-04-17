import io
import json
import unittest
from unittest.mock import patch
from urllib.error import URLError

from dayz_manager.update_check import check_update, compare_versions, fetch_latest_release, parse_version, LATEST_RELEASE_URL


def _fake_http_response(payload: dict) -> io.BytesIO:
    return io.BytesIO(json.dumps(payload).encode("utf-8"))


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


class FetchLatestReleaseTests(unittest.TestCase):
    def test_returns_tag_and_url_on_success(self) -> None:
        payload = {
            "tag_name": "v1.2.0",
            "html_url": "https://github.com/CallMeLewis/DayZ-Server-Manager/releases/tag/v1.2.0",
        }
        with patch("dayz_manager.update_check.urlopen", return_value=_fake_http_response(payload)) as mock_urlopen:
            result = fetch_latest_release(timeout=3.0)

        self.assertEqual(result, {
            "tag": "v1.2.0",
            "url": "https://github.com/CallMeLewis/DayZ-Server-Manager/releases/tag/v1.2.0",
        })
        request = mock_urlopen.call_args.args[0]
        self.assertEqual(request.full_url, LATEST_RELEASE_URL)
        header_keys_lower = [k.lower() for k in dict(request.header_items())]
        self.assertIn("user-agent", header_keys_lower)

    def test_returns_none_on_network_error(self) -> None:
        with patch("dayz_manager.update_check.urlopen", side_effect=URLError("boom")):
            self.assertIsNone(fetch_latest_release(timeout=3.0))

    def test_returns_none_when_payload_missing_tag(self) -> None:
        with patch("dayz_manager.update_check.urlopen", return_value=_fake_http_response({"html_url": "..."})):
            self.assertIsNone(fetch_latest_release(timeout=3.0))


class CheckUpdateTests(unittest.TestCase):
    def _patch_fetch(self, value):
        return patch("dayz_manager.update_check.fetch_latest_release", return_value=value)

    def test_reports_update_available_when_remote_is_newer(self) -> None:
        with self._patch_fetch({"tag": "v1.2.0", "url": "https://example.invalid/v1.2.0"}):
            result = check_update(current_version="1.1.0", timeout=3.0)

        self.assertEqual(result, {
            "currentVersion": "1.1.0",
            "latestVersion": "1.2.0",
            "latestTag": "v1.2.0",
            "releaseUrl": "https://example.invalid/v1.2.0",
            "updateAvailable": True,
            "error": None,
        })

    def test_reports_no_update_when_current_matches_remote(self) -> None:
        with self._patch_fetch({"tag": "v1.1.0", "url": "https://example.invalid/v1.1.0"}):
            result = check_update(current_version="1.1.0", timeout=3.0)

        self.assertFalse(result["updateAvailable"])
        self.assertEqual(result["latestVersion"], "1.1.0")
        self.assertIsNone(result["error"])

    def test_reports_no_update_when_current_is_ahead(self) -> None:
        with self._patch_fetch({"tag": "v1.0.9", "url": "https://example.invalid/v1.0.9"}):
            result = check_update(current_version="1.1.0", timeout=3.0)

        self.assertFalse(result["updateAvailable"])

    def test_reports_error_on_network_failure(self) -> None:
        with self._patch_fetch(None):
            result = check_update(current_version="1.1.0", timeout=3.0)

        self.assertFalse(result["updateAvailable"])
        self.assertIsNone(result["latestVersion"])
        self.assertEqual(result["error"], "network error")

    def test_reports_error_on_malformed_tag(self) -> None:
        with self._patch_fetch({"tag": "release-2026", "url": ""}):
            result = check_update(current_version="1.1.0", timeout=3.0)

        self.assertFalse(result["updateAvailable"])
        self.assertEqual(result["error"], "invalid tag: release-2026")

    def test_reports_error_on_malformed_current_version(self) -> None:
        with self._patch_fetch({"tag": "v1.2.0", "url": ""}):
            result = check_update(current_version="not-a-version", timeout=3.0)

        self.assertFalse(result["updateAvailable"])
        self.assertTrue(result["error"].startswith("invalid current version"))
