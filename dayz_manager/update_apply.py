from __future__ import annotations

import shutil
import tempfile
import zipfile
from collections.abc import Iterator
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

from dayz_manager._common import normalize_platform

_ASSET_URL_TEMPLATE = (
    "https://github.com/CallMeLewis/DayZ-Server-Manager/releases/download/"
    "{tag}/dayz-server-manager-{platform}-x64-{tag}.zip"
)
_USER_AGENT = "dayz-server-manager-apply-update"


def build_release_zip_url(tag: str, platform: str) -> str:
    return _ASSET_URL_TEMPLATE.format(tag=tag, platform=normalize_platform(platform))


def download_release_zip(tag: str, platform: str, destination: Path, timeout: float) -> None:
    request = Request(
        build_release_zip_url(tag, platform),
        headers={"User-Agent": _USER_AGENT, "Accept": "application/zip"},
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urlopen(request, timeout=timeout) as response, destination.open("wb") as out:
        shutil.copyfileobj(response, out)


def extract_release_zip(zip_path: Path, staging_dir: Path) -> None:
    if staging_dir.exists():
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True)

    with zipfile.ZipFile(zip_path, "r") as archive:
        for member in archive.infolist():
            if member.is_dir():
                continue
            relative = member.filename
            if not relative or relative.startswith("/") or ".." in Path(relative).parts:
                raise ValueError(f"unsafe zip entry: {member.filename}")
            target = staging_dir / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member, "r") as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)


_RESERVED_DIRS = frozenset({".git", ".update-backup", ".update-staging"})


def _iter_relative_files(root: Path) -> Iterator[Path]:
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if rel.parts and rel.parts[0] in _RESERVED_DIRS:
            continue
        yield rel


def apply_staged_update(repo_root: Path, staging_dir: Path, backup_dir: Path) -> int:
    if backup_dir.exists():
        shutil.rmtree(backup_dir)
    backup_dir.mkdir(parents=True)

    applied = 0
    for rel in _iter_relative_files(staging_dir):
        target = repo_root / rel
        if target.exists():
            backup_target = backup_dir / rel
            backup_target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup_target)

        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(staging_dir / rel, target)
        applied += 1

    return applied


def rollback_update(repo_root: Path, backup_dir: Path) -> None:
    if not backup_dir.is_dir():
        return
    for rel in _iter_relative_files(backup_dir):
        target = repo_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(backup_dir / rel, target)
    shutil.rmtree(backup_dir)


def apply_update(tag: str, repo_root: Path, platform: str, timeout: float) -> dict[str, object]:
    repo_root = Path(repo_root)
    backup = repo_root / ".update-backup"

    try:
        normalize_platform(platform)
    except ValueError as exc:
        return {
            "success": False,
            "tag": tag,
            "appliedFiles": 0,
            "backupPath": None,
            "error": str(exc),
        }

    with tempfile.TemporaryDirectory(prefix="dayz-update-", ignore_cleanup_errors=True) as staging_str:
        staging = Path(staging_str)
        zip_path = staging / "release.zip"
        extract_dir = staging / "extracted"

        try:
            download_release_zip(tag, platform, zip_path, timeout=timeout)
        except (URLError, TimeoutError, OSError) as exc:
            return {
                "success": False,
                "tag": tag,
                "appliedFiles": 0,
                "backupPath": None,
                "error": f"download failed: {exc}",
            }

        try:
            extract_release_zip(zip_path, extract_dir)
        except (zipfile.BadZipFile, ValueError) as exc:
            return {
                "success": False,
                "tag": tag,
                "appliedFiles": 0,
                "backupPath": None,
                "error": f"extract failed: {exc}",
            }

        try:
            applied = apply_staged_update(repo_root, extract_dir, backup)
        except OSError as exc:
            rollback_update(repo_root, backup)
            return {
                "success": False,
                "tag": tag,
                "appliedFiles": 0,
                "backupPath": None,
                "error": f"apply failed: {exc}",
            }

        return {
            "success": True,
            "tag": tag,
            "appliedFiles": applied,
            "backupPath": str(backup),
            "error": None,
        }
