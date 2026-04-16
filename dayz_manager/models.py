from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class ModGroup:
    name: str
    mods: list[str] = field(default_factory=list)
    server_mods: list[str] = field(default_factory=list)
    mission: str = ""


@dataclass
class ManagerConfig:
    platform: str
    library_client_ids: list[str] = field(default_factory=list)
    library_server_ids: list[str] = field(default_factory=list)
    groups: list[ModGroup] = field(default_factory=list)
    active_group_name: str = ""
    launch_parameters: str = ""
    profiles_path: str = ""
    server_root: str = ""
    autostart: bool = True
    service_user: str = ""
    service_name: str = ""
    steam_username: str = ""
    steam_save_mode: str = ""
    steam_password_file: str = ""

    def get_group(self, name: str) -> ModGroup | None:
        if not name:
            return None

        if self.platform == "linux":
            for group in self.groups:
                if group.name == name:
                    return group
            return None

        target = name.lower()
        for group in self.groups:
            if group.name.lower() == target:
                return group
        return None

    @property
    def active_client_ids(self) -> list[str]:
        group = self.get_group(self.active_group_name)
        if group:
            return list(group.mods)
        return list(self.library_client_ids)

    @property
    def active_server_ids(self) -> list[str]:
        group = self.get_group(self.active_group_name)
        if group:
            return list(group.server_mods)
        return list(self.library_server_ids)

    def active_ids_for_kind(self, kind: str) -> list[str]:
        if kind == "serverMods":
            return self.active_server_ids
        return self.active_client_ids

    def ids_for_kind(self, kind: str, *, strict_active_group: bool = False) -> list[str]:
        group = self.get_group(self.active_group_name)
        if group:
            return list(group.server_mods if kind == "serverMods" else group.mods)
        if strict_active_group and self.active_group_name:
            return []
        if kind == "serverMods":
            return list(self.library_server_ids)
        return list(self.library_client_ids)

    def group_status_summary(self) -> dict[str, object]:
        active_group = self.active_group_name
        if not active_group:
            return {
                "activeGroup": "",
                "groupState": "none",
                "clientCount": 0,
                "serverCount": 0,
                "danglingCount": 0,
                "missionName": "",
            }

        group = self.get_group(active_group)
        if group is None:
            return {
                "activeGroup": active_group,
                "groupState": "missing",
                "clientCount": 0,
                "serverCount": 0,
                "danglingCount": 0,
                "missionName": "",
            }

        dangling_client = [item for item in group.mods if item not in self.library_client_ids]
        dangling_server = [item for item in group.server_mods if item not in self.library_server_ids]

        return {
            "activeGroup": active_group,
            "groupState": "present",
            "clientCount": len(group.mods),
            "serverCount": len(group.server_mods),
            "danglingCount": len(dangling_client) + len(dangling_server),
            "missionName": group.mission,
        }

    def group_catalog_summary(self) -> dict[str, object]:
        return {
            "activeGroup": self.active_group_name,
            "libraryClientIds": list(self.library_client_ids),
            "libraryServerIds": list(self.library_server_ids),
            "groups": [
                {
                    "name": group.name,
                    "modCount": len(group.mods),
                    "serverModCount": len(group.server_mods),
                    "missionName": group.mission,
                }
                for group in self.groups
            ],
        }

    def mod_summary(self) -> dict[str, object]:
        return {
            "activeGroup": self.active_group_name,
            "libraryClientIds": list(self.library_client_ids),
            "groups": [
                {
                    "name": group.name,
                    "mods": list(group.mods),
                    "serverMods": list(group.server_mods),
                    "missionName": group.mission,
                }
                for group in self.groups
            ],
        }

    def config_summary(self) -> dict[str, object]:
        return {
            "serverRoot": self.server_root or "/srv/dayz/server",
            "autostart": self.autostart,
            "serviceUser": self.service_user or "dayz",
            "serviceName": self.service_name or "dayz-server",
            "steamUsername": self.steam_username,
            "steamSaveMode": self.steam_save_mode or "session",
            "steamPasswordFile": self.steam_password_file or "/etc/dayz-server-manager/credentials.env",
            "groupStatus": self.group_status_summary(),
        }

    def valid_library_ids_for_kind(self, kind: str) -> list[str]:
        source = self.library_server_ids if kind == "serverMods" else self.library_client_ids
        return [item for item in source if re.fullmatch(r"\d{8,}", item)]
