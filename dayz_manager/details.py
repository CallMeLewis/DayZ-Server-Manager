from __future__ import annotations

from typing import Any


def _normalize_string(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _normalize_workshop_id(value: Any) -> str:
    if isinstance(value, dict):
        return _normalize_string(value.get("workshopId", ""))
    return _normalize_string(value)


def _extract_workshop_items(values: Any) -> list[dict[str, str]]:
    if not isinstance(values, list):
        return []

    items: list[dict[str, str]] = []
    for value in values:
        if isinstance(value, dict):
            workshop_id = _normalize_string(value.get("workshopId", ""))
            if not workshop_id:
                continue
            items.append(
                {
                    "workshopId": workshop_id,
                    "name": _normalize_string(value.get("name", "")),
                    "url": _normalize_string(value.get("url", "")),
                }
            )
        else:
            workshop_id = _normalize_string(value)
            if not workshop_id:
                continue
            items.append({"workshopId": workshop_id, "name": "", "url": ""})
    return items


def _extract_groups(platform: str, data: dict[str, Any]) -> list[dict[str, Any]]:
    if platform == "windows":
        raw_groups = data.get("modGroups", [])
    else:
        raw_groups = data.get("modLibrary", {}).get("groups", [])

    if not isinstance(raw_groups, list):
        return []

    groups: list[dict[str, Any]] = []
    for value in raw_groups:
        if not isinstance(value, dict):
            continue
        name = _normalize_string(value.get("name", ""))
        if not name:
            continue
        groups.append(
            {
                "name": name,
                "mods": [_normalize_workshop_id(item) for item in value.get("mods", []) if _normalize_workshop_id(item)],
                "serverMods": [_normalize_workshop_id(item) for item in value.get("serverMods", []) if _normalize_workshop_id(item)],
                "mission": _normalize_string(value.get("mission", "")),
            }
        )
    return groups


def _active_group_name(platform: str, data: dict[str, Any]) -> str:
    if platform == "windows":
        return _normalize_string(data.get("activeGroup", ""))
    return _normalize_string(data.get("modLibrary", {}).get("activeGroup", ""))


def _find_group(platform: str, groups: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    target = _normalize_string(name)
    if not target:
        return None

    if platform == "windows":
        target_lower = target.lower()
        for group in groups:
            if group["name"].lower() == target_lower:
                return group
        return None

    for group in groups:
        if group["name"] == target:
            return group
    return None


def _library_items_by_kind(platform: str, data: dict[str, Any], kind: str) -> list[dict[str, str]]:
    if platform == "windows":
        return _extract_workshop_items(data.get("serverMods" if kind == "serverMods" else "mods", []))

    mod_library = data.get("modLibrary", {})
    return _extract_workshop_items(mod_library.get("serverWorkshopIds" if kind == "serverMods" else "workshopIds", []))


def workshop_usage_summary(platform: str, data: dict[str, Any], workshop_id: str, kind: str) -> dict[str, Any]:
    normalized_id = _normalize_string(workshop_id)
    groups = _extract_groups(platform, data)
    active_group = _active_group_name(platform, data)
    field_name = "serverMods" if kind == "serverMods" else "mods"

    referencing = [group["name"] for group in groups if normalized_id in group[field_name]]
    return {
        "workshopId": normalized_id,
        "kind": kind,
        "referencingGroups": referencing,
        "activeGroupAffected": active_group in referencing,
    }


def group_detail_summary(platform: str, data: dict[str, Any], group_name: str) -> dict[str, Any]:
    groups = _extract_groups(platform, data)
    group = _find_group(platform, groups, group_name)
    if group is None:
        raise ValueError(f"unknown mod group: {group_name}")

    client_items = _library_items_by_kind(platform, data, "mods")
    server_items = _library_items_by_kind(platform, data, "serverMods")
    client_by_id = {item["workshopId"]: item for item in client_items}
    server_by_id = {item["workshopId"]: item for item in server_items}

    resolved_mods: list[dict[str, str]] = []
    dangling_mods: list[str] = []
    for workshop_id in group["mods"]:
        item = client_by_id.get(workshop_id)
        if item is None:
            dangling_mods.append(workshop_id)
        else:
            resolved_mods.append(dict(item))

    resolved_server_mods: list[dict[str, str]] = []
    dangling_server_mods: list[str] = []
    for workshop_id in group["serverMods"]:
        item = server_by_id.get(workshop_id)
        if item is None:
            dangling_server_mods.append(workshop_id)
        else:
            resolved_server_mods.append(dict(item))

    return {
        "groupName": group["name"],
        "missionName": group["mission"],
        "resolvedMods": resolved_mods,
        "danglingMods": dangling_mods,
        "resolvedServerMods": resolved_server_mods,
        "danglingServerMods": dangling_server_mods,
    }
