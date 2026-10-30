import json
import unittest
from unittest import mock

from choutesos_installer import backend, system_info
from choutesos_installer.backend import Config, Installer


def good() -> Config:
    return Config(disk="/dev/nvme0n1", filesystem="ext4", hostname="choutes-pc",
                  username="wafiq", fullname="Wafiq", password="secret", timezone="UTC")


class ConfigTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(good().validate(), [])

    def test_bad_username(self):
        for name in ["Root", "root", "1abc", "has space", "live"]:
            cfg = good(); cfg.username = name
            self.assertTrue(cfg.validate(), name)

    def test_bad_disk_and_password(self):
        cfg = good(); cfg.disk = "sda"; cfg.password = ""
        self.assertEqual(len(cfg.validate()), 2)

    def test_bad_hostname(self):
        cfg = good(); cfg.hostname = "-bad-"
        self.assertTrue(cfg.validate())


class HelperTests(unittest.TestCase):
    def test_part_path(self):
        self.assertEqual(backend.part_path("/dev/sda", 1), "/dev/sda1")
        self.assertEqual(backend.part_path("/dev/nvme0n1", 2), "/dev/nvme0n1p2")
        self.assertEqual(backend.part_path("/dev/mmcblk0", 1), "/dev/mmcblk0p1")

    def test_locale_gen(self):
        text = "#en_US.UTF-8 UTF-8\n#ms_MY.UTF-8 UTF-8\n#de_DE.UTF-8 UTF-8\n# comment\n"
        out = backend.uncomment_locales(text, ["ms_MY.UTF-8", "en_US.UTF-8"])
        self.assertIn("\nms_MY.UTF-8 UTF-8\n", "\n" + out)
        self.assertIn("en_US.UTF-8 UTF-8\n", out)
        self.assertIn("#de_DE.UTF-8 UTF-8", out)

    def test_timezones_include_kuala_lumpur(self):
        sample = "MY\t+0310+10142\tAsia/Kuala_Lumpur\tMalaysia (peninsula)\nSG\t+0117+10351\tAsia/Singapore\t\n"
        zones = system_info.parse_zone_tab(sample, {"MY": "Malaysia", "SG": "Singapore"})
        labels = {z["value"]: z["label"] for z in zones}
        self.assertEqual(labels["Asia/Kuala_Lumpur"], "Kuala Lumpur, Malaysia")
        self.assertIn("UTC", labels)

    def test_system_timezones_include_kuala_lumpur(self):
        if not backend.Path("/usr/share/zoneinfo/zone.tab").exists():
            self.skipTest("no tzdata on this machine")
        self.assertIn("Asia/Kuala_Lumpur", {z["value"] for z in system_info.list_timezones()})

    def test_set_grub(self):
        text = 'GRUB_TIMEOUT=10\n#GRUB_THEME="/path/to/gfxtheme"\nGRUB_DISTRIBUTOR="Arch"\n'
        text = backend.set_grub(text, "GRUB_TIMEOUT", "5")
        text = backend.set_grub(text, "GRUB_THEME", '"/x/theme.txt"')
        text = backend.set_grub(text, "GRUB_GFXMODE", "auto")
        self.assertIn("GRUB_TIMEOUT=5\n", text)
        self.assertIn('\nGRUB_THEME="/x/theme.txt"\n', text)
        self.assertTrue(text.endswith("GRUB_GFXMODE=auto\n"))
        self.assertNotIn("#GRUB_THEME", text)

    def test_parse_disks(self):
        sample = json.dumps({"blockdevices": [
            {"name": "/dev/sda", "path": "/dev/sda", "size": 512110190592, "model": "Samsung SSD ", "type": "disk",
             "rm": False, "tran": "sata", "mountpoints": [None], "children": [
                 {"path": "/dev/sda1", "type": "part", "mountpoints": [None]}]},
            {"path": "/dev/sdb", "size": 8000000000000, "model": "USB live", "type": "disk", "rm": True, "tran": "usb",
             "mountpoints": [None], "children": [{"path": "/dev/sdb1", "type": "part", "mountpoints": ["/run/archiso/bootmnt"]}]},
            {"path": "/dev/loop0", "size": 900000000, "type": "loop", "mountpoints": [None]},
            {"path": "/dev/sdc", "size": 1000000000, "type": "disk", "mountpoints": [None]},
        ]})
        disks = system_info.parse_disks(sample)
        self.assertEqual([d["path"] for d in disks], ["/dev/sda"])
        self.assertEqual(disks[0]["model"], "Samsung SSD")


class DryRunTests(unittest.TestCase):
    def run_install(self, uefi: bool, fs: str):
        cfg = good(); cfg.filesystem = fs; cfg.autologin = True
        events = []
        with mock.patch.object(backend.Path, "exists", return_value=uefi):
            inst = Installer(cfg, dry_run=True, progress=lambda p, s: events.append((p, s)))
            inst.uefi = uefi
            inst.run()
        return inst, events

    def flat(self, inst):
        return [" ".join(c) for c in inst.r.history]

    def test_uefi_ext4(self):
        inst, events = self.run_install(True, "ext4")
        cmds = self.flat(inst)
        self.assertTrue(any("sgdisk -n1:0:+1G" in c for c in cmds))
        self.assertTrue(any(c.startswith("mkfs.ext4 -F -L ChoutesOS /dev/nvme0n1p2") for c in cmds))
        self.assertTrue(any("rsync -aAXH" in c and "/run/archiso/airootfs/" in c for c in cmds))
        self.assertTrue(any("grub-install --target=x86_64-efi" in c for c in cmds))
        self.assertTrue(any("useradd -m -s /bin/zsh" in c and c.endswith("wafiq") for c in cmds))
        self.assertEqual(events[-1][0], 100.0)
        self.assertEqual([e[1] for e in events][0], "Preparing the disk")

    def test_bios_btrfs(self):
        inst, _ = self.run_install(False, "btrfs")
        cmds = self.flat(inst)
        self.assertTrue(any("-t1:ef02" in c for c in cmds))
        self.assertTrue(any(c.startswith("mkfs.btrfs") for c in cmds))
        self.assertTrue(any("subvol=@home" in c for c in cmds))
        self.assertTrue(any("grub-install --target=i386-pc" in c and c.endswith("/dev/nvme0n1") for c in cmds))

    def test_live_leftovers_removed(self):
        inst, _ = self.run_install(True, "ext4")
        cmds = self.flat(inst)
        self.assertTrue(any(c.endswith("userdel -rf live") for c in cmds))
        self.assertTrue(any("pacman -Rns --noconfirm pyside6 mkinitcpio-archiso" in c for c in cmds))
        self.assertTrue(any("89-choutesos-archiso-preset.hook" in c for c in cmds))

    def test_password_not_logged(self):
        logs = []
        cfg = good()
        inst = Installer(cfg, dry_run=True, log=logs.append)
        inst.run()
        self.assertFalse(any("wafiq:secret" in line for line in logs))

    def test_progress_monotonic(self):
        _, events = self.run_install(True, "ext4")
        values = [p for p, _ in events]
        self.assertEqual(values, sorted(values))


if __name__ == "__main__":
    unittest.main()
