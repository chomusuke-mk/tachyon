#!/usr/bin/env python3
"""
Tachyon Windows Performance Benchmark Harness
Automated profiler measuring:
- Working Set (WorkingSetSize in MB, equivalent to VmRSS)
- Private Commit (PrivateUsage in MB, equivalent to RssAnon)
- Peak Working Set (PeakWorkingSetSize in MB)
- CPU Utilization (GetProcessTimes kernel delta, normalized across system cores)
- Performance metrics evaluated against strict acceptance criteria
"""

import argparse
import ctypes
import ctypes.wintypes as wintypes
import json
import os
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Dict, List, Optional


@dataclass
class PerformanceSample:
    timestamp: float
    working_set_mb: float
    private_commit_mb: float
    peak_working_set_mb: float
    cpu_percent: float


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD),
        ("PageFaultCount", wintypes.DWORD),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
        ("PrivateUsage", ctypes.c_size_t),
    ]


class WindowsProfiler:
    """Zero-dependency Windows kernel metrics profiler using Win32 APIs."""

    def __init__(self, pid: int):
        self.pid = pid
        self.kernel32 = ctypes.windll.kernel32
        self.psapi = ctypes.windll.psapi

        self.psapi.GetProcessMemoryInfo.argtypes = [
            wintypes.HANDLE,
            ctypes.POINTER(PROCESS_MEMORY_COUNTERS_EX),
            wintypes.DWORD,
        ]
        self.psapi.GetProcessMemoryInfo.restype = wintypes.BOOL

        process_query_information = 0x0400
        process_vm_read = 0x0010
        self.h_process = self.kernel32.OpenProcess(
            process_query_information | process_vm_read, False, self.pid
        )

        self.num_cpus = os.cpu_count() or 1
        self._last_kernel_time: Optional[int] = None
        self._last_user_time: Optional[int] = None
        self._last_sample_time: Optional[float] = None

    def close(self):
        if self.h_process:
            self.kernel32.CloseHandle(self.h_process)
            self.h_process = None

    def is_alive(self) -> bool:
        if not self.h_process:
            return False
        exit_code = wintypes.DWORD()
        if self.kernel32.GetExitCodeProcess(self.h_process, ctypes.byref(exit_code)):
            # STILL_ACTIVE = 259
            return exit_code.value == 259
        return False

    def read_memory(self) -> Dict[str, float]:
        if not self.h_process:
            return {"working_set_mb": 0.0, "private_commit_mb": 0.0, "peak_working_set_mb": 0.0}

        pmc = PROCESS_MEMORY_COUNTERS_EX()
        pmc.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS_EX)
        if self.psapi.GetProcessMemoryInfo(self.h_process, ctypes.byref(pmc), pmc.cb):
            return {
                "working_set_mb": round(pmc.WorkingSetSize / (1024.0 * 1024.0), 2),
                "private_commit_mb": round(pmc.PrivateUsage / (1024.0 * 1024.0), 2),
                "peak_working_set_mb": round(pmc.PeakWorkingSetSize / (1024.0 * 1024.0), 2),
            }
        return {"working_set_mb": 0.0, "private_commit_mb": 0.0, "peak_working_set_mb": 0.0}

    def read_cpu(self) -> float:
        if not self.h_process:
            return 0.0

        creation_time = wintypes.FILETIME()
        exit_time = wintypes.FILETIME()
        kernel_time = wintypes.FILETIME()
        user_time = wintypes.FILETIME()

        res = self.kernel32.GetProcessTimes(
            self.h_process,
            ctypes.byref(creation_time),
            ctypes.byref(exit_time),
            ctypes.byref(kernel_time),
            ctypes.byref(user_time),
        )
        if not res:
            return 0.0

        k_val = (kernel_time.dwHighDateTime << 32) + kernel_time.dwLowDateTime
        u_val = (user_time.dwHighDateTime << 32) + user_time.dwLowDateTime
        now = time.time()
        cpu_percent = 0.0

        if self._last_kernel_time is not None and self._last_sample_time is not None:
            delta_ticks = (k_val - self._last_kernel_time) + (u_val - self._last_user_time)
            delta_sec = now - self._last_sample_time
            # 1 tick = 100 nanoseconds = 1e-7 seconds
            if delta_sec > 0:
                cpu_seconds = delta_ticks * 1e-7
                cpu_percent = ((cpu_seconds / delta_sec) * 100.0) / self.num_cpus

        self._last_kernel_time = k_val
        self._last_user_time = u_val
        self._last_sample_time = now
        return round(cpu_percent, 2)

    def sample(self) -> PerformanceSample:
        mem = self.read_memory()
        cpu = self.read_cpu()
        return PerformanceSample(
            timestamp=round(time.time(), 3),
            working_set_mb=mem["working_set_mb"],
            private_commit_mb=mem["private_commit_mb"],
            peak_working_set_mb=mem["peak_working_set_mb"],
            cpu_percent=cpu,
        )


def run_benchmark(
    binary_path: str,
    duration_sec: int = 10,
    mode: str = "idle",
    sample_interval: float = 1.0,
) -> Dict[str, any]:
    """Launch Tachyon Windows binary, collect performance samples, and evaluate results."""
    print(f"Launching target: {binary_path} (mode: {mode})...")
    proc = subprocess.Popen([binary_path])
    profiler = WindowsProfiler(proc.pid)
    samples: List[PerformanceSample] = []

    try:
        print("Waiting 3.0s for engine & Win32 window stabilization...")
        time.sleep(3.0)
        profiler.read_cpu()  # Initialize first CPU reference

        start = time.time()
        print(f"Sampling metrics for {duration_sec}s at {sample_interval}s interval:")
        while time.time() - start < duration_sec:
            if not profiler.is_alive():
                print("Target process exited unexpectedly.")
                break
            time.sleep(sample_interval)
            sample = profiler.sample()
            samples.append(sample)
            print(
                f"  [{mode.upper()}] Working Set: {sample.working_set_mb:6.1f} MB "
                f"(Private: {sample.private_commit_mb:5.1f} MB | Peak: {sample.peak_working_set_mb:5.1f} MB) | "
                f"CPU: {sample.cpu_percent:4.1f}%"
            )

    finally:
        print("Terminating target process...")
        profiler.close()
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    if not samples:
        return {"error": "No samples collected"}

    avg_ws = round(sum(s.working_set_mb for s in samples) / len(samples), 2)
    max_ws = round(max(s.working_set_mb for s in samples), 2)
    avg_priv = round(sum(s.private_commit_mb for s in samples) / len(samples), 2)
    max_peak = round(max(s.peak_working_set_mb for s in samples), 2)
    avg_cpu = round(sum(s.cpu_percent for s in samples) / len(samples), 2)
    max_cpu = round(max(s.cpu_percent for s in samples), 2)

    # Acceptance targets (aligned with Linux benchmark):
    # Idle targets: Working Set <= 50.0 MB, CPU < 2.0%
    # Playback targets: Working Set <= 75.0 MB, CPU < 2.0%
    ws_target = 50.0 if mode == "idle" else 75.0
    cpu_target = 2.0

    mem_pass = avg_ws <= ws_target
    cpu_pass = avg_cpu < cpu_target

    summary = {
        "platform": "windows",
        "mode": mode,
        "duration_sec": duration_sec,
        "sample_count": len(samples),
        "metrics": {
            "avg_working_set_mb": avg_ws,
            "max_working_set_mb": max_ws,
            "avg_private_commit_mb": avg_priv,
            "max_peak_working_set_mb": max_peak,
            "avg_cpu_percent": avg_cpu,
            "max_cpu_percent": max_cpu,
        },
        "targets": {
            "working_set_target_mb": ws_target,
            "cpu_target_percent": cpu_target,
        },
        "status": {
            "memory_check": "PASS" if mem_pass else "FAIL",
            "cpu_check": "PASS" if cpu_pass else "FAIL",
            "overall": "PASS" if (mem_pass and cpu_pass) else "FAIL",
        },
        "samples": [asdict(s) for s in samples],
    }

    return summary


def main():
    parser = argparse.ArgumentParser(description="Tachyon Windows Performance Benchmark")
    parser.add_argument(
        "--binary",
        default=r"build\windows\x64\runner\Profile\tachyon.exe",
        help="Path to Tachyon Windows executable (default: build/windows/x64/runner/Profile/tachyon.exe)",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=10,
        help="Benchmark duration in seconds (default: 10)",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Sample interval in seconds (default: 1.0)",
    )
    parser.add_argument(
        "--mode",
        choices=["idle", "playback"],
        default="idle",
        help="Benchmark test mode (default: idle)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Optional path to write JSON report output",
    )
    args = parser.parse_args()

    if not os.path.exists(args.binary):
        print(f"Error: Target binary not found at '{args.binary}'.")
        print("Please build the profile binary first: 'flutter build windows --profile'")
        sys.exit(1)

    print("================================================================")
    print("          TACHYON WINDOWS PERFORMANCE BENCHMARK HARNESS         ")
    print("================================================================")
    result = run_benchmark(
        binary_path=args.binary,
        duration_sec=args.duration,
        mode=args.mode,
        sample_interval=args.interval,
    )

    if "error" in result:
        print(f"Benchmark failed: {result['error']}")
        sys.exit(1)

    m = result["metrics"]
    s = result["status"]
    t = result["targets"]

    print("\n----------------------------------------------------------------")
    print("                       BENCHMARK RESULTS                        ")
    print("----------------------------------------------------------------")
    print(f"Mode:                  {result['mode']}")
    print(f"Duration:              {result['duration_sec']}s ({result['sample_count']} samples)")
    print(
        f"Average Working Set:   {m['avg_working_set_mb']} MB (Max: {m['max_working_set_mb']} MB) "
        f"[Target <= {t['working_set_target_mb']} MB] -> {s['memory_check']}"
    )
    print(f"Average Private:       {m['avg_private_commit_mb']} MB")
    print(f"Peak Working Set:      {m['max_peak_working_set_mb']} MB")
    print(
        f"Average CPU:           {m['avg_cpu_percent']}% (Max: {m['max_cpu_percent']}%) "
        f"[Target < {t['cpu_target_percent']}%] -> {s['cpu_check']}"
    )
    print(f"Overall Assessment:    {s['overall']}")
    print("----------------------------------------------------------------")

    if args.output:
        with open(args.output, "w") as f:
            json.dump(result, f, indent=2)
        print(f"Report exported to: {args.output}")

    if s["overall"] != "PASS":
        sys.exit(1)


if __name__ == "__main__":
    main()
