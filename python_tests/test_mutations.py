import unittest

from dayz_manager.mutations import mutate_group_config


class MutationTests(unittest.TestCase):
    def test_windows_add_workshop_item_appends_new_object_to_requested_list(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "mods": [{"workshopId": "11111111", "name": "CF"}],
                "serverMods": [],
            },
            "add-workshop-item",
            target_kind="serverMods",
            workshop_id="33333333",
            item_name="Server Pack",
            item_url="https://example.invalid/server-pack",
        )

        self.assertEqual([item["workshopId"] for item in updated["mods"]], ["11111111"])
        self.assertEqual(updated["serverMods"][0]["workshopId"], "33333333")
        self.assertEqual(updated["serverMods"][0]["name"], "Server Pack")
        self.assertEqual(updated["serverMods"][0]["url"], "https://example.invalid/server-pack")

    def test_windows_move_workshop_item_moves_existing_object_between_lists(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "mods": [{"workshopId": "11111111", "name": "CF", "url": "https://example.invalid/cf"}],
                "serverMods": [{"workshopId": "33333333", "name": "Server Pack"}],
            },
            "move-workshop-item",
            target_kind="serverMods",
            workshop_id="11111111",
        )

        self.assertEqual(updated["mods"], [])
        self.assertEqual([item["workshopId"] for item in updated["serverMods"]], ["33333333", "11111111"])
        self.assertEqual(updated["serverMods"][1]["name"], "CF")
        self.assertEqual(updated["serverMods"][1]["url"], "https://example.invalid/cf")

    def test_windows_upsert_creates_group_when_name_is_new(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "activeGroup": "Core",
                "modGroups": [
                    {"name": "Core", "mods": ["11111111"], "serverMods": []},
                ],
            },
            "upsert",
            group_name="Raid",
            client_ids=["22222222"],
            server_ids=["33333333"],
            mission_name="empty.chernarusplus",
        )

        self.assertEqual(updated["activeGroup"], "Core")
        self.assertEqual(
            updated["modGroups"][-1],
            {
                "name": "Raid",
                "mods": ["22222222"],
                "serverMods": ["33333333"],
                "mission": "empty.chernarusplus",
            },
        )

    def test_windows_upsert_updates_existing_group_by_existing_name(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "activeGroup": "Raid",
                "modGroups": [
                    {"name": "Raid", "mods": ["11111111"], "serverMods": []},
                ],
            },
            "upsert",
            existing_name="Raid",
            group_name="Raid",
            client_ids=["22222222"],
            server_ids=["33333333"],
            mission_name="empty.deerisle",
        )

        self.assertEqual(updated["activeGroup"], "Raid")
        self.assertEqual(len(updated["modGroups"]), 1)
        self.assertEqual(updated["modGroups"][0]["mods"], ["22222222"])
        self.assertEqual(updated["modGroups"][0]["serverMods"], ["33333333"])
        self.assertEqual(updated["modGroups"][0]["mission"], "empty.deerisle")

    def test_windows_set_active_group_uses_matched_group_name(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "activeGroup": "Default",
                "modGroups": [
                    {"name": "Core", "mods": ["11111111"], "serverMods": []},
                    {"name": "Raid", "mods": ["22222222"], "serverMods": ["33333333"]},
                ],
                "mods": [{"workshopId": "11111111", "name": "CF"}],
            },
            "set-active",
            group_name="raid",
        )

        self.assertEqual(updated["activeGroup"], "Raid")
        self.assertEqual(updated["mods"][0]["name"], "CF")

    def test_windows_set_active_group_allows_clear(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "activeGroup": "Raid",
                "modGroups": [
                    {"name": "Raid", "mods": ["11111111"], "serverMods": []},
                ],
            },
            "set-active",
            group_name="",
        )

        self.assertEqual(updated["activeGroup"], "")

    def test_windows_rename_group_updates_active_group(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "activeGroup": "Core",
                "modGroups": [
                    {"name": "Core", "mods": ["11111111"], "serverMods": []},
                ],
            },
            "rename",
            old_name="Core",
            new_name="Main Ops",
        )

        self.assertEqual(updated["activeGroup"], "Main Ops")
        self.assertEqual(updated["modGroups"][0]["name"], "Main Ops")

    def test_windows_remove_group_rejects_last_group(self) -> None:
        with self.assertRaisesRegex(ValueError, "last remaining group"):
            mutate_group_config(
                "windows",
                {
                    "activeGroup": "Core",
                    "modGroups": [
                        {"name": "Core", "mods": [], "serverMods": []},
                    ],
                },
                "delete",
                group_name="Backup",
            )

    def test_linux_set_active_group_allows_clear(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "groups": [{"name": "raid", "mods": [], "serverMods": []}],
                }
            },
            "set-active",
            group_name="",
        )

        self.assertEqual(updated["modLibrary"]["activeGroup"], "")

    def test_linux_add_workshop_item_without_active_group_updates_library_only(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "",
                    "workshopIds": [],
                    "serverWorkshopIds": [],
                    "groups": [],
                }
            },
            "add-workshop-item",
            target_kind="mods",
            workshop_id="11111111",
            item_name="CF",
            item_url="https://example.invalid/cf",
        )

        self.assertEqual(updated["modLibrary"]["workshopIds"][0]["workshopId"], "11111111")
        self.assertEqual(updated["modLibrary"]["serverWorkshopIds"], [])
        self.assertEqual(updated["modLibrary"]["groups"], [])

    def test_linux_add_workshop_item_with_active_group_updates_group_membership(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": [],
                    "serverWorkshopIds": [{"workshopId": "11111111", "name": "CF"}],
                    "groups": [
                        {"name": "raid", "mods": [], "serverMods": ["11111111"]},
                    ],
                }
            },
            "add-workshop-item",
            target_kind="mods",
            workshop_id="11111111",
            item_name="CF",
            item_url="https://example.invalid/cf",
        )

        self.assertEqual(updated["modLibrary"]["workshopIds"][0]["workshopId"], "11111111")
        self.assertEqual([item["workshopId"] for item in updated["modLibrary"]["serverWorkshopIds"]], ["11111111"])
        self.assertEqual(updated["modLibrary"]["groups"][0]["mods"], ["11111111"])
        self.assertEqual(updated["modLibrary"]["groups"][0]["serverMods"], [])

    def test_linux_move_workshop_item_between_active_group_lists_updates_library_and_group(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": [{"workshopId": "11111111", "name": "CF", "url": "https://example.invalid/cf"}],
                    "serverWorkshopIds": [{"workshopId": "33333333", "name": "Server Pack"}],
                    "groups": [
                        {"name": "raid", "mods": ["11111111"], "serverMods": ["33333333"]},
                    ],
                }
            },
            "move-workshop-item",
            target_kind="serverMods",
            workshop_id="11111111",
        )

        self.assertEqual(updated["modLibrary"]["workshopIds"], [])
        self.assertEqual([item["workshopId"] for item in updated["modLibrary"]["serverWorkshopIds"]], ["33333333", "11111111"])
        self.assertEqual(updated["modLibrary"]["serverWorkshopIds"][1]["name"], "CF")
        self.assertEqual(updated["modLibrary"]["groups"][0]["mods"], [])
        self.assertEqual(updated["modLibrary"]["groups"][0]["serverMods"], ["33333333", "11111111"])

    def test_linux_upsert_creates_group_with_unique_workshop_ids(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "",
                    "groups": [{"name": "backup", "mods": [], "serverMods": []}],
                }
            },
            "upsert",
            group_name="raid",
            client_ids=["11111111", "11111111", "22222222"],
            server_ids=["33333333", "33333333"],
            mission_name="empty.60.deerisle",
        )

        self.assertEqual(
            updated["modLibrary"]["groups"][-1],
            {
                "name": "raid",
                "mods": ["11111111", "22222222"],
                "serverMods": ["33333333"],
                "mission": "empty.60.deerisle",
            },
        )

    def test_linux_upsert_replaces_existing_group_by_exact_name(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "groups": [{"name": "raid", "mods": ["11111111"], "serverMods": []}],
                }
            },
            "upsert",
            group_name="raid",
            client_ids=["22222222"],
            server_ids=["33333333"],
            mission_name="empty.chernarusplus",
        )

        self.assertEqual(len(updated["modLibrary"]["groups"]), 1)
        self.assertEqual(updated["modLibrary"]["groups"][0]["mods"], ["22222222"])
        self.assertEqual(updated["modLibrary"]["groups"][0]["serverMods"], ["33333333"])
        self.assertEqual(updated["modLibrary"]["groups"][0]["mission"], "empty.chernarusplus")

    def test_linux_rename_group_updates_active_group(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "groups": [{"name": "raid", "mods": [], "serverMods": []}],
                }
            },
            "rename",
            old_name="raid",
            new_name=" operations ",
        )

        self.assertEqual(updated["modLibrary"]["activeGroup"], "operations")
        self.assertEqual(updated["modLibrary"]["groups"][0]["name"], "operations")

    def test_linux_delete_group_clears_active_group(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "groups": [
                        {"name": "raid", "mods": [], "serverMods": []},
                        {"name": "backup", "mods": [], "serverMods": []},
                    ],
                }
            },
            "delete",
            group_name="raid",
        )

        self.assertEqual(updated["modLibrary"]["activeGroup"], "")
        self.assertEqual([group["name"] for group in updated["modLibrary"]["groups"]], ["backup"])

    def test_windows_remove_workshop_id_updates_library_and_group_memberships(self) -> None:
        updated = mutate_group_config(
            "windows",
            {
                "activeGroup": "Raid",
                "mods": [
                    {"workshopId": "11111111", "name": "CF"},
                    {"workshopId": "22222222", "name": "Dabs"},
                ],
                "serverMods": [
                    {"workshopId": "33333333", "name": "Server Pack"},
                ],
                "modGroups": [
                    {"name": "Raid", "mods": ["11111111", "22222222"], "serverMods": ["33333333"]}
                ],
            },
            "remove-workshop-id",
            workshop_id="11111111",
        )

        self.assertEqual([item["workshopId"] for item in updated["mods"]], ["22222222"])
        self.assertEqual(updated["modGroups"][0]["mods"], ["22222222"])

    def test_linux_remove_workshop_id_updates_library_and_group_memberships(self) -> None:
        updated = mutate_group_config(
            "linux",
            {
                "modLibrary": {
                    "workshopIds": [
                        {"workshopId": "11111111", "name": "CF"},
                        {"workshopId": "22222222", "name": "Dabs"},
                    ],
                    "serverWorkshopIds": [
                        {"workshopId": "33333333", "name": "Server Pack"},
                    ],
                    "groups": [
                        {"name": "raid", "mods": ["11111111", "22222222"], "serverMods": ["33333333"]}
                    ],
                }
            },
            "remove-workshop-id",
            workshop_id="11111111",
        )

        self.assertEqual(
            [item["workshopId"] for item in updated["modLibrary"]["workshopIds"]],
            ["22222222"],
        )
        self.assertEqual(updated["modLibrary"]["groups"][0]["mods"], ["22222222"])


if __name__ == "__main__":
    unittest.main()
