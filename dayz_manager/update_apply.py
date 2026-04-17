from __future__ import annotations

import shutil
import zipfile
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


_ARCHIVE_URL_TEMPLATE = "https://github.com/CallMeLewis/DayZ-Server-Manager/archive/refs/tags/{tag}.zip"
_USER_AGENT = "dayz-server-manager-apply-update"


def build_release_zip_url(tag: str) -> str:
    return _ARCHIVE_URL_TEMPLATE.format(tag=tag)


def download_release_zip(tag: str, destination: Path, timeout: float) -> None:
    request = Request(
        build_release_zip_url(tag),
        headers={"User-Agent": _USER_AGENT, "Accept": "application/zip"},
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urlopen(request, timeout=timeout) as response, destination.open("wb") as out:
        shutil.copyfileobj(response, out)


def _common_top_level(names: list[str]) -> str:
    roots = set()
    for name in names:
        if not name:
            continue
        head = name.split("/", 1)[0]
        if head:
            roots.add(head)
    if len(roots) != 1:
        raise ValueError(f"expected a single top-level directory in zip, found: {sorted(roots)}")
    return next(iter(roots))


def extract_release_zip(zip_path: Path, staging_dir: Path) -> None:
    if staging_dir.exists():
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True)

    with zipfile.ZipFile(zip_path, "r") as archive:
        names = [name for name in archive.namelist() if name and not name.endswith("/")]
        top_level = _common_top_level(names)
        prefix = top_level + "/"

        for member in archive.infolist():
            if member.is_dir():
                continue
            if not member.filename.startswith(prefix):
                raise ValueError(f"unexpected zip entry outside {top_level!r}: {member.filename}")
            relative = member.filename[len(prefix):]
            if not relative:
                continue
            target = staging_dir / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member, "r") as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)


_RESERVED_DIRS = frozenset({".git", ".update-backup", ".update-staging"})


def _iter_relative_files(root: Path):
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
