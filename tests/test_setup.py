import json
import unittest
from unittest import mock

from choutesos_installer import backend, oobe, oobe_helper, requirements
from choutesos_installer.backend import Config, Installer

CPU_OK = "processor : 0\nflags : fpu sse sse2 pni ssse3 sse4_1 sse4_2 popcnt cx16 lahf_lm avx avx2\n"
CPU_OLD = "processor : 0\nflags : fpu sse sse2 pni\n"
MEM_8G = "MemTotal:        8000000 kB\nMemFree: 1 kB\n"
MEM_2G = "MemTotal:        2000000 kB\n"


class RequirementTests(unittest.TestCase):
    def test_cpu(self):
        self.assertEqual(requirements.check_cpu(requirements.parse_cpu_flags(CPU_OK))["status"], "ok")
        bad = requirements.check_cpu(requirements.parse_cpu_flags(CPU_OLD))
        self.assertEqual(bad["status"], "fail")
        self.assertIn("sse4_2", bad["detail"])

    def test_ram(self):
        self.assertEqual(requirements.check_ram(requirements.parse_meminfo_gib(MEM_2G))["status"], "fail")
        self.assertEqual(requirements.check_ram(requirements.parse_meminfo_gib(MEM_8G))["status"], "ok")
        self.assertEqual(requirements.check_ram(4.0)["status"], "warn")

    def test_disks_and_overall(self):
        small = [{"sizeGb": 16}]
        big = [{"sizeGb": 512}, {"sizeGb": 16}]
        self.assertEqual(requirements.check_disks(small)["status"], "fail")
        self.assertEqual(requirements.check_disks(big)["status"], "ok")
        checks = [requirements.check_architecture("x86_64"), requirements.check_ram(8)]
        self.assertTrue(requirements.can_install(checks))
        checks.append(requirements.check_architecture("aarch64"))
        self.assertFalse(requirements.can_install(checks))


class OobeTests(unittest.TestCase):
    def test_parse_wifi(self):
        text = ("*:Home\\:5G:81:WPA2\n:Cafe:55:--\n:Home\\:5G:40:WPA2\n::70:WPA2\n:Office:90:WPA2 WPA3\n")
        nets = oobe.parse_wifi(text)
        self.assertEqual([n["ssid"] for n in nets], ["Home:5G", "Office", "Cafe"])
        self.assertTrue(nets[0]["connected"])
        self.assertFalse(nets[2]["secure"])
        self.assertEqual(nets[0]["signal"], 81)

    def test_ethernet(self):
        self.assertTrue(oobe.parse_ethernet("wifi:disconnected\nethernet:connected\n"))
        self.assertFalse(oobe.parse_ethernet("ethernet:unavailable\n"))

    def test_stage_default(self):
        with mock.patch.object(oobe, "STAGE_FILE", oobe.Path("/nonexistent/stage")):
            self.assertEqual(oobe.read_stage(), "language")


class HelperTests(unittest.TestCase):
    def test_validate_account(self):
        ok = {"username": "wafiq", "password": "x", "fullname": "Wafiq", "hostname": "pc"}
        self.assertEqual(oobe_helper.validate_account(ok), [])
        for bad in ({"username": "root"}, {"username": "choutesos-setup"}, {"username": "Bad Name"}):
            self.assertTrue(oobe_helper.validate_account({**ok, **bad}))
        self.assertTrue(oobe_helper.validate_account({**ok, "password": ""}))
        self.assertTrue(oobe_helper.validate_account({**ok, "fullname": "a:b"}))

    def test_avatar_rejects_outside_paths(self):
        self.assertFalse(oobe_helper.avatar_ok("/etc/shadow"))
        self.assertFalse(oobe_helper.avatar_ok(""))

    def test_create_user_dry_run(self):
        logs = []
        h = oobe_helper.Helper(dry_run=True, log=logs.append)
        h.create_user({"username": "wafiq", "password": "secret", "fullname": "Wafiq", "hostname": "pc"})
        text = "\n".join(logs)
        self.assertIn("useradd -m -s /bin/zsh", text)
        self.assertNotIn("wafiq:secret", text)

    def test_region_rejects_bad_input(self):
        h = oobe_helper.Helper(dry_run=True, log=lambda s: None)
        with self.assertRaises(backend.InstallError):
            h.region({"locale": "en_US.UTF-8; rm -rf /", "timezone": "UTC", "keymap": "us"})
        with self.assertRaises(backend.InstallError):
            h.region({"locale": "en_US.UTF-8", "timezone": "../../etc/passwd", "keymap": "us"})

    def test_stage_names(self):
        h = oobe_helper.Helper(dry_run=True, log=lambda s: None)
        with self.assertRaises(backend.InstallError):
            h.set_stage("../../x")

    def test_finish_cleans_everything(self):
        logs = []
        h = oobe_helper.Helper(dry_run=True, log=logs.append)
        h.finish({"autologin": False})
        cmd = " ".join(" ".join(c) for c in h.r.history)
        for fragment in ("userdel -rf choutesos-setup", "/usr/share/choutesos-installer",
                         "/etc/sudoers.d/90-choutesos-setup", "/usr/lib/choutesos/oobe-helper"):
            self.assertIn(fragment, cmd)


class PacmanProgressTests(unittest.TestCase):
    SAMPLE = """Packages (3) linux-7.2.14-1  mesa-26.2.6-1  zsh-5.9.3-1

:: Proceed with installation? [Y/n]
:: Retrieving packages...
 mesa-26.2.6-1-x86_64   40.1 MiB  9.43 MiB/s 00:04
 zsh-5.9.3-1-x86_64      3.2 MiB  7.00 MiB/s 00:00
 linux-7.2.14-1-x86_64 140.0 MiB  9.00 MiB/s 00:15
(3/3) checking keys in keyring
(3/3) checking package integrity
( 1/3) upgrading mesa
( 2/3) upgrading zsh
( 3/3) upgrading linux
"""

    def test_progress_is_monotonic_and_ends_high(self):
        p = oobe_helper.PacmanProgress()
        steps = p.feed(self.SAMPLE)
        values = [v for v, _ in steps]
        self.assertEqual(values, sorted(values))
        self.assertGreater(values[-1], 90)
        self.assertLess(values[-1], 100)
        self.assertTrue(any("Installing linux" in label for _, label in steps))


class FirstBootInstallTests(unittest.TestCase):
    def run_install(self):
        cfg = Config(disk="/dev/nvme0n1", filesystem="ext4")
        with mock.patch.object(backend.Path, "exists", return_value=True):
            inst = Installer(cfg, dry_run=True)
            inst.uefi = True
            inst.run()
        return [" ".join(c) for c in inst.r.history]

    def test_no_account_is_created(self):
        cmds = self.run_install()
        self.assertFalse(any("useradd -m -s /bin/zsh" in c for c in cmds))
        self.assertTrue(any("useradd -m -k /usr/share/choutesos-setup/skel" in c for c in cmds))
        self.assertTrue(any(c.endswith("passwd -l root") for c in cmds))

    def test_config_without_account_is_valid(self):
        self.assertEqual(Config(disk="/dev/sda").validate(check_paths=False), [])


if __name__ == "__main__":
    unittest.main()
