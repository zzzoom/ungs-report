#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --job-name=nv-hpl-a100x8
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=32
#SBATCH --exclusive
#SBATCH --time=01:00:00
#SBATCH --output=nv-hpl-%j.out
#SBATCH --error=nv-hpl-%j.err

set -euo pipefail

# Adjust these for your site
IMAGE="${IMAGE:-$PWD/hpc-benchmarks_26.02.sif}"
WORKDIR="${SLURM_SUBMIT_DIR:-$PWD}"
DAT="${WORKDIR}/HPL.dat"

nvidia-smi -L

# Generic 8-rank layout:
# - 8 MPI ranks
# - 1 GPU per rank
# - 2 x 4 process grid
#
GPU_AFFINITY="0:1:2:3:4:5:6:7"
MEM_AFFINITY="0:0:0:0:1:1:1:1"
CPU_AFFINITY="0-31:32-63:64-95:96-127:128-159:160-191:192-223:224-255"

export OMP_NUM_THREADS=1
export HPL_USE_NVSHMEM=0   # safer default for simple single-node runs

srun --mpi=pmix --cpu-bind=none --mem-bind=none \
    singularity run --nv -B "$WORKDIR:$WORKDIR" "$IMAGE" /workspace/hpl.sh --dat "$DAT" --no-multinode
#    --gpu-affinity "$GPU_AFFINITY" --cpu-affinity "$CPU_AFFINITY" --mem-affinity "$MEM_AFFINITY"
