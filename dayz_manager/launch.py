from __future__ import annotations

import re

from dayz_manager.models import ManagerConfig


def build_launch_string(workshop_ids: list[str]) -> str:
    values = [workshop_id for workshop_id in workshop_ids if workshop_id]
    if not values:
        return ""
    return ";".join(values) + ";"


def _flag_name(kind: str) -> str:
    return "serverMod" if kind == "serverMods" else "mod"


def get_mod_ids_from_launch_parameters(parameters: str, kind: str) -> list[str]:
    if not parameters:
        return []

    flag = _flag_name(kind)
    match = re.search(rf'"?-{flag}=([^"]*)"?', parameters, re.IGNORECASE)
    if not match:
        return []

    return [value for value in match.group(1).split(";") if re.fullmatch(r"\d{8,}", value)]


def set_mods_in_launch_parameters(parameters: str, kind: str, workshop_ids: list[str]) -> str:
    if not parameters:
        return parameters

    flag = _flag_name(kind)
    match = re.search(rf'("?)-{flag}=([^"]*)("?)', parameters, re.IGNORECASE)
    if not match:
        return parameters

    replacement = f'{match.group(1)}-{flag}={build_launch_string(workshop_ids)}{match.group(3)}'
    return parameters[: match.start()] + replacement + parameters[match.end() :]


def build_server_launch_args(base_args: str, mod_launch_string: str, server_mod_launch_string: str) -> str:
    parts = [base_args] if base_args else []
    if mod_launch_string:
        parts.append(f'"-mod={mod_launch_string}"')
    if server_mod_launch_string:
        parts.append(f'"-serverMod={server_mod_launch_string}"')
    return " ".join(parts)


def build_linux_launch_args(config: ManagerConfig) -> str:
    profiles_path = config.profiles_path or "/srv/dayz/server/profiles"
    base_args = f"-config=serverDZ.cfg -profiles={profiles_path} -port=2302 -freezecheck -adminlog -dologs"
    return build_server_launch_args(
        base_args,
        build_launch_string(config.active_client_ids),
        build_launch_string(config.active_server_ids),
    )

