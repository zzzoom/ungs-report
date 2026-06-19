#let metrics = json("data/derived_metrics.json")
#let runs = metrics.runs
#let cpu4 = runs.at(0)
#let cpu12 = runs.at(1)
#let gpu = runs.at(2)
#let sweep = metrics.gpu_sweep
#let power = metrics.power_4n
#let rpeak = metrics.rpeak_assumptions

#let fmt(value, digits: 2) = str(calc.round(value, digits: digits))
#let pct(value) = fmt(value, digits: 1) + "%"
#let tf(value) = fmt(value, digits: 2) + " TFLOP/s"
#let kw(value) = fmt(value / 1000, digits: 2) + " kW"
#let ti(value_gib) = fmt(value_gib / 1024, digits: 2) + " TiB"
#let seconds_to_min(value) = fmt(value / 60, digits: 1) + " min"

#set document(title: metrics.report.title)
#set page(
  paper: "a4",
  margin: (x: 2.1cm, y: 2.2cm),
  numbering: "1",
)
#set text(
  font: "Libertinus Serif",
  size: 10pt,
  lang: "es",
)
#set heading(numbering: "1.")
#set table(
  stroke: 0.35pt + rgb("#d0d5dd"),
  inset: (x: 5pt, y: 4pt),
)

#align(center)[
  #text(size: 18pt, weight: "bold")[Informe técnico de mediciones HPL y consumo del cluster HPC]

  #v(0.5em)
  #text(
    size: 11pt,
  )[Resultados de HPL en nodos CPU AMD EPYC 9754, HPL-NVIDIA en 8x A100 y consumo de un chasis de 4 nodos]
]

#v(1em)

= Resumen

Se analizaron tres corridas de HPL disponibles en el repositorio: una corrida CPU sobre 12 nodos de cómputo, una corrida HPL-NVIDIA sobre un nodo con 8 GPU NVIDIA A100 de 40 GB y una corrida CPU sobre 4 nodos acompañada por telemetría de consumo del chasis. Las tres ejecuciones finalizaron con verificación residual `PASSED`.

El resultado CPU escala de forma prácticamente lineal entre 4 y 12 nodos: #tf(cpu4.tflops) en 4 nodos y #tf(cpu12.tflops) en 12 nodos, con aproximadamente #tf(cpu12.per_node_tflops) por nodo en ambos casos. En GPU, el mejor resultado válido del barrido fue #tf(gpu.tflops) para N=#gpu.n, equivalente a #tf(gpu.per_gpu_gflops / 1000) por GPU. Para la corrida con medición eléctrica, la potencia media del chasis fue #kw(power.sys_power_avg_w) y la energía integrada fue #fmt(power.energy_kwh, digits: 3) kWh.

#figure(
  image("figures/rmax_comparison.svg", width: 100%),
  caption: [Comparación de Rmax HPL observado y Rpeak estimado para cada escenario medido.],
)

= Corridas realizadas

== Cluster CPU completo

Para la ejecución de HPL se eligió AMD Zen HPL, la versión optimizada del fabricante de los procesadores. Este paquete requiere OpenMPI 4 o 5 por lo que se utilizó para comunicación el módulo OpenMPI 5 compilado con GCC 15 de OpenHPC que está instalado en el cluster.

Aunque el paquete recomienda lanzar un rank MPI por procesador y saturar todos los cores del procesador con 128 hilos por rank, se ejecutó el benchmark lanzando un rank MPI por cada uno de los 4 dominios NUMA que expone cada procesador con 32 hilos por rank atados al mismo dominio NUMA, disposición que es levemente más veloz.

La configuración de HPL.dat fue la generada por el paquete de AMD para la disposición elegida, con una grilla de 8x12 procesos y N=1041408.

El resultado del benchmark fue un Rmax de 109 TFLOPS.

```
================================================================================
T/V         SWP           N    NB     P     Q            Time             Gflops
--------------------------------------------------------------------------------
WRC17R8C48c 211      1041408   384     8    12         6907.83         1.0900e+05
HPL_pdgesv() start time Thu Jun  4 13:57:48 2026
HPL_pdgesv() end time   Thu Jun  4 15:52:56 2026
--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV--VVV-
Timing Phase                                     Min         Avg         Max
rfact . . . . . . . . . . . . . . :             9.91       14.59       29.32
    pfact . . . . . . . . . . . . :             6.49       11.22       25.89
    mxswp . . . . . . . . . . . . :             3.78        8.76       23.29
update  . . . . . . . . . . . . . :          6876.49     6891.21     6895.35
    dtrsm . . . . . . . . . . . . :            34.26       35.06       35.94
    dgemm . . . . . . . . . . . . :          6170.80     6383.30     6647.30
    laswp . . . . . . . . . . . . :            94.22      325.39      642.15
pbcst . . . . . . . . . . . . . . :            19.23      145.87      414.62
    init  . . . . . . . . . . . . :             1.53        1.56        1.65
    cast  . . . . . . . . . . . . :             0.03       10.19       92.29
    dpiv  . . . . . . . . . . . . :             0.89       99.90      367.96
    wait  . . . . . . . . . . . . :            14.95       34.22       91.62
ptrsv . . . . . . . . . . . . . . :             0.83        0.83        0.83
================================================================================
--------------------------------------------------------------------------------
||Ax-b||_oo/(eps*(||A||_oo*||x||_oo+||b||_oo)*N)=   1.67684241e-03 ...... PASSED
================================================================================

Finished      1 tests with the following results:
              1 tests completed and passed residual checks,
              0 tests completed and failed residual checks,
              0 tests skipped because of illegal input values.
--------------------------------------------------------------------------------

End of Tests.
================================================================================
```

== Chasis con mediciones de consumo

Se realizó una ejecución de HPL con configuración similar a la anterior pero limitada a los cuatro nodos de cómputo de un mismo chasis, con registro del consumo durante la ejecución.

La telemetría de potencia se tomó de `hpl-4n/4n.csv` y se alineó con las marcas de HPL entre #power.interval_start y #power.interval_end. En ese intervalo hay #power.samples muestras de `SYS_POWER`; la integración por trapecios cubre #power.duration_integrated_s s y entrega #fmt(power.energy_kwh, digits: 3) kWh.

#figure(
  image("figures/power_timeseries.svg", width: 100%),
  caption: [Potencia del chasis durante la corrida HPL de 4 nodos.],
)

#table(
  columns: (1.9fr, 1fr),
  align: (left, right),
  [*Métrica*], [*Valor*],
  [Potencia media], [#kw(power.sys_power_avg_w)],
  [Potencia mediana], [#kw(power.sys_power_median_w)],
  [Percentil 5], [#kw(power.sys_power_p05_w)],
  [Percentil 95], [#kw(power.sys_power_p95_w)],
  [Potencia máxima], [#kw(power.sys_power_max_w)],
  [Energía integrada], [#fmt(power.energy_kwh, digits: 3) kWh],
  [Eficiencia energética HPL], [#fmt(power.efficiency_gflops_per_w, digits: 2) GFLOP/s/W],
)

La potencia mínima registrada dentro del intervalo fue #kw(power.sys_power_min_w), asociada a la muestra de #power.outliers.at(0).timestamp. Esa muestra ocurre al final de la corrida y se considera un outlier de transición, por lo que la mediana y los percentiles describen mejor el régimen sostenido. También aparecen valores `no` en mediciones de potencia por nodo: 9 en nodo 1, 13 en nodo 2, 11 en nodo 3 y 17 en nodo 4.

#table(
  columns: (0.8fr, 1fr, 1fr, 1fr),
  align: (left, right, right, right),
  [*Nodo*], [*Potencia media*], [*Temp. media*], [*Temp. máxima*],
  [ND01],
  [#kw(power.node_stats.node_1.power_avg_w)],
  [#fmt(power.node_stats.node_1.temp_avg_c, digits: 1) °C],
  [#fmt(power.node_stats.node_1.temp_max_c, digits: 0) °C],

  [ND02],
  [#kw(power.node_stats.node_2.power_avg_w)],
  [#fmt(power.node_stats.node_2.temp_avg_c, digits: 1) °C],
  [#fmt(power.node_stats.node_2.temp_max_c, digits: 0) °C],

  [ND03],
  [#kw(power.node_stats.node_3.power_avg_w)],
  [#fmt(power.node_stats.node_3.temp_avg_c, digits: 1) °C],
  [#fmt(power.node_stats.node_3.temp_max_c, digits: 0) °C],

  [ND04],
  [#kw(power.node_stats.node_4.power_avg_w)],
  [#fmt(power.node_stats.node_4.temp_avg_c, digits: 1) °C],
  [#fmt(power.node_stats.node_4.temp_max_c, digits: 0) °C],
)

== Nodo GPU

La corrida GPU utilizó el nodo con 8 NVIDIA A100-SXM4-40GB. La versión de HPL elegida fue NVIDIA HPL 26.02 que se distribuye en el container NVIDIA HPC-Benchmarks 26.02. El container fue lanzado en el cluster utilizando Apptainer, con un rank MPI por GPU, 32 hilos por rank y `HPL_USE_NVSHMEM=0`.

El barrido HPL-NVIDIA evaluó ocho tamaños de problema. El mejor resultado fue el primer caso válido, N=#gpu.n, con #tf(gpu.tflops) agregados y #tf(gpu.per_gpu_gflops / 1000) por GPU. La corrida de mayor tamaño de problema, N=#sweep.at(7).n, alcanzó #tf(sweep.at(7).tflops), por lo que el rango completo se mantuvo entre #tf(sweep.at(6).tflops) y #tf(gpu.tflops).

#figure(
  image("figures/gpu_sweep.svg", width: 100%),
  caption: [Rendimiento HPL-NVIDIA observado en el barrido de tamaños de problema.],
)

#table(
  columns: (0.9fr, 0.8fr, 0.9fr, 0.9fr, 1fr),
  align: (right, right, right, right, right),
  [*N*], [*NB*], [*Tiempo (s)*], [*Rmax*], [*Por GPU*],
  [#sweep.at(0).n],
  [#sweep.at(0).nb],
  [#fmt(sweep.at(0).time_s, digits: 2)],
  [#tf(sweep.at(0).tflops)],
  [#tf(sweep.at(0).per_gpu_tflops)],

  [#sweep.at(1).n],
  [#sweep.at(1).nb],
  [#fmt(sweep.at(1).time_s, digits: 2)],
  [#tf(sweep.at(1).tflops)],
  [#tf(sweep.at(1).per_gpu_tflops)],

  [#sweep.at(2).n],
  [#sweep.at(2).nb],
  [#fmt(sweep.at(2).time_s, digits: 2)],
  [#tf(sweep.at(2).tflops)],
  [#tf(sweep.at(2).per_gpu_tflops)],

  [#sweep.at(3).n],
  [#sweep.at(3).nb],
  [#fmt(sweep.at(3).time_s, digits: 2)],
  [#tf(sweep.at(3).tflops)],
  [#tf(sweep.at(3).per_gpu_tflops)],

  [#sweep.at(4).n],
  [#sweep.at(4).nb],
  [#fmt(sweep.at(4).time_s, digits: 2)],
  [#tf(sweep.at(4).tflops)],
  [#tf(sweep.at(4).per_gpu_tflops)],

  [#sweep.at(5).n],
  [#sweep.at(5).nb],
  [#fmt(sweep.at(5).time_s, digits: 2)],
  [#tf(sweep.at(5).tflops)],
  [#tf(sweep.at(5).per_gpu_tflops)],

  [#sweep.at(6).n],
  [#sweep.at(6).nb],
  [#fmt(sweep.at(6).time_s, digits: 2)],
  [#tf(sweep.at(6).tflops)],
  [#tf(sweep.at(6).per_gpu_tflops)],

  [#sweep.at(7).n],
  [#sweep.at(7).nb],
  [#fmt(sweep.at(7).time_s, digits: 2)],
  [#tf(sweep.at(7).tflops)],
  [#tf(sweep.at(7).per_gpu_tflops)],
)

La eficiencia del mejor caso GPU frente al Rpeak FP64 Tensor Core estimado para 8 A100 fue #pct(gpu.efficiency_pct). Esta comparación debe leerse como referencia de techo teórico, no como potencia eléctrica ni como límite garantizado de aplicación real.


= Plataforma y metodología

Las corridas CPU utilizaron nodos con dos procesadores AMD EPYC 9754 por nodo. Cada procesador aporta 128 núcleos, por lo que cada nodo CPU tiene 256 núcleos físicos. Los scripts Slurm lanzaron 8 tareas MPI por nodo y 32 hilos OpenMP por tarea, usando `gnu15`, `openmpi5`, `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`, `OPENBLAS_NUM_THREADS=$SLURM_CPUS_PER_TASK`, `OMP_PROC_BIND=true` y `OMP_PLACES=cores`.


El cálculo de Rpeak sigue el criterio solicitado de comparación con TOP500. Para CPU se usa una constante de #fmt(rpeak.cpu_gflops_per_core, digits: 2) GFLOP/s por núcleo, derivada de entradas TOP500 con EPYC 9654, y se escala por el número de núcleos de los EPYC 9754 medidos. Para GPU se usa el pico FP64 Tensor Core publicado para A100: #fmt(rpeak.gpu_a100_fp64_tensor_tflops, digits: 1) TFLOP/s por GPU.

#table(
  columns: (1.8fr, 0.7fr, 0.8fr, 0.8fr, 0.8fr, 1fr, 0.9fr),
  align: (left, right, right, right, right, right, right),
  [*Escenario*], [*Nodos*], [*MPI*], [*N*], [*NB*], [*Tiempo*], [*Estado*],
  [CPU 4 nodos],
  [#cpu4.nodes],
  [#cpu4.ranks],
  [#cpu4.n],
  [#cpu4.nb],
  [#seconds_to_min(cpu4.time_s)],
  [#cpu4.residual_status],

  [CPU 12 nodos],
  [#cpu12.nodes],
  [#cpu12.ranks],
  [#cpu12.n],
  [#cpu12.nb],
  [#seconds_to_min(cpu12.time_s)],
  [#cpu12.residual_status],

  [GPU 8x A100], [#gpu.nodes], [#gpu.ranks], [#gpu.n], [#gpu.nb], [#seconds_to_min(gpu.time_s)], [#gpu.residual_status],
)

= Resultados HPL CPU

La medición de 4 nodos reportó #tf(cpu4.tflops) con N=#cpu4.n, matriz de #ti(cpu4.matrix_memory_gib), malla `P x Q` = #cpu4.p x #cpu4.q y residual #fmt(cpu4.residual, digits: 6). La eficiencia frente al Rpeak estimado fue #pct(cpu4.efficiency_pct).

La medición de 12 nodos reportó #tf(cpu12.tflops) con N=#cpu12.n, matriz de #ti(cpu12.matrix_memory_gib), malla `P x Q` = #cpu12.p x #cpu12.q y residual #fmt(cpu12.residual, digits: 6). La eficiencia frente al Rpeak estimado fue #pct(cpu12.efficiency_pct).

#table(
  columns: (1.7fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  align: (left, right, right, right, right, right),
  [*Corrida*], [*Rmax*], [*Por nodo*], [*Rpeak est.*], [*Eficiencia*], [*Memoria matriz*],
  [CPU 4 nodos],
  [#tf(cpu4.tflops)],
  [#tf(cpu4.per_node_tflops)],
  [#tf(cpu4.rpeak_tflops)],
  [#pct(cpu4.efficiency_pct)],
  [#ti(cpu4.matrix_memory_gib)],

  [CPU 12 nodos],
  [#tf(cpu12.tflops)],
  [#tf(cpu12.per_node_tflops)],
  [#tf(cpu12.rpeak_tflops)],
  [#pct(cpu12.efficiency_pct)],
  [#ti(cpu12.matrix_memory_gib)],
)

La diferencia por nodo entre ambas corridas es menor al redondeo operativo: #tf(cpu4.per_node_tflops) por nodo en 4 nodos y #tf(cpu12.per_node_tflops) por nodo en 12 nodos. Esto indica que, para estos tamaños de problema y parámetros HPL, el rendimiento agregado aumentó proporcionalmente con el número de nodos CPU utilizados.

= Resultados HPL-NVIDIA

= Consumo del chasis de 4 nodos



= Conclusiones

Los resultados CPU muestran una eficiencia HPL consistente al pasar de 4 a 12 nodos, con #pct(cpu4.efficiency_pct) y #pct(cpu12.efficiency_pct) del Rpeak estimado respectivamente. La similitud del rendimiento por nodo sugiere que la configuración de MPI/OpenMP, el tamaño de problema y la red fueron adecuados para sostener escalamiento en la porción medida del cluster.

El nodo GPU con 8 A100 alcanza un Rmax comparable al resultado CPU de 12 nodos, aunque con una ejecución mucho más breve para el tamaño de problema seleccionado. El mejor valor observado fue #tf(gpu.tflops), mientras que la corrida de mayor `N` mantuvo #tf(sweep.at(7).tflops). Para reportes de capacidad, conviene citar el mejor resultado válido y acompañarlo con la tabla completa del barrido.

La medición eléctrica del chasis de 4 nodos indica una potencia sostenida cercana a 5 kW durante HPL y una eficiencia energética de #fmt(power.efficiency_gflops_per_w, digits: 2) GFLOP/s/W para esa corrida. Esta métrica sólo aplica al chasis medido y no debe extrapolarse automáticamente a la corrida de 12 nodos sin telemetría equivalente.


= Fuentes externas para Rpeak

- TOP500 June 2025: #link("https://top500.org/lists/top500/list/2025/06/?page=2")[Rmax/Rpeak y criterio de clock anunciado para CPU].
- TOP500 CATT EPYC 9654: #link("https://top500.org/system/180324/")[entrada usada como referencia EPYC 9654].
- AMD EPYC 9754: #link("https://www.amd.com/en/products/processors/server/epyc/4th-generation-9004-and-8004-series/amd-epyc-9754.html")[especificaciones de núcleos y frecuencia].
- NVIDIA A100: #link("https://www.nvidia.com/en-eu/data-center/a100/")[pico FP64 Tensor Core por GPU].
