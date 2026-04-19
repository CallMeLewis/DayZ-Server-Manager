from __future__ import annotations

from dataclasses import dataclass, field

from dayz_manager._common import is_valid_workshop_id


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

    def ids_for_kind(self, kind: str, *, strict_active_group: bool = False) -> list[str]:
        group = self.get_group(self.active_group_name)
        if group:
            return list(group.server_mods if kind == "serverMods" else group.mods)
        if strict_active_group and self.active_group_name:
            return []
        source = self.library_server_ids if kind == "serverMods" else self.library_client_ids
        return list(source)

    def active_ids_for_kind(self, kind: str) -> list[str]:
        return self.ids_for_kind(kind)

    @property
    def active_client_ids(self) -> list[str]:
        return self.ids_for_kind("mods")

    @property
    def active_server_ids(self) -> list[str]:
        return self.ids_for_kind("serverMods")

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

        client_library = set(self.library_client_ids)
        server_library = set(self.library_server_ids)
        dangling_count = sum(1 for item in group.mods if item not in client_library) + sum(
            1 for item in group.server_mods if item not in server_library
        )

        return {
            "activeGroup": active_group,
            "groupState": "present",
            "clientCount": len(group.mods),
            "serverCount": len(group.server_mods),
            "danglingCount": dangling_count,
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
        return [item for item in source if is_valid_workshop_id(item)]
