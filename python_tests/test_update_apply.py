import io
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from dayz_manager.update_apply import (
    build_release_zip_url,
    download_release_zip,
    extract_release_zip,
)


def _fake_http_response(body: bytes) -> io.BytesIO:
    return io.BytesIO(body)


def _build_fixture_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("DayZ-Server-Manager-9.9.9/README.md", "hello")
        archive.writestr("DayZ-Server-Manager-9.9.9/windows/Server_manager.ps1", "ps1 body")
        archive.writestr("DayZ-Server-Manager-9.9.9/linux/lib/linux_manager.sh", "bash body")
    return buffer.getvalue()


class BuildReleaseZipUrlTests(unittest.TestCase):
    def test_constructs_github_archive_url(self) -> None:
        self.assertEqual(
            build_release_zip_url("v1.2.0"),
            "https://github.com/CallMeLewis/DayZ-Server-Manager/archive/refs/tags/v1.2.0.zip",
        )


class DownloadReleaseZipTests(unittest.TestCase):
    def test_writes_body_to_destination(self) -> None:
        body = b"zip-bytes"
        with TemporaryDirectory() as tmp:
            destination = Path(tmp) / "release.zip"
            with patch("dayz_manager.update_apply.urlopen", return_value=_fake_http_response(body)):
                download_release_zip("v1.2.0", destination, timeout=30.0)
            self.assertEqual(destination.read_bytes(), body)


class ExtractReleaseZipTests(unittest.TestCase):
    def test_strips_top_level_prefix(self) -> None:
        zip_bytes = _build_fixture_zip()
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "release.zip"
            zip_path.write_bytes(zip_bytes)
            staging = Path(tmp) / "staging"
            extract_release_zip(zip_path, staging)

            self.assertTrue((staging / "README.md").exists())
            self.assertEqual((staging / "README.md").read_text(), "hello")
            self.assertTrue((staging / "windows" / "Server_manager.ps1").exists())
            self.assertTrue((staging / "linux" / "lib" / "linux_manager.sh").exists())
            self.assertFalse((staging / "DayZ-Server-Manager-9.9.9").exists())

    def test_rejects_zip_without_single_top_level_prefix(self) -> None:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("README.md", "x")
            archive.writestr("other-root/file.txt", "y")
        with TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "bad.zip"
            zip_path.write_bytes(buffer.getvalue())
            staging = Path(tmp) / "staging"
            with self.assertRaises(ValueError):
                extract_release_zip(zip_path, staging)


if __name__ == "__main__":
    unittest.main()
