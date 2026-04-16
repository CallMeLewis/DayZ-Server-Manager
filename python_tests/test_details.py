import unittest

from dayz_manager.details import group_detail_summary, workshop_usage_summary


class DetailTests(unittest.TestCase):
    def test_windows_group_detail_reports_resolved_and_dangling_items(self) -> None:
        summary = group_detail_summary(
            "windows",
            {
                "mods": [
                    {"workshopId": "11111111", "name": "CF", "url": "https://example.invalid/cf"},
                ],
                "serverMods": [
                    {"workshopId": "33333333", "name": "Server Pack", "url": "https://example.invalid/server"},
                ],
                "modGroups": [
                    {
                        "name": "Raid",
                        "mods": ["11111111", "22222222"],
                        "serverMods": ["33333333", "44444444"],
                        "mission": "empty.chernarusplus",
                    }
                ],
            },
            "Raid",
        )

        self.assertEqual(summary["groupName"], "Raid")
        self.assertEqual(summary["missionName"], "empty.chernarusplus")
        self.assertEqual(summary["resolvedMods"][0]["name"], "CF")
        self.assertEqual(summary["resolvedServerMods"][0]["workshopId"], "33333333")
        self.assertEqual(summary["danglingMods"], ["22222222"])
        self.assertEqual(summary["danglingServerMods"], ["44444444"])

    def test_linux_workshop_usage_summary_reports_referencing_groups(self) -> None:
        summary = workshop_usage_summary(
            "linux",
            {
                "modLibrary": {
                    "activeGroup": "raid",
                    "groups": [
                        {"name": "raid", "mods": ["11111111"], "serverMods": []},
                        {"name": "backup", "mods": ["11111111"], "serverMods": ["33333333"]},
                    ]
                }
            },
            "11111111",
            "mods",
        )

        self.assertEqual(summary["referencingGroups"], ["raid", "backup"])
        self.assertEqual(summary["activeGroupAffected"], True)


if __name__ == "__main__":
    unittest.main()
