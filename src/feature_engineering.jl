# Partie 3 : features dérivées (ratio, diff, produit)

"""
Impureté de Gini pour un nœud : G(p) = 1 - sum_k p_k^2, où p_k est la proportion de la classe k.
"""
function gini_impurity(y::Vector{Any}, classes::Vector{Any})
    n = length(y)
    n == 0 && return 0.0
    p = zeros(length(classes))
    for i in 1:n
        k = findfirst(isequal(y[i]), classes)
        k !== nothing && (p[k] += 1.0)
    end
    p ./= n
    1.0 - sum(p.^2)
end

"""
Pour une feature continue (vecteur) et les labels, trouve le meilleur seuil (parmi les midpoints
entre valeurs consécutives triées) qui maximise le gain de Gini pour un split binaire.
Retourne (gain, seuil) ou (0.0, NaN) si pas de split valide.
"""
function best_single_split_gain(x::Vector{Float64}, y::Vector{Any}, classes::Vector{Any})
    n = length(y)
    n <= 1 && return (0.0, NaN)
    perm = sortperm(x)
    x_sorted = x[perm]
    y_sorted = y[perm]
    G_parent = gini_impurity(y, classes)
    best_gain = 0.0
    best_thresh = NaN
    # Seuils = midpoints
    for i in 1:(n-1)
        x_sorted[i] == x_sorted[i+1] && continue
        thresh = (x_sorted[i] + x_sorted[i+1]) / 2.0
        left = y_sorted[1:i]
        right = y_sorted[(i+1):n]
        n_l = length(left)
        n_r = length(right)
        G_l = gini_impurity(left, classes)
        G_r = gini_impurity(right, classes)
        gain = G_parent - (n_l / n) * G_l - (n_r / n) * G_r
        if gain > best_gain
            best_gain = gain
            best_thresh = thresh
        end
    end
    return (best_gain, best_thresh)
end

const EPS = 1e-8

# Recettes : (:ratio,i,j), (:diff,i,j), (:product,i,j), (:circle,i,j,cx,cy,r)
const RecipeAlg = Tuple{Symbol,Int,Int}
const RecipeCircle = Tuple{Symbol,Int,Int,Float64,Float64,Float64}
const Recipe = Union{RecipeAlg, RecipeCircle}

"""
Calcule une colonne candidate à partir de X et d'une recette.
Algébrique (type, i, j) : :ratio, :diff, :product.
Cercle (type, i, j, cx, cy, r) : binaire 1 si (x_i - cx)^2 + (x_j - cy)^2 <= r^2, 0 sinon.
"""
function compute_candidate_column(X::Matrix{Float64}, recipe::Recipe)
    n = size(X, 1)
    if length(recipe) == 3
        typ, i, j = recipe
        if typ == :ratio
            return X[:, i] ./ (X[:, j] .+ EPS)
        elseif typ == :diff
            return X[:, i] .- X[:, j]
        elseif typ == :product
            return X[:, i] .* X[:, j]
        end
        return zeros(n)
    else
        _, i, j, cx, cy, r = recipe
        r2 = r * r
        col = zeros(n)
        for idx in 1:n
            d2 = (X[idx, i] - cx)^2 + (X[idx, j] - cy)^2
            col[idx] = d2 <= r2 ? 1.0 : 0.0
        end
        return col
    end
end

"""
Génère les recettes algébriques pour nf features : ratios, diffs, products pour i != j.
"""
function generate_algebraic_recipes(nf::Int)
    recipes = Recipe[]
    for i in 1:nf
        for j in 1:nf
            i == j && continue
            push!(recipes, (:ratio, i, j))
            push!(recipes, (:diff, i, j))
            push!(recipes, (:product, i, j))
        end
    end
    return recipes
end

"""
Pour une paire de features (i, j) et une classe k, calcule le centroïde des points de classe k
et le rayon = max des distances des points de classe k au centroïde (ou 0 si un seul point).
Retourne (cx, cy, radius).
"""
function _circle_params(X::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any}, feat_i::Int, feat_j::Int, class_idx::Int)
    idxs = [idx for idx in 1:length(y) if findfirst(isequal(y[idx]), classes) == class_idx]
    nk = length(idxs)
    if nk == 0
        return (0.0, 0.0, 0.0)
    end
    cx = sum(X[idx, feat_i] for idx in idxs) / nk
    cy = sum(X[idx, feat_j] for idx in idxs) / nk
    r = 0.0
    for idx in idxs
        d = sqrt((X[idx, feat_i] - cx)^2 + (X[idx, feat_j] - cy)^2)
        r = max(r, d)
    end
    (cx, cy, r)
end

"""
Génère les recettes "cercle" : pour chaque paire (i,j) et chaque classe k, un disque (centroïde de la classe k, rayon = max distance).
Feature binaire = 1 si le point est dans le disque, 0 sinon (exemple de l'énoncé).
"""
function generate_circle_recipes(X::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any})
    nf = size(X, 2)
    recipes = Recipe[]
    for i in 1:nf
        for j in 1:nf
            i == j && continue
            for (class_idx, _) in enumerate(classes)
                cx, cy, r = _circle_params(X, y, classes, i, j, class_idx)
                push!(recipes, (:circle, i, j, cx, cy, r))
            end
        end
    end
    return recipes
end

"""
Génère les recettes algébriques uniquement (pour compatibilité).
"""
function generate_candidate_recipes(nf::Int)
    return generate_algebraic_recipes(nf)
end

"""
Génère toutes les recettes : algébriques + optionnellement cercles (binaire « dans le disque »).
Avec (X, y, classes), si include_circles=true (défaut), ajoute pour chaque paire (i,j) et chaque classe
un disque (centroïde de la classe, rayon = max distance) → feature binaire 1/0.
"""
function generate_candidate_recipes(nf::Int, X::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any}; include_circles::Bool=true)
    recipes = generate_algebraic_recipes(nf)
    if include_circles && nf >= 2
        circle_recipes = generate_circle_recipes(X, y, classes)
        append!(recipes, circle_recipes)
    end
    return recipes
end

"""
Construit la matrice des candidats (une colonne par recette) pour X.
"""
function compute_candidate_matrix(X::Matrix{Float64}, recipes::Vector{<:Tuple})
    n = size(X, 1)
    M = zeros(n, length(recipes))
    for (c, r) in enumerate(recipes)
        M[:, c] = compute_candidate_column(X, r)
    end
    return M
end

"""
Score chaque colonne candidate par le gain de Gini du meilleur split sur cette colonne.
Retourne (gains, thresholds) deux vecteurs de longueur length(recipes).
"""
function score_candidates(M::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any})
    n_cand = size(M, 2)
    gains = zeros(n_cand)
    for c in 1:n_cand
        g, _ = best_single_split_gain(M[:, c], y, classes)
        gains[c] = g
    end
    return gains
end

"""
Augmente la matrice X avec les k meilleures features candidates (sélectionnées par gain de Gini sur (X, y)).
Retourne (X_aug, recipes, selected_indices) pour pouvoir appliquer la même transformation à un autre ensemble (ex. test).
Si include_circle_features=true (défaut), les candidats incluent les features binaires « dans un disque » (exemple de l'énoncé).
"""
function augment_dataset(X::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any}; k::Int=5, include_circle_features::Bool=true)
    nf = size(X, 2)
    recipes = nf >= 2 && include_circle_features ?
        generate_candidate_recipes(nf, X, y, classes; include_circles=true) :
        generate_candidate_recipes(nf)
    M = compute_candidate_matrix(X, recipes)
    gains = score_candidates(M, y, classes)
    perm = sortperm(gains; rev=true)
    selected = perm[1:min(k, length(perm))]
    selected = [i for i in selected if gains[i] > 1e-10]
    selected = selected[1:min(k, length(selected))]
    X_aug = hcat(X, M[:, selected])
    return (X_aug, recipes, selected)
end

"""
Applique la même augmentation à une autre matrice X_other (ex. test) en utilisant les recettes et indices sélectionnés.
"""
function apply_augmentation(X_other::Matrix{Float64}, recipes::Vector{<:Tuple}, selected_indices::Vector{Int})
    M_other = compute_candidate_matrix(X_other, recipes)
    return hcat(X_other, M_other[:, selected_indices])
end
