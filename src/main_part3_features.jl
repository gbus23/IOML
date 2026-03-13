# Partie 3 : features dérivées (ratios, diff, produits) par gain Gini
include("building_tree.jl")
include("utilities.jl")
include("feature_engineering.jl")
using DelimitedFiles

"""
Normalise les colonnes de X avec les min/max fournis (ex. calculés sur l'entraînement).
X peut être train ou test ; pour les colonnes où max_j == min_j, on laisse la colonne inchangée (ou à 0).
"""
function normalize_with_bounds(X::Matrix{Float64}, min_vec::Vector{Float64}, max_vec::Vector{Float64})
    Xn = copy(X)
    for j in 1:size(X, 2)
        r = max_vec[j] - min_vec[j]
        if r > 1e-12
            Xn[:, j] .= (X[:, j] .- min_vec[j]) ./ r
        else
            Xn[:, j] .= 0.0
        end
    end
    return Xn
end

"""
Lance les expériences Partie 3 : avec/sans features dérivées (ratios, différences, produits).
- datasets : noms des jeux (iris, seeds, wine)
- depths : profondeurs d'arbre à tester
- k_features : nombre de nouvelles features à ajouter (sélectionnées par gain de Gini)
Mesure : nombre d'erreurs (train/test), temps de résolution, objectif, taille d'arbre (fixe = 2^D - 1 nœuds).
"""
function run_part3(; time_limit_sec::Int=60, datasets::Vector{String}=["iris", "seeds", "wine", "glass", "ecoli"], depths::Vector{Int}=[2, 3], k_features::Int=5, save_results::Union{String,Nothing}=nothing)
    headers = ["dataset", "depth", "n_train", "n_test", "n_features_orig", "n_features_aug", "k_added", "config", "time_sec", "gap_pct", "objective", "tree_n_splits", "err_train", "err_test"]
    rows = Vector{Vector{Any}}(undef, 0)

    for dataSetName in datasets
        data_path = abspath(joinpath(@__DIR__, "..", "data", dataSetName * ".txt"))
        isfile(data_path) || continue
        include(data_path)
        X = Main.eval(:X)
        Y = Main.eval(:Y)

        X_full = Matrix{Float64}(X)
        for j in 1:size(X_full, 2)
            mj, Mj = minimum(X_full[:, j]), maximum(X_full[:, j])
            X_full[:, j] .= (X_full[:, j] .- mj) ./ (Mj > mj ? (Mj - mj) : 1.0)
        end

        train, test = train_test_indexes(length(Y))
        X_train = X_full[train, :]
        Y_train = Y[train]
        X_test = X_full[test, :]
        Y_test = Y[test]
        classes = unique(Y)
        n_train = size(X_train, 1)
        n_test = size(X_test, 1)
        n_features_orig = size(X_train, 2)

        println("=== Dataset ", dataSetName, " (n_train=", n_train, ", n_test=", n_test, ", features=", n_features_orig, ") k_added=", k_features)

        for D in depths
            println("  --- D = ", D, " ---")
            print("    Sans nouvelles features : ")
            T_orig, obj_orig, t_orig, gap_orig, _, _ = build_tree(X_train, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true)
            err_orig_train = T_orig !== nothing ? prediction_errors(T_orig, X_train, Y_train, classes) : -1
            err_orig_test  = T_orig !== nothing ? prediction_errors(T_orig, X_test,  Y_test,  classes) : -1
            n_splits = 2^D - 1
            println(round(t_orig, digits=2), " s, objectif ", obj_orig, ", err train/test ", err_orig_train, "/", err_orig_test)
            push!(rows, [dataSetName, D, n_train, n_test, n_features_orig, n_features_orig, 0, "sans_nouvelles_features", round(t_orig, digits=4), round(gap_orig, digits=4), obj_orig, n_splits, err_orig_train, err_orig_test])
        end

        X_train_aug, recipes, selected_indices = augment_dataset(X_train, Y_train, classes; k=k_features)
        X_test_aug = apply_augmentation(X_test, recipes, selected_indices)
        k_added = length(selected_indices)
        n_features_aug = n_features_orig + k_added

        min_aug = [minimum(X_train_aug[:, j]) for j in 1:size(X_train_aug, 2)]
        max_aug = [maximum(X_train_aug[:, j]) for j in 1:size(X_train_aug, 2)]
        X_train_aug_norm = normalize_with_bounds(X_train_aug, min_aug, max_aug)
        X_test_aug_norm = normalize_with_bounds(X_test_aug, min_aug, max_aug)

        for D in depths
            print("    Avec ", k_added, " nouvelles features (D=", D, ") : ")
            T_aug, obj_aug, t_aug, gap_aug, _, _ = build_tree(X_train_aug_norm, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true)
            err_aug_train = T_aug !== nothing ? prediction_errors(T_aug, X_train_aug_norm, Y_train, classes) : -1
            err_aug_test  = T_aug !== nothing ? prediction_errors(T_aug, X_test_aug_norm,  Y_test,  classes) : -1
            n_splits = 2^D - 1
            println(round(t_aug, digits=2), " s, objectif ", obj_aug, ", err train/test ", err_aug_train, "/", err_aug_test)
            push!(rows, [dataSetName, D, n_train, n_test, n_features_orig, n_features_aug, k_added, "avec_nouvelles_features", round(t_aug, digits=4), round(gap_aug, digits=4), obj_aug, n_splits, err_aug_train, err_aug_test])
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
        println("Résultats Partie 3 enregistrés dans : ", out_path)
    end

    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_part3(time_limit_sec=60, save_results="results/part3_results.csv", k_features=5)
end
