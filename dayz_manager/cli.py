from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from dayz_manager.adapters import load_config_from_json_text, load_config_from_path
from dayz_manager.update_check import check_update
from dayz_manager.details import group_detail_summary, workshop_usage_summary
from dayz_manager.launch import (
    build_launch_string,
    build_linux_launch_args,
    get_mod_ids_from_launch_parameters,
    set_mods_in_launch_parameters,
)
from dayz_manager.mutations import mutate_group_config
from dayz_manager.transfer import build_export_envelope, import_config_envelope
from dayz_manager.update_apply import apply_update


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Shared DayZ Server Manager Python core")
    subparsers = parser.add_subparsers(dest="command", required=True)

    launch_string_parser = subparsers.add_parser("launch-string")
    launch_string_parser.add_argument("ids", nargs="*")

    get_mod_ids_parser = subparsers.add_parser("get-mod-ids")
    get_mod_ids_parser.add_argument("--parameters", required=True)
    get_mod_ids_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)

    set_mods_parser = subparsers.add_parser("set-mods")
    set_mods_parser.add_argument("--parameters", required=True)
    set_mods_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)
    set_mods_parser.add_argument("ids", nargs="*")

    active_ids_parser = subparsers.add_parser("active-ids")
    active_ids_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    active_ids_parser.add_argument("--config", required=True)
    active_ids_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)

    active_ids_json_parser = subparsers.add_parser("active-ids-json")
    active_ids_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    active_ids_json_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)
    active_ids_json_parser.add_argument("--strict-active-group", action="store_true")

    group_status_parser = subparsers.add_parser("group-status")
    group_status_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    group_status_parser.add_argument("--config", required=True)

    group_status_json_parser = subparsers.add_parser("group-status-json")
    group_status_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)

    group_catalog_parser = subparsers.add_parser("group-catalog")
    group_catalog_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    group_catalog_parser.add_argument("--config", required=True)

    group_catalog_json_parser = subparsers.add_parser("group-catalog-json")
    group_catalog_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)

    group_detail_json_parser = subparsers.add_parser("group-detail-json")
    group_detail_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    group_detail_json_parser.add_argument("--group-name", required=True)

    mod_summary_parser = subparsers.add_parser("mod-summary")
    mod_summary_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    mod_summary_parser.add_argument("--config", required=True)

    workshop_usage_json_parser = subparsers.add_parser("workshop-usage-json")
    workshop_usage_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    workshop_usage_json_parser.add_argument("--workshop-id", required=True)
    workshop_usage_json_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)

    remove_workshop_id_json_parser = subparsers.add_parser("remove-workshop-id-json")
    remove_workshop_id_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    remove_workshop_id_json_parser.add_argument("--workshop-id", required=True)

    mutate_inventory_json_parser = subparsers.add_parser("mutate-inventory-json")
    mutate_inventory_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    mutate_inventory_json_parser.add_argument("--operation", choices=("add-workshop-item", "move-workshop-item"), required=True)
    mutate_inventory_json_parser.add_argument("--target-kind", required=True)
    mutate_inventory_json_parser.add_argument("--workshop-id", required=True)
    mutate_inventory_json_parser.add_argument("--item-name")
    mutate_inventory_json_parser.add_argument("--item-url")

    mutate_groups_json_parser = subparsers.add_parser("mutate-groups-json")
    mutate_groups_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    mutate_groups_json_parser.add_argument("--operation", choices=("set-active", "rename", "delete", "upsert"), required=True)
    mutate_groups_json_parser.add_argument("--group-name")
    mutate_groups_json_parser.add_argument("--old-name")
    mutate_groups_json_parser.add_argument("--new-name")
    mutate_groups_json_parser.add_argument("--existing-name")
    mutate_groups_json_parser.add_argument("--client-ids-json")
    mutate_groups_json_parser.add_argument("--server-ids-json")
    mutate_groups_json_parser.add_argument("--mission-name")

    config_summary_parser = subparsers.add_parser("config-summary")
    config_summary_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    config_summary_parser.add_argument("--config", required=True)

    configured_ids_json_parser = subparsers.add_parser("configured-ids-json")
    configured_ids_json_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    configured_ids_json_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)

    configured_ids_parser = subparsers.add_parser("configured-ids")
    configured_ids_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    configured_ids_parser.add_argument("--config", required=True)
    configured_ids_parser.add_argument("--kind", choices=("mods", "serverMods"), required=True)

    linux_launch_parser = subparsers.add_parser("linux-launch-args")
    linux_launch_parser.add_argument("--config", required=True)

    export_config_parser = subparsers.add_parser("export-config-json")
    export_config_parser.add_argument("--platform", choices=("windows", "linux"), required=True)
    export_config_parser.add_argument("--config", required=True)

    subparsers.add_parser("import-config-json")

    check_update_parser = subparsers.add_parser("check-update")
    check_update_parser.add_argument("--current-version", required=True)
    check_update_parser.add_argument("--timeout", type=float, default=3.0)

    apply_update_parser = subparsers.add_parser("apply-update")
    apply_update_parser.add_argument("--tag", required=True)
    apply_update_parser.add_argument("--repo-root", required=True)
    apply_update_parser.add_argument("--timeout", type=float, default=60.0)

    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    if args.command == "launch-string":
        print(build_launch_string(args.ids))
        return 0

    if args.command == "get-mod-ids":
        print(json.dumps(get_mod_ids_from_launch_parameters(args.parameters, args.kind)))
        return 0

    if args.command == "set-mods":
        print(set_mods_in_launch_parameters(args.parameters, args.kind, args.ids))
        return 0

    if args.command == "active-ids":
        print(json.dumps(load_config_from_path(args.platform, args.config).active_ids_for_kind(args.kind)))
        return 0

    if args.command == "active-ids-json":
        config = load_config_from_json_text(args.platform, sys.stdin.read())
        print(json.dumps(config.ids_for_kind(args.kind, strict_active_group=args.strict_active_group)))
        return 0

    if args.command == "group-status":
        print(json.dumps(load_config_from_path(args.platform, args.config).group_status_summary()))
        return 0

    if args.command == "group-status-json":
        print(json.dumps(load_config_from_json_text(args.platform, sys.stdin.read()).group_status_summary()))
        return 0

    if args.command == "group-catalog":
        print(json.dumps(load_config_from_path(args.platform, args.config).group_catalog_summary()))
        return 0

    if args.command == "group-catalog-json":
        print(json.dumps(load_config_from_json_text(args.platform, sys.stdin.read()).group_catalog_summary()))
        return 0

    if args.command == "group-detail-json":
        try:
            payload = json.loads(sys.stdin.read())
            print(json.dumps(group_detail_summary(args.platform, payload, args.group_name)))
            return 0
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1

    if args.command == "mod-summary":
        print(json.dumps(load_config_from_path(args.platform, args.config).mod_summary()))
        return 0

    if args.command == "workshop-usage-json":
        payload = json.loads(sys.stdin.read())
        print(json.dumps(workshop_usage_summary(args.platform, payload, args.workshop_id, args.kind)))
        return 0

    if args.command == "remove-workshop-id-json":
        try:
            payload = json.loads(sys.stdin.read())
            updated = mutate_group_config(
                args.platform,
                payload,
                "remove-workshop-id",
                workshop_id=args.workshop_id,
            )
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        print(json.dumps(updated))
        return 0

    if args.command == "mutate-inventory-json":
        try:
            payload = json.loads(sys.stdin.read())
            updated = mutate_group_config(
                args.platform,
                payload,
                args.operation,
                target_kind=args.target_kind,
                workshop_id=args.workshop_id,
                item_name=args.item_name,
                item_url=args.item_url,
            )
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        print(json.dumps(updated))
        return 0

    if args.command == "mutate-groups-json":
        try:
            payload = json.loads(sys.stdin.read())
            client_ids = json.loads(args.client_ids_json) if args.client_ids_json else []
            server_ids = json.loads(args.server_ids_json) if args.server_ids_json else []
            updated = mutate_group_config(
                args.platform,
                payload,
                args.operation,
                group_name=args.group_name,
                old_name=args.old_name,
                new_name=args.new_name,
                existing_name=args.existing_name,
                client_ids=client_ids,
                server_ids=server_ids,
                mission_name=args.mission_name,
            )
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        print(json.dumps(updated))
        return 0

    if args.command == "config-summary":
        print(json.dumps(load_config_from_path(args.platform, args.config).config_summary()))
        return 0

    if args.command == "configured-ids-json":
        print(json.dumps(load_config_from_json_text(args.platform, sys.stdin.read()).valid_library_ids_for_kind(args.kind)))
        return 0

    if args.command == "configured-ids":
        print(json.dumps(load_config_from_path(args.platform, args.config).valid_library_ids_for_kind(args.kind)))
        return 0

    if args.command == "linux-launch-args":
        print(build_linux_launch_args(load_config_from_path("linux", args.config)))
        return 0

    if args.command == "export-config-json":
        try:
            payload = json.loads(Path(args.config).read_text(encoding="utf-8"))
            print(json.dumps(build_export_envelope(args.platform, payload)))
            return 0
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1

    if args.command == "import-config-json":
        try:
            envelope = json.loads(sys.stdin.read())
            print(json.dumps(import_config_envelope(envelope)))
            return 0
        except (json.JSONDecodeError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1

    if args.command == "check-update":
        print(json.dumps(check_update(current_version=args.current_version, timeout=args.timeout)))
        return 0

    if args.command == "apply-update":
        result = apply_update(tag=args.tag, repo_root=Path(args.repo_root), timeout=args.timeout)
        print(json.dumps(result))
        return 0 if result["success"] else 1

    raise ValueError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
