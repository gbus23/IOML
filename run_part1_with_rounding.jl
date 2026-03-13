# Partie 1 avec arrondi (1 ou 2 décimales)
include("src/main_part1_box_equalities.jl")
run_part1(time_limit_sec=60, round_digits_list=[nothing, 1, 2], save_results="results/part1_results_v3.csv")
