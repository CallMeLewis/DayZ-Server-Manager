import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def run_cli(*args: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "dayz_manager.cli", *args],
        input=input_text,
        capture_output=True,
        text=True,
        check=True,
    )


class CliTests(unittest.TestCase):
    def test_windows_configured_mods_output_separates_entries_with_blank_lines(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        temp_dir = Path(tempfile.mkdtemp())
        doc_folder = temp_dir / "DayZ_Server"
        config_path = doc_folder / "server-manager.config.json"
        doc_folder.mkdir(parents=True, exist_ok=True)
        config_path.write_text(
            json.dumps(
                {
                    "mods": [
                        {"workshopId": "11111111", "name": "CF", "url": "https://example.invalid/cf"},
                        {"workshopId": "22222222", "name": "Dabs", "url": "https://example.invalid/dabs"},
                    ]
                }
            ),
            encoding="utf-8",
        )

        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                f"$docFolder = '{doc_folder}'; "
                f"$rootConfigPath = '{config_path}'; "
                "Show-ConfiguredMods 'mods' 6>&1"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("11111111)\n    https://example.invalid/cf\n\n", result.stdout)
        self.assertIn("22222222)\n    https://example.invalid/dabs\n\n", result.stdout)

    def test_windows_config_path_helper_prefers_documents_location(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                "Get-WindowsRootConfigPath"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        stdout = result.stdout.strip().replace("\\", "/")
        self.assertIn("DayZ_Server", stdout)
        self.assertTrue(stdout.endswith("server-manager.config.json"))

    def test_windows_legacy_config_helper_returns_script_local_path(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                "Get-WindowsLegacyRootConfigPath"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        stdout = result.stdout.strip().replace("/", "\\")
        self.assertTrue(stdout.lower().endswith(r"windows\server-manager.config.json"))

    def test_windows_startup_migrates_legacy_config_to_canonical_path(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        temp_dir = Path(tempfile.mkdtemp())
        canonical_path = temp_dir / "Documents" / "DayZ_Server" / "server-manager.config.json"
        legacy_path = temp_dir / "windows" / "server-manager.config.json"
        canonical_path.parent.mkdir(parents=True, exist_ok=True)
        legacy_path.parent.mkdir(parents=True, exist_ok=True)

        payload = {
            "launchParameters": "-config=serverDZ.cfg -port=2302",
            "mods": [{"workshopId": "11111111", "name": "CF"}],
            "serverMods": [{"workshopId": "22222222", "name": "Dabs"}],
        }
        legacy_path.write_text(json.dumps(payload), encoding="utf-8")

        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                f"Invoke-WindowsRootConfigMigration -CanonicalPath '{canonical_path}' -LegacyPath '{legacy_path}'"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(canonical_path.exists())
        self.assertEqual(json.loads(canonical_path.read_text(encoding="utf-8")), payload)
        self.assertTrue((legacy_path.parent / "server-manager.config.json.legacy.bak").exists())
        self.assertIn("migrated", result.stdout.lower())

    def test_windows_startup_keeps_legacy_config_when_migration_copy_fails(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        temp_dir = Path(tempfile.mkdtemp())
        legacy_path = temp_dir / "windows" / "server-manager.config.json"
        legacy_path.parent.mkdir(parents=True, exist_ok=True)
        canonical_path = temp_dir / "Documents" / "DayZ_Server" / "bad|name.json"

        payload = {
            "launchParameters": "-config=serverDZ.cfg -port=2302",
            "mods": [{"workshopId": "11111111", "name": "CF"}],
        }
        legacy_path.write_text(json.dumps(payload), encoding="utf-8")

        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                "$ErrorActionPreference = 'Stop'; "
                f"Invoke-WindowsRootConfigMigration -CanonicalPath '{canonical_path}' -LegacyPath '{legacy_path}'"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(legacy_path.exists())
        self.assertEqual(json.loads(legacy_path.read_text(encoding="utf-8")), payload)
        self.assertFalse((legacy_path.parent / "server-manager.config.json.legacy.bak").exists())

    def test_linux_mod_list_output_separates_entries_with_blank_lines(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        temp_dir = Path(tempfile.mkdtemp())
        config_path = temp_dir / "server-manager.config.json"
        config_path.write_text(
            json.dumps(
                {
                    "modLibrary": {
                        "workshopIds": [
                            {"workshopId": "11111111", "name": "CF", "url": "https://example.invalid/cf"},
                            {"workshopId": "22222222", "name": "Dabs", "url": "https://example.invalid/dabs"},
                        ],
                        "serverWorkshopIds": [],
                        "groups": [],
                    }
                }
            ),
            encoding="utf-8",
        )

        command = [
            "bash",
            "-lc",
            (
                f"source '{script_path}' && "
                f"linux_manager_list_mods_with_heading 'Client mods' '{config_path}' 11111111 22222222"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("11111111)\n   https://example.invalid/cf\n\n", result.stdout)
        self.assertIn("22222222)\n   https://example.invalid/dabs\n\n", result.stdout)

    def test_linux_config_path_helper_returns_xdg_location(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        temp_dir = Path(tempfile.mkdtemp())
        xdg_config_home = temp_dir / "xdg"

        command = [
            "bash",
            "-lc",
            (
                f"export XDG_CONFIG_HOME='{xdg_config_home}'; "
                f"source '{script_path}' && "
                "linux_manager_get_config_path"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        stdout = result.stdout.strip().replace("\\", "/")
        expected = xdg_config_home / "dayz-server-manager" / "server-manager.config.json"
        self.assertEqual(stdout, str(expected).replace("\\", "/"))

    def test_windows_python_prereq_helper_returns_winget_command(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                "$env:DAYZ_SERVER_MANAGER_PYTHON = 'missing-python-for-test'; "
                "Get-HybridPythonInstallCommand"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("winget install -e --id Python.Python.3.12", result.stdout)

    def test_linux_python_prereq_helper_returns_install_command(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        command = [
            "bash",
            "-lc",
            (
                f"source '{script_path}' && "
                "PATH='' linux_manager_get_python_install_command"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("sudo apt update && sudo apt install -y python3", result.stdout)

    def test_windows_python_prereq_check_fails_when_python_missing(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$script:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                "$env:DAYZ_SERVER_MANAGER_PYTHON = 'missing-python-for-test'; "
                "if (Test-HybridPythonPrerequisite) { 'OK' } else { 'MISSING' }"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("MISSING", result.stdout)
        self.assertIn("install -e --id Python.Python.3.12", result.stdout)

    def test_linux_python_prereq_check_fails_when_python_missing(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        command = [
            "bash",
            "-lc",
            (
                f"source '{script_path}' && "
                "PATH='' DAYZ_SERVER_MANAGER_PYTHON='missing-python-for-test' "
                "linux_manager_check_python_prerequisite >/tmp/linux-python-prereq.out 2>&1; "
                "status=$?; cat /tmp/linux-python-prereq.out; printf '\\nSTATUS=%s\\n' \"$status\""
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=1", result.stdout)
        self.assertIn("sudo apt update && sudo apt install -y python3", result.stdout)

    def test_export_config_json_cli_emits_windows_envelope_without_secrets(self) -> None:
        temp_dir = Path(tempfile.mkdtemp())
        config_path = temp_dir / "server-manager.config.json"
        config_path.write_text(
            json.dumps(
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
                }
            ),
            encoding="utf-8",
        )

        result = run_cli(
            "export-config-json",
            "--platform",
            "windows",
            "--config",
            str(config_path),
        )

        envelope = json.loads(result.stdout)
        self.assertEqual(envelope["formatVersion"], 1)
        self.assertEqual(envelope["platform"], "windows")
        self.assertEqual(envelope["config"]["activeGroup"], "Core")
        self.assertNotIn("steamAccount", envelope["config"])
        self.assertNotIn("runtime", envelope["config"])

    def test_import_config_json_cli_accepts_valid_windows_payload(self) -> None:
        payload = {
            "formatVersion": 1,
            "platform": "windows",
            "config": {
                "launchParameters": '-config=serverDZ.cfg "-mod=11111111;"',
                "mods": [{"workshopId": "11111111", "name": "CF"}],
                "modGroups": [
                    {
                        "name": "Core",
                        "mods": ["11111111"],
                        "serverMods": ["33333333"],
                    }
                ],
                "activeGroup": "Core",
                "steamAccount": {"username": "secret-user"},
            },
        }

        result = run_cli("import-config-json", input_text=json.dumps(payload))

        config = json.loads(result.stdout)
        self.assertEqual(config["activeGroup"], "Core")
        self.assertNotIn("steamAccount", config)
        self.assertEqual(config["modGroups"][0]["name"], "Core")

    def test_import_config_json_cli_accepts_valid_linux_payload(self) -> None:
        payload = {
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

        result = run_cli("import-config-json", input_text=json.dumps(payload))

        config = json.loads(result.stdout)
        self.assertEqual(config["modLibrary"]["activeGroup"], "raid")
        self.assertNotIn("steamAccount", config)
        self.assertEqual(config["serverRoot"], "/srv/dayz/server")

    def test_import_config_json_cli_rejects_missing_required_structures(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "dayz_manager.cli",
                "import-config-json",
            ],
            input=json.dumps({"formatVersion": 1, "platform": "windows"}),
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("export envelope config must be a JSON object", result.stderr)

    def test_windows_export_writes_expected_json(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        temp_dir = Path(tempfile.mkdtemp())
        doc_folder = temp_dir / "DayZ_Server"
        doc_folder.mkdir(parents=True, exist_ok=True)
        config_path = doc_folder / "server-manager.config.json"
        export_path = temp_dir / "windows-export.json"
        config_path.write_text(
            json.dumps(
                {
                    "launchParameters": '-config=serverDZ.cfg "-mod=11111111;"',
                    "mods": [{"workshopId": "11111111", "name": "CF"}],
                    "serverMods": [{"workshopId": "33333333", "name": "Server Pack"}],
                    "activeGroup": "Core",
                    "modGroups": [{"name": "Core", "mods": ["11111111"], "serverMods": ["33333333"]}],
                    "runtime": {"pid": 999},
                }
            ),
            encoding="utf-8",
        )

        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$global:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                f"$docFolder = '{doc_folder}'; "
                f"$rootConfigPath = '{config_path}'; "
                f"if (Export-ConfigTransferToPath -DestinationPath '{export_path}' -ConfigPath '{config_path}') {{ 'STATUS=1' }} else {{ 'STATUS=0' }}"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=1", result.stdout)
        envelope = json.loads(export_path.read_text(encoding="utf-8"))
        self.assertEqual(envelope["formatVersion"], 1)
        self.assertEqual(envelope["platform"], "windows")
        self.assertEqual(envelope["config"]["activeGroup"], "Core")
        self.assertNotIn("runtime", envelope["config"])

    def test_windows_import_replaces_canonical_config(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        temp_dir = Path(tempfile.mkdtemp())
        doc_folder = temp_dir / "DayZ_Server"
        doc_folder.mkdir(parents=True, exist_ok=True)
        config_path = doc_folder / "server-manager.config.json"
        state_path = doc_folder / "server-manager.state.json"
        source_path = temp_dir / "windows-import.json"
        server_folder = temp_dir / "server"
        server_folder.mkdir(parents=True, exist_ok=True)
        server_cfg_path = server_folder / "serverDZ.cfg"
        server_cfg_path.write_text('template="empty.chernarusplus";\n', encoding="utf-8")
        config_path.write_text(json.dumps({"launchParameters": "-config=serverDZ.cfg"}), encoding="utf-8")

        payload = {
            "formatVersion": 1,
            "platform": "windows",
            "config": {
                "serverFolder": str(server_folder),
                "launchParameters": '-config=serverDZ.cfg "-mod=99999999;" "-serverMod=88888888;"',
                "mods": [{"workshopId": "11111111", "name": "CF"}],
                "serverMods": [{"workshopId": "33333333", "name": "Server Pack"}],
                "activeGroup": "Core",
                "modGroups": [
                    {
                        "name": "Core",
                        "mods": ["11111111"],
                        "serverMods": ["33333333"],
                        "mission": "empty.deerisle",
                    }
                ],
            },
        }
        source_path.write_text(json.dumps(payload), encoding="utf-8")

        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$global:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                f"$docFolder = '{doc_folder}'; "
                f"$rootConfigPath = '{config_path}'; "
                f"$stateConfigPath = '{state_path}'; "
                f"if (Import-ConfigTransferFromPath -SourcePath '{source_path}' -ConfigPath '{config_path}') {{ 'STATUS=1' }} else {{ 'STATUS=0' }}"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=1", result.stdout)
        imported = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(imported["activeGroup"], "Core")
        self.assertIn("-mod=11111111;", imported["launchParameters"])
        self.assertIn("-serverMod=33333333;", imported["launchParameters"])
        self.assertTrue((doc_folder / "server-manager.config.json.import.bak").exists())
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertEqual(state["generatedLaunch"]["mod"], "11111111;")
        self.assertEqual(state["generatedLaunch"]["serverMod"], "33333333;")
        self.assertIn('template="empty.deerisle"', server_cfg_path.read_text(encoding="utf-8"))

    def test_windows_import_refuses_invalid_payload_without_overwriting_canonical_config(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "windows" / "Server_manager.ps1"
        temp_dir = Path(tempfile.mkdtemp())
        doc_folder = temp_dir / "DayZ_Server"
        doc_folder.mkdir(parents=True, exist_ok=True)
        config_path = doc_folder / "server-manager.config.json"
        source_path = temp_dir / "windows-invalid-import.json"
        original = {"launchParameters": '-config=serverDZ.cfg "-mod=11111111;"'}
        config_path.write_text(json.dumps(original), encoding="utf-8")
        source_path.write_text(json.dumps({"formatVersion": 1, "platform": "windows"}), encoding="utf-8")

        command = [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$global:ServerManagerSkipAutoRun = $true; "
                f". '{script_path}'; "
                f"$docFolder = '{doc_folder}'; "
                f"$rootConfigPath = '{config_path}'; "
                f"if (Import-ConfigTransferFromPath -SourcePath '{source_path}' -ConfigPath '{config_path}') {{ 'STATUS=1' }} else {{ 'STATUS=0' }}"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=0", result.stdout)
        self.assertEqual(json.loads(config_path.read_text(encoding="utf-8")), original)
        self.assertFalse((doc_folder / "server-manager.config.json.import.bak").exists())

    def test_linux_export_writes_expected_json(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        temp_dir = Path(tempfile.mkdtemp())
        config_path = temp_dir / "server-manager.config.json"
        export_path = temp_dir / "linux-export.json"
        config_path.write_text(
            json.dumps(
                {
                    "serverRoot": "/srv/dayz/server",
                    "steamAccount": {"username": "secret-user", "saveMode": "saved"},
                    "modLibrary": {
                        "activeGroup": "raid",
                        "workshopIds": ["11111111"],
                        "serverWorkshopIds": ["33333333"],
                        "groups": [{"name": "raid", "mods": ["11111111"], "serverMods": ["33333333"]}],
                    },
                }
            ),
            encoding="utf-8",
        )

        command = [
            "bash",
            "-lc",
            (
                f"source '{script_path}' && "
                f"linux_manager_export_config_transfer_to_path '{config_path}' '{export_path}' && "
                "printf 'STATUS=1\\n'"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=1", result.stdout)
        envelope = json.loads(export_path.read_text(encoding="utf-8"))
        self.assertEqual(envelope["formatVersion"], 1)
        self.assertEqual(envelope["platform"], "linux")
        self.assertEqual(envelope["config"]["modLibrary"]["activeGroup"], "raid")
        self.assertNotIn("steamAccount", envelope["config"])

    def test_linux_import_replaces_canonical_config(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        temp_dir = Path(tempfile.mkdtemp())
        config_path = temp_dir / "server-manager.config.json"
        source_path = temp_dir / "linux-import.json"
        server_root = temp_dir / "server"
        mpmissions_dir = server_root / "mpmissions"
        mpmissions_dir.mkdir(parents=True, exist_ok=True)
        (mpmissions_dir / "empty.deerisle").mkdir(exist_ok=True)
        server_cfg_path = server_root / "serverDZ.cfg"
        server_cfg_path.write_text('template="empty.chernarusplus";\n', encoding="utf-8")
        config_path.write_text(json.dumps({"serverRoot": str(server_root), "modLibrary": {}}), encoding="utf-8")

        payload = {
            "formatVersion": 1,
            "platform": "linux",
            "config": {
                "serverRoot": str(server_root).replace("\\", "/"),
                "modLibrary": {
                    "activeGroup": "raid",
                    "workshopIds": ["11111111"],
                    "serverWorkshopIds": ["33333333"],
                    "groups": [
                        {
                            "name": "raid",
                            "mods": ["11111111"],
                            "serverMods": ["33333333"],
                            "mission": "empty.deerisle",
                        }
                    ],
                },
            },
        }
        source_path.write_text(json.dumps(payload), encoding="utf-8")

        command = [
            "bash",
            "-lc",
            (
                f"source '{script_path}' && "
                f"linux_manager_import_config_transfer_from_path '{config_path}' '{source_path}' && "
                "printf 'STATUS=1\\n'"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=1", result.stdout)
        imported = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(imported["modLibrary"]["activeGroup"], "raid")
        self.assertTrue((temp_dir / "server-manager.config.json.import.bak").exists())
        self.assertIn('template="empty.deerisle"', server_cfg_path.read_text(encoding="utf-8"))

    def test_linux_import_refuses_invalid_payload_without_overwriting_canonical_config(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "linux" / "lib" / "linux_manager.sh"
        temp_dir = Path(tempfile.mkdtemp())
        config_path = temp_dir / "server-manager.config.json"
        source_path = temp_dir / "linux-invalid-import.json"
        original = {"serverRoot": "/srv/dayz/server", "modLibrary": {"activeGroup": ""}}
        config_path.write_text(json.dumps(original), encoding="utf-8")
        source_path.write_text(json.dumps({"formatVersion": 1, "platform": "linux"}), encoding="utf-8")

        command = [
            "bash",
            "-lc",
            (
                f"source '{script_path}' && "
                f"if linux_manager_import_config_transfer_from_path '{config_path}' '{source_path}'; then printf 'STATUS=1\\n'; else printf 'STATUS=0\\n'; fi"
            ),
        ]

        result = subprocess.run(command, capture_output=True, text=True, check=True)

        self.assertIn("STATUS=0", result.stdout)
        self.assertEqual(json.loads(config_path.read_text(encoding="utf-8")), original)
        self.assertFalse((temp_dir / "server-manager.config.json.import.bak").exists())

    def test_mutate_inventory_json_cli_moves_windows_item_between_lists(self) -> None:
        config = {
            "mods": [
                {"workshopId": "11111111", "name": "CF", "url": "https://example.invalid/cf"},
            ],
            "serverMods": [
                {"workshopId": "33333333", "name": "Server Pack"},
            ],
        }

        result = run_cli(
            "mutate-inventory-json",
            "--platform",
            "windows",
            "--operation",
            "move-workshop-item",
            "--target-kind",
            "serverMods",
            "--workshop-id",
            "11111111",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["mods"], [])
        self.assertEqual([item["workshopId"] for item in updated["serverMods"]], ["33333333", "11111111"])

    def test_mutate_inventory_json_cli_adds_linux_item_to_active_group(self) -> None:
        config = {
            "modLibrary": {
                "activeGroup": "raid",
                "workshopIds": [],
                "serverWorkshopIds": [
                    {"workshopId": "11111111", "name": "CF"},
                ],
                "groups": [
                    {"name": "raid", "mods": [], "serverMods": ["11111111"]},
                ],
            }
        }

        result = run_cli(
            "mutate-inventory-json",
            "--platform",
            "linux",
            "--operation",
            "add-workshop-item",
            "--target-kind",
            "mods",
            "--workshop-id",
            "11111111",
            "--item-name",
            "CF",
            "--item-url",
            "https://example.invalid/cf",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["modLibrary"]["groups"][0]["mods"], ["11111111"])
        self.assertEqual(updated["modLibrary"]["groups"][0]["serverMods"], [])

    def test_mutate_groups_json_cli_renames_windows_group(self) -> None:
        config = {
            "activeGroup": "Core",
            "modGroups": [
                {
                    "name": "Core",
                    "mods": ["11111111"],
                    "serverMods": ["33333333"],
                }
            ],
        }

        result = run_cli(
            "mutate-groups-json",
            "--platform",
            "windows",
            "--operation",
            "rename",
            "--old-name",
            "Core",
            "--new-name",
            "Main Ops",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["activeGroup"], "Main Ops")
        self.assertEqual(updated["modGroups"][0]["name"], "Main Ops")

    def test_mutate_groups_json_cli_clears_windows_active_group(self) -> None:
        config = {
            "activeGroup": "Core",
            "modGroups": [
                {"name": "Core", "mods": ["11111111"], "serverMods": []},
            ],
        }

        result = run_cli(
            "mutate-groups-json",
            "--platform",
            "windows",
            "--operation",
            "set-active",
            "--group-name",
            "",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["activeGroup"], "")

    def test_mutate_groups_json_cli_deletes_linux_group(self) -> None:
        config = {
            "modLibrary": {
                "activeGroup": "raid",
                "groups": [
                    {"name": "raid", "mods": [], "serverMods": []},
                    {"name": "backup", "mods": [], "serverMods": []},
                ],
            }
        }

        result = run_cli(
            "mutate-groups-json",
            "--platform",
            "linux",
            "--operation",
            "delete",
            "--group-name",
            "raid",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["modLibrary"]["activeGroup"], "")
        self.assertEqual([group["name"] for group in updated["modLibrary"]["groups"]], ["backup"])

    def test_mutate_groups_json_cli_rejects_invalid_windows_delete(self) -> None:
        config = {
            "activeGroup": "Core",
            "modGroups": [
                {"name": "Core", "mods": [], "serverMods": []},
            ],
        }

        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "dayz_manager.cli",
                "mutate-groups-json",
                "--platform",
                "windows",
                "--operation",
                "delete",
                "--group-name",
                "Core",
            ],
            input=json.dumps(config),
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)

    def test_mutate_groups_json_cli_upserts_windows_group(self) -> None:
        config = {
            "activeGroup": "Core",
            "modGroups": [
                {"name": "Core", "mods": ["11111111"], "serverMods": []},
            ],
        }

        result = run_cli(
            "mutate-groups-json",
            "--platform",
            "windows",
            "--operation",
            "upsert",
            "--group-name",
            "Raid",
            "--client-ids-json",
            "[\"22222222\"]",
            "--server-ids-json",
            "[\"33333333\"]",
            "--mission-name",
            "empty.chernarusplus",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["modGroups"][-1]["name"], "Raid")
        self.assertEqual(updated["modGroups"][-1]["mods"], ["22222222"])

    def test_mutate_groups_json_cli_upserts_linux_group(self) -> None:
        config = {
            "modLibrary": {
                "activeGroup": "",
                "groups": [],
            }
        }

        result = run_cli(
            "mutate-groups-json",
            "--platform",
            "linux",
            "--operation",
            "upsert",
            "--group-name",
            "raid",
            "--client-ids-json",
            "[\"11111111\",\"11111111\"]",
            "--server-ids-json",
            "[\"33333333\"]",
            "--mission-name",
            "empty.60.deerisle",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual(updated["modLibrary"]["groups"][0]["mods"], ["11111111"])
        self.assertEqual(updated["modLibrary"]["groups"][0]["mission"], "empty.60.deerisle")

    def test_group_detail_json_cli_returns_windows_resolved_and_dangling_items(self) -> None:
        config = {
            "mods": [
                {"workshopId": "11111111", "name": "CF"},
            ],
            "serverMods": [
                {"workshopId": "33333333", "name": "Server Pack"},
            ],
            "modGroups": [
                {
                    "name": "Raid",
                    "mods": ["11111111", "22222222"],
                    "serverMods": ["33333333", "44444444"],
                    "mission": "empty.chernarusplus",
                }
            ],
        }

        result = run_cli(
            "group-detail-json",
            "--platform",
            "windows",
            "--group-name",
            "Raid",
            input_text=json.dumps(config),
        )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["resolvedMods"][0]["name"], "CF")
        self.assertEqual(summary["danglingMods"], ["22222222"])
        self.assertEqual(summary["danglingServerMods"], ["44444444"])

    def test_workshop_usage_json_cli_returns_linux_usage(self) -> None:
        config = {
            "modLibrary": {
                "activeGroup": "raid",
                "groups": [
                    {"name": "raid", "mods": ["11111111"], "serverMods": []},
                    {"name": "backup", "mods": ["11111111"], "serverMods": ["33333333"]},
                ],
            }
        }

        result = run_cli(
            "workshop-usage-json",
            "--platform",
            "linux",
            "--workshop-id",
            "11111111",
            "--kind",
            "mods",
            input_text=json.dumps(config),
        )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["referencingGroups"], ["raid", "backup"])
        self.assertEqual(summary["activeGroupAffected"], True)

    def test_remove_workshop_id_json_cli_updates_windows_config(self) -> None:
        config = {
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
        }

        result = run_cli(
            "remove-workshop-id-json",
            "--platform",
            "windows",
            "--workshop-id",
            "11111111",
            input_text=json.dumps(config),
        )

        updated = json.loads(result.stdout)
        self.assertEqual([item["workshopId"] for item in updated["mods"]], ["22222222"])
        self.assertEqual(updated["modGroups"][0]["mods"], ["22222222"])

    def test_active_ids_cli_returns_group_filtered_mods_for_linux(self) -> None:
        config = {
            "modLibrary": {
                "activeGroup": "raid",
                "workshopIds": ["11111111", "22222222"],
                "serverWorkshopIds": ["33333333", "44444444"],
                "groups": [
                    {
                        "name": "raid",
                        "mods": ["22222222"],
                        "serverMods": ["44444444"],
                    }
                ],
            }
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "active-ids",
                "--platform",
                "linux",
                "--config",
                str(config_path),
                "--kind",
                "mods",
            )

        self.assertEqual(json.loads(result.stdout), ["22222222"])

    def test_active_ids_cli_returns_group_filtered_server_mods_for_linux(self) -> None:
        config = {
            "modLibrary": {
                "activeGroup": "raid",
                "workshopIds": ["11111111", "22222222"],
                "serverWorkshopIds": ["33333333", "44444444"],
                "groups": [
                    {
                        "name": "raid",
                        "mods": ["22222222"],
                        "serverMods": ["44444444"],
                    }
                ],
            }
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "active-ids",
                "--platform",
                "linux",
                "--config",
                str(config_path),
                "--kind",
                "serverMods",
            )

        self.assertEqual(json.loads(result.stdout), ["44444444"])

    def test_active_ids_json_cli_returns_group_filtered_mods_for_windows(self) -> None:
        config = {
            "activeGroup": "core",
            "mods": [
                {"workshopId": "11111111", "name": "CF"},
                {"workshopId": "22222222", "name": "Dabs"},
            ],
            "serverMods": [
                {"workshopId": "33333333", "name": "Server Pack"},
            ],
            "modGroups": [
                {
                    "name": "core",
                    "mods": ["22222222"],
                    "serverMods": ["33333333"],
                }
            ],
        }

        result = run_cli(
            "active-ids-json",
            "--platform",
            "windows",
            "--kind",
            "mods",
            "--strict-active-group",
            input_text=json.dumps(config),
        )

        self.assertEqual(json.loads(result.stdout), ["22222222"])

    def test_active_ids_json_cli_returns_empty_when_strict_active_group_is_missing(self) -> None:
        config = {
            "activeGroup": "missing",
            "mods": [
                {"workshopId": "11111111", "name": "CF"},
            ],
            "serverMods": [
                {"workshopId": "33333333", "name": "Server Pack"},
            ],
            "modGroups": [
                {
                    "name": "core",
                    "mods": ["22222222"],
                    "serverMods": ["33333333"],
                }
            ],
        }

        result = run_cli(
            "active-ids-json",
            "--platform",
            "windows",
            "--kind",
            "serverMods",
            "--strict-active-group",
            input_text=json.dumps(config),
        )

        self.assertEqual(json.loads(result.stdout), [])

    def test_group_status_cli_returns_linux_summary(self) -> None:
        config = {
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
            }
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "group-status",
                "--platform",
                "linux",
                "--config",
                str(config_path),
            )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["groupState"], "present")
        self.assertEqual(summary["danglingCount"], 2)
        self.assertEqual(summary["missionName"], "empty.60.deerisle")

    def test_group_status_json_cli_returns_windows_missing_group_summary(self) -> None:
        config = {
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

        result = run_cli(
            "group-status-json",
            "--platform",
            "windows",
            input_text=json.dumps(config),
        )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["activeGroup"], "missing")
        self.assertEqual(summary["groupState"], "missing")

    def test_config_summary_cli_returns_linux_summary(self) -> None:
        config = {
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
                "serverWorkshopIds": ["33333333"],
                "groups": [
                    {
                        "name": "raid",
                        "mods": ["11111111"],
                        "serverMods": ["33333333"],
                        "mission": "empty.60.deerisle",
                    }
                ],
            },
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "config-summary",
                "--platform",
                "linux",
                "--config",
                str(config_path),
            )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["serverRoot"], "/srv/dayz/custom")
        self.assertEqual(summary["autostart"], False)
        self.assertEqual(summary["serviceUser"], "customuser")
        self.assertEqual(summary["serviceName"], "custom-dayz")
        self.assertEqual(summary["steamUsername"], "example-user")

    def test_group_catalog_cli_returns_linux_rows_and_library_ids(self) -> None:
        config = {
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

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "group-catalog",
                "--platform",
                "linux",
                "--config",
                str(config_path),
            )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["activeGroup"], "raid")
        self.assertEqual(summary["libraryClientIds"], ["11111111", "22222222"])
        self.assertEqual(summary["groups"][0]["name"], "raid")
        self.assertEqual(summary["groups"][0]["modCount"], 2)
        self.assertEqual(summary["groups"][0]["missionName"], "empty.60.deerisle")

    def test_group_catalog_json_cli_returns_windows_rows(self) -> None:
        config = {
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

        result = run_cli(
            "group-catalog-json",
            "--platform",
            "windows",
            input_text=json.dumps(config),
        )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["activeGroup"], "core")
        self.assertEqual(summary["libraryServerIds"], ["33333333"])
        self.assertEqual(summary["groups"][0]["name"], "core")
        self.assertEqual(summary["groups"][0]["serverModCount"], 1)

    def test_mod_summary_cli_returns_linux_group_membership_lists(self) -> None:
        config = {
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

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "mod-summary",
                "--platform",
                "linux",
                "--config",
                str(config_path),
            )

        summary = json.loads(result.stdout)
        self.assertEqual(summary["activeGroup"], "raid")
        self.assertEqual(summary["libraryClientIds"], ["11111111", "22222222"])
        self.assertEqual(summary["groups"][0]["mods"], ["11111111", "22222222"])
        self.assertEqual(summary["groups"][0]["serverMods"], ["33333333"])
        self.assertEqual(summary["groups"][0]["missionName"], "empty.60.deerisle")

    def test_configured_ids_json_cli_returns_valid_windows_client_ids(self) -> None:
        config = {
            "mods": [
                {"workshopId": "11111111", "name": "CF"},
                {"workshopId": "bad-id", "name": "Broken"},
                {"workshopId": "11111111", "name": "Duplicate"},
                "22222222",
            ],
            "serverMods": [],
        }

        result = run_cli(
            "configured-ids-json",
            "--platform",
            "windows",
            "--kind",
            "mods",
            input_text=json.dumps(config),
        )

        self.assertEqual(json.loads(result.stdout), ["11111111", "22222222"])

    def test_configured_ids_json_cli_returns_valid_windows_server_ids(self) -> None:
        config = {
            "mods": [],
            "serverMods": [
                {"workshopId": "33333333", "name": "Server Pack"},
                "33333333",
                "bad-server-id",
            ],
        }

        result = run_cli(
            "configured-ids-json",
            "--platform",
            "windows",
            "--kind",
            "serverMods",
            input_text=json.dumps(config),
        )

        self.assertEqual(json.loads(result.stdout), ["33333333"])

    def test_configured_ids_cli_returns_valid_linux_client_ids(self) -> None:
        config = {
            "modLibrary": {
                "workshopIds": [
                    {"workshopId": "11111111", "name": "CF"},
                    {"workshopId": "bad-id", "name": "Broken"},
                    {"workshopId": "11111111", "name": "Duplicate"},
                    "22222222",
                ],
                "serverWorkshopIds": [],
            }
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "configured-ids",
                "--platform",
                "linux",
                "--config",
                str(config_path),
                "--kind",
                "mods",
            )

        self.assertEqual(json.loads(result.stdout), ["11111111", "22222222"])

    def test_configured_ids_cli_returns_valid_linux_server_ids(self) -> None:
        config = {
            "modLibrary": {
                "workshopIds": [],
                "serverWorkshopIds": [
                    {"workshopId": "33333333", "name": "Server Pack"},
                    "33333333",
                    "bad-server-id",
                ],
            }
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "server-manager.config.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")

            result = run_cli(
                "configured-ids",
                "--platform",
                "linux",
                "--config",
                str(config_path),
                "--kind",
                "serverMods",
            )

        self.assertEqual(json.loads(result.stdout), ["33333333"])

    def test_linux_group_status_summary_falls_back_when_python_output_is_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config_path = temp_path / "server-manager.config.json"
            fake_python_path = temp_path / "fake-python.sh"

            config_path.write_text(
                json.dumps(
                    {
                        "modLibrary": {
                            "activeGroup": "raid",
                            "workshopIds": ["11111111"],
                            "serverWorkshopIds": ["33333333"],
                            "groups": [
                                {
                                    "name": "raid",
                                    "mods": ["11111111"],
                                    "serverMods": ["33333333"],
                                    "mission": "empty.60.deerisle",
                                }
                            ],
                        }
                    }
                ),
                encoding="utf-8",
            )
            fake_python_path.write_text("#!/usr/bin/env bash\nprintf '{bad json'\n", encoding="utf-8")
            os.chmod(fake_python_path, 0o755)

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    f"source './linux/lib/linux_manager.sh'; linux_manager_get_group_status_summary_tsv '{config_path.as_posix()}'",
                ],
                capture_output=True,
                text=True,
                check=True,
                env={**os.environ, "DAYZ_SERVER_MANAGER_PYTHON": fake_python_path.as_posix()},
            )

        self.assertEqual(result.stdout.strip(), "raid\tpresent\t1\t1\t0\tempty.60.deerisle")

    def test_linux_inventory_mutation_falls_back_when_python_output_is_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config_path = temp_path / "server-manager.config.json"
            fake_python_path = temp_path / "fake-python.sh"

            config_path.write_text(
                json.dumps(
                    {
                        "modLibrary": {
                            "activeGroup": "",
                            "workshopIds": [],
                            "serverWorkshopIds": [],
                            "groups": [],
                        }
                    }
                ),
                encoding="utf-8",
            )
            fake_python_path.write_text("#!/usr/bin/env bash\nprintf 'not-json\\n'\n", encoding="utf-8")
            os.chmod(fake_python_path, 0o755)

            subprocess.run(
                [
                    "bash",
                    "-lc",
                    "source './linux/lib/linux_manager.sh'; "
                    f"linux_manager_add_mod_to_active_group '{config_path.as_posix()}' 11111111 client TestMod https://example.invalid/mod",
                ],
                capture_output=True,
                text=True,
                check=True,
                env={**os.environ, "DAYZ_SERVER_MANAGER_PYTHON": fake_python_path.as_posix()},
            )

            updated = json.loads(config_path.read_text(encoding="utf-8"))

        self.assertEqual(updated["modLibrary"]["workshopIds"][0]["workshopId"], "11111111")
        self.assertEqual(updated["modLibrary"]["serverWorkshopIds"], [])
        self.assertEqual(updated["modLibrary"]["groups"], [])


class CheckUpdateCliTests(unittest.TestCase):
    def test_check_update_subcommand_returns_json_payload(self) -> None:
        env = os.environ.copy()
        env["PYTHONPATH"] = str(Path(__file__).resolve().parents[1])
        script = "\n".join([
            "import json, sys",
            "from unittest.mock import patch",
            "import dayz_manager.cli as cli",
            "with patch('dayz_manager.update_check.fetch_latest_release', return_value={'tag': 'v9.9.9', 'url': 'https://example.invalid/v9.9.9'}):",
            "    sys.argv = ['cli', 'check-update', '--current-version', '1.1.0']",
            "    cli.main()",
        ])
        result = subprocess.run(
            [sys.executable, "-c", script],
            capture_output=True,
            text=True,
            env=env,
            check=True,
        )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["currentVersion"], "1.1.0")
        self.assertEqual(payload["latestVersion"], "9.9.9")
        self.assertTrue(payload["updateAvailable"])
        self.assertIsNone(payload["error"])


class ApplyUpdateCliTests(unittest.TestCase):
    def test_apply_update_subcommand_returns_json_payload(self) -> None:
        env = os.environ.copy()
        env["PYTHONPATH"] = str(Path(__file__).resolve().parents[1])
        script = "\n".join([
            "import json, sys",
            "from unittest.mock import patch",
            "import dayz_manager.cli as cli",
            "def fake_apply_update(**kwargs):",
            "    return {'success': True, 'tag': kwargs['tag'], 'appliedFiles': 3, 'backupPath': '/tmp/b', 'error': None}",
            "with patch('dayz_manager.cli.apply_update', side_effect=fake_apply_update):",
            "    sys.argv = ['cli', 'apply-update', '--tag', 'v1.2.0', '--repo-root', '/tmp/r', '--platform', 'windows']",
            "    sys.exit(cli.main())",
        ])
        result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, env=env, check=True)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["success"])
        self.assertEqual(payload["tag"], "v1.2.0")

    def test_apply_update_subcommand_exits_non_zero_on_failure(self) -> None:
        env = os.environ.copy()
        env["PYTHONPATH"] = str(Path(__file__).resolve().parents[1])
        script = "\n".join([
            "import sys",
            "from unittest.mock import patch",
            "import dayz_manager.cli as cli",
            "def fake_apply_update(**kwargs):",
            "    return {'success': False, 'tag': kwargs['tag'], 'appliedFiles': 0, 'backupPath': None, 'error': 'boom'}",
            "with patch('dayz_manager.cli.apply_update', side_effect=fake_apply_update):",
            "    sys.argv = ['cli', 'apply-update', '--tag', 'v1.2.0', '--repo-root', '/tmp/r', '--platform', 'windows']",
            "    sys.exit(cli.main())",
        ])
        result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, env=env)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
