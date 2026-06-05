# Informe HPL del cluster HPC

Este repositorio contiene los datos fuente y el informe Typst para tres mediciones:

- HPL CPU en 12 nodos: `hpl-12n/`
- HPL-NVIDIA en un nodo con 8 GPU NVIDIA A100 40 GB: `hpl-nvidia/`
- HPL CPU en 4 nodos con telemetría de consumo del chasis: `hpl-4n/`

## Regenerar métricas y figuras

El informe usa métricas derivadas en `data/derived_metrics.json` y figuras SVG en `figures/`.

```sh
python3 scripts/extract_metrics.py
```

Dependencias del extractor:

- Python 3
- Matplotlib

No requiere Pandas.

## Compilar el informe

```sh
typst compile report.typ report.pdf
```

En el entorno actual se verificó `typst 0.14.2` y la compilación genera `report.pdf`.

## Archivos principales

- `report.typ`: fuente del informe técnico.
- `scripts/extract_metrics.py`: parser de logs HPL, integración de potencia y generación de gráficos.
- `data/derived_metrics.json`: métricas normalizadas usadas por Typst.
- `figures/rmax_comparison.svg`: comparación de Rmax y Rpeak estimado.
- `figures/gpu_sweep.svg`: barrido HPL-NVIDIA por tamaño de problema.
- `figures/power_timeseries.svg`: potencia del chasis durante HPL de 4 nodos.

## Supuestos de Rpeak

El Rpeak CPU se calcula con el criterio solicitado de referencia estilo TOP500: `45.12 GFLOP/s` por núcleo, derivado de entradas TOP500 con AMD EPYC 9654 y escalado por el conteo de núcleos de los EPYC 9754 medidos.

El Rpeak GPU usa el pico FP64 Tensor Core de NVIDIA A100: `19.5 TFLOP/s` por GPU.
