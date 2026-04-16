from __future__ import annotations

from typing import Any

from dayz_manager.adapters import load_config

EXPORT_FORMAT_VERSION = 1
_SUPPORTED_PLATFORMS = {"windows", "linux"}
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


def _normalize_platform(platform: Any) -> str:
    platform_key = "" if platform is None else str(platform).strip().lower()
    if platform_key not in _SUPPORTED_PLATFORMS:
        raise ValueError(f"unsupported platform: {platform}")
    return platform_key


def _ensure_object(value: Any, message: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(message)
    return value


def _sanitize_config(platform: str, config: dict[str, Any]) -> dict[str, Any]:
    sanitized = dict(config)
    for key in _REDACT_TOP_LEVEL_KEYS:
        sanitized.pop(key, None)

    if platform == "linux":
        mod_library = sanitized.get("modLibrary")
        if isinstance(mod_library, dict):
            nested = dict(mod_library)
            nested.pop("steamAccount", None)
            nested.pop("runtime", None)
            nested.pop("state", None)
            nested.pop("process", None)
            nested.pop("pid", None)
            nested.pop("running", None)
            sanitized["modLibrary"] = nested

    return sanitized


def build_export_envelope(platform: Any, config: Any) -> dict[str, Any]:
    platform_key = _normalize_platform(platform)
    config_object = _ensure_object(config, "config payload must be a JSON object")
    load_config(platform_key, config_object)
    return {
        "formatVersion": EXPORT_FORMAT_VERSION,
        "platform": platform_key,
        "config": _sanitize_config(platform_key, config_object),
    }


def import_config_envelope(envelope: Any) -> dict[str, Any]:
    envelope_object = _ensure_object(envelope, "export envelope must be a JSON object")

    if envelope_object.get("formatVersion") != EXPORT_FORMAT_VERSION:
        raise ValueError(f"unsupported export format version: {envelope_object.get('formatVersion')}")

    platform_key = _normalize_platform(envelope_object.get("platform"))
    config_object = _ensure_object(envelope_object.get("config"), "export envelope config must be a JSON object")
    load_config(platform_key, config_object)
    return _sanitize_config(platform_key, config_object)
