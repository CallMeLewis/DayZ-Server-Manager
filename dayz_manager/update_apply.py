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
