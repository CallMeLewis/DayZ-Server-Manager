from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from dayz_manager.models import ManagerConfig, ModGroup


def _normalize_string(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _normalize_workshop_id(value: Any) -> str:
    if isinstance(value, dict):
        return _normalize_string(value.get("workshopId", ""))
    return _normalize_string(value)


def _normalize_workshop_ids(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []

    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        workshop_id = _normalize_workshop_id(value)
        if not workshop_id or workshop_id in seen:
            continue
        seen.add(workshop_id)
        result.append(workshop_id)
    return result


def _normalize_group(entry: Any) -> ModGroup | None:
    if not isinstance(entry, dict):
        return None

    name = _normalize_string(entry.get("name", ""))
    if not name:
        return None

    return ModGroup(
        name=name,
        mods=_normalize_workshop_ids(entry.get("mods", [])),
        server_mods=_normalize_workshop_ids(entry.get("serverMods", [])),
        mission=_normalize_string(entry.get("mission", "")),
    )


def load_windows_config(data: dict[str, Any]) -> ManagerConfig:
    groups = [_normalize_group(entry) for entry in data.get("modGroups", [])]

    return ManagerConfig(
        platform="windows",
        library_client_ids=_normalize_workshop_ids(data.get("mods", [])),
        library_server_ids=_normalize_workshop_ids(data.get("serverMods", [])),
        groups=[group for group in groups if group is not None],
        active_group_name=_normalize_string(data.get("activeGroup", "")),
        launch_parameters=_normalize_string(data.get("launchParameters", "")),
    )


def load_linux_config(data: dict[str, Any]) -> ManagerConfig:
    mod_library = data.get("modLibrary", {})
    steam_account = data.get("steamAccount", {})
    groups = [_normalize_group(entry) for entry in mod_library.get("groups", [])]

    return ManagerConfig(
        platform="linux",
        library_client_ids=_normalize_workshop_ids(mod_library.get("workshopIds", [])),
        library_server_ids=_normalize_workshop_ids(mod_library.get("serverWorkshopIds", [])),
        groups=[group for group in groups if group is not None],
        active_group_name=_normalize_string(mod_library.get("activeGroup", "")),
        profiles_path=_normalize_string(data.get("profilesPath", "")),
        server_root=_normalize_string(data.get("serverRoot", "")),
        autostart=bool(data.get("autostart", True)),
        service_user=_normalize_string(data.get("serviceUser", "")),
        service_name=_normalize_string(data.get("serviceName", "")),
        steam_username=_normalize_string(steam_account.get("username", "")),
        steam_save_mode=_normalize_string(steam_account.get("saveMode", "")),
        steam_password_file=_normalize_string(steam_account.get("passwordFile", "")),
    )


def load_config(platform: str, data: dict[str, Any]) -> ManagerConfig:
    platform_key = _normalize_string(platform).lower()
    if platform_key == "windows":
        return load_windows_config(data)
    if platform_key == "linux":
        return load_linux_config(data)
    raise ValueError(f"unsupported platform: {platform}")


def load_config_from_path(platform: str, path: str) -> ManagerConfig:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("config payload must be a JSON object")
    return load_config(platform, payload)


def load_config_from_json_text(platform: str, text: str) -> ManagerConfig:
    payload = json.loads(text)
    if not isinstance(payload, dict):
        raise ValueError("config payload must be a JSON object")
    return load_config(platform, payload)
