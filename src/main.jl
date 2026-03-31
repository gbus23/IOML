include("datasets_config.jl")
include("building_tree.jl")
include("utilities.jl")

function main(; time_limit::Int=DEFAULT_TIME_LIMIT_MAIN)

    # Pour chaque jeu de données (3 + 2 comme dans le sujet)
    for dataSetName in DEFAULT_DATASETS
        data_path = abspath(joinpath(@__DIR__, "..", "data", dataSetName * ".txt"))
        isfile(data_path) || continue

        print("=== Dataset ", dataSetName)

        # Préparation des données (chemin relatif au fichier main.jl)
        include(data_path)
        # Récupération via eval pour éviter l'erreur "world age" (bindings définis par include)
        X = Main.eval(:X)
        Y = Main.eval(:Y)

        # Ramener chaque caractéristique sur [0, 1]
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

        println(" (train size ", size(X_train, 1), ", test size ", size(X_test, 1), ", ", size(X_train, 2), ", features count: ", size(X_train, 2), ")")
        println("Time limit CPLEX pour cet appel : ", time_limit, " s (IOML_TL_MAIN / main(; time_limit=…)).")

        # Pour chaque profondeur considérée
        for D in 2:4

            println("  D = ", D)

            ## 1 - Univarié (séparation sur une seule variable à la fois)
            # Création de l'arbre
            print("    Univarié...  \t")
            T, obj, resolution_time, gap = build_tree(X_train, Y_train, D,  classes, multivariate = false, time_limit = time_limit)

            # Test de la performance de l'arbre
            print(round(resolution_time, digits = 1), "s\t")
            print("gap ", round(gap, digits = 1), "%\t")
            if T != nothing
                print("Erreurs train/test ", prediction_errors(T,X_train,Y_train, classes))
                print("/", prediction_errors(T,X_test,Y_test, classes), "\t")
            end
            println()

            ## 2 - Multivarié
            print("    Multivarié...\t")
            T, obj, resolution_time, gap = build_tree(X_train, Y_train, D, classes, multivariate = true, time_limit = time_limit)
            print(round(resolution_time, digits = 1), "s\t")
            print("gap ", round(gap, digits = 1), "%\t")
            if T != nothing
                print("Erreurs train/test ", prediction_errors(T,X_train,Y_train, classes))
                print("/", prediction_errors(T,X_test,Y_test, classes), "\t")
            end
            println("\n")
        end
    end 
end
