#!/usr/bin/env python3
"""
Tachyon Music Player - Automated Android Performance & Memory Benchmark
Measures VmRSS, PSS, Private Dirty, Native Heap, Dart VM Heap, and Graphics RAM
in both Foreground (Active) and Minimized (Background) states via ADB.
"""

import argparse
import re
import subprocess
import sys
import time

PACKAGE_NAME = "dev.chomusuke.tachyon"
MAIN_ACTIVITY = f"{PACKAGE_NAME}/.MainActivity"


def run_adb(args: list[str], timeout: int = 15) -> str:
    cmd = ["adb"] + args
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return res.stdout.strip()


def get_pid() -> int | None:
    out = run_adb(["shell", "pidof", PACKAGE_NAME])
    if not out:
        return None
    try:
        return int(out.split()[0])
    except ValueError:
        return None


def sample_memory(pid: int) -> dict[str, float]:
    metrics: dict[str, float] = {
        "vm_rss_mb": 0.0,
        "rss_anon_mb": 0.0,
        "rss_file_mb": 0.0,
        "rss_shmem_mb": 0.0,
        "vm_swap_mb": 0.0,
        "total_pss_mb": 0.0,
        "private_dirty_mb": 0.0,
        "native_heap_pss_mb": 0.0,
        "native_heap_alloc_mb": 0.0,
        "dalvik_heap_pss_mb": 0.0,
        "graphics_pss_mb": 0.0,
    }

    status_out = run_adb(["shell", f"cat /proc/{pid}/status"])
    for line in status_out.splitlines():
        if line.startswith("VmRSS:"):
            metrics["vm_rss_mb"] = int(line.split()[1]) / 1024.0
        elif line.startswith("RssAnon:"):
            metrics["rss_anon_mb"] = int(line.split()[1]) / 1024.0
        elif line.startswith("RssFile:"):
            metrics["rss_file_mb"] = int(line.split()[1]) / 1024.0
        elif line.startswith("RssShmem:"):
            metrics["rss_shmem_mb"] = int(line.split()[1]) / 1024.0
        elif line.startswith("VmSwap:"):
            metrics["vm_swap_mb"] = int(line.split()[1]) / 1024.0

    meminfo_out = run_adb(["shell", "dumpsys", "meminfo", str(pid)])
    for line in meminfo_out.splitlines():
        s = line.strip()
        if s.startswith("Native Heap"):
            parts = s.split()
            if len(parts) >= 8 and parts[2].isdigit():
                metrics["native_heap_pss_mb"] = int(parts[2]) / 1024.0
                metrics["native_heap_alloc_mb"] = int(parts[-2]) / 1024.0
        elif s.startswith("Dalvik Heap"):
            parts = s.split()
            if len(parts) >= 4 and parts[2].isdigit():
                metrics["dalvik_heap_pss_mb"] = int(parts[2]) / 1024.0
        elif s.startswith("Graphics:"):
            m = re.search(r"Graphics:\s+(\d+)", s)
            if m:
                metrics["graphics_pss_mb"] = int(m.group(1)) / 1024.0
        elif s.startswith("TOTAL PSS:"):
            m_pss = re.search(r"TOTAL PSS:\s+(\d+)", s)
            if m_pss:
                metrics["total_pss_mb"] = int(m_pss.group(1)) / 1024.0
        elif s.startswith("TOTAL") and "TOTAL PSS:" not in s:
            parts = s.split()
            if len(parts) >= 3 and parts[1].isdigit() and parts[2].isdigit():
                metrics["total_pss_mb"] = int(parts[1]) / 1024.0
                metrics["private_dirty_mb"] = int(parts[2]) / 1024.0

    return metrics


def print_snapshot(label: str, m: dict[str, float]) -> None:
    print(f"\n--- {label} ---")
    print(
        f"  VmRSS:           {m['vm_rss_mb']:6.2f} MB "
        f"(Anon: {m['rss_anon_mb']:.1f} MB | File: {m['rss_file_mb']:.1f} MB | "
        f"Shmem: {m['rss_shmem_mb']:.1f} MB | Swap: {m['vm_swap_mb']:.1f} MB)"
    )
    print(f"  TOTAL PSS:       {m['total_pss_mb']:6.2f} MB")
    print(f"  Private Dirty:   {m['private_dirty_mb']:6.2f} MB")
    print(
        f"  Native Heap:     {m['native_heap_pss_mb']:6.2f} MB PSS "
        f"({m['native_heap_alloc_mb']:.2f} MB Allocated)"
    )
    print(f"  Dalvik/ART Heap: {m['dalvik_heap_pss_mb']:6.2f} MB PSS")
    print(f"  Graphics (GPU):  {m['graphics_pss_mb']:6.2f} MB PSS")


def main() -> None:
    parser = argparse.ArgumentParser(description="Tachyon Android RAM Benchmark")
    parser.add_argument(
        "--relaunch",
        action="store_true",
        help="Force-stop and cold-launch the app before measuring",
    )
    args = parser.parse_args()

    if args.relaunch:
        print(f"Force-stopping and launching {MAIN_ACTIVITY}...")
        run_adb(["shell", "am", "force-stop", PACKAGE_NAME])
        time.sleep(1.0)
        run_adb(["shell", "am", "start", "-n", MAIN_ACTIVITY])
        time.sleep(5.0)

    pid = get_pid()
    if not pid:
        print(f"Error: {PACKAGE_NAME} is not running on the connected Android device.")
        sys.exit(1)

    print(f"Attached to {PACKAGE_NAME} (PID: {pid})")
    fg = sample_memory(pid)
    print_snapshot("FOREGROUND (ACTIVE)", fg)

    print("\nMinimizing app to background (KEYCODE_HOME)...")
    run_adb(["shell", "input", "keyevent", "KEYCODE_HOME"])
    time.sleep(3.0)

    bg = sample_memory(pid)
    print_snapshot("MINIMIZED (BACKGROUND)", bg)

    print("\nRestoring app to foreground...")
    run_adb(["shell", "am", "start", "-n", MAIN_ACTIVITY])
    time.sleep(2.0)
    resumed = sample_memory(pid)
    print_snapshot("RESUMED (FOREGROUND)", resumed)


if __name__ == "__main__":
    main()
