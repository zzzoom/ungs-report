#!/bin/bash
#SBATCH --partition=batch
#SBATCH --nodes=12
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=32
#SBATCH --time=2-00:00:00

. /etc/profile

module load gnu15
module load openmpi5

export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export OMP_PROC_BIND=true
export OMP_PLACES=cores

srun --cpu-bind=ldoms,verbose xhpl --progress --timing --file 12nodes.dat
