# Cutting plane pour box corners

include("building_tree.jl")
include("box_equalities.jl")
using JuMP
using MathOptInterface
const MOI = MathOptInterface

"""
Résout la formulation F (univarié, flux unitaire) en ajoutant les égalités
opposite box corners par un algorithme à plans coupants :
1. Résoudre la relaxation linéaire
2. Ajouter les égalités violées
3. Répéter jusqu'à ce qu'aucune égalité ne soit violée
4. Résoudre le problème entier avec les égalités ajoutées

Retourne (T, objectif, temps_total, gap, n_rounds, n_equalities_added).
"""
function build_tree_cutting_plane_box(x::Matrix{Float64}, y::Vector{Any}, D::Int64, classes; time_limit_sec::Int=-1, tol_violation::Float64=1e-6)
    dataCount = length(y)
    featuresCount = size(x, 2)
    classCount = length(classes)
    sepCount = 2^D - 1
    leavesCount = 2^D

    eq_list = find_opposite_box_corner_equalities(x)
    added = Tuple{Int,Int,Int,Int}[]
    n_rounds = 0
    total_time = 0.0

    m = Model(CPLEX.Optimizer)
    set_silent(m)
    if time_limit_sec > 0
        set_time_limit_sec(m, time_limit_sec)
    end

    mu_vect = ones(Float64, featuresCount)
    mu_min, mu_max = 1.0, 0.0
    for j in 1:featuresCount
        for i1 in 1:dataCount
            for i2 in (i1+1):dataCount
                if abs(x[i1, j] - x[i2, j]) > 1e-4
                    mu_vect[j] = min(mu_vect[j], abs(x[i1, j] - x[i2, j]))
                end
            end
        end
        mu_min = min(mu_min, mu_vect[j])
        mu_max = max(mu_max, mu_vect[j])
    end

    @variable(m, a[1:featuresCount, 1:sepCount], Bin)
    @variable(m, b[1:sepCount])
    @variable(m, c[1:classCount, 1:(sepCount+leavesCount)], Bin)
    @variable(m, u_at[1:dataCount, 1:(sepCount+leavesCount)], Bin)
    @variable(m, u_tw[1:dataCount, 1:(sepCount+leavesCount)], Bin)
    @variable(m, z[1:dataCount, (sepCount+1):(sepCount+leavesCount)], Bin)

    @constraint(m, [t in 1:sepCount], sum(a[j, t] for j in 1:featuresCount) + sum(c[k, t] for k in 1:classCount) == 1)
    @constraint(m, [t in 1:sepCount], b[t] <= sum(a[j, t] for j in 1:featuresCount))
    @constraint(m, [t in 1:sepCount], b[t] >= 0)
    @constraint(m, [t in (sepCount+1):(sepCount+leavesCount)], sum(c[k, t] for k in 1:classCount) == 1)

    @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t] == u_at[i, t*2] + u_at[i, t*2+1] + u_tw[i, t])
    @constraint(m, [i in 1:dataCount, t in (sepCount+1):(sepCount+leavesCount)], u_at[i, t] == u_tw[i, t])
    @constraint(m, [i in 1:dataCount], sum(u_tw[i, t] for t in (sepCount+1):(sepCount+leavesCount)) == 1)

    k_i = [findfirst(classes .== y[i]) for i in 1:dataCount]
    for i in 1:dataCount
        for t in (sepCount+1):(sepCount+leavesCount)
            @constraint(m, z[i, t] <= u_tw[i, t])
            @constraint(m, z[i, t] <= c[k_i[i], t])
            @constraint(m, z[i, t] >= u_tw[i, t] + c[k_i[i], t] - 1)
        end
    end

    for (i1, i2, i3, i4) in added
        @constraint(m, u_at[i1, 2] + u_at[i2, 2] == u_at[i3, 2] + u_at[i4, 2])
    end

    @constraint(m, [i in 1:dataCount, t in 1:sepCount], sum(a[j, t]*(x[i, j]+mu_vect[j]-mu_min) for j in 1:featuresCount) + mu_min <= b[t] + (1+mu_max)*(1-u_at[i, t*2]))
    @constraint(m, [i in 1:dataCount, t in 1:sepCount], sum(a[j, t]*x[i, j] for j in 1:featuresCount) >= b[t] - (1-u_at[i, t*2 + 1]))
    @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t*2+1] <= sum(a[j, t] for j in 1:featuresCount))
    @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t*2] <= sum(a[j, t] for j in 1:featuresCount))

    @objective(m, Max, sum(z[i, t] for i in 1:dataCount for t in (sepCount+1):(sepCount+leavesCount)))

    # Cutting plane
    all_binary = vcat(vec(a), vec(c), vec(u_at), vec(u_tw), vec(z))
    while true
        n_rounds += 1
        relax_integrality(m)
        set_time_limit_sec(m, time_limit_sec > 0 ? max(10, time_limit_sec ÷ 2) : -1)
        t0 = time()
        optimize!(m)
        total_time += time() - t0
        if primal_status(m) != MOI.FEASIBLE_POINT
            break
        end
        u_val = value.(u_at)
        u_root_left = u_val[:, 2]
        violated = Tuple{Int,Int,Int,Int}[]
        for eq in eq_list
            i1, i2, i3, i4 = eq
            if !(eq in added) && is_equality_violated(u_root_left, i1, i2, i3, i4; tol=tol_violation)
                push!(violated, eq)
            end
        end
        if isempty(violated)
            break
        end
        for eq in violated
            i1, i2, i3, i4 = eq
            @constraint(m, u_at[i1, 2] + u_at[i2, 2] == u_at[i3, 2] + u_at[i4, 2])
            push!(added, eq)
        end
    end

    # MIP entier
    for v in all_binary
        set_binary(v)
    end
    set_time_limit_sec(m, time_limit_sec)
    t0 = time()
    optimize!(m)
    total_time += time() - t0

    gap = -1.0
    T = nothing
    objective = -1
    if primal_status(m) == MOI.FEASIBLE_POINT
        objective = JuMP.objective_value(m)
        if termination_status(m) == MOI.OPTIMAL
            gap = 0.0
        else
            bound = JuMP.objective_bound(m)
            gap = 100.0 * abs(objective - bound) / (objective + 1e-4)
        end
        class = Vector{Int64}(undef, sepCount+leavesCount)
        for t in 1:(sepCount+leavesCount)
            k = argmax(value.(c[:, t]))
            class[t] = value.(c[k, t]) >= 1.0 - 1e-4 ? k : -1
        end
        T = Tree(D, value.(a), class, round.(Int, value.(u_at)), x)
    end

    return T, objective, total_time, gap, n_rounds, length(added)
end
