from __future__ import annotations

import copy
import re
from typing import Any

from dayz_manager._common import (
    ensure_dict,
    ensure_safe_workshop_id,
    normalize_platform,
    normalize_string,
    normalize_workshop_id,
    normalize_workshop_ids,
)

_LINUX_ARRAY_BY_KIND = {"mods": "workshopIds", "serverMods": "serverWorkshopIds"}
_SAFE_NAME_RE = re.compile(r"[A-Za-z0-9._ -]+")


def _as_group_list(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def _normalize_string_list(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    return [normalized for value in values if (normalized := normalize_string(value))]


def _normalize_linux_workshop_ids(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []

    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        workshop_id = normalize_string(value)
        if not workshop_id:
            continue
        ensure_safe_workshop_id(workshop_id)
        if workshop_id in seen:
            continue
        seen.add(workshop_id)
        result.append(workshop_id)
    return result


def _remove_workshop_id_from_values(values: Any, workshop_id: str) -> list[Any]:
    if not isinstance(values, list):
        return []
    return [value for value in values if normalize_workshop_id(value) != workshop_id]


def _normalize_target_kind(value: Any) -> str:
    normalized = normalize_string(value).lower()
    if normalized in ("mods", "client"):
        return "mods"
    if normalized in ("servermods", "server"):
        return "serverMods"
    raise ValueError(f"unknown target kind: {value}")


def _default_workshop_url(workshop_id: str) -> str:
    return f"https://steamcommunity.com/sharedfiles/filedetails/?id={workshop_id}"


def _find_best_existing_workshop_item(values: list[Any], workshop_id: str) -> dict[str, str] | None:
    best_item: dict[str, str] | None = None
    best_score = -1

    for value in values:
        if normalize_workshop_id(value) != workshop_id:
            continue
        if isinstance(value, dict):
            candidate = {
                "workshopId": workshop_id,
                "name": normalize_string(value.get("name", "")),
                "url": normalize_string(value.get("url", "")),
            }
        else:
            candidate = {"workshopId": workshop_id, "name": "", "url": ""}
        score = len(candidate["name"]) + len(candidate["url"])
        if score >= best_score:
            best_item = candidate
            best_score = score

    return best_item


def _build_windows_workshop_item(workshop_id: str, item_name: Any, item_url: Any, existing_values: list[Any]) -> dict[str, str]:
    name = normalize_string(item_name)
    url = normalize_string(item_url)
    existing_item = _find_best_existing_workshop_item(existing_values, workshop_id)
    if not name and existing_item is not None:
        name = existing_item["name"]
    if not url and existing_item is not None:
        url = existing_item["url"]
    return {"workshopId": workshop_id, "name": name, "url": url}


def _build_linux_workshop_item(workshop_id: str, item_name: Any, item_url: Any, existing_values: list[Any]) -> Any:
    name = normalize_string(item_name)
    url = normalize_string(item_url)
    if name or url:
        if not url:
            url = _default_workshop_url(workshop_id)
        return {"workshopId": workshop_id, "name": name, "url": url}

    existing_item = _find_best_existing_workshop_item(existing_values, workshop_id)
    if existing_item is not None and (existing_item["name"] or existing_item["url"]):
        return existing_item

    return workshop_id


def _set_workshop_item(values: Any, workshop_id: str, item: Any) -> list[Any]:
    result = _remove_workshop_id_from_values(values, workshop_id)
    result.append(item)
    return result


def _find_group_index_case_insensitive(groups: list[dict[str, Any]], name: str) -> int | None:
    if not name:
        return None

    target = name.lower()
    for index, group in enumerate(groups):
        group_name = normalize_string(group.get("name", ""))
        if group_name.lower() == target:
            return index
    return None


def _find_group_index_exact(groups: list[dict[str, Any]], name: str) -> int | None:
    for index, group in enumerate(groups):
        if normalize_string(group.get("name", "")) == name:
            return index
    return None


def _validate_windows_group_name(name: str, groups: list[dict[str, Any]], *, ignore_name: str | None = None) -> str:
    normalized = normalize_string(name)
    if not normalized:
        raise ValueError("group name is required")
    if len(normalized) > 64:
        raise ValueError("group name is too long")

    ignore_lower = ignore_name.lower() if ignore_name else None
    for group in groups:
        existing_name = normalize_string(group.get("name", ""))
        if not existing_name:
            continue
        existing_lower = existing_name.lower()
        if ignore_lower and existing_lower == ignore_lower:
            continue
        if existing_lower == normalized.lower():
            raise ValueError(f"duplicate group name: {normalized}")
    return normalized


def _validate_safe_identifier(value: Any, *, label: str, extra_forbidden: str = "") -> str:
    normalized = normalize_string(value)
    if not normalized:
        raise ValueError(f"{label} is required")
    forbidden = ("\n", "\r", '"', "\\") + tuple(extra_forbidden)
    if any(char in normalized for char in forbidden) or not _SAFE_NAME_RE.fullmatch(normalized):
        raise ValueError(f"unsafe {label}: {normalized}")
    return normalized


def _validate_linux_group_name(name: str) -> str:
    return _validate_safe_identifier(name, label="mod group name")


def _validate_linux_mission_name(name: Any) -> str:
    normalized = normalize_string(name)
    if not normalized:
        return ""
    return _validate_safe_identifier(normalized, label="mission name", extra_forbidden="/")


def _mutate_windows_group_config(data: dict[str, Any], operation: str, **kwargs: Any) -> dict[str, Any]:
    updated = copy.deepcopy(data)
    groups = _as_group_list(updated.get("modGroups", []))
    active_group = normalize_string(updated.get("activeGroup", ""))

    if operation == "add-workshop-item":
        workshop_id = normalize_string(kwargs.get("workshop_id", ""))
        target_kind = _normalize_target_kind(kwargs.get("target_kind", ""))
        existing_values = [*updated.get("mods", []), *updated.get("serverMods", [])]
        updated[target_kind] = _set_workshop_item(
            updated.get(target_kind, []),
            workshop_id,
            _build_windows_workshop_item(
                workshop_id,
                kwargs.get("item_name", ""),
                kwargs.get("item_url", ""),
                existing_values,
            ),
        )
        return updated

    if operation == "move-workshop-item":
        workshop_id = normalize_string(kwargs.get("workshop_id", ""))
        target_kind = _normalize_target_kind(kwargs.get("target_kind", ""))
        existing_values = [*updated.get("mods", []), *updated.get("serverMods", [])]
        existing_item = _find_best_existing_workshop_item(existing_values, workshop_id)
        if existing_item is None:
            return updated
        updated["mods"] = _remove_workshop_id_from_values(updated.get("mods", []), workshop_id)
        updated["serverMods"] = _remove_workshop_id_from_values(updated.get("serverMods", []), workshop_id)
        updated[target_kind] = _set_workshop_item(
            updated.get(target_kind, []),
            workshop_id,
            _build_windows_workshop_item(
                workshop_id,
                existing_item["name"],
                existing_item["url"],
                existing_values,
            ),
        )
        return updated

    if operation == "set-active":
        group_name = normalize_string(kwargs.get("group_name", ""))
        if not group_name:
            updated["activeGroup"] = ""
            return updated
        target_index = _find_group_index_case_insensitive(groups, group_name)
        if target_index is None:
            raise ValueError(f"unknown mod group: {group_name}")
        updated["activeGroup"] = normalize_string(groups[target_index].get("name", ""))
        return updated

    if operation == "rename":
        old_name = normalize_string(kwargs.get("old_name", ""))
        target_index = _find_group_index_case_insensitive(groups, old_name)
        if target_index is None:
            raise ValueError(f"unknown mod group: {old_name}")
        new_name = _validate_windows_group_name(kwargs.get("new_name", ""), groups, ignore_name=normalize_string(groups[target_index].get("name", "")))
        groups[target_index]["name"] = new_name
        if active_group and active_group == old_name:
            updated["activeGroup"] = new_name
        updated["modGroups"] = groups
        return updated

    if operation == "delete":
        group_name = normalize_string(kwargs.get("group_name", ""))
        if len(groups) <= 1:
            raise ValueError("cannot delete last remaining group")
        if active_group == group_name:
            raise ValueError("cannot delete active group")
        target_index = _find_group_index_case_insensitive(groups, group_name)
        if target_index is None:
            raise ValueError(f"unknown mod group: {group_name}")
        del groups[target_index]
        updated["modGroups"] = groups
        return updated

    if operation == "upsert":
        existing_name = normalize_string(kwargs.get("existing_name", ""))
        requested_name = normalize_string(kwargs.get("group_name", ""))
        target_index = _find_group_index_case_insensitive(groups, existing_name) if existing_name else None
        ignore_name = normalize_string(groups[target_index].get("name", "")) if target_index is not None else None
        final_name = _validate_windows_group_name(requested_name, groups, ignore_name=ignore_name)
        group_payload: dict[str, Any] = {
            "name": final_name,
            "mods": _normalize_string_list(kwargs.get("client_ids", [])),
            "serverMods": _normalize_string_list(kwargs.get("server_ids", [])),
        }
        mission_name = normalize_string(kwargs.get("mission_name", ""))
        if mission_name:
            group_payload["mission"] = mission_name

        if target_index is None:
            groups.append(group_payload)
        else:
            groups[target_index] = group_payload
        updated["modGroups"] = groups
        return updated

    if operation == "remove-workshop-id":
        workshop_id = normalize_string(kwargs.get("workshop_id", ""))
        updated["mods"] = _remove_workshop_id_from_values(updated.get("mods", []), workshop_id)
        updated["serverMods"] = _remove_workshop_id_from_values(updated.get("serverMods", []), workshop_id)
        for group in groups:
            group["mods"] = [item for item in group.get("mods", []) if normalize_workshop_id(item) != workshop_id]
            group["serverMods"] = [item for item in group.get("serverMods", []) if normalize_workshop_id(item) != workshop_id]
        updated["modGroups"] = groups
        return updated

    raise ValueError(f"unsupported operation: {operation}")


def _apply_linux_active_group_update(groups: list[dict[str, Any]], active_group: str, target_kind: str, workshop_id: str) -> None:
    if not active_group:
        return
    other_kind = "serverMods" if target_kind == "mods" else "mods"
    for group in groups:
        if normalize_string(group.get("name", "")) != active_group:
            continue
        group[target_kind] = normalize_workshop_ids([*group.get(target_kind, []), workshop_id])
        group[other_kind] = [item for item in group.get(other_kind, []) if normalize_workshop_id(item) != workshop_id]


def _mutate_linux_group_config(data: dict[str, Any], operation: str, **kwargs: Any) -> dict[str, Any]:
    updated = copy.deepcopy(data)
    mod_library = updated.get("modLibrary")
    if not isinstance(mod_library, dict):
        mod_library = {}
        updated["modLibrary"] = mod_library

    groups = _as_group_list(mod_library.get("groups", []))
    active_group = normalize_string(mod_library.get("activeGroup", ""))

    if operation == "add-workshop-item":
        workshop_id = ensure_safe_workshop_id(normalize_string(kwargs.get("workshop_id", "")))
        target_kind = _normalize_target_kind(kwargs.get("target_kind", ""))
        array_name = _LINUX_ARRAY_BY_KIND[target_kind]
        existing_values = [*mod_library.get("workshopIds", []), *mod_library.get("serverWorkshopIds", [])]
        mod_library[array_name] = _set_workshop_item(
            mod_library.get(array_name, []),
            workshop_id,
            _build_linux_workshop_item(
                workshop_id,
                kwargs.get("item_name", ""),
                kwargs.get("item_url", ""),
                existing_values,
            ),
        )
        if not active_group:
            return updated
        _apply_linux_active_group_update(groups, active_group, target_kind, workshop_id)
        mod_library["groups"] = groups
        return updated

    if operation == "move-workshop-item":
        workshop_id = ensure_safe_workshop_id(normalize_string(kwargs.get("workshop_id", "")))
        if not active_group:
            raise ValueError("Set an active mod group before moving mods between client and server lists.")
        target_kind = _normalize_target_kind(kwargs.get("target_kind", ""))
        target_array = _LINUX_ARRAY_BY_KIND[target_kind]
        source_array = _LINUX_ARRAY_BY_KIND["serverMods" if target_kind == "mods" else "mods"]
        existing_values = [*mod_library.get("workshopIds", []), *mod_library.get("serverWorkshopIds", [])]
        mod_library[target_array] = _set_workshop_item(
            mod_library.get(target_array, []),
            workshop_id,
            _build_linux_workshop_item(
                workshop_id,
                kwargs.get("item_name", ""),
                kwargs.get("item_url", ""),
                existing_values,
            ),
        )
        mod_library[source_array] = _remove_workshop_id_from_values(mod_library.get(source_array, []), workshop_id)
        _apply_linux_active_group_update(groups, active_group, target_kind, workshop_id)
        mod_library["groups"] = groups
        return updated

    if operation == "set-active":
        group_name = normalize_string(kwargs.get("group_name", ""))
        if group_name:
            group_name = _validate_linux_group_name(group_name)
            if _find_group_index_exact(groups, group_name) is None:
                raise ValueError(f"unknown mod group: {group_name}")
        mod_library["activeGroup"] = group_name
        return updated

    if operation == "rename":
        old_name = _validate_linux_group_name(kwargs.get("old_name", ""))
        new_name = _validate_linux_group_name(kwargs.get("new_name", ""))
        target_index = _find_group_index_exact(groups, old_name)
        if target_index is None:
            raise ValueError(f"unknown mod group: {old_name}")
        groups[target_index]["name"] = new_name
        if active_group == old_name:
            mod_library["activeGroup"] = new_name
        mod_library["groups"] = groups
        return updated

    if operation == "delete":
        group_name = _validate_linux_group_name(kwargs.get("group_name", ""))
        mod_library["groups"] = [group for group in groups if normalize_string(group.get("name", "")) != group_name]
        if active_group == group_name:
            mod_library["activeGroup"] = ""
        return updated

    if operation == "upsert":
        group_name = _validate_linux_group_name(kwargs.get("group_name", ""))
        client_ids = _normalize_linux_workshop_ids(kwargs.get("client_ids", []))
        server_ids = _normalize_linux_workshop_ids(kwargs.get("server_ids", []))
        mission_name = _validate_linux_mission_name(kwargs.get("mission_name", ""))
        group_payload: dict[str, Any] = {
            "name": group_name,
            "mods": client_ids,
            "serverMods": server_ids,
            "mission": mission_name,
        }
        mod_library["groups"] = [group for group in groups if normalize_string(group.get("name", "")) != group_name] + [group_payload]
        return updated

    if operation == "remove-workshop-id":
        workshop_id = ensure_safe_workshop_id(normalize_string(kwargs.get("workshop_id", "")))
        mod_library["workshopIds"] = _remove_workshop_id_from_values(mod_library.get("workshopIds", []), workshop_id)
        mod_library["serverWorkshopIds"] = _remove_workshop_id_from_values(mod_library.get("serverWorkshopIds", []), workshop_id)
        for group in groups:
            group["mods"] = [item for item in group.get("mods", []) if normalize_workshop_id(item) != workshop_id]
            group["serverMods"] = [item for item in group.get("serverMods", []) if normalize_workshop_id(item) != workshop_id]
        mod_library["groups"] = groups
        return updated

    raise ValueError(f"unsupported operation: {operation}")


def mutate_group_config(platform: str, data: dict[str, Any], operation: str, **kwargs: Any) -> dict[str, Any]:
    ensure_dict(data, "config payload must be a JSON object")
    platform_key = normalize_platform(platform)
    if platform_key == "windows":
        return _mutate_windows_group_config(data, operation, **kwargs)
    return _mutate_linux_group_config(data, operation, **kwargs)
