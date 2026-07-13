#!/usr/bin/env python3

import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("verify-executable-arch.py")


def elf(machine: int) -> bytes:
    data = bytearray(64)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 18, machine)
    return bytes(data)


def pe(machine: int) -> bytes:
    data = bytearray(256)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<H", data, 0x84, machine)
    return bytes(data)


def macho(cpu_type: int) -> bytes:
    data = bytearray(32)
    struct.pack_into("<II", data, 0, 0xFEEDFACF, cpu_type)
    return bytes(data)


def macho32(cpu_type: int) -> bytes:
    data = bytearray(28)
    struct.pack_into("<II", data, 0, 0xFEEDFACE, cpu_type)
    return bytes(data)


class VerifyExecutableArchTest(unittest.TestCase):
    def run_verifier(self, platform: str, executable: bytes) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile() as fixture:
            fixture.write(executable)
            fixture.flush()
            return subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--platform",
                    platform,
                    "--file",
                    fixture.name,
                ],
                capture_output=True,
                text=True,
                check=False,
            )

    def assert_rejected(
        self, result: subprocess.CompletedProcess[str], expected_error: str
    ) -> None:
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(f"error: {expected_error}", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_accepts_all_supported_platform_architectures(self) -> None:
        cases = (
            ("linux/amd64", elf(62), "format=ELF machine=62 platform=linux/amd64"),
            ("linux/arm64", elf(183), "format=ELF machine=183 platform=linux/arm64"),
            (
                "darwin/amd64",
                macho(0x01000007),
                "format=Mach-O machine=16777223 platform=darwin/amd64",
            ),
            (
                "darwin/arm64",
                macho(0x0100000C),
                "format=Mach-O machine=16777228 platform=darwin/arm64",
            ),
            ("windows/amd64", pe(0x8664), "format=PE machine=34404 platform=windows/amd64"),
            ("windows/arm64", pe(0xAA64), "format=PE machine=43620 platform=windows/arm64"),
        )

        for platform, executable, expected_output in cases:
            with self.subTest(platform=platform):
                result = self.run_verifier(platform, executable)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected_output)

    def test_rejects_architecture_mismatch(self) -> None:
        result = self.run_verifier("linux/amd64", elf(183))

        self.assert_rejected(result, "architecture mismatch")

    def test_rejects_unknown_magic(self) -> None:
        result = self.run_verifier("linux/amd64", bytes(64))

        self.assert_rejected(result, "unknown executable format")

    def test_rejects_fat_macho(self) -> None:
        result = self.run_verifier("darwin/arm64", bytes.fromhex("cafebabe") + bytes(28))

        self.assert_rejected(result, "fat Mach-O binaries are not supported")

    def test_rejects_truncated_headers(self) -> None:
        cases = (
            ("linux/amd64", b"\x7fELF\x02\x01", "truncated ELF header"),
            ("darwin/amd64", struct.pack("<I", 0xFEEDFACF), "truncated Mach-O header"),
            ("windows/amd64", b"MZ", "truncated PE DOS header"),
        )

        for platform, executable, expected_error in cases:
            with self.subTest(platform=platform):
                result = self.run_verifier(platform, executable)
                self.assert_rejected(result, expected_error)

    def test_rejects_headers_with_machine_field_but_incomplete_full_header(self) -> None:
        cases = (
            ("linux/amd64", elf(62)[:20], "truncated ELF header"),
            ("darwin/amd64", macho(0x01000007)[:8], "truncated Mach-O header"),
            ("windows/amd64", pe(0x8664)[:0x86], "truncated PE COFF header"),
        )

        for platform, executable, expected_error in cases:
            with self.subTest(platform=platform):
                result = self.run_verifier(platform, executable)
                self.assert_rejected(result, expected_error)

    def test_rejects_32_bit_headers_with_64_bit_machine(self) -> None:
        elf32 = bytearray(elf(62))
        elf32[4] = 1
        cases = (
            ("linux/amd64", bytes(elf32), "ELF binary is not 64-bit"),
            ("darwin/amd64", macho32(0x01000007), "Mach-O binary is not 64-bit"),
        )

        for platform, executable, expected_error in cases:
            with self.subTest(platform=platform):
                result = self.run_verifier(platform, executable)
                self.assert_rejected(result, expected_error)

    def test_rejects_unsupported_platform(self) -> None:
        result = self.run_verifier("freebsd/amd64", elf(62))

        self.assert_rejected(result, "unsupported platform: freebsd/amd64")


if __name__ == "__main__":
    result = unittest.main(exit=False)
    if result.result.wasSuccessful():
        print("ALL PASS")
    raise SystemExit(not result.result.wasSuccessful())
