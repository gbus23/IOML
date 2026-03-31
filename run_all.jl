# Lance tout le projet : main + parties 1–4 (CSV dans results/).
# Temps CPLEX : IOML_TL_MAIN (défaut 180 s), IOML_TL_PARTS (défaut 300 s) — voir src/datasets_config.jl
# Optionnel : IOML_RUN_CLUSTERING=1 pour enchainer main_merge() et main_iterative().
#
#   julia --project=. run_all.jl
#   IOML_RUN_CLUSTERING=1 julia --project=. run_all.jl

const _ROOT = @__DIR__

include(joinpath(_ROOT, "src", "main.jl"))
include(joinpath(_ROOT, "src", "main_part1_box_equalities.jl"))
include(joinpath(_ROOT, "src", "main_part2_fairness.jl"))
include(joinpath(_ROOT, "src", "main_part3_features.jl"))
include(joinpath(_ROOT, "src", "main_part4_binary.jl"))

function _section(title::String)
    println()
    println("="^72)
    println(" ", title)
    println("="^72)
end

function run_all_pipeline()
    cd(_ROOT) do
        _section("[1/5] main() — formulation F (DEFAULT_DATASETS, uni / multivarié, D = 2…4)")
        main()

        _section("[2/5] Partie 1 — Section 4 → results/part1_results.csv")
        run_part1(time_limit_sec=DEFAULT_TIME_LIMIT_PARTS, save_results="results/part1_results.csv")

        _section("[3/5] Partie 2 — Fairness → results/part2_results.csv")
        run_part2(time_limit_sec=DEFAULT_TIME_LIMIT_PARTS, save_results="results/part2_results.csv", run_constraint=true, run_penalty=true, penalty_value=80.0, fairness_tolerance=0.15)

        _section("[4/5] Partie 3 — Features derivees (Gini) -> results/part3_results.csv")
        run_part3(time_limit_sec=DEFAULT_TIME_LIMIT_PARTS, save_results="results/part3_results.csv", k_features=5)

        _section("[5/5] Partie 4 — Binaire 5.1–5.3 + F → results/part4_results.csv")
        run_part4(time_limit_sec=DEFAULT_TIME_LIMIT_PARTS, save_results="results/part4_results.csv")

        if get(ENV, "IOML_RUN_CLUSTERING", "0") == "1"
            _section("[+] main_merge() puis main_iterative() (FU / FhS / FeS)")
            include(joinpath(_ROOT, "src", "main_iterative_algorithm.jl"))
            main_merge()
            main_iterative()
        end

        println()
        println("="^72)
        println(" Termine. CSV : results/part1_results.csv … part4_results.csv")
        if get(ENV, "IOML_RUN_CLUSTERING", "0") != "1"
            println(" Option : IOML_RUN_CLUSTERING=1 julia --project=. run_all.jl  (merge + iterative)")
        end
        println(" Arrondi Partie 1 (optionnel) : julia --project=. run_part1_with_rounding.jl")
        println("="^72)
    end
end

run_all_pipeline()
