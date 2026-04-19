from __future__ import annotations

from typing import Any

from dayz_manager._common import normalize_string, normalize_workshop_id


def _extract_workshop_items(values: Any) -> list[dict[str, str]]:
    if not isinstance(values, list):
        return []

    items: list[dict[str, str]] = []
    for value in values:
        if isinstance(value, dict):
            workshop_id = normalize_string(value.get("workshopId", ""))
            if not workshop_id:
                continue
            items.append(
                {
                    "workshopId": workshop_id,
                    "name": normalize_string(value.get("name", "")),
                    "url": normalize_string(value.get("url", "")),
                }
            )
        else:
            workshop_id = normalize_string(value)
            if not workshop_id:
                continue
            items.append({"workshopId": workshop_id, "name": "", "url": ""})
    return items


def _extract_groups(platform: str, data: dict[str, Any]) -> list[dict[str, Any]]:
    raw_groups = data.get("modGroups", []) if platform == "windows" else data.get("modLibrary", {}).get("groups", [])
    if not isinstance(raw_groups, list):
        return []

    groups: list[dict[str, Any]] = []
    for value in raw_groups:
        if not isinstance(value, dict):
            continue
        name = normalize_string(value.get("name", ""))
        if not name:
            continue
        groups.append(
            {
                "name": name,
                "mods": [wid for item in value.get("mods", []) if (wid := normalize_workshop_id(item))],
                "serverMods": [wid for item in value.get("serverMods", []) if (wid := normalize_workshop_id(item))],
                "mission": normalize_string(value.get("mission", "")),
            }
        )
    return groups


def _active_group_name(platform: str, data: dict[str, Any]) -> str:
    source = data if platform == "windows" else data.get("modLibrary", {})
    return normalize_string(source.get("activeGroup", ""))


def _find_group(platform: str, groups: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    target = normalize_string(name)
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
    normalized_id = normalize_string(workshop_id)
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

    client_by_id = {item["workshopId"]: item for item in _library_items_by_kind(platform, data, "mods")}
    server_by_id = {item["workshopId"]: item for item in _library_items_by_kind(platform, data, "serverMods")}

    def resolve(ids: list[str], catalog: dict[str, dict[str, str]]) -> tuple[list[dict[str, str]], list[str]]:
        resolved: list[dict[str, str]] = []
        dangling: list[str] = []
        for workshop_id in ids:
            item = catalog.get(workshop_id)
            if item is None:
                dangling.append(workshop_id)
            else:
                resolved.append(dict(item))
        return resolved, dangling

    resolved_mods, dangling_mods = resolve(group["mods"], client_by_id)
    resolved_server_mods, dangling_server_mods = resolve(group["serverMods"], server_by_id)

    return {
        "groupName": group["name"],
        "missionName": group["mission"],
        "resolvedMods": resolved_mods,
        "danglingMods": dangling_mods,
        "resolvedServerMods": resolved_server_mods,
        "danglingServerMods": dangling_server_mods,
    }
