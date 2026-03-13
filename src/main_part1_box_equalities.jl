# Partie 1 : linked sets + box corners
function run_part1(; time_limit_sec::Int=60, datasets::Vector{String}=["iris", "seeds", "wine", "glass", "ecoli"], depths::Vector{Int}=[2, 3], round_digits_list::Vector{Union{Int,Nothing}}=Union{Int,Nothing}[nothing], save_results::Union{String,Nothing}=nothing, use_box_corners_too::Bool=true)
    headers = ["dataset", "round_digits", "depth", "n_train", "n_test", "n_features", "n_equalities", "config", "time_sec", "gap_pct", "objective", "lp_value", "nodes_bb", "err_train", "err_test"]
    rows = Vector{Vector{Any}}(undef, 0)

    for dataSetName in datasets
        data_path = abspath(joinpath(@__DIR__, "..", "data", dataSetName * ".txt"))
        include(data_path)
        X = Main.eval(:X)
        Y = Main.eval(:Y)

        reducedX = Matrix{Float64}(X)
        for j in 1:size(X, 2)
            mj, Mj = minimum(X[:, j]), maximum(X[:, j])
            reducedX[:, j] .-= mj
            if Mj > mj
                reducedX[:, j] ./= (Mj - mj)
            end
        end

        train, test = train_test_indexes(length(Y))
        X_train = reducedX[train, :]
        Y_train = Y[train]
        X_test = reducedX[test, :]
        Y_test = Y[test]
        classes = unique(Y)
        n_train = size(X_train, 1)
        n_test = size(X_test, 1)
        n_features = size(X_train, 2)

        for round_digits in round_digits_list
            rd_label = round_digits === nothing ? "none" : round_digits
            X_tr = round_digits === nothing ? X_train : round.(X_train, digits=round_digits)
            X_te = round_digits === nothing ? X_test : round.(X_test, digits=round_digits)

            println("=== Dataset ", dataSetName, " round_digits=", rd_label, " (n_train=", n_train, ", n_test=", n_test, ", features=", n_features, ")")

            eq_tol = round_digits === nothing ? 1e-9 : (0.5 * 10.0^(-round_digits))
            linked_set_list = find_linked_sets(X_tr; tol=eq_tol)
            box_list = use_box_corners_too ? find_opposite_box_corner_equalities(X_tr; tol=eq_tol) : nothing
            n_linked = length(linked_set_list)
            n_box = use_box_corners_too ? length(box_list) : 0
            n_eq = n_linked + n_box
            println("  Égalités linked sets : ", n_linked, ", opposite box corners : ", n_box, " → total ", n_eq)

            for D in depths
                println("  --- D = ", D, " ---")

                print("    Sans égalités (flux unitaire) : ")
                T1, obj1, t1, gap1, lp1, nodes1 = build_tree(X_tr, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true, box_equalities=false, return_lp_node_stats=true)
                err1_train = T1 !== nothing ? prediction_errors(T1, X_tr, Y_train, classes) : -1
                err1_test  = T1 !== nothing ? prediction_errors(T1, X_te,  Y_test,  classes) : -1
                lp1_val = lp1 !== nothing ? round(lp1, digits=4) : ""
                nodes1_val = (nodes1 !== nothing && nodes1 >= 0) ? nodes1 : ""
                println(round(t1, digits=2), " s, gap ", round(gap1, digits=2), " %, objectif ", obj1, ", LP=", lp1_val, ", nœuds B&B=", nodes1_val, ", erreurs train/test ", err1_train, "/", err1_test)

                push!(rows, [dataSetName, rd_label, D, n_train, n_test, n_features, 0, "sans_egalites", round(t1, digits=4), round(gap1, digits=4), obj1, lp1_val, nodes1_val, err1_train, err1_test])

                print("    Avec égalités linked sets", (use_box_corners_too ? " + box corners" : ""), " : ")
                T2, obj2, t2, gap2, lp2, nodes2 = build_tree(X_tr, Y_train, D, classes; multivariate=false, time_limit=time_limit_sec, unitary_flow=true, linked_set_equalities=true, linked_set_list=linked_set_list, box_equalities=use_box_corners_too, box_equalities_list=box_list, return_lp_node_stats=true)
                err2_train = T2 !== nothing ? prediction_errors(T2, X_tr, Y_train, classes) : -1
                err2_test  = T2 !== nothing ? prediction_errors(T2, X_te,  Y_test,  classes) : -1
                lp2_val = lp2 !== nothing ? round(lp2, digits=4) : ""
                nodes2_val = (nodes2 !== nothing && nodes2 >= 0) ? nodes2 : ""
                println(round(t2, digits=2), " s, gap ", round(gap2, digits=2), " %, objectif ", obj2, ", LP=", lp2_val, ", nœuds B&B=", nodes2_val, ", erreurs train/test ", err2_train, "/", err2_test)

                push!(rows, [dataSetName, rd_label, D, n_train, n_test, n_features, n_eq, "avec_egalites", round(t2, digits=4), round(gap2, digits=4), obj2, lp2_val, nodes2_val, err2_train, err2_test])
            end
            println()
        end
    end

    # Sauvegarde des résultats
    if save_results !== nothing && length(rows) > 0
        out_path = abspath(joinpath(@__DIR__, "..", save_results))
        mkpath(dirname(out_path))
        open(out_path, "w") do io
            writedlm(io, [headers], ',')
            writedlm(io, rows, ',')
        end
        println("Résultats enregistrés dans : ", out_path)
    end

    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_part1(time_limit_sec=60, save_results="results/part1_results.csv")
end
