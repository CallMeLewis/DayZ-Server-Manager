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


from dayz_manager.update_apply import apply_staged_update, rollback_update


class ApplyStagedUpdateTests(unittest.TestCase):
    def _populate_staging(self, staging: Path) -> None:
        (staging / "windows").mkdir(parents=True)
        (staging / "linux" / "lib").mkdir(parents=True)
        (staging / "README.md").write_text("new readme")
        (staging / "windows" / "Server_manager.ps1").write_text("new ps1")
        (staging / "linux" / "lib" / "linux_manager.sh").write_text("new bash")
        (staging / "NEWFILE.txt").write_text("brand new")

    def _populate_repo(self, repo: Path) -> None:
        (repo / "windows").mkdir(parents=True)
        (repo / "linux" / "lib").mkdir(parents=True)
        (repo / "README.md").write_text("old readme")
        (repo / "windows" / "Server_manager.ps1").write_text("old ps1")
        (repo / "linux" / "lib" / "linux_manager.sh").write_text("old bash")
        (repo / "local-untracked.txt").write_text("user-local")

    def test_overwrites_existing_creates_new_and_backs_up_overwritten(self) -> None:
        with TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            staging = Path(tmp) / "staging"
            backup = repo / ".update-backup"
            self._populate_repo(repo)
            self._populate_staging(staging)

            count = apply_staged_update(repo, staging, backup)

            self.assertEqual(count, 4)
            self.assertEqual((repo / "README.md").read_text(), "new readme")
            self.assertEqual((repo / "windows" / "Server_manager.ps1").read_text(), "new ps1")
            self.assertEqual((repo / "linux" / "lib" / "linux_manager.sh").read_text(), "new bash")
            self.assertEqual((repo / "NEWFILE.txt").read_text(), "brand new")
            self.assertEqual((repo / "local-untracked.txt").read_text(), "user-local")

            self.assertEqual((backup / "README.md").read_text(), "old readme")
            self.assertEqual((backup / "windows" / "Server_manager.ps1").read_text(), "old ps1")
            self.assertFalse((backup / "NEWFILE.txt").exists())

    def test_skips_reserved_directories(self) -> None:
        with TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            staging = Path(tmp) / "staging"
            (repo / ".git").mkdir(parents=True)
            (repo / ".git" / "HEAD").write_text("ref: refs/heads/main")
            (staging / ".git").mkdir(parents=True)
            (staging / ".git" / "HEAD").write_text("SHOULD NOT BE APPLIED")
            (staging / "README.md").write_text("new")

            apply_staged_update(repo, staging, repo / ".update-backup")

            self.assertEqual((repo / ".git" / "HEAD").read_text(), "ref: refs/heads/main")
            self.assertEqual((repo / "README.md").read_text(), "new")


class RollbackUpdateTests(unittest.TestCase):
    def test_restores_backed_up_files(self) -> None:
        with TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            backup = repo / ".update-backup"
            (repo / "windows").mkdir(parents=True)
            backup_sub = backup / "windows"
            backup_sub.mkdir(parents=True)
            (repo / "README.md").write_text("bad-new")
            (repo / "windows" / "Server_manager.ps1").write_text("bad-new-ps1")
            (backup / "README.md").write_text("good-old")
            (backup_sub / "Server_manager.ps1").write_text("good-old-ps1")

            rollback_update(repo, backup)

            self.assertEqual((repo / "README.md").read_text(), "good-old")
            self.assertEqual((repo / "windows" / "Server_manager.ps1").read_text(), "good-old-ps1")
            self.assertFalse(backup.exists())


if __name__ == "__main__":
    unittest.main()
