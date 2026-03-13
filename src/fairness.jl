# Partie 2 : parité démographique, equal opportunity

"""
Retourne la classe prédite (indice 1-based dans classes) pour l'échantillon x[i,:] par l'arbre T.
Retourne 0 si aucune feuille n'est atteinte (ne devrait pas arriver pour un arbre valide).
"""
function predicted_class_index(T, x::Matrix{Float64}, i::Int, classes::Vector)
    featuresCount = size(x, 2)
    t = 1
    for _ in 1:(T.D + 1)
        if T.c[t] != -1
            return T.c[t]
        end
        if sum(T.a[j, t] * x[i, j] for j in 1:featuresCount) - T.b[t] < 0
            t = t * 2
        else
            t = t * 2 + 1
        end
    end
    return 0
end

"""
Pour chaque échantillon, indique s'il est prédit comme classe positive (positive_class = indice dans classes).
pred_pos[i] = 1 si l'arbre prédit classes[positive_class] pour i.
"""
function predicted_positive(T, x::Matrix{Float64}, classes::Vector{Any}, positive_class::Int)
    n = size(x, 1)
    pred_pos = zeros(Int, n)
    for i in 1:n
        k = predicted_class_index(T, x, i, classes)
        pred_pos[i] = (k > 0 && k == positive_class) ? 1 : 0
    end
    return pred_pos
end

"""
Parité démographique : écart entre les taux de prédiction positive dans les deux groupes.
rate_g = (1/|g|) * sum_{i in g} pred_pos[i].
Retourne (rate_1, rate_2, |rate_1 - rate_2|). Si un groupe est vide, retourne (0, 0, 0).
"""
function demographic_parity_gap(T, x::Matrix{Float64}, classes::Vector{Any}, group::Vector{Int}, positive_class::Int)
    pred_pos = predicted_positive(T, x, classes, positive_class)
    idx1 = findall(==(1), group)
    idx2 = findall(==(2), group)
    n1 = length(idx1)
    n2 = length(idx2)
    if n1 == 0 || n2 == 0
        return (0.0, 0.0, 0.0)
    end
    rate1 = sum(pred_pos[i] for i in idx1) / n1
    rate2 = sum(pred_pos[i] for i in idx2) / n2
    return (rate1, rate2, abs(rate1 - rate2))
end

"""
Equal opportunity : écart entre les TPR (taux de vrais positifs) des deux groupes.
TPR_g = parmi les i avec y_i = classe positive et group[i] = g, proportion prédite positive.
Retourne (tpr_1, tpr_2, |tpr_1 - tpr_2|). Si un groupe n'a aucun vrai positif, on utilise 0.
"""
function equal_opportunity_gap(T, x::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any}, group::Vector{Int}, positive_class::Int)
    pred_pos = predicted_positive(T, x, classes, positive_class)
    pos_label = classes[positive_class]
    idx1 = findall(i -> group[i] == 1 && y[i] == pos_label, 1:length(y))
    idx2 = findall(i -> group[i] == 2 && y[i] == pos_label, 1:length(y))
    n1 = length(idx1)
    n2 = length(idx2)
    tpr1 = n1 > 0 ? sum(pred_pos[i] for i in idx1) / n1 : 0.0
    tpr2 = n2 > 0 ? sum(pred_pos[i] for i in idx2) / n2 : 0.0
    return (tpr1, tpr2, abs(tpr1 - tpr2))
end
