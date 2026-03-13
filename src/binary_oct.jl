# Partie 4 : formulation binaire (2a)-(2i), ES (5.2), borne alt. θ + lazy (5.3)
using JuMP
using CPLEX
using Statistics

include("struct/tree.jl")

# Binarisation

"""
Binarise X par seuil médian par colonne : x_bin[i,j] = 1 si x[i,j] >= median(X[:,j]), 0 sinon.
"""
function binarize_threshold(X::Matrix{Float64})
    Xb = zeros(size(X))
    for j in 1:size(X, 2)
        m = median(X[:, j])
        for i in 1:size(X, 1)
            Xb[i, j] = X[i, j] >= m ? 1.0 : 0.0
        end
    end
    return Xb
end

# Utilitaires arbre

function get_ancestors(n::Int)
    A = Int[]
    k = n
    while k > 1
        k = k ÷ 2
        push!(A, k)
    end
    return A
end

"""
AL(n) = ancêtres dont le fils GAUCHE est sur le chemin racine→n  (gauche = x_f=0).
AR(n) = ancêtres dont le fils DROIT  est sur le chemin racine→n  (droit  = x_f=1).
"""
function get_AL_AR(n::Int)
    AL, AR = Int[], Int[]
    k = n
    while k > 1
        parent = k ÷ 2
        if k % 2 == 0   # k = enfant gauche
            push!(AL, parent)
        else             # k = enfant droit
            push!(AR, parent)
        end
        k = parent
    end
    return (AL, AR)
end

# Equivalent Sets (ES)

"""
Trouve les Equivalent Sets (ES) maximaux avec |J̄| ≥ 2.
Un ES pour J̄ ⊆ J est un sous-ensemble maximal Ī ⊆ I tel que :
  - tous les échantillons de Ī ont la même valeur sur toutes les features de J̄
  - ils n'ont pas tous la même classe.
Retourne une liste de tuples (Ī::Vector{Int}, J̄::Vector{Int}).
"""
function find_maximal_es(x::Matrix{Float64}, y::Vector{Any}; min_jbar_size::Int=2)
    n_samples, n_features = size(x)
    es_list = Tuple{Vector{Int}, Vector{Int}}[]
    
    # D'abord J̄ = toutes les features
    all_features = collect(1:n_features)
    groups_full = _group_by_features(x, all_features)
    for (_, idxs) in groups_full
        if length(idxs) >= 2 && !_same_class(y, idxs)
            push!(es_list, (idxs, copy(all_features)))
        end
    end
    
    # Puis paires de features
    if n_features > 2
        for j1 in 1:n_features
            for j2 in (j1+1):n_features
                jbar = [j1, j2]
                groups = _group_by_features(x, jbar)
                for (_, idxs) in groups
                    if length(idxs) >= 2 && !_same_class(y, idxs)
                        if !_is_subset_of_existing(idxs, es_list)
                            push!(es_list, (idxs, jbar))
                        end
                    end
                end
            end
        end
    end
    
    return es_list
end

function _group_by_features(x::Matrix{Float64}, features::Vector{Int})
    groups = Dict{Vector{Float64}, Vector{Int}}()
    for i in 1:size(x, 1)
        key = [x[i, f] for f in features]
        if haskey(groups, key)
            push!(groups[key], i)
        else
            groups[key] = [i]
        end
    end
    return groups
end

function _same_class(y::Vector{Any}, idxs::Vector{Int})
    c0 = y[idxs[1]]
    return all(y[i] == c0 for i in idxs)
end

function _is_subset_of_existing(idxs::Vector{Int}, es_list::Vector{Tuple{Vector{Int}, Vector{Int}}})
    s = Set(idxs)
    for (existing_idxs, _) in es_list
        if s ⊆ Set(existing_idxs)
            return true
        end
    end
    return false
end

# Formulation (2a)-(2i)

"""
build_tree_binary : formulation Section 5.1 pour données binaires.

Options supplémentaires :
- use_es : si true, ajoute le renforcement Section 5.2 (Equivalent Sets)
- theta_bound_mode : :standard (2d+2e), :alternative (5 remplace 2d), :both (2d+2e + 5)
- use_lazy_theta : si true, contraintes (2d)/(2e)/(5) ajoutées en lazy callback au lieu d'être posées d'emblée
"""
function build_tree_binary(
    x::Matrix{Float64},
    y::Vector{Any},
    D::Int64,
    classes;
    lambda::Float64=0.0,
    time_limit::Int=-1,
    use_es::Bool=false,
    theta_bound_mode::Symbol=:standard,   # :standard, :alternative, :both
    use_lazy_theta::Bool=false,
)
    n_samples = size(x, 1)
    n_features = size(x, 2)
    n_classes = length(classes)
    sepCount = 2^D - 1
    leavesCount = 2^D
    allNodes = 1:(sepCount + leavesCount)
    N_nodes = 1:sepCount
    L_nodes = (sepCount + 1):(sepCount + leavesCount)

    class_to_idx = Dict(c => k for (k, c) in enumerate(classes))
    y_idx = [class_to_idx[y[i]] for i in 1:n_samples]

    model = Model(CPLEX.Optimizer)
    set_silent(model)
    if time_limit >= 0
        set_time_limit_sec(model, Float64(time_limit))
    end

    # ── Variables ──
    @variable(model, b[1:sepCount, 1:n_features], Bin)
    @variable(model, p[1:(sepCount+leavesCount)], Bin)
    @variable(model, w[1:(sepCount+leavesCount), 1:n_classes], Bin)
    @variable(model, theta[1:n_samples], Bin)

    # (2b) Structure arbre
    for n in N_nodes
        A_n = get_ancestors(n)
        @constraint(model, sum(b[n, f] for f in 1:n_features) + p[n] + sum(p[na] for na in A_n; init=0) == 1)
    end

    # (2c) Prédiction classe
    for n in allNodes
        @constraint(model, sum(w[n, k] for k in 1:n_classes) == p[n])
    end

    # Feuilles structurelles
    for n in L_nodes
        A_n = get_ancestors(n)
        @constraint(model, p[n] + sum(p[na] for na in A_n; init=0) == 1)
    end

    # Contraintes θ (2d, 2e, 5)

    if !use_lazy_theta
        L_set = Set(L_nodes)
        leaf_parent_set = Set(n for n in N_nodes if (2n in L_set) || (2n+1 in L_set))
        non_leaf_parent_N = [n for n in N_nodes if !(n in leaf_parent_set)]

        if theta_bound_mode == :standard
            _add_theta_2d!(model, b, p, w, theta, x, y_idx, N_nodes, n_samples, n_features)
            _add_theta_2e!(model, b, w, theta, x, y_idx, L_nodes, n_samples, n_features)
        elseif theta_bound_mode == :alternative
            _add_theta_2d!(model, b, p, w, theta, x, y_idx, non_leaf_parent_N, n_samples, n_features)
            _add_theta_2e!(model, b, w, theta, x, y_idx, L_nodes, n_samples, n_features)
            _add_theta_alternative!(model, b, p, w, theta, x, y_idx, N_nodes, L_nodes, n_samples, n_features, sepCount)
        elseif theta_bound_mode == :both
            _add_theta_2d!(model, b, p, w, theta, x, y_idx, N_nodes, n_samples, n_features)
            _add_theta_2e!(model, b, w, theta, x, y_idx, L_nodes, n_samples, n_features)
            _add_theta_alternative!(model, b, p, w, theta, x, y_idx, N_nodes, L_nodes, n_samples, n_features, sepCount)
        end
    end

    # ES (5.2)
    if use_es
        es_list = find_maximal_es(x, y)
        _add_es_constraints!(model, b, p, w, theta, x, y, y_idx, classes, class_to_idx, es_list, N_nodes, L_nodes, n_features, n_classes, sepCount)
    end

    # Objectif (2a)
    @objective(model, Max, (1.0 / n_samples) * sum(theta[i] for i in 1:n_samples) - lambda * sum(p[n] for n in allNodes))

    # ── Lazy callback (Section 5.3 Q8) ──
    if use_lazy_theta
        _setup_lazy_theta_callback!(model, b, p, w, theta, x, y_idx, N_nodes, L_nodes, n_samples, n_features, sepCount, theta_bound_mode)
    end

    optimize!(model)
    status = termination_status(model)
    obj_val = has_values(model) ? objective_value(model) : NaN
    t_sec = solve_time(model)
    gap_pct = -1.0
    if has_values(model)
        bound = objective_bound(model)
        gap_pct = 100.0 * abs(obj_val - bound) / (abs(obj_val) + 1e-4)
    end

    if !has_values(model)
        return (nothing, obj_val, t_sec, gap_pct)
    end

    # Extraction arbre
    a_mat = zeros(Float64, n_features, sepCount)
    b_vec = zeros(Float64, sepCount)
    c_vec = fill(-1, sepCount + leavesCount)

    for t in 1:sepCount
        if value(p[t]) < 0.5   # nœud de branchement
            for f in 1:n_features
                if value(b[t, f]) > 0.5
                    a_mat[f, t] = 1.0
                    b_vec[t] = 0.5
                    break
                end
            end
        else   # nœud interne qui est une feuille
            for k in 1:n_classes
                if value(w[t, k]) > 0.5
                    c_vec[t] = k
                    break
                end
            end
        end
    end
    for n in L_nodes
        for k in 1:n_classes
            if value(w[n, k]) > 0.5
                c_vec[n] = k
                break
            end
        end
    end

    T = Tree(D, a_mat, b_vec, c_vec)
    return (T, obj_val, t_sec, gap_pct)
end


function _add_theta_2d!(model, b, p, w, theta, x, y_idx, nodes_set, n_samples, n_features)
    for n_l in nodes_set
        AL, AR = get_AL_AR(n_l)
        for i in 1:n_samples
            wrong_left  = sum(sum(b[na, f] for f in 1:n_features if x[i, f] >= 0.5; init=0) for na in AL; init=0)
            wrong_right = sum(sum(b[na, f] for f in 1:n_features if x[i, f] < 0.5;  init=0) for na in AR; init=0)
            branch_n = sum(b[n_l, f] for f in 1:n_features)
            A_plus = vcat(get_ancestors(n_l), [n_l])
            w_pred = sum(w[na, y_idx[i]] for na in A_plus; init=0)
            @constraint(model, theta[i] <= wrong_left + wrong_right + branch_n + w_pred)
        end
    end
end


function _add_theta_2e!(model, b, w, theta, x, y_idx, L_nodes, n_samples, n_features)
    for n_l in L_nodes
        AL, AR = get_AL_AR(n_l)
        for i in 1:n_samples
            wrong_left  = sum(sum(b[na, f] for f in 1:n_features if x[i, f] >= 0.5; init=0) for na in AL; init=0)
            wrong_right = sum(sum(b[na, f] for f in 1:n_features if x[i, f] < 0.5;  init=0) for na in AR; init=0)
            A_plus = vcat(get_ancestors(n_l), [n_l])
            w_pred = sum(w[na, y_idx[i]] for na in A_plus; init=0)
            @constraint(model, theta[i] <= wrong_left + wrong_right + w_pred)
        end
    end
end

# Borne alternative θ (5)

function _add_theta_alternative!(model, b, p, w, theta, x, y_idx, N_nodes, L_nodes, n_samples, n_features, sepCount)
    L_set = Set(L_nodes)
    for np in N_nodes
        n_left  = 2 * np
        n_right = 2 * np + 1
        child_configs = Tuple{Int,Int,Bool}[]
        if n_left in L_set
            push!(child_configs, (n_left, n_right, true))
        end
        if n_right in L_set
            push!(child_configs, (n_right, n_left, false))
        end
        isempty(child_configs) && continue

        AL_np, AR_np = get_AL_AR(np)
        for (n_l, ns, is_left_child) in child_configs
            for i in 1:n_samples
                wrong_left  = sum(sum(b[na, f] for f in 1:n_features if x[i, f] >= 0.5; init=0) for na in AL_np; init=0)
                wrong_right = sum(sum(b[na, f] for f in 1:n_features if x[i, f] < 0.5;  init=0) for na in AR_np; init=0)

                if is_left_child
                    half_wrong = sum(b[np, f] for f in 1:n_features if x[i, f] >= 0.5; init=0)
                else
                    half_wrong = sum(b[np, f] for f in 1:n_features if x[i, f] < 0.5; init=0)
                end
                half_term = 0.5 * (half_wrong + w[ns, y_idx[i]])

                A_plus_nl = vcat(get_ancestors(n_l), [n_l])
                w_pred = sum(w[na, y_idx[i]] for na in A_plus_nl; init=0)
                @constraint(model, theta[i] <= wrong_left + wrong_right + half_term + w_pred)
            end
        end
    end
end


function _setup_lazy_theta_callback!(model, b, p, w, theta, x, y_idx, N_nodes, L_nodes, n_samples, n_features, sepCount, mode)
    function lazy_cb(cb_data)
        theta_val = [callback_value(cb_data, theta[i]) for i in 1:n_samples]
        b_val = [callback_value(cb_data, b[n, f]) for n in 1:sepCount, f in 1:n_features]
        p_val = [callback_value(cb_data, p[n]) for n in 1:(sepCount + length(L_nodes))]
        w_val = [callback_value(cb_data, w[n, k]) for n in 1:(sepCount + length(L_nodes)), k in 1:size(w, 2)]

        for i in 1:n_samples
            theta_val[i] < 0.5 && continue
            violated = false
            all_nodes = vcat(collect(N_nodes), collect(L_nodes))
            for n_l in all_nodes
                AL, AR = get_AL_AR(n_l)
                wl = sum(sum(b_val[na, f] for f in 1:n_features if x[i, f] >= 0.5; init=0.0) for na in AL; init=0.0)
                wr = sum(sum(b_val[na, f] for f in 1:n_features if x[i, f] < 0.5; init=0.0) for na in AR; init=0.0)
                A_plus = vcat(get_ancestors(n_l), [n_l])
                wp = sum(w_val[na, y_idx[i]] for na in A_plus; init=0.0)
                is_internal = n_l <= sepCount
                branch_n = is_internal ? sum(b_val[n_l, f] for f in 1:n_features) : 0.0
                rhs = wl + wr + branch_n + wp
                if theta_val[i] > rhs + 1e-6
                    if is_internal
                        con = @build_constraint(theta[i] <= sum(sum(b[na, f] for f in 1:n_features if x[i, f] >= 0.5; init=0) for na in AL; init=0) + sum(sum(b[na, f] for f in 1:n_features if x[i, f] < 0.5; init=0) for na in AR; init=0) + sum(b[n_l, f] for f in 1:n_features) + sum(w[na, y_idx[i]] for na in A_plus; init=0))
                    else
                        con = @build_constraint(theta[i] <= sum(sum(b[na, f] for f in 1:n_features if x[i, f] >= 0.5; init=0) for na in AL; init=0) + sum(sum(b[na, f] for f in 1:n_features if x[i, f] < 0.5; init=0) for na in AR; init=0) + sum(w[na, y_idx[i]] for na in A_plus; init=0))
                    end
                    MOI.submit(model, MOI.LazyConstraint(cb_data), con)
                    violated = true
                end
            end
        end
    end
    MOI.set(model, MOI.LazyConstraintCallback(), lazy_cb)
end

# Contraintes ES (système 4)

function _add_es_constraints!(model, b, p, w, theta, x, y, y_idx, classes, class_to_idx, es_list, N_nodes, L_nodes, n_features, n_classes, sepCount)
    for (I_bar, J_bar) in es_list
        J_bar_set = Set(J_bar)
        J_comp = [f for f in 1:n_features if !(f in J_bar_set)]
        K_star = unique([y_idx[i] for i in I_bar])
        length(K_star) < 2 && continue

        # Variables β et G pour cet ES
        n_internal = length(N_nodes)
        β_n  = @variable(model, [1:sepCount], lower_bound=0, upper_bound=1)
        β_nl = @variable(model, [1:sepCount], lower_bound=0, upper_bound=1)
        β_nr = @variable(model, [1:sepCount], lower_bound=0, upper_bound=1)
        β_G  = @variable(model, lower_bound=0)
        G_k  = @variable(model, [K_star], lower_bound=0, upper_bound=1)

        x_ref = x[I_bar[1], :]

        for n in N_nodes
            # β_{n,Ī} ≤ ∑_{f ∈ J̄} b_{n,f} + β_{n,l,Ī} + β_{n,r,Ī}
            @constraint(model, β_n[n] <= sum(b[n, f] for f in J_bar; init=0) + β_nl[n] + β_nr[n])

            # β_{n,l,Ī} ≤ ∑_{f ∈ J\J̄ : x_{if}=0} b_{n,f}   (gauche = x_f=0)
            @constraint(model, β_nl[n] <= sum(b[n, f] for f in J_comp if x_ref[f] < 0.5; init=0))

            # β_{n,r,Ī} ≤ ∑_{f ∈ J\J̄ : x_{if}=1} b_{n,f}   (droite = x_f=1)
            @constraint(model, β_nr[n] <= sum(b[n, f] for f in J_comp if x_ref[f] >= 0.5; init=0))

            # β_{n,l,Ī} ≤ β_{l(n),Ī}  (l(n) = 2n)
            ln = 2 * n
            if ln <= sepCount
                @constraint(model, β_nl[n] <= β_n[ln])
            end
            # β_{n,r,Ī} ≤ β_{r(n),Ī}  (r(n) = 2n+1)
            rn = 2 * n + 1
            if rn <= sepCount
                @constraint(model, β_nr[n] <= β_n[rn])
            end
        end

        # β_{G,Ī} ≤ β_{1,Ī}
        @constraint(model, β_G <= β_n[1])

        # ∑_{k ∈ K*} G_k ≤ 1 + (|K*| - 1) β_{G,Ī}
        @constraint(model, sum(G_k[k] for k in K_star) <= 1 + (length(K_star) - 1) * β_G)

        # ∑_{i ∈ Ī_k} θ_i = |Ī_k| G_k   ∀k ∈ K*
        for k in K_star
            I_k = [i for i in I_bar if y_idx[i] == k]
            @constraint(model, sum(theta[i] for i in I_k) == length(I_k) * G_k[k])
        end
    end
end
