# Partie 2 : arbres équitables (parité démographique / equal opportunity)
include("datasets_config.jl")
include("building_tree.jl")
include("utilities.jl")
include("fairness.jl")
using DelimitedFiles

"""
Construit un vecteur de groupe binaire (1 ou 2) à partir de la première colonne de X :
group[i] = 1 si X[i,1] <= médiane, 2 sinon. Utile pour tester quand on n'a pas d'attribut sensible.
Pour un vrai jeu "fairness", passer un vecteur group déjà défini (ex. genre, race) et ne pas l'inclure dans X.
"""
function synthetic_group_by_median(X::Matrix{Float64})
    m = median(X[:, 1])
    return [X[i, 1] <= m ? 1 : 2 for i in 1:size(X, 1)]
end

"""
Lance les expériences Partie 2 : avec/sans équité (parité démographique ou equal opportunity).
- datasets : noms des jeux (iris, seeds, wine) ou chemins vers des données avec groupe
- group_fn : fonction (X_train, X_test) -> (group_train, group_test). Par défaut : synthetic_group_by_median.
- fairness_type : :demographic_parity ou :equal_opportunity
- positive_class : indice 1-based de la classe "positive" (défaut 1)
- run_constraint : si true, lance une config avec contrainte stricte
- run_penalty : si true, lance une config avec pénalité (fairness_penalty)
- penalty_value : valeur de fairness_penalty si run_penalty (défaut 80.0 pour avoir un effet visible)
- fairness_tolerance : si > 0 et run_constraint, lance aussi une config avec contrainte assouplie |taux_A - taux_B| <= tolerance (défaut 0.15)
"""
function run_part2(; time_limit_sec::Int=DEFAULT_TIME_LIMIT_PARTS, datasets::Vector{String}=copy(DEFAULT_DATASETS), depths::Vector{Int}=[2, 3], fairness_type::Symbol=:demographic_parity, positive_class::Int=1, run_constraint::Bool=true, run_penalty::Bool=true, penalty_value::Float64=80.0, fairness_tolerance::Float64=0.15, save_results::Union{String,Nothing}=nothing)
    headers = ["dataset", "depth", "n_train", "n_test", "config", "time_sec", "gap_pct", "objective", "err_train", "err_test", "parity_gap", "eq_opp_gap"]
    rows = Vector{Vector{Any}}(undef, 0)

    for dataSetName in datasets
        data_path = abspath(joinpath(@__DIR__, "..", "data", dataSetName * ".txt"))
        isfile(data_path) || continue
        include(data_path)
        X = Main.eval(:X)
        Y = Main.eval(:Y)
        X_mat = Matrix{Float64}(X)
        for j in 1:size(X_mat, 2)
            mj, Mj = minimum(X_mat[:, j]), maximum(X_mat[:, j])
            X_mat[:, j] .= (X_mat[:, j] .- mj) ./ (Mj > mj ? (Mj - mj) : 1.0)
        end
        train, test = train_test_indexes(length(Y))
        X_train = X_mat[train, :]
        Y_train = Y[train]
        X_test = X_mat[test, :]
        Y_test = Y[test]
        classes = unique(Y)
        n_train = size(X_train, 1)
        n_test = size(X_test, 1)

        # Groupe synthétique (médiane feature 1)
        group_train = synthetic_group_by_median(X_train)
        group_test = synthetic_group_by_median(X_test)

        println("=== Dataset ", dataSetName, " (n_train=", n_train, ", n_test=", n_test, ") fairness_type=", fairness_type)

        for D in depths
            println("  --- D = ", D, " ---")

            print("    Sans équité : ")
            T0, obj0, t0, gap0, _, _ = build_tree(X_train, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true)
            err0_train = T0 !== nothing ? prediction_errors(T0, X_train, Y_train, classes) : -1
            err0_test = T0 !== nothing ? prediction_errors(T0, X_test, Y_test, classes) : -1
            dp0 = T0 !== nothing ? demographic_parity_gap(T0, X_train, classes, group_train, positive_class)[3] : NaN
            eo0 = T0 !== nothing ? equal_opportunity_gap(T0, X_train, Y_train, classes, group_train, positive_class)[3] : NaN
            println(round(t0, digits=2), " s, objectif ", obj0, ", err train/test ", err0_train, "/", err0_test, ", parity_gap=", round(dp0, digits=4))
            push!(rows, [dataSetName, D, n_train, n_test, "sans_equite", round(t0, digits=4), round(gap0, digits=4), obj0, err0_train, err0_test, round(dp0, digits=6), round(eo0, digits=6)])

            if run_constraint
                print("    Contrainte stricte ", fairness_type, " : ")
                T1, obj1, t1, gap1, _, _ = build_tree(X_train, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true, sensitive_group=group_train, positive_class=positive_class, fairness_type=fairness_type, fairness_constraint=true, fairness_tolerance=0.0)
                err1_train = T1 !== nothing ? prediction_errors(T1, X_train, Y_train, classes) : -1
                err1_test = T1 !== nothing ? prediction_errors(T1, X_test, Y_test, classes) : -1
                dp1 = T1 !== nothing ? demographic_parity_gap(T1, X_train, classes, group_train, positive_class)[3] : NaN
                eo1 = T1 !== nothing ? equal_opportunity_gap(T1, X_train, Y_train, classes, group_train, positive_class)[3] : NaN
                println(round(t1, digits=2), " s, objectif ", obj1, ", err train/test ", err1_train, "/", err1_test, ", parity_gap=", round(dp1, digits=4))
                push!(rows, [dataSetName, D, n_train, n_test, "contrainte_stricte_$(fairness_type)", round(t1, digits=4), round(gap1, digits=4), obj1, err1_train, err1_test, round(dp1, digits=6), round(eo1, digits=6)])
            end

            if run_constraint && fairness_tolerance > 0
                print("    Contrainte tolérance ", fairness_tolerance, " ", fairness_type, " : ")
                T1b, obj1b, t1b, gap1b, _, _ = build_tree(X_train, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true, sensitive_group=group_train, positive_class=positive_class, fairness_type=fairness_type, fairness_constraint=true, fairness_tolerance=fairness_tolerance)
                err1b_train = T1b !== nothing ? prediction_errors(T1b, X_train, Y_train, classes) : -1
                err1b_test = T1b !== nothing ? prediction_errors(T1b, X_test, Y_test, classes) : -1
                dp1b = T1b !== nothing ? demographic_parity_gap(T1b, X_train, classes, group_train, positive_class)[3] : NaN
                eo1b = T1b !== nothing ? equal_opportunity_gap(T1b, X_train, Y_train, classes, group_train, positive_class)[3] : NaN
                println(round(t1b, digits=2), " s, objectif ", obj1b, ", err train/test ", err1b_train, "/", err1b_test, ", parity_gap=", round(dp1b, digits=4))
                push!(rows, [dataSetName, D, n_train, n_test, "contrainte_tolerance_$(fairness_type)", round(t1b, digits=4), round(gap1b, digits=4), obj1b, err1b_train, err1b_test, round(dp1b, digits=6), round(eo1b, digits=6)])
            end

            if run_penalty
                print("    Avec pénalité ", fairness_type, " (λ=", penalty_value, ") : ")
                T2, obj2, t2, gap2, _, _ = build_tree(X_train, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true, sensitive_group=group_train, positive_class=positive_class, fairness_type=fairness_type, fairness_penalty=penalty_value)
                err2_train = T2 !== nothing ? prediction_errors(T2, X_train, Y_train, classes) : -1
                err2_test = T2 !== nothing ? prediction_errors(T2, X_test, Y_test, classes) : -1
                dp2 = T2 !== nothing ? demographic_parity_gap(T2, X_train, classes, group_train, positive_class)[3] : NaN
                eo2 = T2 !== nothing ? equal_opportunity_gap(T2, X_train, Y_train, classes, group_train, positive_class)[3] : NaN
                println(round(t2, digits=2), " s, objectif ", obj2, ", err train/test ", err2_train, "/", err2_test, ", parity_gap=", round(dp2, digits=4))
                push!(rows, [dataSetName, D, n_train, n_test, "penalite_$(fairness_type)", round(t2, digits=4), round(gap2, digits=4), obj2, err2_train, err2_test, round(dp2, digits=6), round(eo2, digits=6)])
            end
        end
        println()
    end

    if save_results !== nothing && length(rows) > 0
        out_path = abspath(joinpath(@__DIR__, "..", save_results))
        mkpath(dirname(out_path))
        open(out_path, "w") do io
            writedlm(io, [headers], ',')
            writedlm(io, rows, ',')
        end
        println("Résultats Partie 2 enregistrés : ", out_path)
    end
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_part2(save_results="results/part2_results.csv", run_constraint=true, run_penalty=true, penalty_value=80.0, fairness_tolerance=0.15)
end
