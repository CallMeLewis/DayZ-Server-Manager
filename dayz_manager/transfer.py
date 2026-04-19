from __future__ import annotations

from typing import Any

from dayz_manager._common import ensure_dict, normalize_platform
from dayz_manager.adapters import load_config

EXPORT_FORMAT_VERSION = 1
_REDACT_TOP_LEVEL_KEYS = {
    "steamAccount",
    "steamUsername",
    "steamPassword",
    "steamPasswordFile",
    "runtime",
    "state",
    "process",
    "pid",
    "running",
}
_REDACT_LINUX_NESTED_KEYS = _REDACT_TOP_LEVEL_KEYS - {"steamUsername", "steamPassword", "steamPasswordFile"}


def _strip_keys(source: dict[str, Any], keys: set[str]) -> dict[str, Any]:
    return {key: value for key, value in source.items() if key not in keys}


def _sanitize_config(platform: str, config: dict[str, Any]) -> dict[str, Any]:
    sanitized = _strip_keys(config, _REDACT_TOP_LEVEL_KEYS)

    if platform == "linux":
        mod_library = sanitized.get("modLibrary")
        if isinstance(mod_library, dict):
            sanitized["modLibrary"] = _strip_keys(mod_library, _REDACT_LINUX_NESTED_KEYS)

    return sanitized


def build_export_envelope(platform: Any, config: Any) -> dict[str, Any]:
    platform_key = normalize_platform(platform)
    config_object = ensure_dict(config, "config payload must be a JSON object")
    load_config(platform_key, config_object)
    return {
        "formatVersion": EXPORT_FORMAT_VERSION,
        "platform": platform_key,
        "config": _sanitize_config(platform_key, config_object),
    }


def import_config_envelope(envelope: Any) -> dict[str, Any]:
    envelope_object = ensure_dict(envelope, "export envelope must be a JSON object")

    if envelope_object.get("formatVersion") != EXPORT_FORMAT_VERSION:
        raise ValueError(f"unsupported export format version: {envelope_object.get('formatVersion')}")

    platform_key = normalize_platform(envelope_object.get("platform"))
    config_object = ensure_dict(envelope_object.get("config"), "export envelope config must be a JSON object")
    load_config(platform_key, config_object)
    return _sanitize_config(platform_key, config_object)
