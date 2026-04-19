from __future__ import annotations

import json
import re
from urllib.error import URLError
from urllib.request import Request, urlopen


_VERSION_PATTERN = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$")


def parse_version(value: str) -> tuple[int, int, int]:
    match = _VERSION_PATTERN.match(value.strip())
    if not match:
        raise ValueError(f"invalid semver: {value!r}")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)))


def compare_versions(a: str, b: str) -> int:
    parsed_a = parse_version(a)
    parsed_b = parse_version(b)
    if parsed_a < parsed_b:
        return -1
    if parsed_a > parsed_b:
        return 1
    return 0


LATEST_RELEASE_URL = "https://api.github.com/repos/CallMeLewis/DayZ-Server-Manager/releases/latest"
_USER_AGENT = "dayz-server-manager-update-check"


def fetch_latest_release(timeout: float) -> dict[str, str] | None:
    request = Request(LATEST_RELEASE_URL, headers={
        "User-Agent": _USER_AGENT,
        "Accept": "application/vnd.github+json",
    })
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except (URLError, TimeoutError, json.JSONDecodeError, OSError):
        return None

    tag = payload.get("tag_name") if isinstance(payload, dict) else None
    url = payload.get("html_url") if isinstance(payload, dict) else None
    if not isinstance(tag, str) or not tag.strip():
        return None
    return {"tag": tag.strip(), "url": url if isinstance(url, str) else ""}


def _result(current_version: str, *, latest_version: str | None = None, latest_tag: str | None = None,
            release_url: str | None = None, update_available: bool = False,
            error: str | None = None) -> dict[str, object]:
    return {
        "currentVersion": current_version,
        "latestVersion": latest_version,
        "latestTag": latest_tag,
        "releaseUrl": release_url,
        "updateAvailable": update_available,
        "error": error,
    }


def check_update(current_version: str, timeout: float) -> dict[str, object]:
    try:
        parsed_current = parse_version(current_version)
    except ValueError as exc:
        return _result(current_version, error=f"invalid current version: {exc}")

    release = fetch_latest_release(timeout=timeout)
    if release is None:
        return _result(current_version, error="network error")

    tag = release["tag"]
    try:
        parsed_latest = parse_version(tag)
    except ValueError:
        return _result(
            current_version,
            latest_tag=tag,
            release_url=release.get("url") or None,
            error=f"invalid tag: {tag}",
        )

    return _result(
        current_version,
        latest_version=".".join(str(part) for part in parsed_latest),
        latest_tag=tag,
        release_url=release.get("url") or None,
        update_available=parsed_current < parsed_latest,
    )
