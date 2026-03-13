"""
Module pour les égalités "opposite box corners" (Section 4 du cours).

Définitions (slides CM1):
- Boîte B(p-, p+) = { v : v_j ∈ [p-_j, p+_j] ∀j }
- Coins opposés (v1, v2) de B : {v1_j, v2_j} = {p-_j, p+_j} pour tout j
- Proposition : si flux unitaire, pour deux paires distinctes de coins opposés (i1,i2) et (i3,i4)
  d'une même boîte : u^i1_{r,l(r)} + u^i2_{r,l(r)} = u^i3_{r,l(r)} + u^i4_{r,l(r)} (valide pour F univarié)
"""

# Tolérance égalité
const DEFAULT_TOL = 1e-9

"""
Retourne true si (i1, i2) sont des coins opposés (pour tout j, x[i1,j] ≠ x[i2,j] et
ils sont les min/max de la boîte qu'ils définissent).
"""
function are_opposite_corners(x::Matrix{Float64}, i1::Int, i2::Int; tol::Float64=DEFAULT_TOL)
    nf = size(x, 2)
    for j in 1:nf
        a, b = x[i1, j], x[i2, j]
        if abs(a - b) <= tol
            return false
        end
    end
    return true
end

"""
Pour la boîte B(p_min, p_max), retourne les indices des points de x qui sont exactement
sur un coin (pour chaque j, x[i,j] ∈ {p_min[j], p_max[j]}).
"""
function find_corner_points(x::Matrix{Float64}, p_min::Vector{Float64}, p_max::Vector{Float64}; tol::Float64=DEFAULT_TOL)
    n, nf = size(x, 1), size(x, 2)
    corners = Int[]
    for i in 1:n
        on_corner = true
        for j in 1:nf
            if abs(x[i, j] - p_min[j]) > tol && abs(x[i, j] - p_max[j]) > tol
                on_corner = false
                break
            end
        end
        if on_corner
            push!(corners, i)
        end
    end
    return corners
end

"""
Retourne true si (i1, i2) sont des coins opposés de la boîte B(p_min, p_max)
(i.e. pour chaque j, {x[i1,j], x[i2,j]} = {p_min[j], p_max[j]}).
"""
function are_opposite_corners_of_box(x::Matrix{Float64}, i1::Int, i2::Int, p_min::Vector{Float64}, p_max::Vector{Float64}; tol::Float64=DEFAULT_TOL)
    nf = size(x, 2)
    for j in 1:nf
        lo, hi = p_min[j], p_max[j]
        a, b = x[i1, j], x[i2, j]
        if !( (abs(a - lo) <= tol && abs(b - hi) <= tol) || (abs(a - hi) <= tol && abs(b - lo) <= tol) )
            return false
        end
    end
    return true
end

"""
Énumère toutes les égalités "opposite box corners" pour la racine.

Pour chaque boîte B ayant au moins deux paires distinctes de coins opposés (i1,i2) et (i3,i4),
on a l'égalité valide : u_at[i1,2] + u_at[i2,2] = u_at[i3,2] + u_at[i4,2]
(noeud 1 = racine, 2 = fils gauche).

Retourne un vecteur de 4-uples (i1, i2, i3, i4) avec i1 < i2, i3 < i4, {i1,i2} ≠ {i3,i4}.
"""
function find_opposite_box_corner_equalities(x::Matrix{Float64}; tol::Float64=DEFAULT_TOL)
    n, nf = size(x, 1), size(x, 2)
    equalities = Tuple{Int,Int,Int,Int}[]
    seen_boxes = Set{Vector{Tuple{Float64,Float64}}}()

    for i1 in 1:n
        for i2 in (i1+1):n
            if !are_opposite_corners(x, i1, i2; tol=tol)
                continue
            end
            p_min = [min(x[i1, j], x[i2, j]) for j in 1:nf]
            p_max = [max(x[i1, j], x[i2, j]) for j in 1:nf]
            box_key = [(p_min[j], p_max[j]) for j in 1:nf]
            if box_key in seen_boxes
                continue
            end
            push!(seen_boxes, copy(box_key))

            corners = find_corner_points(x, p_min, p_max; tol=tol)
            opposite_pairs = Tuple{Int,Int}[]
            for a in 1:length(corners)
                for b in (a+1):length(corners)
                    ia, ib = corners[a], corners[b]
                    if are_opposite_corners_of_box(x, ia, ib, p_min, p_max; tol=tol)
                        push!(opposite_pairs, (min(ia, ib), max(ia, ib)))
                    end
                end
            end

            for p in 1:length(opposite_pairs)
                for q in (p+1):length(opposite_pairs)
                    (i1p, i2p) = opposite_pairs[p]
                    (i3p, i4p) = opposite_pairs[q]
                    if (i1p, i2p) != (i3p, i4p)
                        push!(equalities, (i1p, i2p, i3p, i4p))
                    end
                end
            end
        end
    end
    return equalities
end

"""
Vérifie si l'égalité (i1,i2,i3,i4) est violée par la solution de relaxation linéaire
pour le flux à la racine (u_at[:, 2]).
Violation si |(u[i1,2]+u[i2,2]) - (u[i3,2]+u[i4,2])| > tol.
"""
function is_equality_violated(u_at_root_left::Vector{Float64}, i1::Int, i2::Int, i3::Int, i4::Int; tol::Float64=1e-6)
    lhs = u_at_root_left[i1] + u_at_root_left[i2]
    rhs = u_at_root_left[i3] + u_at_root_left[i4]
    return abs(lhs - rhs) > tol
end

# Linked sets

function _other_coords_key(x::Matrix{Float64}, i::Int, jbar::Int, tol::Float64)
    nf = size(x, 2)
    k = Float64[]
    for j in 1:nf
        j == jbar && continue
        push!(k, round(x[i, j] / tol) * tol)
    end
    return tuple(k...)
end

"""
Identifie les linked sets (Section 4) : pour chaque feature jbar, partitionne les points
par leurs coordonnées sur les autres features ; dans chaque cellule, cherche des paires
de valeurs (a,b) avec au moins 2 points chacune et forme P=(p1,p2), Q=(q1,q2) avec
p1,q2 de valeur a, p2,q1 de valeur b (cycle sur la coordonnée jbar).

Retourne un vecteur de (P, Q, jbar) où P et Q sont des Vector{Int} d'indices (même longueur).
"""
function find_linked_sets(x::Matrix{Float64}; tol::Float64=DEFAULT_TOL)
    n, nf = size(x, 1), size(x, 2)
    result = Tuple{Vector{Int}, Vector{Int}, Int}[]
    for jbar in 1:nf
        # Grouper les points par coordonnées "autres que jbar"
        cells = Dict{Any, Vector{Int}}()
        for i in 1:n
            key = _other_coords_key(x, i, jbar, tol)
            if !haskey(cells, key)
                cells[key] = Int[]
            end
            push!(cells[key], i)
        end
        for (_key, indices) in cells
            length(indices) < 4 && continue
            vals_j = [x[i, jbar] for i in indices]
            # Grouper les indices par valeur sur jbar (avec tol)
            by_val = Dict{Float64, Vector{Int}}()
            for (idx, i) in enumerate(indices)
                v = round(vals_j[idx] / tol) * tol
                if !haskey(by_val, v)
                    by_val[v] = Int[]
                end
                push!(by_val[v], indices[idx])
            end
            val_list = collect(keys(by_val))
            for a in 1:length(val_list), b in (a+1):length(val_list)
                va, vb = val_list[a], val_list[b]
                A = by_val[va]
                B = by_val[vb]
                length(A) >= 2 && length(B) >= 2 || continue
                # Former un linked set de taille 2 : P=(p1,p2), Q=(q1,q2)
                # x_{q1,jbar}=x_{p2,jbar}=vb, x_{q2,jbar}=x_{p1,jbar}=va
                p1, q2 = A[1], A[2]
                p2, q1 = B[1], B[2]
                push!(result, ([p1, p2], [q1, q2], jbar))
            end
        end
    end
    return result
end
