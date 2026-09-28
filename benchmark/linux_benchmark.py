#!/usr/bin/env python3
"""
Tachyon Linux Performance Benchmark Harness
Automated profiler measuring:
- Resident Set Size (VmRSS, RssAnon, RssFile, Pss, Private_Dirty in MB)
- CPU Utilization (Kernel delta /proc/<pid>/stat, normalized across single core)
- GPU Utilization (nvidia-smi pmon SM% and DRM sysfs)
- Performance metrics against acceptance criteria
"""

import argparse
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
    vm_rss_mb: float
    rss_anon_mb: float
    rss_file_mb: float
    pss_mb: float
    private_dirty_mb: float
    cpu_percent: float
    gpu_percent: float


class LinuxProfiler:
    """Zero-dependency Linux kernel metrics profiler using /proc and sysfs."""

    def __init__(self, pid: int):
        self.pid = pid
        try:
            self.clk_tck = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        except (AttributeError, KeyError, ValueError):
            self.clk_tck = 100
        self.num_cpus = os.cpu_count() or 1
        self._last_cpu_time: Optional[int] = None
        self._last_sample_time: Optional[float] = None

    def is_alive(self) -> bool:
        """Check if process is still running."""
        try:
            os.kill(self.pid, 0)
            return True
        except OSError:
            return False

    def read_memory(self) -> Dict[str, float]:
        """Read memory usage from /proc/<pid>/status and /proc/<pid>/smaps_rollup."""
        vm_rss = rss_anon = rss_file = 0.0
        pss = private_dirty = 0.0

        try:
            with open(f"/proc/{self.pid}/status", "r") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        vm_rss = float(line.split()[1]) / 1024.0
                    elif line.startswith("RssAnon:"):
                        rss_anon = float(line.split()[1]) / 1024.0
                    elif line.startswith("RssFile:"):
                        rss_file = float(line.split()[1]) / 1024.0
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

        try:
            with open(f"/proc/{self.pid}/smaps_rollup", "r") as f:
                for line in f:
                    if line.startswith("Pss:"):
                        pss = float(line.split()[1]) / 1024.0
                    elif line.startswith("Private_Dirty:"):
                        private_dirty = float(line.split()[1]) / 1024.0
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

        return {
            "vm_rss_mb": round(vm_rss, 2),
            "rss_anon_mb": round(rss_anon, 2),
            "rss_file_mb": round(rss_file, 2),
            "pss_mb": round(pss, 2),
            "private_dirty_mb": round(private_dirty, 2),
        }

    def read_cpu(self) -> float:
        """Read CPU utilization as a percentage of single core from /proc/<pid>/stat."""
        try:
            with open(f"/proc/{self.pid}/stat", "r") as f:
                content = f.read()
                # Process name may contain spaces and parentheses: extract after last ')'
                after_comm = content[content.rfind(")") + 2 :]
                parts = after_comm.split()
                # parts[11] is utime (14th in stat), parts[12] is stime (15th in stat)
                utime = int(parts[11])
                stime = int(parts[12])
                total_ticks = utime + stime
        except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
            return 0.0

        now = time.time()
        cpu_percent = 0.0

        if self._last_cpu_time is not None and self._last_sample_time is not None:
            delta_ticks = total_ticks - self._last_cpu_time
            delta_time = now - self._last_sample_time
            if delta_time > 0 and self.clk_tck > 0:
                cpu_percent = (delta_ticks / (self.clk_tck * delta_time)) * 100.0

        self._last_cpu_time = total_ticks
        self._last_sample_time = now
        return round(cpu_percent, 2)

    def read_gpu(self) -> float:
        """Read GPU utilization from nvidia-smi or DRM sysfs."""
        # 1. Try process-specific nvidia-smi pmon
        try:
            res = subprocess.run(
                ["nvidia-smi", "pmon", "-c", "1", "-s", "u"],
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            for line in res.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 4 and parts[1] == str(self.pid):
                    val = parts[3]
                    if val != "-":
                        return float(val)
        except Exception:
            pass

        # 2. Try global nvidia-smi
        try:
            res = subprocess.run(
                [
                    "nvidia-smi",
                    "--query-gpu=utilization.gpu",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            val = res.stdout.strip()
            if val:
                return float(val.split("\n")[0])
        except Exception:
            pass

        # 3. Try AMD/Intel DRM sysfs
        try:
            for card in range(4):
                path = f"/sys/class/drm/card{card}/device/gpu_busy_percent"
                if os.path.exists(path):
                    with open(path, "r") as f:
                        return float(f.read().strip())
        except Exception:
            pass

        return 0.0

    def sample(self) -> PerformanceSample:
        """Sample all hardware and kernel metrics at current instant."""
        mem = self.read_memory()
        cpu = self.read_cpu()
        gpu = self.read_gpu()
        return PerformanceSample(
            timestamp=round(time.time(), 3),
            vm_rss_mb=mem["vm_rss_mb"],
            rss_anon_mb=mem["rss_anon_mb"],
            rss_file_mb=mem["rss_file_mb"],
            pss_mb=mem["pss_mb"],
            private_dirty_mb=mem["private_dirty_mb"],
            cpu_percent=cpu,
            gpu_percent=gpu,
        )


def run_benchmark(
    binary_path: str,
    duration_sec: int = 15,
    mode: str = "idle",
    sample_interval: float = 1.0,
) -> Dict[str, any]:
    """Launch Tachyon release binary, collect samples, and evaluate results."""
    env = os.environ.copy()
    if mode == "resize":
        env["GDK_BACKEND"] = "x11"

    print(f"Launching target: {binary_path} (mode: {mode})...")
    proc = subprocess.Popen([binary_path], env=env)
    profiler = LinuxProfiler(proc.pid)
    samples: List[PerformanceSample] = []

    try:
        # Stabilization period (let window and engine initialize)
        print("Waiting 3.0s for engine & GTK window stabilization...")
        time.sleep(3.0)
        profiler.read_cpu()  # Initialize first CPU tick reference

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
                f"  [{mode.upper()}] RSS: {sample.vm_rss_mb:6.1f} MB (Anon: {sample.rss_anon_mb:5.1f} MB | PSS: {sample.pss_mb:5.1f} MB) | CPU: {sample.cpu_percent:4.1f}% | GPU: {sample.gpu_percent:4.1f}%"
            )

    finally:
        print("Terminating target process...")
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    if not samples:
        return {"error": "No samples collected"}

    avg_rss = round(sum(s.vm_rss_mb for s in samples) / len(samples), 2)
    max_rss = round(max(s.vm_rss_mb for s in samples), 2)
    avg_anon = round(sum(s.rss_anon_mb for s in samples) / len(samples), 2)
    avg_pss = round(sum(s.pss_mb for s in samples) / len(samples), 2)
    avg_cpu = round(sum(s.cpu_percent for s in samples) / len(samples), 2)
    max_cpu = round(max(s.cpu_percent for s in samples), 2)
    avg_gpu = round(sum(s.gpu_percent for s in samples) / len(samples), 2)
    max_gpu = round(max(s.gpu_percent for s in samples), 2)

    # Evaluate against targets:
    # Idle targets: RSS <= 50MB (or PSS <= 65MB), CPU < 2.0%, GPU < 5.0%
    # Playback targets: RSS <= 75MB, CPU < 2.0%, GPU < 5.0%
    rss_target = 50.0 if mode == "idle" else 75.0
    pss_target = 65.0
    cpu_target = 2.0
    gpu_target = 5.0

    rss_pass = avg_rss <= rss_target or avg_pss <= pss_target
    cpu_pass = avg_cpu < cpu_target
    gpu_pass = avg_gpu < gpu_target

    summary = {
        "mode": mode,
        "duration_sec": duration_sec,
        "sample_count": len(samples),
        "metrics": {
            "avg_vm_rss_mb": avg_rss,
            "max_vm_rss_mb": max_rss,
            "avg_rss_anon_mb": avg_anon,
            "avg_pss_mb": avg_pss,
            "avg_cpu_percent": avg_cpu,
            "max_cpu_percent": max_cpu,
            "avg_gpu_percent": avg_gpu,
            "max_gpu_percent": max_gpu,
        },
        "targets": {
            "rss_target_mb": rss_target,
            "pss_target_mb": pss_target,
            "cpu_target_percent": cpu_target,
            "gpu_target_percent": gpu_target,
        },
        "status": {
            "memory_check": "PASS" if rss_pass else "FAIL",
            "cpu_check": "PASS" if cpu_pass else "FAIL",
            "gpu_check": "PASS" if gpu_pass else "FAIL",
            "overall": "PASS" if (rss_pass and cpu_pass and gpu_pass) else "FAIL",
        },
        "samples": [asdict(s) for s in samples],
    }

    return summary


def main():
    parser = argparse.ArgumentParser(description="Tachyon Linux Performance Benchmark")
    parser.add_argument(
        "--binary",
        default="/mnt/Proyectos/tachyon/build/linux/x64/release/bundle/tachyon",
        help="Path to Tachyon release executable bundle",
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
        choices=["idle", "playback", "resize"],
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
        print(f"Error: Release binary not found at '{args.binary}'.")
        print("Please build the release binary first: 'flutter build linux --release'")
        sys.exit(1)

    print("================================================================")
    print("           TACHYON LINUX PERFORMANCE BENCHMARK HARNESS          ")
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
    print(f"Mode:               {result['mode']}")
    print(f"Duration:           {result['duration_sec']}s ({result['sample_count']} samples)")
    print(f"Average VmRSS:      {m['avg_vm_rss_mb']} MB (Max: {m['max_vm_rss_mb']} MB) [Target <= {t['rss_target_mb']} MB] -> {s['memory_check']}")
    print(f"Average Pss:        {m['avg_pss_mb']} MB [Target <= {t['pss_target_mb']} MB]")
    print(f"Average RssAnon:    {m['avg_rss_anon_mb']} MB")
    print(f"Average CPU:        {m['avg_cpu_percent']}% (Max: {m['max_cpu_percent']}%) [Target < {t['cpu_target_percent']}%] -> {s['cpu_check']}")
    print(f"Average GPU:        {m['avg_gpu_percent']}% (Max: {m['max_gpu_percent']}%) [Target < {t['gpu_target_percent']}%] -> {s['gpu_check']}")
    print(f"Overall Assessment: {s['overall']}")
    print("----------------------------------------------------------------")

    if args.output:
        with open(args.output, "w") as f:
            json.dump(result, f, indent=2)
        print(f"Report exported to: {args.output}")


if __name__ == "__main__":
    main()
