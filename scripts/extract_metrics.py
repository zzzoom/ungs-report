#!/usr/bin/env python3
"""Extract benchmark metrics and render figures for the Typst report."""

from __future__ import annotations

import csv
import json
import os
import re
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from statistics import mean, median
from typing import Any

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-ungs-report")

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
FIGURES_DIR = ROOT / "figures"

CPU_RPEAK_GFLOPS_PER_CORE = 45.12
GPU_A100_FP64_TENSOR_TFLOPS = 19.5

CPU_4N_START = datetime(2026, 5, 22, 0, 52, 39)
CPU_4N_END = datetime(2026, 5, 22, 1, 59, 25)

RESULT_RE = re.compile(
    r"^(?P<variant>\S+)\s+"
    r"(?:(?P<swp>\d+)\s+)?"
    r"(?P<n>\d+)\s+"
    r"(?P<nb>\d+)\s+"
    r"(?P<p>\d+)\s+"
    r"(?P<q>\d+)\s+"
    r"(?P<time>[0-9.]+)\s+"
    r"(?P<gflops>[0-9.eE+-]+)"
    r"(?:\s+\(\s*(?P<per_gpu>[0-9.eE+-]+)\))?"
)
RESIDUAL_RE = re.compile(r"=\s*(?P<residual>[0-9.eE+-]+)\s+\.\.\.\.\.\.\s+(?P<status>PASSED|FAILED)")
START_RE = re.compile(r"HPL_pdgesv\(\) start time\s+(?P<date>.+)$", re.MULTILINE)
END_RE = re.compile(r"HPL_pdgesv\(\) end time\s+(?P<date>.+)$", re.MULTILINE)


@dataclass(frozen=True)
class HplRun:
    id: str
    label: str
    kind: str
    source_dir: str
    log_file: str
    nodes: int
    sockets_per_node: int | None
    cpu_model: str | None
    cpu_cores_per_socket: int | None
    gpus: int | None
    gpu_model: str | None
    ranks: int
    cpus_per_task: int
    omp_threads: int | None
    hpl_impl: str
    n: int
    nb: int
    p: int
    q: int
    time_s: float
    gflops: float
    tflops: float
    per_gpu_gflops: float | None
    per_node_tflops: float | None
    residual: float
    residual_status: str
    start_time: str
    end_time: str
    matrix_memory_gib: float
    rpeak_tflops: float
    efficiency_pct: float


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def parse_hpl_datetime(value: str) -> datetime:
    parts = value.split()
    if len(parts) != 5:
        raise ValueError(f"Unexpected HPL datetime: {value!r}")
    normalized = " ".join(parts)
    return datetime.strptime(normalized, "%a %b %d %H:%M:%S %Y")


def parse_hpl_results(text: str) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    starts = [parse_hpl_datetime(m.group("date")) for m in START_RE.finditer(text)]
    ends = [parse_hpl_datetime(m.group("date")) for m in END_RE.finditer(text)]
    residuals = [
        {
            "residual": float(m.group("residual")),
            "residual_status": m.group("status"),
        }
        for m in RESIDUAL_RE.finditer(text)
    ]

    for line in text.splitlines():
        match = RESULT_RE.match(strip_ansi(line.strip()))
        if not match:
            continue
        groups = match.groupdict()
        if not groups["variant"].startswith("WR"):
            continue
        result = {
            "variant": groups["variant"],
            "swp": int(groups["swp"]) if groups["swp"] else None,
            "n": int(groups["n"]),
            "nb": int(groups["nb"]),
            "p": int(groups["p"]),
            "q": int(groups["q"]),
            "time_s": float(groups["time"]),
            "gflops": float(groups["gflops"]),
            "per_gpu_gflops": float(groups["per_gpu"]) if groups["per_gpu"] else None,
        }
        results.append(result)

    for idx, result in enumerate(results):
        if idx < len(starts):
            result["start_time"] = starts[idx].isoformat(sep=" ")
        if idx < len(ends):
            result["end_time"] = ends[idx].isoformat(sep=" ")
        if idx < len(residuals):
            result.update(residuals[idx])

    return results


def strip_ansi(value: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", value)


def matrix_memory_gib(n: int) -> float:
    return n * n * 8 / 1024**3


def make_cpu_run(
    *,
    id_: str,
    label: str,
    source_dir: str,
    log_name: str,
    nodes: int,
    p: int,
    q: int,
) -> HplRun:
    text = read_text(ROOT / source_dir / log_name)
    results = parse_hpl_results(text)
    if len(results) != 1:
        raise AssertionError(f"Expected one HPL result in {log_name}, got {len(results)}")
    result = results[0]
    total_cores = nodes * 2 * 128
    rpeak_tflops = total_cores * CPU_RPEAK_GFLOPS_PER_CORE / 1000
    tflops = result["gflops"] / 1000
    return HplRun(
        id=id_,
        label=label,
        kind="cpu",
        source_dir=source_dir,
        log_file=log_name,
        nodes=nodes,
        sockets_per_node=2,
        cpu_model="AMD EPYC 9754",
        cpu_cores_per_socket=128,
        gpus=None,
        gpu_model=None,
        ranks=p * q,
        cpus_per_task=32,
        omp_threads=32,
        hpl_impl="AMD Zen HPL 2024_10_08, AOCL BLIS",
        n=result["n"],
        nb=result["nb"],
        p=result["p"],
        q=result["q"],
        time_s=result["time_s"],
        gflops=result["gflops"],
        tflops=tflops,
        per_gpu_gflops=None,
        per_node_tflops=tflops / nodes,
        residual=result["residual"],
        residual_status=result["residual_status"],
        start_time=result["start_time"],
        end_time=result["end_time"],
        matrix_memory_gib=matrix_memory_gib(result["n"]),
        rpeak_tflops=rpeak_tflops,
        efficiency_pct=tflops / rpeak_tflops * 100,
    )


def make_gpu_runs() -> tuple[HplRun, list[dict[str, Any]]]:
    source_dir = "hpl-nvidia"
    log_name = "nv-hpl-622.out"
    text = read_text(ROOT / source_dir / log_name)
    results = parse_hpl_results(text)
    if len(results) != 8:
        raise AssertionError(f"Expected eight GPU HPL results, got {len(results)}")

    rpeak_tflops = 8 * GPU_A100_FP64_TENSOR_TFLOPS
    sweep = []
    for result in results:
        tflops = result["gflops"] / 1000
        sweep.append(
            {
                "n": result["n"],
                "nb": result["nb"],
                "p": result["p"],
                "q": result["q"],
                "time_s": result["time_s"],
                "gflops": result["gflops"],
                "tflops": tflops,
                "per_gpu_tflops": (result["per_gpu_gflops"] or 0) / 1000,
                "residual": result["residual"],
                "residual_status": result["residual_status"],
                "start_time": result["start_time"],
                "end_time": result["end_time"],
                "matrix_memory_gib": matrix_memory_gib(result["n"]),
                "efficiency_pct": tflops / rpeak_tflops * 100,
            }
        )

    best = max(sweep, key=lambda row: row["gflops"])
    run = HplRun(
        id="gpu_8a100_best",
        label="1 nodo GPU, 8x NVIDIA A100 40 GB",
        kind="gpu",
        source_dir=source_dir,
        log_file=log_name,
        nodes=1,
        sockets_per_node=None,
        cpu_model=None,
        cpu_cores_per_socket=None,
        gpus=8,
        gpu_model="NVIDIA A100-SXM4-40GB",
        ranks=8,
        cpus_per_task=32,
        omp_threads=1,
        hpl_impl="HPL-NVIDIA 26.2.0",
        n=best["n"],
        nb=best["nb"],
        p=best["p"],
        q=best["q"],
        time_s=best["time_s"],
        gflops=best["gflops"],
        tflops=best["tflops"],
        per_gpu_gflops=best["per_gpu_tflops"] * 1000,
        per_node_tflops=best["tflops"],
        residual=best["residual"],
        residual_status=best["residual_status"],
        start_time=best["start_time"],
        end_time=best["end_time"],
        matrix_memory_gib=best["matrix_memory_gib"],
        rpeak_tflops=rpeak_tflops,
        efficiency_pct=best["efficiency_pct"],
    )
    return run, sweep


def parse_power_csv() -> dict[str, Any]:
    path = ROOT / "hpl-4n" / "4n.csv"
    rows = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row["timestamp_dt"] = datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S")
            rows.append(row)

    interval_rows = [
        row
        for row in rows
        if CPU_4N_START <= row["timestamp_dt"] <= CPU_4N_END and is_number(row["SYS_POWER"])
    ]
    if len(interval_rows) != 603:
        raise AssertionError(f"Expected 603 power samples during HPL, got {len(interval_rows)}")

    powers = [float(row["SYS_POWER"]) for row in interval_rows]
    energy_ws = 0.0
    for previous, current in zip(interval_rows, interval_rows[1:]):
        dt_seconds = (current["timestamp_dt"] - previous["timestamp_dt"]).total_seconds()
        energy_ws += (float(previous["SYS_POWER"]) + float(current["SYS_POWER"])) / 2 * dt_seconds

    node_stats = {}
    for node in range(1, 5):
        power_key = f"ND0{node}_PWR"
        temp_key = f"ND0{node}_CPU_TEMP"
        node_powers = [float(row[power_key]) for row in interval_rows if is_number(row[power_key])]
        node_temps = [float(row[temp_key]) for row in interval_rows if is_number(row[temp_key])]
        node_stats[f"node_{node}"] = {
            "power_avg_w": mean(node_powers),
            "power_valid_samples": len(node_powers),
            "power_missing_samples": len(interval_rows) - len(node_powers),
            "temp_avg_c": mean(node_temps),
            "temp_max_c": max(node_temps),
        }

    power_min = min(powers)
    outliers = [
        {
            "timestamp": row["timestamp_dt"].isoformat(sep=" "),
            "sys_power_w": float(row["SYS_POWER"]),
        }
        for row in interval_rows
        if float(row["SYS_POWER"]) == power_min
    ]

    return {
        "source_file": "hpl-4n/4n.csv",
        "interval_start": CPU_4N_START.isoformat(sep=" "),
        "interval_end": CPU_4N_END.isoformat(sep=" "),
        "samples": len(interval_rows),
        "duration_integrated_s": int(
            (interval_rows[-1]["timestamp_dt"] - interval_rows[0]["timestamp_dt"]).total_seconds()
        ),
        "sys_power_avg_w": mean(powers),
        "sys_power_median_w": median(powers),
        "sys_power_min_w": power_min,
        "sys_power_max_w": max(powers),
        "sys_power_p05_w": percentile(powers, 0.05),
        "sys_power_p95_w": percentile(powers, 0.95),
        "energy_wh": energy_ws / 3600,
        "energy_kwh": energy_ws / 3_600_000,
        "node_stats": node_stats,
        "outliers": outliers,
        "timeseries": [
            {
                "timestamp": row["timestamp_dt"].isoformat(sep=" "),
                "seconds_from_start": (row["timestamp_dt"] - CPU_4N_START).total_seconds(),
                "sys_power_w": float(row["SYS_POWER"]),
            }
            for row in interval_rows
        ],
    }


def is_number(value: str) -> bool:
    try:
        float(value)
    except (TypeError, ValueError):
        return False
    return True


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    index = round((len(ordered) - 1) * quantile)
    return ordered[index]


def render_figures(runs: list[HplRun], gpu_sweep: list[dict[str, Any]], power: dict[str, Any]) -> None:
    FIGURES_DIR.mkdir(exist_ok=True)
    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 10,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.grid": True,
            "grid.alpha": 0.25,
            "figure.dpi": 130,
        }
    )

    render_rmax_bars(runs)
    render_gpu_sweep(gpu_sweep)
    render_power_timeseries(power)


def render_rmax_bars(runs: list[HplRun]) -> None:
    labels = ["CPU 4 nodos", "CPU 12 nodos", "GPU 8xA100"]
    ordered = [next(run for run in runs if run.id == id_) for id_ in ["cpu_4n", "cpu_12n", "gpu_8a100_best"]]
    values = [run.tflops for run in ordered]
    rpeaks = [run.rpeak_tflops for run in ordered]

    fig, ax = plt.subplots(figsize=(6.8, 3.6))
    bars = ax.bar(labels, values, color=["#3a6ea5", "#3a6ea5", "#7a4f9f"])
    ax.scatter(labels, rpeaks, marker="_", s=520, color="#222222", linewidths=2.2, label="Rpeak estimado")
    ax.set_ylabel("TFLOP/s")
    ax.set_title("Rmax HPL observado")
    ax.yaxis.set_major_locator(mticker.MaxNLocator(6))
    for bar, run in zip(bars, ordered):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + max(values) * 0.025,
            f"{run.tflops:.2f}",
            ha="center",
            va="bottom",
        )
    ax.legend(loc="upper left", frameon=False)
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "rmax_comparison.svg")
    plt.close(fig)


def render_gpu_sweep(gpu_sweep: list[dict[str, Any]]) -> None:
    fig, ax = plt.subplots(figsize=(6.8, 3.6))
    xs = [row["n"] for row in gpu_sweep]
    ys = [row["tflops"] for row in gpu_sweep]
    ax.plot(xs, ys, color="#7a4f9f", marker="o", linewidth=2)
    best = max(gpu_sweep, key=lambda row: row["tflops"])
    ax.scatter([best["n"]], [best["tflops"]], color="#222222", zorder=3)
    ax.annotate(
        f"Mejor: {best['tflops']:.2f} TFLOP/s",
        xy=(best["n"], best["tflops"]),
        xytext=(12, 14),
        textcoords="offset points",
        arrowprops={"arrowstyle": "->", "color": "#444444", "lw": 1},
    )
    ax.set_title("Barrido HPL-NVIDIA por tamaño de problema")
    ax.set_xlabel("N")
    ax.set_ylabel("TFLOP/s")
    ax.ticklabel_format(style="plain", axis="x")
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "gpu_sweep.svg")
    plt.close(fig)


def render_power_timeseries(power: dict[str, Any]) -> None:
    series = power["timeseries"]
    xs = [row["seconds_from_start"] / 60 for row in series]
    ys = [row["sys_power_w"] / 1000 for row in series]
    avg_kw = power["sys_power_avg_w"] / 1000

    fig, ax = plt.subplots(figsize=(7.2, 3.6))
    ax.plot(xs, ys, color="#2b7a78", linewidth=1.6)
    ax.axhline(avg_kw, color="#222222", linestyle="--", linewidth=1, label=f"Media {avg_kw:.2f} kW")
    ax.set_title("Potencia del chasis durante HPL 4 nodos")
    ax.set_xlabel("Minutos desde inicio de HPL")
    ax.set_ylabel("SYS_POWER (kW)")
    ax.set_ylim(bottom=0)
    ax.legend(loc="lower left", frameon=False)
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "power_timeseries.svg")
    plt.close(fig)


def main() -> None:
    DATA_DIR.mkdir(exist_ok=True)
    FIGURES_DIR.mkdir(exist_ok=True)

    cpu_4n = make_cpu_run(
        id_="cpu_4n",
        label="4 nodos CPU, 2x AMD EPYC 9754 por nodo",
        source_dir="hpl-4n",
        log_name="slurm-493.out",
        nodes=4,
        p=4,
        q=8,
    )
    cpu_12n = make_cpu_run(
        id_="cpu_12n",
        label="12 nodos CPU, 2x AMD EPYC 9754 por nodo",
        source_dir="hpl-12n",
        log_name="slurm-615.out",
        nodes=12,
        p=8,
        q=12,
    )
    gpu_best, gpu_sweep = make_gpu_runs()
    power = parse_power_csv()

    assert round(cpu_4n.gflops, 1) == 36327.0
    assert round(cpu_12n.gflops, 1) == 109000.0
    assert round(gpu_best.gflops, 1) == 96980.0

    runs = [cpu_4n, cpu_12n, gpu_best]
    power["efficiency_gflops_per_w"] = cpu_4n.gflops / power["sys_power_avg_w"]
    power["hpl_tflops"] = cpu_4n.tflops

    metrics = {
        "report": {
            "title": "Informe técnico de mediciones HPL y consumo del cluster HPC",
            "source": "Datos locales en hpl-12n/, hpl-nvidia/ y hpl-4n/.",
        },
        "runs": [asdict(run) for run in runs],
        "gpu_sweep": gpu_sweep,
        "power_4n": power,
        "rpeak_assumptions": {
            "cpu_method": "TOP500-style estimate derived from EPYC 9654 entries: 45.12 GFLOP/s per core.",
            "cpu_gflops_per_core": CPU_RPEAK_GFLOPS_PER_CORE,
            "gpu_method": "NVIDIA A100 FP64 Tensor Core peak.",
            "gpu_a100_fp64_tensor_tflops": GPU_A100_FP64_TENSOR_TFLOPS,
        },
        "sources": [
            {
                "label": "TOP500 June 2025 list",
                "url": "https://top500.org/lists/top500/list/2025/06/?page=2",
            },
            {
                "label": "TOP500 CATT EPYC 9654 entry",
                "url": "https://top500.org/system/180324/",
            },
            {
                "label": "AMD EPYC 9754 specifications",
                "url": "https://www.amd.com/en/products/processors/server/epyc/4th-generation-9004-and-8004-series/amd-epyc-9754.html",
            },
            {
                "label": "NVIDIA A100 specifications",
                "url": "https://www.nvidia.com/en-eu/data-center/a100/",
            },
        ],
    }

    render_figures(runs, gpu_sweep, power)

    output_path = DATA_DIR / "derived_metrics.json"
    output_path.write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {output_path.relative_to(ROOT)}")
    for figure in sorted(FIGURES_DIR.glob("*.svg")):
        print(f"Wrote {figure.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
