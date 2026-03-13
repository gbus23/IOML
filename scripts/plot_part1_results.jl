# Figures Partie 1 → doc/figures/

using Pkg
if !haskey(Pkg.project().dependencies, "Plots")
    Pkg.add("Plots")
    Pkg.add("CSV")
    Pkg.add("DataFrames")
end
using Plots
using CSV
using DataFrames

const SCRIPT_DIR = @__DIR__
const PROJECT_ROOT = abspath(joinpath(SCRIPT_DIR, ".."))
const CSV_PATH = joinpath(PROJECT_ROOT, "results", "part1_results.csv")
const FIG_DIR = joinpath(PROJECT_ROOT, "doc", "figures")

default(
    fontfamily = "sans-serif",
    titlefontsize = 11,
    legendfontsize = 9,
    guidefontsize = 10,
    tickfontsize = 9,
    grid = true,
    legend = :best,
)

function find_csv()
    isfile(CSV_PATH) && return CSV_PATH
    for alt in [joinpath(pwd(), "results", "part1_results.csv"), joinpath(pwd(), "part1_results.csv")]
        isfile(alt) && return alt
    end
    return nothing
end

is_none(r) = r == "none" || (isa(r, String) && lowercase(string(r)) == "none")

function rd_to_num(r)
    is_none(r) && return 0.0
    r isa Number && return Float64(r)
    return try parse(Float64, string(r)) catch; 0.0 end
end

to_float(x) = x isa Number ? Float64(x) : (try parse(Float64, string(x)) catch; 0.0 end)

const RD_DISPLAY_ORDER = [0, 2, 1, 3, 4]
const RD_LABELS = ["none", "2", "1", "3", "4"]

rd_to_xpos(rd) = (idx = findfirst(==(Int(round(rd))), RD_DISPLAY_ORDER); idx === nothing ? 0 : idx - 1)

function sort_by_rd_order(rd_num, y)
    xpos = [rd_to_xpos(r) for r in rd_num]
    perm = sortperm(xpos)
    xpos[perm], y[perm]
end

function xticks_for_rounding(xpos_list)
    u = sort(unique(xpos_list))
    labels = [i + 1 <= length(RD_LABELS) ? RD_LABELS[i + 1] : string(i) for i in u]
    return (u, labels)
end

function savepng(plt, name)
    fp = joinpath(FIG_DIR, name * ".png")
    savefig(plt, fp)
    println("  -> ", fp)
end

function main()
    csv_path = find_csv()
    if csv_path === nothing
        println("ERREUR: Fichier CSV introuvable. Lancez d'abord run_part1.jl ou run_part1_with_rounding.jl")
        return
    end
    println("CSV: ", csv_path)
    mkpath(FIG_DIR)
    println("Figures: ", FIG_DIR)

    df = CSV.read(csv_path, DataFrame)
    n = nrow(df)
    if n == 0
        println("Aucune donnée.")
        return
    end
    println("Lignes: ", n)

    datasets = unique(df.dataset)
    depths = unique(df.depth)

    # Égalités vs arrondi (global)
    df_eq = df[(df.config .== "avec_egalites") .& (df.depth .== 2), :]
    if nrow(df_eq) > 0
        p = plot(size = (600, 400))
        colors = [:blue, :red, :green]
        all_x = Int[]
        for (idx, ds) in enumerate(datasets)
            sub = df_eq[df_eq.dataset .== ds, :]
            rd_num = [rd_to_num(r) for r in sub.round_digits]
            neq = [to_float(v) for v in sub.n_equalities]
            x, y = sort_by_rd_order(rd_num, neq)
            append!(all_x, x)
            plot!(p, x, y, label = String(ds), lw = 2, marker = (:circle, 6),
                  color = colors[mod1(idx, length(colors))])
        end
        u, lab = xticks_for_rounding(all_x)
        xticks!(p, u, lab)
        xlabel!(p, "Précision d'arrondi (décimales)")
        ylabel!(p, "Nombre d'égalités (linked sets + box corners)")
        title!(p, "Évolution du nombre d'égalités selon l'arrondi (D=2)")
        savepng(p, "part1_equalities_vs_rounding_global")
    end

    # Par dataset
    for ds in datasets
        sub = df[df.dataset .== ds, :]
        nsub = nrow(sub)
        if nsub == 0
            continue
        end
        ds_str = String(ds)
        sub_avec = sub[sub.config .== "avec_egalites", :]

        layout = @layout [a; b c]
        p_combined = plot(layout = layout, size = (700, 700))
        xpos_eq = Int[]
        xpos_time = Int[]
        xpos_nodes = Int[]

        # Égalités
        for (i, D) in enumerate([2, 3])
            s = sub_avec[sub_avec.depth .== D, :]
            if nrow(s) > 0
                rd_num = [rd_to_num(r) for r in s.round_digits]
                neq = [to_float(v) for v in s.n_equalities]
                x, y = sort_by_rd_order(rd_num, neq)
                append!(xpos_eq, x)
                if i == 1
                    plot!(p_combined, x, y, subplot = 1, lw = 2, marker = (:circle, 5),
                          label = "D=$D", xlabel = "Arrondi", ylabel = "Nb égalités",
                          title = ds_str * " : égalités (linked sets + box corners) vs arrondi")
                else
                    plot!(p_combined, x, y, subplot = 1, lw = 2, marker = (:circle, 5), label = "D=$D")
                end
            end
        end
        if !isempty(xpos_eq)
            u, lab = xticks_for_rounding(xpos_eq)
            xticks!(p_combined, u, lab, subplot = 1)
        end

        # Temps
        for (cfg, lab) in [("sans_egalites", "sans"), ("avec_egalites", "avec")]
            s = sub[(sub.config .== cfg) .& (sub.depth .== 2), :]
            if nrow(s) > 0
                rd_num = [rd_to_num(r) for r in s.round_digits]
                t = [to_float(v) for v in s.time_sec]
                x, y = sort_by_rd_order(rd_num, t)
                append!(xpos_time, x)
                plot!(p_combined, x, y, subplot = 2, lw = 2, marker = (:rect, 5), label = lab,
                      xlabel = "Arrondi", ylabel = "Temps (s)", title = ds_str * " : temps (D=2)")
            end
        end
        if !isempty(xpos_time)
            u, lab = xticks_for_rounding(xpos_time)
            xticks!(p_combined, u, lab, subplot = 2)
        end

        # Nœuds B&B
        for (cfg, lab) in [("sans_egalites", "sans"), ("avec_egalites", "avec")]
            s = sub[(sub.config .== cfg) .& (sub.depth .== 2), :]
            if nrow(s) > 0
                rd_num = [rd_to_num(r) for r in s.round_digits]
                nodes = [to_float(n) for n in s.nodes_bb]
                x, y = sort_by_rd_order(rd_num, nodes)
                append!(xpos_nodes, x)
                plot!(p_combined, x, y, subplot = 3, lw = 2, marker = (:diamond, 5), label = lab,
                      xlabel = "Arrondi", ylabel = "Nœuds B&B", title = ds_str * " : nœuds B&B (D=2)")
            end
        end
        if !isempty(xpos_nodes)
            u, lab = xticks_for_rounding(xpos_nodes)
            xticks!(p_combined, u, lab, subplot = 3)
        end

        savepng(p_combined, "part1_$(ds_str)_summary")
    end

    # Barres temps
    idx_none = [is_none(r) for r in df.round_digits]
    df2 = df[(df.depth .== 2) .& idx_none, :]
    if nrow(df2) >= 2
        ds_list = unique(df2.dataset)
        sans_t = Float64[]
        avec_t = Float64[]
        for d in ds_list
            r = df2[(df2.dataset .== d) .& (df2.config .== "sans_egalites"), :]
            push!(sans_t, nrow(r) > 0 ? to_float(r.time_sec[1]) : 0.0)
            r = df2[(df2.dataset .== d) .& (df2.config .== "avec_egalites"), :]
            push!(avec_t, nrow(r) > 0 ? to_float(r.time_sec[1]) : 0.0)
        end
        p = bar(string.(ds_list), [sans_t avec_t],
                label = ["sans égalités" "avec égalités (linked + box)"],
                xlabel = "Dataset", ylabel = "Temps (s)",
                title = "Temps de résolution (D=2, sans arrondi)")
        savepng(p, "part1_time_sans_vs_avec")
    end

    # Barres nœuds
    if nrow(df2) >= 2
        ds_list = unique(df2.dataset)
        sans_n = Float64[]
        avec_n = Float64[]
        for d in ds_list
            r = df2[(df2.dataset .== d) .& (df2.config .== "sans_egalites"), :]
            push!(sans_n, nrow(r) > 0 ? to_float(r.nodes_bb[1]) : 0.0)
            r = df2[(df2.dataset .== d) .& (df2.config .== "avec_egalites"), :]
            push!(avec_n, nrow(r) > 0 ? to_float(r.nodes_bb[1]) : 0.0)
        end
        p = bar(string.(ds_list), [sans_n avec_n],
                label = ["sans égalités" "avec égalités (linked + box)"],
                xlabel = "Dataset", ylabel = "Nœuds B&B",
                title = "Nœuds du branch-and-bound (D=2, sans arrondi)")
        savepng(p, "part1_nodes_bb_sans_vs_avec")
    end

    # Égalités par dataset
    for ds in datasets
        sub = df[(df.dataset .== ds) .& (df.config .== "avec_egalites"), :]
        if nrow(sub) == 0
            continue
        end
        p = plot(size = (500, 350))
        xpos_used = Int[]
        for D in sort(unique(sub.depth))
            s = sub[sub.depth .== D, :]
            if nrow(s) > 0
                rd_num = [rd_to_num(r) for r in s.round_digits]
                y = [to_float(v) for v in s.n_equalities]
                x, y_sorted = sort_by_rd_order(rd_num, y)
                append!(xpos_used, x)
                plot!(p, x, y_sorted, lw = 2.5, marker = (:circle, 8), label = "Profondeur D = $D")
            end
        end
        if !isempty(xpos_used)
            u, lab = xticks_for_rounding(xpos_used)
            xticks!(p, u, lab)
        end
        xlabel!(p, "Précision d'arrondi")
        ylabel!(p, "Nombre d'égalités (linked sets + box corners)")
        title!(p, String(ds) * " : égalités selon l'arrondi")
        savepng(p, "part1_$(ds)_equalities_vs_rounding")
    end

    println("Terminé. Figures dans: ", FIG_DIR)
end

main()
