# likwid-perfctr -c 0-7 -g MEM_DP -m likwid-pin -s 0xfffffffffffff801 -c 0-7 julia --project=. --math-mode=fast -t8 bwbench_likwid.jl
# likwid-perfctr -c S1:0-7 -g MEM_DP -m likwid-pin -s 0xfffffffffffff801 -c S1:0-7 julia --project=. --math-mode=fast -t8 bwbench_likwid.jl
JULIA_EXCLUSIVE=1 likwid-perfctr -c 0-7 -g MEM_DP -m julia --project=. --math-mode=fast -t8 bwbench_likwid.jl