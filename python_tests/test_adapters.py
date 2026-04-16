import unittest
from pathlib import Path

from dayz_manager.adapters import load_config_from_path, load_linux_config, load_windows_config
from dayz_manager.transfer import build_export_envelope, import_config_envelope


class AdapterTests(unittest.TestCase):
    def test_load_windows_realworld_fixture_from_path(self) -> None:
        fixture_path = Path(__file__).resolve().parent / "fixtures" / "windows-realworld-config.json"

        config = load_config_from_path("windows", str(fixture_path))

        self.assertEqual(config.active_group_name, "Deerisle 6.0")
        self.assertEqual(config.active_client_ids, ["1559212036", "1828439124", "3703215741", "1750506510", "3706391334"])
        self.assertEqual(config.active_server_ids, ["3705672649", "3703219006", "3704607948"])
        self.assertIn("-profiles=D:\\DayZServer\\logs", config.launch_parameters)

    def test_load_windows_config_reads_active_group_membership(self) -> None:
        config = load_windows_config(
            {
                "launchParameters": '-config=serverDZ.cfg "-mod=99999999;" "-serverMod="',
                "mods": [
                    {"workshopId": "11111111", "name": "CF"},
                    {"workshopId": "22222222", "name": "Dabs"},
                ],
                "serverMods": [
                    {"workshopId": "33333333", "name": "Server Pack"},
                ],
                "activeGroup": "core",
                "modGroups": [
                    {
                        "name": "core",
                        "mods": ["22222222", "11111111"],
                        "serverMods": ["33333333"],
                    }
                ],
            }
        )

        self.assertEqual(config.active_group_name, "core")
        self.assertEqual(config.active_client_ids, ["22222222", "11111111"])
        self.assertEqual(config.active_server_ids, ["33333333"])
        self.assertEqual(config.launch_parameters, '-config=serverDZ.cfg "-mod=99999999;" "-serverMod="')

    def test_load_linux_config_reads_nested_mod_library_shape(self) -> None:
        config = load_linux_config(
            {
                "profilesPath": "/srv/dayz/server/profiles",
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": [
                        {"workshopId": "11111111", "name": "CF"},
                        "22222222",
                    ],
                    "serverWorkshopIds": [
                        {"workshopId": "33333333", "name": "Server Pack"},
                        "44444444",
                    ],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["22222222"],
                            "serverMods": ["33333333"],
                        }
                    ],
                },
            }
        )

        self.assertEqual(config.active_group_name, "raid")
        self.assertEqual(config.library_client_ids, ["11111111", "22222222"])
        self.assertEqual(config.library_server_ids, ["33333333", "44444444"])
        self.assertEqual(config.active_client_ids, ["22222222"])
        self.assertEqual(config.active_server_ids, ["33333333"])
        self.assertEqual(config.profiles_path, "/srv/dayz/server/profiles")

    def test_linux_config_without_active_group_falls_back_to_library_ids(self) -> None:
        config = load_linux_config(
            {
                "modLibrary": {
                    "activeGroup": "",
                    "workshopIds": ["11111111", "22222222"],
                    "serverWorkshopIds": ["33333333"],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["99999999"],
                            "serverMods": ["88888888"],
                        }
                    ],
                },
            }
        )

        self.assertEqual(config.active_ids_for_kind("mods"), ["11111111", "22222222"])
        self.assertEqual(config.active_ids_for_kind("serverMods"), ["33333333"])

    def test_linux_active_group_lookup_is_case_sensitive(self) -> None:
        config = load_linux_config(
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": ["11111111"],
                    "serverWorkshopIds": ["33333333"],
                    "groups": [
                        {
                            "name": "Raid",
                            "mods": ["22222222"],
                            "serverMods": ["44444444"],
                        }
                    ],
                },
            }
        )

        self.assertEqual(config.active_ids_for_kind("mods"), ["11111111"])
        self.assertEqual(config.active_ids_for_kind("serverMods"), ["33333333"])
        self.assertEqual(config.group_status_summary()["groupState"], "missing")

    def test_linux_group_status_summary_reports_mission_and_dangling_refs(self) -> None:
        config = load_linux_config(
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": ["11111111"],
                    "serverWorkshopIds": ["33333333"],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["11111111", "22222222"],
                            "serverMods": ["33333333", "44444444"],
                            "mission": "empty.60.deerisle",
                        }
                    ],
                },
            }
        )

        summary = config.group_status_summary()

        self.assertEqual(summary["activeGroup"], "raid")
        self.assertEqual(summary["groupState"], "present")
        self.assertEqual(summary["clientCount"], 2)
        self.assertEqual(summary["serverCount"], 2)
        self.assertEqual(summary["danglingCount"], 2)
        self.assertEqual(summary["missionName"], "empty.60.deerisle")

    def test_windows_group_status_summary_reports_missing_group(self) -> None:
        config = load_windows_config(
            {
                "activeGroup": "missing",
                "mods": [{"workshopId": "11111111", "name": "CF"}],
                "serverMods": [{"workshopId": "33333333", "name": "Server Pack"}],
                "modGroups": [
                    {
                        "name": "core",
                        "mods": ["11111111"],
                        "serverMods": ["33333333"],
                    }
                ],
            }
        )

        summary = config.group_status_summary()

        self.assertEqual(summary["activeGroup"], "missing")
        self.assertEqual(summary["groupState"], "missing")
        self.assertEqual(summary["clientCount"], 0)
        self.assertEqual(summary["serverCount"], 0)
        self.assertEqual(summary["danglingCount"], 0)

    def test_linux_group_catalog_summary_includes_active_group_library_ids_and_rows(self) -> None:
        config = load_linux_config(
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": ["11111111", "22222222"],
                    "serverWorkshopIds": ["33333333"],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["11111111", "22222222"],
                            "serverMods": ["33333333"],
                            "mission": "empty.60.deerisle",
                        },
                        {
                            "name": "vanilla",
                            "mods": [],
                            "serverMods": [],
                        },
                    ],
                }
            }
        )

        summary = config.group_catalog_summary()

        self.assertEqual(summary["activeGroup"], "raid")
        self.assertEqual(summary["libraryClientIds"], ["11111111", "22222222"])
        self.assertEqual(summary["libraryServerIds"], ["33333333"])
        self.assertEqual(
            summary["groups"],
            [
                {
                    "name": "raid",
                    "modCount": 2,
                    "serverModCount": 1,
                    "missionName": "empty.60.deerisle",
                },
                {
                    "name": "vanilla",
                    "modCount": 0,
                    "serverModCount": 0,
                    "missionName": "",
                },
            ],
        )

    def test_windows_group_catalog_summary_counts_group_members(self) -> None:
        config = load_windows_config(
            {
                "activeGroup": "core",
                "mods": [{"workshopId": "11111111", "name": "CF"}],
                "serverMods": [{"workshopId": "33333333", "name": "Server Pack"}],
                "modGroups": [
                    {
                        "name": "core",
                        "mods": ["11111111", "22222222"],
                        "serverMods": ["33333333"],
                    }
                ],
            }
        )

        summary = config.group_catalog_summary()

        self.assertEqual(summary["activeGroup"], "core")
        self.assertEqual(summary["libraryClientIds"], ["11111111"])
        self.assertEqual(summary["libraryServerIds"], ["33333333"])
        self.assertEqual(
            summary["groups"],
            [
                {
                    "name": "core",
                    "modCount": 2,
                    "serverModCount": 1,
                    "missionName": "",
                }
            ],
        )

    def test_linux_mod_summary_includes_group_membership_lists(self) -> None:
        config = load_linux_config(
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": ["11111111", "22222222"],
                    "serverWorkshopIds": ["33333333"],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["11111111", "22222222"],
                            "serverMods": ["33333333"],
                            "mission": "empty.60.deerisle",
                        }
                    ],
                }
            }
        )

        summary = config.mod_summary()

        self.assertEqual(summary["activeGroup"], "raid")
        self.assertEqual(summary["libraryClientIds"], ["11111111", "22222222"])
        self.assertEqual(
            summary["groups"],
            [
                {
                    "name": "raid",
                    "mods": ["11111111", "22222222"],
                    "serverMods": ["33333333"],
                    "missionName": "empty.60.deerisle",
                }
            ],
        )

    def test_linux_config_summary_uses_defaults_for_missing_optional_fields(self) -> None:
        config = load_linux_config({"modLibrary": {}})

        summary = config.config_summary()

        self.assertEqual(summary["serverRoot"], "/srv/dayz/server")
        self.assertEqual(summary["autostart"], True)
        self.assertEqual(summary["serviceUser"], "dayz")
        self.assertEqual(summary["serviceName"], "dayz-server")
        self.assertEqual(summary["steamUsername"], "")
        self.assertEqual(summary["steamSaveMode"], "session")
        self.assertEqual(summary["steamPasswordFile"], "/etc/dayz-server-manager/credentials.env")

    def test_linux_config_summary_carries_explicit_config_values(self) -> None:
        config = load_linux_config(
            {
                "serverRoot": "/srv/dayz/custom",
                "autostart": False,
                "serviceUser": "customuser",
                "serviceName": "custom-dayz",
                "steamAccount": {
                    "username": "example-user",
                    "saveMode": "saved",
                    "passwordFile": "/etc/dayz/custom.env",
                },
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": ["11111111"],
                    "groups": [{"name": "raid", "mods": ["11111111"], "serverMods": []}],
                },
            }
        )

        summary = config.config_summary()

        self.assertEqual(summary["serverRoot"], "/srv/dayz/custom")
        self.assertEqual(summary["autostart"], False)
        self.assertEqual(summary["serviceUser"], "customuser")
        self.assertEqual(summary["serviceName"], "custom-dayz")
        self.assertEqual(summary["steamUsername"], "example-user")
        self.assertEqual(summary["steamSaveMode"], "saved")
        self.assertEqual(summary["steamPasswordFile"], "/etc/dayz/custom.env")

    def test_windows_valid_library_ids_filter_invalid_and_duplicate_entries(self) -> None:
        config = load_windows_config(
            {
                "mods": [
                    {"workshopId": "11111111", "name": "CF"},
                    {"workshopId": "bad-id", "name": "Broken"},
                    {"workshopId": "11111111", "name": "Duplicate"},
                    "22222222",
                    "not-a-number",
                ],
                "serverMods": [
                    {"workshopId": "33333333", "name": "Server Pack"},
                    "33333333",
                    "",
                    "bad-server-id",
                ],
            }
        )

        self.assertEqual(config.valid_library_ids_for_kind("mods"), ["11111111", "22222222"])
        self.assertEqual(config.valid_library_ids_for_kind("serverMods"), ["33333333"])

    def test_linux_valid_library_ids_filter_invalid_and_duplicate_entries(self) -> None:
        config = load_linux_config(
            {
                "modLibrary": {
                    "workshopIds": [
                        {"workshopId": "11111111", "name": "CF"},
                        {"workshopId": "bad-id", "name": "Broken"},
                        {"workshopId": "11111111", "name": "Duplicate"},
                        "22222222",
                        "not-a-number",
                    ],
                    "serverWorkshopIds": [
                        {"workshopId": "33333333", "name": "Server Pack"},
                        "33333333",
                        "",
                        "bad-server-id",
                    ],
                }
            }
        )

        self.assertEqual(config.valid_library_ids_for_kind("mods"), ["11111111", "22222222"])
        self.assertEqual(config.valid_library_ids_for_kind("serverMods"), ["33333333"])

    def test_export_envelope_sanitizes_windows_config(self) -> None:
        envelope = build_export_envelope(
            "windows",
            {
                "launchParameters": '-config=serverDZ.cfg "-mod=11111111;"',
                "mods": [{"workshopId": "11111111", "name": "CF"}],
                "serverMods": [{"workshopId": "33333333", "name": "Server Pack"}],
                "modGroups": [
                    {
                        "name": "Core",
                        "mods": ["11111111"],
                        "serverMods": ["33333333"],
                    }
                ],
                "activeGroup": "Core",
                "steamAccount": {"username": "secret-user"},
                "runtime": {"pid": 1234},
            },
        )

        self.assertEqual(envelope["formatVersion"], 1)
        self.assertEqual(envelope["platform"], "windows")
        self.assertEqual(envelope["config"]["activeGroup"], "Core")
        self.assertNotIn("steamAccount", envelope["config"])
        self.assertNotIn("runtime", envelope["config"])

    def test_import_envelope_sanitizes_linux_config(self) -> None:
        config = import_config_envelope(
            {
                "formatVersion": 1,
                "platform": "linux",
                "config": {
                    "serverRoot": "/srv/dayz/server",
                    "profilesPath": "/srv/dayz/server/profiles",
                    "autostart": False,
                    "serviceUser": "dayz",
                    "serviceName": "dayz-server",
                    "steamAccount": {
                        "username": "secret-user",
                        "saveMode": "saved",
                        "passwordFile": "/etc/dayz/credentials.env",
                    },
                    "modLibrary": {
                        "activeGroup": "raid",
                        "workshopIds": ["11111111"],
                        "serverWorkshopIds": ["33333333"],
                        "groups": [{"name": "raid", "mods": ["11111111"], "serverMods": ["33333333"]}],
                    },
                },
            }
        )

        self.assertEqual(config["serverRoot"], "/srv/dayz/server")
        self.assertEqual(config["modLibrary"]["activeGroup"], "raid")
        self.assertNotIn("steamAccount", config)

    def test_import_envelope_rejects_missing_config_payload(self) -> None:
        with self.assertRaises(ValueError):
            import_config_envelope({"formatVersion": 1, "platform": "windows"})


if __name__ == "__main__":
    unittest.main()
