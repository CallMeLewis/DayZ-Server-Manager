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


import io
import json
from unittest.mock import patch
from urllib.error import URLError

from dayz_manager.update_check import fetch_latest_release, LATEST_RELEASE_URL


def _fake_http_response(payload: dict) -> io.BytesIO:
    return io.BytesIO(json.dumps(payload).encode("utf-8"))


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
