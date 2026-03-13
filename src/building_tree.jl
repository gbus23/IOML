include("struct/tree.jl")
include("box_equalities.jl")

"""
Construit un arbre de décision par résolution de la formulation F

Entrées :
- x : caractéristiques des données d'entraînement
- y : classe des données d'entraînement
- D : Nombre maximal de séparations d'une branche (profondeur de l'arbre - 1)
- multivariate (optionnel): vrai si les séparations sont multivariées; faux si elles sont univariées (faux par défaut)
- mu (optionnel, utilisé en multivarié): distance minimale à gauche d'une séparation où aucune donnée ne peut se trouver (i.e., pour la séparation ax <= b, il n'y aura aucune donnée dans ]b - ax - mu, b - ax[) (10^-4 par défaut)
- time_limits (optionnel) : temps maximal de résolution (-1 si le temps n'est pas limité) (-1 par défaut)
- classes : labels des classes figurant dans le dataset
- unitary_flow (optionnel) : si true, chaque point envoie exactement 1 unité de flot vers une feuille (nécessaire pour les égalités opposite box corners, Section 4)
- box_equalities (optionnel) : si true (univarié uniquement), ajoute les égalités opposite box corners à la racine
- box_equalities_list (optionnel) : liste de 4-uples (i1,i2,i3,i4) à utiliser au lieu de les recalculer
- linked_set_equalities (optionnel) : si true (univarié uniquement), ajoute les égalités Section 4 linked sets (sum_ell sum_k (u^{p_k}_{ell,w} - u^{q_k}_{ell,w}) = 0)
- linked_set_list (optionnel) : liste de (P, Q, jbar) avec P,Q vecteurs d'indices ; si nothing et linked_set_equalities=true, appelle find_linked_sets(x)
- return_lp_node_stats (optionnel) : si true, résout d'abord la relaxation linéaire puis le MIP et retourne (lp_val, node_count) en plus
- sensitive_group (optionnel, Partie 2) : vecteur group[i] ∈ {1,2} ; si rien, pas d'équité
- positive_class (optionnel) : indice 1-based de la classe "positive" pour parité (défaut 1)
- fairness_type (optionnel) : :none, :demographic_parity ou :equal_opportunity
- fairness_penalty (optionnel) : si > 0, ajoute au objectif -penalty*(slack) (équité en pénalité)
- fairness_constraint (optionnel) : si true, contrainte d'équité entre groupes (stricte si tolerance=0)
- fairness_tolerance (optionnel) : si > 0 et contrainte, autorise |taux_A - taux_B| <= tolerance (assouplit la contrainte, meilleure précision)
"""
function build_tree(x::Matrix{Float64}, y::Vector{Any}, D::Int64, classes; multivariate::Bool=false, time_limit::Int64 = -1, mu::Float64=10^(-4), unitary_flow::Bool=false, box_equalities::Bool=false, box_equalities_list::Union{Vector{Tuple{Int,Int,Int,Int}}, Nothing}=nothing, linked_set_equalities::Bool=false, linked_set_list::Union{Vector{Tuple{Vector{Int},Vector{Int},Int}}, Nothing}=nothing, return_lp_node_stats::Bool=false, sensitive_group::Union{Vector{Int}, Nothing}=nothing, positive_class::Int=1, fairness_type::Symbol=:none, fairness_penalty::Float64=0.0, fairness_constraint::Bool=false, fairness_tolerance::Float64=0.0)
    
    dataCount = length(y) # Nombre de données d'entraînement
    featuresCount = length(x[1, :]) # Nombre de caractéristiques
    classCount = length(classes) # Nombre de classes différentes
    sepCount = 2^D - 1 # Nombre de séparations de l'arbre
    leavesCount = 2^D # Nombre de feuilles de l'arbre

    m = Model(CPLEX.Optimizer) 
    set_silent(m)

    if time_limit!=-1
        set_time_limit_sec(m, time_limit)
    end

    # Plus petite différence entre deux données pour une caractéristique
    mu_min = 1.0 
    # Plus grande différence entre deux données pour une caractéristique
    mu_max = 0.0
    
    if !multivariate # calcul des constantes mu_min, mu_max et du vecteur mu

        # mu_vect[j] est la plus petite différence (>0) entre deux données, pour la caractéristiques j
        mu_vect = ones(Float64, featuresCount)
        for j in 1:featuresCount
            for i1 in 1:dataCount
                for i2 in (i1+1):dataCount
                    if abs(x[i1, j] - x[i2, j]) > 1E-4
                        mu_vect[j] = min(mu_vect[j], abs(x[i1, j] - x[i2, j]))
                    end
                end
            end
            mu_min = min(mu_min, mu_vect[j])
            mu_max = max(mu_max, mu_vect[j])
        end
    end

    ## Déclaration des variables
    if multivariate
        @variable(m, a[1:featuresCount, 1:sepCount], base_name="a_{j, t}")
        @variable(m, a_h[1:featuresCount, 1:sepCount], base_name="â_{j, t}")
        @variable(m, s[1:featuresCount, 1:sepCount], Bin, base_name="s_{j, t}")
        @variable(m, d[1:sepCount], Bin, base_name="d_t")
    else
        @variable(m, a[1:featuresCount, 1:sepCount], Bin, base_name="a")
    end 
    @variable(m, b[1:sepCount], base_name="b_t")
    @variable(m, c[1:classCount, 1:(sepCount+leavesCount)], Bin, base_name = "c_{k, t}")
    @variable(m, u_at[1:dataCount, 1:(sepCount+leavesCount)], Bin, base_name = "u^i_{a(t), t}")
    @variable(m, u_tw[1:dataCount, 1:(sepCount+leavesCount)], Bin, base_name = "u^i_{t, w}")
    # Pour flux unitaire : objectif = nombre de bien classés (linéarisé via z)
    if unitary_flow
        @variable(m, z[1:dataCount, (sepCount+1):(sepCount+leavesCount)], Bin, base_name = "z_i_t")
    end

    ## Déclaration des contraintes

    # contraintes définissant la structure de l'arbre
    if multivariate
        @constraint(m, [t in 1:sepCount], d[t] + sum(c[k, t] for k in 1:classCount) == 1) # on s'assure que le noeud applique une règle de branchement OU attribue une classe
        @constraint(m, [t in 1:sepCount], b[t] <= d[t]) # b doit être nul si il n'y a pas de branchement 
        @constraint(m, [t in 1:sepCount], b[t] >= -d[t]) # b doit être nul si il n'y a pas de branchement 
        @constraint(m, [t in 1:sepCount], sum(a_h[j, t] for j in 1:featuresCount) <= d[t]) # on borne la norme du vecteur a
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] <= a_h[j, t]) # définition de â borne sup de la valeur absolu de a
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] >= -a_h[j, t]) # définition de â borne sup de la valeur absolu de a
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] <= s[j, t]) # définition de s, non nul ssi a non nul
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] >= -s[j, t]) # définition de s, non nul ssi a non nul
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], s[j, t] <= d[t]) # définition de d, non nul si il existe un coef non nul
        @constraint(m, [t in 1:sepCount], sum(s[j, t] for j in 1:featuresCount) >= d[t]) # définition de d, non nul si il existe un coef non nul
        @constraint(m, [t in 2:sepCount], d[t] <= d[t ÷ 2]) # on s'assure que si un noeud de branchement n'applique pas de règle de branchement, ses fils non plus
    else
        @constraint(m, [t in 1:sepCount], sum(a[j, t] for j in 1:featuresCount) + sum(c[k, t] for k in 1:classCount) == 1) # on s'assure que le noeud applique une règle de branchement OU attribue une classe
        @constraint(m, [t in 1:sepCount], b[t] <= sum(a[j, t] for j in 1:featuresCount)) # b doit être nul si il n'y a pas de branchement 
        @constraint(m, [t in 1:sepCount], b[t] >= 0) # b doit être positif
    end
    @constraint(m, [t in (sepCount+1):(sepCount+leavesCount)], sum(c[k, t] for k in 1:classCount) == 1) # on s'assure qu'on attribue une classe par feuille

    # contraintes de conservation du flot et contraintes de capacité
    @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t] == u_at[i, t*2] + u_at[i, t*2+1] + u_tw[i, t]) # conservation du flot dans les noeuds de branchement
    @constraint(m, [i in 1:dataCount, t in (sepCount+1):(sepCount+leavesCount)], u_at[i, t] == u_tw[i, t]) # conservation du flot dans les feuilles
    # Avec flux unitaire : chaque point va vers une feuille (éventuellement mal classée) ; sans flux unitaire : flot uniquement vers feuille de sa classe
    if !unitary_flow
        @constraint(m, [i in 1:dataCount, t in 1:(sepCount+leavesCount)], u_tw[i, t] <= c[findfirst(classes .== y[i]), t]) # contrainte de capacité qui impose le flot a etre nul si la classe de la feuille n'est pas la bonne
    end

    # Flux unitaire (Section 4) : chaque donnée envoie exactement 1 unité vers une feuille
    if unitary_flow
        @constraint(m, [i in 1:dataCount], sum(u_tw[i, t] for t in (sepCount+1):(sepCount+leavesCount)) == 1)
        k_i = [findfirst(classes .== y[i]) for i in 1:dataCount]
        for i in 1:dataCount
            for t in (sepCount+1):(sepCount+leavesCount)
                @constraint(m, z[i, t] <= u_tw[i, t])
                @constraint(m, z[i, t] <= c[k_i[i], t])
                @constraint(m, z[i, t] >= u_tw[i, t] + c[k_i[i], t] - 1)
            end
        end
    end

    # Égalités "opposite box corners" à la racine (univarié uniquement)
    if box_equalities && !multivariate
        eq_list = box_equalities_list !== nothing ? box_equalities_list : find_opposite_box_corner_equalities(x)
        for (i1, i2, i3, i4) in eq_list
            @constraint(m, u_at[i1, 2] + u_at[i2, 2] == u_at[i3, 2] + u_at[i4, 2])
        end
    end

    # Égalités linked sets Section 4 : sum_ell sum_k (u_tw[p_k,ell] - u_tw[q_k,ell]) = 0 (feuilles = sepCount+1 : sepCount+leavesCount)
    if linked_set_equalities && !multivariate
        leaves = (sepCount+1):(sepCount+leavesCount)
        ls_list = linked_set_list !== nothing ? linked_set_list : find_linked_sets(x)
        for (P, Q, _jbar) in ls_list
            @constraint(m, sum(u_tw[P[k], t] - u_tw[Q[k], t] for k in 1:length(P) for t in leaves) == 0)
        end
    end

    # Partie 2 : équité (parité démographique ou equal opportunity). Nécessite flux unitaire.
    use_fairness = (fairness_type in (:demographic_parity, :equal_opportunity)) && sensitive_group !== nothing && length(sensitive_group) == dataCount && unitary_flow && !multivariate
    fair_has_slack = false
    if use_fairness
        leaves = (sepCount+1):(sepCount+leavesCount)
        k_pos = max(1, min(positive_class, classCount))
        @variable(m, w[1:dataCount, leaves], Bin, base_name="w_fair")
        for t in leaves
            for i in 1:dataCount
                @constraint(m, w[i, t] <= u_tw[i, t])
                @constraint(m, w[i, t] <= c[k_pos, t])
                @constraint(m, w[i, t] >= u_tw[i, t] + c[k_pos, t] - 1)
            end
        end
        group1 = findall(==(1), sensitive_group)
        group2 = findall(==(2), sensitive_group)
        n1 = length(group1)
        n2 = length(group2)
        if n1 > 0 && n2 > 0
            sum_pos_A = sum(w[i, t] for i in group1 for t in leaves)
            sum_pos_B = sum(w[i, t] for i in group2 for t in leaves)
            if fairness_type == :equal_opportunity
                group1_pos = findall(i -> sensitive_group[i] == 1 && findfirst(isequal(y[i]), classes) == k_pos, 1:dataCount)
                group2_pos = findall(i -> sensitive_group[i] == 2 && findfirst(isequal(y[i]), classes) == k_pos, 1:dataCount)
                n1_pos = length(group1_pos)
                n2_pos = length(group2_pos)
                if n1_pos > 0 && n2_pos > 0
                    sum_pos_A_eq = sum(w[i, t] for i in group1_pos for t in leaves)
                    sum_pos_B_eq = sum(w[i, t] for i in group2_pos for t in leaves)
                    need_slack = (fairness_constraint && fairness_tolerance > 0) || fairness_penalty > 0
                    if need_slack
                        @variable(m, slack_fair_pos >= 0)
                        @variable(m, slack_fair_neg >= 0)
                        @constraint(m, (1.0 / n1_pos) * sum_pos_A_eq - (1.0 / n2_pos) * sum_pos_B_eq == slack_fair_pos - slack_fair_neg)
                        if fairness_constraint && fairness_tolerance > 0
                            @constraint(m, slack_fair_pos + slack_fair_neg <= fairness_tolerance)
                        end
                        if fairness_penalty > 0
                            fair_has_slack = true
                        end
                    elseif fairness_constraint
                        @constraint(m, n2_pos * sum_pos_A_eq == n1_pos * sum_pos_B_eq)
                    end
                end
            else
                # demographic_parity
                need_slack = (fairness_constraint && fairness_tolerance > 0) || fairness_penalty > 0
                if need_slack
                    @variable(m, slack_fair_pos >= 0)
                    @variable(m, slack_fair_neg >= 0)
                    @constraint(m, (1.0 / n1) * sum_pos_A - (1.0 / n2) * sum_pos_B == slack_fair_pos - slack_fair_neg)
                    if fairness_constraint && fairness_tolerance > 0
                        @constraint(m, slack_fair_pos + slack_fair_neg <= fairness_tolerance)
                    end
                    if fairness_penalty > 0
                        fair_has_slack = true
                    end
                elseif fairness_constraint
                    @constraint(m, n2 * sum_pos_A == n1 * sum_pos_B)
                end
            end
        end
    end

    if multivariate
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], sum(a[j, t]*x[i, j] for j in 1:featuresCount) + mu <= b[t] + (2+mu)*(1-u_at[i, t*2])) # contrainte de capacité controlant le passage dans le noeud fils gauche
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], sum(a[j, t]*x[i, j] for j in 1:featuresCount) >= b[t] - 2*(1-u_at[i, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t*2+1] <= d[t]) # contrainte de capacité empechant les données de passer dans le fils droit d'un noeud n'appliquant pas de règle de branchement
    else
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], sum(a[j, t]*(x[i, j]+mu_vect[j]-mu_min) for j in 1:featuresCount) + mu_min <= b[t] + (1+mu_max)*(1-u_at[i, t*2])) # contrainte de capacité controlant le passage dans le noeud fils gauche
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], sum(a[j, t]*x[i, j] for j in 1:featuresCount) >= b[t] - (1-u_at[i, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t*2+1] <= sum(a[j, t] for j in 1:featuresCount)) # contrainte de capacité empechant les données de passer dans le fils droit d'un noeud n'appliquant pas de règle de branchement
        @constraint(m, [i in 1:dataCount, t in 1:sepCount], u_at[i, t*2] <= sum(a[j, t] for j in 1:featuresCount)) # contrainte de capacité empechant les données de passer dans le fils gauche d'un noeud n'appliquant pas de règle de branchement
    end

    ## Déclaration de l'objectif
    if unitary_flow
        if use_fairness && fairness_penalty > 0 && fair_has_slack
            @objective(m, Max, sum(z[i, t] for i in 1:dataCount for t in (sepCount+1):(sepCount+leavesCount)) - fairness_penalty * (slack_fair_pos + slack_fair_neg))
        else
            @objective(m, Max, sum(z[i, t] for i in 1:dataCount for t in (sepCount+1):(sepCount+leavesCount)))
        end
    else
        @objective(m, Max, sum(u_at[i, 1] for i in 1:dataCount))
    end

    classif = @expression(m, unitary_flow ? sum(z[i, t] for i in 1:dataCount for t in (sepCount+1):(sepCount+leavesCount)) : sum(u_at[i, 1] for i in 1:dataCount))

    lp_val = nothing
    node_count = nothing
    if return_lp_node_stats
        # Collecter toutes les variables binaires pour restaurer l'intégralité après la relaxation
        if multivariate
            binary_refs = vcat(vec(s), vec(d), vec(c), vec(u_at), vec(u_tw))
        else
            binary_refs = vcat(vec(a), vec(c), vec(u_at), vec(u_tw), unitary_flow ? vec(z) : [], use_fairness ? vec(w) : [])
        end
        # Résoudre la relaxation linéaire (limite très haute pour avoir la vraie valeur LP ; CPLEX n'accepte pas -1)
        if time_limit != -1
            set_time_limit_sec(m, 1e6)
        end
        relax_integrality(m)
        optimize!(m)
        lp_val = primal_status(m) == MOI.FEASIBLE_POINT ? objective_value(m) : NaN
        for v in binary_refs
            set_binary(v)
        end
        if time_limit != -1
            set_time_limit_sec(m, Float64(time_limit))
        end
    end

    starting_time = time()
    optimize!(m)
    resolution_time = time() - starting_time

    if return_lp_node_stats
        node_count = try
            MOI.get(JuMP.backend(m), MOI.NodeCount())
        catch
            -1
        end
    end
    
    gap = -1.0

    # Arbre obtenu (vide si le solveur n'a trouvé aucune solution)
    T = nothing
    objective = -1
    
    # Si une solution a été trouvée
    if primal_status(m) == MOI.FEASIBLE_POINT

        # class[t] : classe prédite par le sommet t
        class = Vector{Int64}(undef, sepCount+leavesCount)
        for t in 1:(sepCount+leavesCount)
            k = argmax(value.(c[:, t]))
            if value.(c[k, t])  >=  1.0 - 10^-4
                class[t] = k
            else
                class[t] = -1
            end
        end
        
        objective = JuMP.objective_value(m) 
        # Si une solution optimale a été trouvée
        if termination_status(m) == MOI.OPTIMAL
            gap = 0
        else
            # Calcul du gap relatif entre l'objectif de la meilleure solution entière et la borne continue en fin de résolution
            bound = JuMP.objective_bound(m)
            gap = 100.0 * abs(objective - bound) / (objective + 10^-4) # +10^-4 permet d'éviter de diviser par 0
        end   
        
        # Construction d'une variable de type Tree dans laquelle chaque séparation est recentrée
        if multivariate
            T = Tree(D, class, round.(Int, value.(u_at)), round.(Int, value.(s)), x)
        else
            T = Tree(D, value.(a), class, round.(Int, value.(u_at)), x)
        end
    end   

    return T, objective, resolution_time, gap, lp_val, node_count
end

"""
FONCTION SIMILAIRE A LA PRECEDENTE UTILISEE UNIQUEMENT SI VOUS FAITES DES REGROUPEMENTS 

Construit un arbre de décision par résolution de :
-  la formulation F_U (si les paramètres useFhS et useFeS = false)
-  la formulation F^h_S (si le paramètre useFhS = true)
-  la formulation F^e_S (si le paramètre useFeS = true)

Entrées :
- clusters : partition des données d'entraînement (chaque cluster contient des données de même classe)
- D : Nombre maximal de séparations d'une branche (profondeur de l'arbre - 1)
- multivariate (optionnel): vrai si les séparations sont multivariées; faux si elles sont univariées (faux par défaut)
- mu (optionnel, utilisé en multivarié): distance minimale à gauche d'une séparation où aucune donnée ne peut se trouver (i.e., pour la séparation ax <= b, il n'y aura aucune donnée dans ]b - ax - mu, b - ax[) (10^-4 par défaut)
- time_limits (optionnel) : temps maximal de résolution (-1 si le temps n'est pas limité) (-1 par défaut)
- useFhS (optionnel): vrai si la formulation FhS est utilisée
- useFeS (optionnel): vrai si la formulation FeS est utilisée
"""
function build_tree(clusters::Vector{Cluster}, D::Int64, classes;multivariate::Bool=false, time_limit::Int64 = -1, mu::Float64=10^(-4), useFhS::Bool=false, useFeS::Bool=false)
    
    dataCount = sum(length(c.dataIds) for c in clusters) # Nombre de données d'entraînement
    clusterCount = length(clusters) # Nombre de données d'entraînement
    featuresCount = size(clusters[1].x, 2) # Nombre de caractéristiques
    classCount = length(classes) # Nombre de classes différentes
    sepCount = 2^D - 1 # Nombre de séparations de l'arbre
    leavesCount = 2^D # Nombre de feuilles de l'arbre
    
    m = Model(CPLEX.Optimizer) 

    set_silent(m) # Masque les sorties du solveur

    if time_limit!=-1
        set_time_limit_sec(m, time_limit)
    end

    # Plus petite différence entre deux données pour une caractéristique
    mu_min = 1.0 
    # Plus grande différence entre deux données pour une caractéristique
    mu_max = 0.0
    
    if !multivariate # calcul des constantes mu_min, mu_max et du vecteur mu
        mu_vect = ones(Float64, featuresCount)
        for j in 1:featuresCount
            for i1 in 1:clusterCount
                for i2 in (i1+1):clusterCount

                    if useFhS || useFeS
                        if abs(clusters[i1].barycenter[j] - clusters[i2].barycenter[j]) > 1E-4
                            mu_vect[j] = min(mu_vect[j], abs(clusters[i1].barycenter[j] - clusters[i2].barycenter[j]))
                        end
                    else  
                    v1 = clusters[i1].lBounds[j] - clusters[i2].uBounds[j]
                    v2 = clusters[i2].lBounds[j] - clusters[i1].uBounds[j]

                    # Si les clusters n'ont pas des intervalles pour la caractéristique j qui s'intersectent
                        if v1 > 1E-4 || v2 > 1E-4
                        vMin = min(abs(v1), abs(v2))
                        mu_vect[j] = min(mu_vect[j], vMin)
                        end
                    end
                end
            end
            mu_min = min(mu_min, mu_vect[j])
            mu_max = max(mu_max, mu_vect[j])
        end
    end

    ## Déclaraction des variables
    if multivariate
        @variable(m, a[1:featuresCount, 1:sepCount], base_name="a_{j, t}")
        @variable(m, a_h[1:featuresCount, 1:sepCount], base_name="â_{j, t}")
        @variable(m, s[1:featuresCount, 1:sepCount], Bin, base_name="s_{j, t}")
        @variable(m, d[1:sepCount], Bin, base_name="d_t")
    else
        @variable(m, a[1:featuresCount, 1:sepCount], Bin, base_name="a")
    end 
    @variable(m, b[1:sepCount], base_name="b_t")
    @variable(m, c[1:classCount, 1:(sepCount+leavesCount)], Bin, base_name = "c_{k, t}")
    @variable(m, u_at[1:clusterCount, 1:(sepCount+leavesCount)], Bin, base_name = "u^i_{a(t), t}")
    @variable(m, u_tw[1:clusterCount, 1:(sepCount+leavesCount)], Bin, base_name = "u^i_{t, w}")

    if useFeS
        @variable(m, r[1:dataCount], Bin)
        @constraint(m, [clusterId in 1:clusterCount], sum(r[i] for i in clusters[clusterId].dataIds) == 1)
    end 
    ## Déclaration des contraintes
    
    # Contraintes définissant la structure de l'arbre
    if multivariate
        @constraint(m, [t in 1:sepCount], d[t] + sum(c[k, t] for k in 1:classCount) == 1) # on s'assure que le noeud applique une règle de branchement OU attribue une classe
        @constraint(m, [t in 1:sepCount], b[t] <= d[t]) # b doit être nul si il n'y a pas de branchement 
        @constraint(m, [t in 1:sepCount], b[t] >= -d[t]) # b doit être nul si il n'y a pas de branchement 
        @constraint(m, [t in 1:sepCount], sum(a_h[j, t] for j in 1:featuresCount) <= d[t]) # on borne la norme du vecteur a
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] <= a_h[j, t]) # définition de â borne sup de la valeur absolu de a
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] >= -a_h[j, t]) # définition de â borne sup de la valeur absolu de a
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] <= s[j, t]) # définition de s, non nul ssi a non nul
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], a[j, t] >= -s[j, t]) # définition de s, non nul ssi a non nul
        @constraint(m, [t in 1:sepCount, j in 1:featuresCount], s[j, t] <= d[t]) # définition de d, non nul si il existe un coef non nul
        @constraint(m, [t in 1:sepCount], sum(s[j, t] for j in 1:featuresCount) >= d[t]) # définition de d, non nul si il existe un coef non nul
        @constraint(m, [t in 2:sepCount], d[t] <= d[t ÷ 2]) # on s'assure que si un noeud de branchement n'applique pas de règle de branchement, ses fils non plus
    else
        @constraint(m, [t in 1:sepCount], sum(a[j, t] for j in 1:featuresCount) + sum(c[k, t] for k in 1:classCount) == 1) # on s'assure que le noeud applique une règle de branchement OU attribue une classe
        @constraint(m, [t in 1:sepCount], b[t] <= sum(a[j, t] for j in 1:featuresCount)) # b doit être nul si il n'y a pas de branchement 
        @constraint(m, [t in 1:sepCount], b[t] >= 0) # b doit être positif
    end
    @constraint(m, [t in (sepCount+1):(sepCount+leavesCount)], sum(c[k, t] for k in 1:classCount) == 1) # on s'assure qu'on attribue une classe par feuille

    # contraintes de conservation du flot et contraintes de capacité
    @constraint(m, [i in 1:clusterCount, t in 1:sepCount], u_at[i, t] == u_at[i, t*2] + u_at[i, t*2+1] + u_tw[i, t]) # conservation du flot dans les noeuds de branchement
    @constraint(m, [i in 1:clusterCount, t in (sepCount+1):(sepCount+leavesCount)], u_at[i, t] == u_tw[i, t]) # conservation du flot dans les feuilles
    @constraint(m, [i in 1:clusterCount, t in 1:(sepCount+leavesCount)], u_tw[i, t] <= c[findfirst(classes .== clusters[i].class), t]) # contrainte de capacité qui impose le flot a etre nul si la classe de la feuille n'est pas la bonne
    if multivariate
        if useFhS
            @constraint(m, [i in 1:clusterCount, t in 1:sepCount], sum(a[j, t]*clusters[i].barycenter[j] for j in 1:featuresCount) + mu <= b[t] + (2+mu)*(1-u_at[i, t*2])) # contrainte de capacité controlant le passage dans le noeud fils gauche
            @constraint(m, [i in 1:clusterCount, t in 1:sepCount], sum(a[j, t]*clusters[i].barycenter[j] for j in 1:featuresCount) >= b[t] - 2*(1-u_at[i, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        elseif useFeS
            @constraint(m, [(clusterId, cluster) in enumerate(clusters), dataId in cluster.dataIds, t in 1:sepCount], sum(a[j, t]*cluster.x[dataId, j] for j in 1:featuresCount) + mu <= b[t] + (2+mu)*(2-u_at[clusterId, t*2]-r[dataId])) # contrainte de capacité controlant le passage dans le noeud fils gauche
            @constraint(m, [(clusterId, cluster) in enumerate(clusters), dataId in cluster.dataIds, t in 1:sepCount], sum(a[j, t]*cluster.x[dataId, j] for j in 1:featuresCount) >= b[t] - 2*(1-u_at[clusterId, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        
        else 
            @constraint(m, [i in 1:clusterCount, t in 1:sepCount, dataId in clusters[i].dataIds], sum(a[j, t]*clusters[i].x[dataId, j] for j in 1:featuresCount) + mu <= b[t] + (2+mu)*(1-u_at[i, t*2])) # contrainte de capacité controlant le passage dans le noeud fils gauche
            @constraint(m, [i in 1:clusterCount, t in 1:sepCount, dataId in clusters[i].dataIds], sum(a[j, t]*clusters[i].x[dataId, j] for j in 1:featuresCount) >= b[t] - 2*(1-u_at[i, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        end 
        @constraint(m, [i in 1:clusterCount, t in 1:sepCount], u_at[i, t*2+1] <= d[t]) # contrainte de capacité empechant les données de passer dans le fils droit d'un noeud n'appliquant pas de règle de branchement
    else
        if useFhS
            @constraint(m, [i in 1:clusterCount, t in 1:sepCount], sum(a[j, t]*(clusters[i].barycenter[j]+mu_vect[j]-mu_min) for j in 1:featuresCount) + mu_min <= b[t] + (1+mu_max)*(1-u_at[i, t*2])) # contrainte de capacité controlant le passage dans le noeud fils gauche
            @constraint(m, [i in 1:clusterCount, t in 1:sepCount], sum(a[j, t]*clusters[i].barycenter[j] for j in 1:featuresCount) >= b[t] - (1-u_at[i, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        elseif useFeS
            @constraint(m, [(clusterId, cluster) in enumerate(clusters), dataId in cluster.dataIds, t in 1:sepCount], sum(a[j, t]*(cluster.x[dataId, j]+mu_vect[j]-mu_min) for j in 1:featuresCount) + mu_min <= b[t] + (1+mu_max)*(2-u_at[clusterId, t*2]-r[dataId])) # contrainte de capacité controlant le passage dans le noeud fils gauche
            @constraint(m, [(clusterId, cluster) in enumerate(clusters), dataId in cluster.dataIds, t in 1:sepCount], sum(a[j, t]*cluster.x[dataId, j] for j in 1:featuresCount) >= b[t] - (2-u_at[clusterId, t*2 + 1]-r[dataId])) # contrainte de capacité controlant le passage dans le noeud fils droit
    else
        @constraint(m, [i in 1:clusterCount, t in 1:sepCount], sum(a[j, t]*(clusters[i].uBounds[j]+mu_vect[j]-mu_min) for j in 1:featuresCount) + mu_min <= b[t] + (1+mu_max)*(1-u_at[i, t*2])) # contrainte de capacité controlant le passage dans le noeud fils gauche
        @constraint(m, [i in 1:clusterCount, t in 1:sepCount], sum(a[j, t]*clusters[i].lBounds[j] for j in 1:featuresCount) >= b[t] - (1-u_at[i, t*2 + 1])) # contrainte de capacité controlant le passage dans le noeud fils droit
        end 
        @constraint(m, [i in 1:clusterCount, t in 1:sepCount], u_at[i, t*2+1] <= sum(a[j, t] for j in 1:featuresCount)) # contrainte de capacité empechant les données de passer dans le fils droit d'un noeud n'appliquant pas de règle de branchement
    end

    ## Déclaration de l'objectif
    @objective(m, Max, sum(length(clusters[i].dataIds) * u_at[i, 1] for i in 1:clusterCount)) 

    starting_time = time()
    optimize!(m)
    resolution_time = time() - starting_time

    gap = -1.0


    # Arbre obtenu (vide si le solveur n'a trouvé aucune solution)
    T = nothing
    objective = -1
    
    # Si une solution a été trouvée
    if primal_status(m) == MOI.FEASIBLE_POINT
    # class[t] : classe prédite par le sommet t
    class = Vector{Int64}(undef, sepCount+leavesCount)
    for t in 1:(sepCount+leavesCount)
        k = argmax(value.(c[:, t]))
        if value.(c[k, t]) >= 1.0 - 10^-4
            class[t] = k
        else
            class[t] = -1
        end
    end
        
        objective = JuMP.objective_value(m)

        # Si une solution optimale a été trouvée
        if termination_status(m) == MOI.OPTIMAL
            gap = 0
        else
            # Calcul du gap relatif entre l'objectif de la meilleure solution entière et la borne continue en fin de résolution
            bound = JuMP.objective_bound(m)
            gap = 100.0 * abs(objective - bound) / (objective + 10^-4) # +10^-4 permet d'éviter de diviser par 0
        end   
        
        # Construction d'une variable de type Tree dans laquelle chaque séparation est recentrée
        if multivariate
            T = Tree(D, class, round.(Int, value.(u_at)), round.(Int, value.(s)), clusters)
        else
            T = Tree(D, value.(a), class, round.(Int, value.(u_at)), clusters)
        end
    end   

    return T, objective, resolution_time, gap
end

"""
Construit un arbre de décision par résolution itérative des formulations F^e_S ou F^h_S

Entrées :
- clusters : partition des données d'entraînement (chaque cluster contient des données de même classe)
- D : Nombre maximal de séparations d'une branche (profondeur de l'arbre - 1)
- multivariate (optionnel): vrai si les séparations sont multivariées; faux si elles sont univariées (faux par défaut)
- mu (optionnel, utilisé en multivarié): distance minimale à gauche d'une séparation où aucune donnée ne peut se trouver (i.e., pour la séparation ax <= b, il n'y aura aucune donnée dans ]b - ax - mu, b - ax[) (10^-4 par défaut)
- time_limits (optionnel) : temps maximal de résolution (-1 si le temps n'est pas limité) (-1 par défaut)
- isExact (optionnel) : vrai si la formulation F^e_S est utilisée; la formulation F^h_S est utilisée sinon (false par défaut)
"""
function iteratively_build_tree(clusters::Vector{Cluster}, D::Int64, x::Matrix{Float64}, y::Vector{Any}, classes::Vector{Any};multivariate::Bool=false, time_limit::Int64 = -1, mu::Float64=10^(-4), isExact::Bool=false, shiftSeparations::Bool=false)

    startingTime = time()
    finalTime = startingTime + time_limit

    # Define variables used as return values
    # (otherwise they would not be defined outside of the while loop)
    lastObjective = nothing
    lastFeasibleT = nothing
    gap = nothing

    clusterSplit = true
    iterationCount = 0

    useFhS = !isExact
    useFeS = isExact

    # While cluster are split and the time limit is not reached
    while clusterSplit && (time_limit == -1 || time() < finalTime)

        iterationCount += 1
        remainingTime = round(Int, finalTime-time())
        
        # Solve with the current clusters
        T, objective, resolution_time, gap = build_tree(clusters, D, classes, multivariate=multivariate, time_limit=time_limit==-1 ? -1 : remainingTime, useFhS=useFhS, useFeS=useFeS)

        # If a solution has been obtained
        if objective != -1

            if shiftSeparations
                T = naivelyShiftSeparations(T, x, y, classes, clusters)
            end 
            
            # List of the clusters for the next iteration
            newClusters = Vector{Cluster}()

            # For each cluster
            for cluster in clusters

                # Split its data according to the leaves of tree T they reach
                newCurrentClusters = getSplitClusters(cluster, T)
                append!(newClusters, newCurrentClusters)
            end

            # If no cluster is split
            if length(clusters) == length(newClusters)
                clusterSplit = false
            else 
                clusters = newClusters
            end
            lastFeasibleT = T
            lastObjective = objective
        end 
    end

    resolution_time = time() - startingTime
    return lastFeasibleT, lastObjective, resolution_time, gap, iterationCount
end

