from __future__ import annotations

import re
from typing import Any

WORKSHOP_ID_RE = re.compile(r"\d{8,}")
_SUPPORTED_PLATFORMS = frozenset({"windows", "linux"})


def normalize_string(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def normalize_workshop_id(value: Any) -> str:
    if isinstance(value, dict):
        return normalize_string(value.get("workshopId", ""))
    return normalize_string(value)


def normalize_workshop_ids(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        workshop_id = normalize_workshop_id(value)
        if not workshop_id or workshop_id in seen:
            continue
        seen.add(workshop_id)
        result.append(workshop_id)
    return result


def is_valid_workshop_id(value: str) -> bool:
    return bool(WORKSHOP_ID_RE.fullmatch(value))


def ensure_safe_workshop_id(value: str) -> str:
    if not is_valid_workshop_id(value):
        raise ValueError(f"unsafe workshop id: {value}")
    return value


def normalize_platform(value: Any) -> str:
    platform_key = normalize_string(value).lower()
    if platform_key not in _SUPPORTED_PLATFORMS:
        raise ValueError(f"unsupported platform: {value}")
    return platform_key


def ensure_dict(value: Any, message: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(message)
    return value
