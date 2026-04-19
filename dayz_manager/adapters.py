from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from dayz_manager._common import (
    ensure_dict,
    normalize_platform,
    normalize_string,
    normalize_workshop_ids,
)
from dayz_manager.models import ManagerConfig, ModGroup


def _normalize_group(entry: Any) -> ModGroup | None:
    if not isinstance(entry, dict):
        return None

    name = normalize_string(entry.get("name", ""))
    if not name:
        return None

    return ModGroup(
        name=name,
        mods=normalize_workshop_ids(entry.get("mods", [])),
        server_mods=normalize_workshop_ids(entry.get("serverMods", [])),
        mission=normalize_string(entry.get("mission", "")),
    )


def _normalize_groups(entries: Any) -> list[ModGroup]:
    if not isinstance(entries, list):
        return []
    groups = (_normalize_group(entry) for entry in entries)
    return [group for group in groups if group is not None]


def load_windows_config(data: dict[str, Any]) -> ManagerConfig:
    return ManagerConfig(
        platform="windows",
        library_client_ids=normalize_workshop_ids(data.get("mods", [])),
        library_server_ids=normalize_workshop_ids(data.get("serverMods", [])),
        groups=_normalize_groups(data.get("modGroups", [])),
        active_group_name=normalize_string(data.get("activeGroup", "")),
        launch_parameters=normalize_string(data.get("launchParameters", "")),
    )


def load_linux_config(data: dict[str, Any]) -> ManagerConfig:
    mod_library = data.get("modLibrary", {})
    steam_account = data.get("steamAccount", {})

    return ManagerConfig(
        platform="linux",
        library_client_ids=normalize_workshop_ids(mod_library.get("workshopIds", [])),
        library_server_ids=normalize_workshop_ids(mod_library.get("serverWorkshopIds", [])),
        groups=_normalize_groups(mod_library.get("groups", [])),
        active_group_name=normalize_string(mod_library.get("activeGroup", "")),
        profiles_path=normalize_string(data.get("profilesPath", "")),
        server_root=normalize_string(data.get("serverRoot", "")),
        autostart=bool(data.get("autostart", True)),
        service_user=normalize_string(data.get("serviceUser", "")),
        service_name=normalize_string(data.get("serviceName", "")),
        steam_username=normalize_string(steam_account.get("username", "")),
        steam_save_mode=normalize_string(steam_account.get("saveMode", "")),
        steam_password_file=normalize_string(steam_account.get("passwordFile", "")),
    )


def load_config(platform: str, data: dict[str, Any]) -> ManagerConfig:
    platform_key = normalize_platform(platform)
    if platform_key == "windows":
        return load_windows_config(data)
    return load_linux_config(data)


def load_config_from_path(platform: str, path: str) -> ManagerConfig:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    return load_config(platform, ensure_dict(payload, "config payload must be a JSON object"))


def load_config_from_json_text(platform: str, text: str) -> ManagerConfig:
    payload = json.loads(text)
    return load_config(platform, ensure_dict(payload, "config payload must be a JSON object"))
