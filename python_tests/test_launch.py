import unittest

from dayz_manager.adapters import load_linux_config
from dayz_manager.launch import (
    build_launch_string,
    build_linux_launch_args,
    get_mod_ids_from_launch_parameters,
    set_mods_in_launch_parameters,
)


class LaunchTests(unittest.TestCase):
    def test_build_launch_string_appends_trailing_semicolons(self) -> None:
        self.assertEqual(build_launch_string(["11111111", "22222222"]), "11111111;22222222;")

    def test_get_mod_ids_from_launch_parameters_reads_quoted_sections(self) -> None:
        parameters = '-config=serverDZ.cfg "-mod=11111111;22222222;" "-serverMod=33333333;"'

        self.assertEqual(get_mod_ids_from_launch_parameters(parameters, "mods"), ["11111111", "22222222"])
        self.assertEqual(get_mod_ids_from_launch_parameters(parameters, "serverMods"), ["33333333"])

    def test_set_mods_in_launch_parameters_rewrites_existing_sections(self) -> None:
        parameters = '-config=serverDZ.cfg "-mod=11111111;" "-serverMod=33333333;"'

        updated = set_mods_in_launch_parameters(parameters, "mods", ["22222222", "11111111"])
        updated = set_mods_in_launch_parameters(updated, "serverMods", ["44444444"])

        self.assertEqual(
            updated,
            '-config=serverDZ.cfg "-mod=22222222;11111111;" "-serverMod=44444444;"',
        )

    def test_build_linux_launch_args_uses_active_group_ids(self) -> None:
        config = load_linux_config(
            {
                "profilesPath": "/srv/dayz/server/profiles",
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": [
                        "11111111",
                        "22222222",
                    ],
                    "serverWorkshopIds": [
                        "33333333",
                        "44444444",
                    ],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["22222222"],
                            "serverMods": ["33333333", "44444444"],
                        }
                    ],
                },
            }
        )

        self.assertEqual(
            build_linux_launch_args(config),
            '-config=serverDZ.cfg -profiles=/srv/dayz/server/profiles -port=2302 -freezecheck -adminlog -dologs "-mod=22222222;" "-serverMod=33333333;44444444;"',
        )


if __name__ == "__main__":
    unittest.main()
