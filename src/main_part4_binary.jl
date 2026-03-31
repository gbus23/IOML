# Partie 4 : formulation binaire (5.1, 5.2 ES, 5.3 alt θ, lazy)
include("datasets_config.jl")
include("building_tree.jl")
include("binary_oct.jl")
include("utilities.jl")
using DelimitedFiles

function run_part4(;
    time_limit_sec::Int=DEFAULT_TIME_LIMIT_PARTS,
    datasets::Vector{String}=copy(DEFAULT_DATASETS),
    depths::Vector{Int}=[2, 3],
    lambda::Float64=0.0,
    save_results::Union{String,Nothing}=nothing,
)
    headers = ["dataset", "depth", "n_train", "n_test", "n_features", "config", "time_sec", "gap_pct", "objective", "err_train", "err_test"]
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
        n_features = size(X_train, 2)

        X_train_bin = binarize_threshold(X_train)
        X_test_bin = binarize_threshold(X_test)

        println("=== Dataset ", dataSetName, " (n_train=", n_train, ", n_test=", n_test, ", features=", n_features, ")")

        for D in depths
            println("  --- D = ", D, " ---")

            configs = [
                ("5.1_standard",     Dict(:use_es=>false, :theta_bound_mode=>:standard,    :use_lazy_theta=>false)),
                ("5.2_ES",           Dict(:use_es=>true,  :theta_bound_mode=>:standard,    :use_lazy_theta=>false)),
                ("5.3_alt_replace",  Dict(:use_es=>false, :theta_bound_mode=>:alternative, :use_lazy_theta=>false)),
                ("5.3_alt_both",     Dict(:use_es=>false, :theta_bound_mode=>:both,        :use_lazy_theta=>false)),
                ("5.3_lazy",         Dict(:use_es=>false, :theta_bound_mode=>:standard,    :use_lazy_theta=>true)),
                ("formulation_F",    nothing),
            ]

            for (config_name, opts) in configs
                print("    ", config_name, " : ")
                local T_res, obj_res, t_res, gap_res
                if opts === nothing
                    # Formulation F (référence)
                    T_res, obj_res, t_res, gap_res, _, _ = build_tree(X_train_bin, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true)
                else
                    T_res, obj_res, t_res, gap_res = build_tree_binary(
                        X_train_bin, Y_train, D, classes;
                        lambda=lambda, time_limit=time_limit_sec,
                        use_es=opts[:use_es],
                        theta_bound_mode=opts[:theta_bound_mode],
                        use_lazy_theta=opts[:use_lazy_theta],
                    )
                end
                err_train = T_res !== nothing ? prediction_errors(T_res, X_train_bin, Y_train, classes) : -1
                err_test  = T_res !== nothing ? prediction_errors(T_res, X_test_bin,  Y_test,  classes) : -1
                println(round(t_res, digits=2), " s, gap ", round(gap_res, digits=2), " %, obj ", round(obj_res, digits=4), ", err train/test ", err_train, "/", err_test)
                push!(rows, [dataSetName, D, n_train, n_test, n_features, config_name, round(t_res, digits=4), round(gap_res, digits=4), obj_res, err_train, err_test])
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
        println("Résultats Partie 4 enregistrés dans : ", out_path)
    end

    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_part4(save_results="results/part4_results.csv")
end
