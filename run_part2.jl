# Partie 2
include("src/main_part2_fairness.jl")
run_part2(time_limit_sec=60, save_results="results/part2_results.csv", run_constraint=true, run_penalty=true, penalty_value=80.0, fairness_tolerance=0.15)
