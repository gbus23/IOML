# Génère les figures du rapport → doc/figures/

using Pkg
for pkg in ["Plots", "StatsPlots", "CSV", "DataFrames"]
    haskey(Pkg.project().dependencies, pkg) || Pkg.add(pkg)
end

using Plots, StatsPlots, CSV, DataFrames
gr()

const PROJECT_ROOT = abspath(joinpath(@__DIR__, ".."))
const RESULTS_DIR  = joinpath(PROJECT_ROOT, "results")
const FIG_DIR      = joinpath(PROJECT_ROOT, "doc", "figures")
const DS_LIST      = ["iris", "seeds", "wine", "glass", "ecoli"]

default(
    fontfamily       = "sans-serif",
    titlefontsize    = 12,
    legendfontsize   = 9,
    guidefontsize    = 11,
    tickfontsize     = 9,
    grid             = true,
    gridalpha        = 0.35,
    legend           = :best,
    background_color = :white,
    framestyle       = :box,
)

# Style un peu plus soigné pour les figures *enrichies* (nouveaux fichiers uniquement)
function style_enriched!(p)
    plot!(p; gridlinewidth = 0.8, minorgrid = true, minorgridalpha = 0.2,
        tick_direction = :in)
    p
end

const COLORS = [:steelblue, :darkorange, :forestgreen, :indianred,
                :mediumpurple, :sienna, :hotpink, :gray, :olive, :teal]

to_float(x) = x isa Number ? Float64(x) : (try parse(Float64, string(x)) catch; 0.0 end)

function savepng(p, name)
    png_name = endswith(name, ".png") ? name : string(name, ".png")
    pdf_name = replace(png_name, r"\.png$" => ".pdf")
    png_path = joinpath(FIG_DIR, png_name)
    pdf_path = joinpath(FIG_DIR, pdf_name)
    savefig(p, png_path)
    savefig(p, pdf_path)
    println("  ✓ $png_path")
    println("  ✓ $pdf_path")
end

function read_csv_safe(fname)
    path = joinpath(RESULTS_DIR, fname)
    if !isfile(path)
        println("  ⚠ $fname introuvable — section ignorée")
        return nothing
    end
    df = CSV.read(path, DataFrame)
    println("  Chargé $fname ($(nrow(df)) lignes)")
    df
end

"""First-row value of `col` matching all `(column, value)` filter pairs."""
function val(df, col::Symbol, pairs...)
    sub = df
    for (c, v) in pairs
        sub = sub[sub[!, c] .== v, :]
    end
    nrow(sub) == 0 && return 0.0
    to_float(sub[1, col])
end

function generate_part1(df)
    println("\n── Partie 1 ──")
    ds_list = DS_LIST
    df[!, :round_digits] = string.(df.round_digits)

    # Temps avec/sans égalités
    xlabs = String[]; sans_t = Float64[]; avec_t = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(xlabs, "$ds D=$D")
        push!(sans_t, val(df, :time_sec,
            (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none")))
        push!(avec_t, val(df, :time_sec,
            (:dataset, ds), (:depth, D), (:config, "avec_egalites"), (:round_digits, "none")))
    end
    p = groupedbar(xlabs, [sans_t avec_t];
        label = ["Sans égalités" "Avec égalités"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Temps (s)",
        title = "Temps de résolution avec/sans égalités",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.5)
    savepng(p, "part1_time_comparison.png")

    # Nœuds B&B
    sans_n = Float64[]; avec_n = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(sans_n, val(df, :nodes_bb,
            (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none")))
        push!(avec_n, val(df, :nodes_bb,
            (:dataset, ds), (:depth, D), (:config, "avec_egalites"), (:round_digits, "none")))
    end
    p = groupedbar(xlabs, [sans_n avec_n];
        label = ["Sans égalités" "Avec égalités"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Nœuds B&B",
        title = "Nœuds B&B avec/sans égalités",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.5)
    savepng(p, "part1_nodes_comparison.png")

    # Égalités vs arrondi
    rd_order = ["none", "2", "1"]
    mat = zeros(length(ds_list), length(rd_order))
    for (i, ds) in enumerate(ds_list), (j, rd) in enumerate(rd_order)
        mat[i, j] = val(df, :n_equalities,
            (:dataset, ds), (:depth, 2), (:config, "avec_egalites"), (:round_digits, rd))
    end
    p = groupedbar(ds_list, mat;
        label = permutedims(["Arrondi : $r" for r in rd_order]),
        color = reshape(COLORS[1:3], 1, :),
        xlabel = "Dataset", ylabel = "Nombre d'égalités",
        title = "Nombre d'égalités selon l'arrondi",
        size = (800, 500), dpi = 600, bar_width = 0.55)
    savepng(p, "part1_equalities_by_rounding.png")

    # —— Figures enrichies (ne remplacent pas les précédentes) ——
    # Réduction relative des nœuds B&B quand on ajoute les coupes (none, D=2,3)
    xlabs2 = String[]; reduc = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(xlabs2, "$ds D=$D")
        sn = val(df, :nodes_bb, (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none"))
        an = val(df, :nodes_bb, (:dataset, ds), (:depth, D), (:config, "avec_egalites"), (:round_digits, "none"))
        push!(reduc, sn > 0 ? 100.0 * (sn - an) / sn : 0.0)
    end
    p = bar(xlabs2, reduc; label = "Réduction % des nœuds B&B",
        color = :coral,
        xlabel = "Dataset, profondeur", ylabel = "% nœuds en moins (avec vs sans égalités)",
        title = "Partie 1 — impact des égalités sur l’exploration B&B (arrondi = none)",
        size = (880, 520), dpi = 600, xrotation = 18, bar_width = 0.62, legend = false)
    savepng(style_enriched!(p), "part1_bb_node_reduction_pct.png")

    # Écart LP vs valeur entière : (UB_LP - z_MIP) / n_train (ordre de grandeur du trou d’intégralité)
    xlabs3 = String[]; gaps_lp = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(xlabs3, "$ds D=$D")
        z = val(df, :objective, (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none"))
        lp = val(df, :lp_value, (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none"))
        nt = val(df, :n_train, (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none"))
        push!(gaps_lp, nt > 0 ? max(0.0, (lp - z) / nt) : 0.0)
    end
    p = bar(xlabs3, gaps_lp; label = "Sans égalités (flux unitaire)",
        color = :teal, xlabel = "Dataset, profondeur",
        ylabel = "(valeur LP − objectif MIP) / n_train",
        title = "Partie 1 — trou LP/MIP normalisé (↑ = relaxation plus lâche avant coupes)",
        size = (880, 520), dpi = 600, xrotation = 18, legend = false)
    savepng(style_enriched!(p), "part1_lp_mip_gap_normalized.png")
end

function generate_part2(df)
    println("\n── Partie 2 ──")
    ds_list = DS_LIST
    cfgs = [
        "sans_equite",
        "contrainte_stricte_demographic_parity",
        "contrainte_tolerance_demographic_parity",
        "penalite_demographic_parity",
    ]
    cfg_labels = ["Sans", "Stricte", "Tol. 0.15", "Pénalité"]
    nc = length(cfgs)

    # Erreurs train par config
    mat = zeros(length(ds_list), nc)
    for (i, ds) in enumerate(ds_list), (j, cfg) in enumerate(cfgs)
        mat[i, j] = val(df, :err_train, (:dataset, ds), (:depth, 2), (:config, cfg))
    end
    p = groupedbar(ds_list, mat;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Erreurs d'entraînement",
        title = "Erreurs train selon la configuration d'équité (D=2)",
        size = (800, 500), dpi = 600, bar_width = 0.55)
    savepng(p, "part2_accuracy_vs_fairness.png")

    # Parity gap
    mat_pg = zeros(length(ds_list), nc)
    for (i, ds) in enumerate(ds_list), (j, cfg) in enumerate(cfgs)
        mat_pg[i, j] = val(df, :parity_gap, (:dataset, ds), (:depth, 2), (:config, cfg))
    end
    p = groupedbar(ds_list, mat_pg;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Parity gap",
        title = "Parity gap par configuration (D=2)",
        size = (800, 500), dpi = 600, bar_width = 0.55)
    savepng(p, "part2_parity_gap.png")

    # —— Enrichi : coût en erreurs test vs baseline “sans équité” (plus lisible que les barres brutes)
    cost_cfg_ids = [
        ("contrainte_stricte_demographic_parity", "Stricte"),
        ("contrainte_tolerance_demographic_parity", "Tolérance"),
        ("penalite_demographic_parity", "Pénalité"),
    ]
    for D in [2, 3]
        mat_c = zeros(length(ds_list), length(cost_cfg_ids))
        for (i, ds) in enumerate(ds_list)
            base = val(df, :err_test, (:dataset, ds), (:depth, D), (:config, "sans_equite"))
            for (j, (cid, _)) in enumerate(cost_cfg_ids)
                mat_c[i, j] = val(df, :err_test, (:dataset, ds), (:depth, D), (:config, cid)) - base
            end
        end
        labels_short = [s[2] for s in cost_cfg_ids]
        p = groupedbar(ds_list, mat_c;
            label = permutedims(labels_short),
            color = reshape([:firebrick :darkcyan :mediumpurple], 1, :),
            xlabel = "Dataset",
            ylabel = "Δ erreurs test vs sans équité",
            title = "Partie 2 — coût équité (hausse des erreurs test, D=$D)",
            size = (880, 500), dpi = 600, bar_width = 0.55, legend = :topright)
        hline!(p, [0]; color = :gray, linestyle = :dash, label = "Baseline", linewidth = 1.5)
        savepng(style_enriched!(p), "part2_fairness_cost_delta_test_D$(D).png")
    end

    # Nuage : compromis direct (points non reliés pour éviter les zigzags visuels), D=2
    cfg_path = ["sans_equite", "penalite_demographic_parity",
        "contrainte_tolerance_demographic_parity", "contrainte_stricte_demographic_parity"]
    p = plot(; title = "Partie 2 — nuage équité / précision (D=2, test)",
        xlabel = "Parity gap (|P(ŷ|A)−P(ŷ|B)|)", ylabel = "Erreurs test",
        size = (820, 520), dpi = 600, legend = :topright)
    for (k, ds) in enumerate(ds_list)
        xs = Float64[]; ys = Float64[]
        for cid in cfg_path
            push!(xs, val(df, :parity_gap, (:dataset, ds), (:depth, 2), (:config, cid)))
            push!(ys, val(df, :err_test, (:dataset, ds), (:depth, 2), (:config, cid)))
        end
        scatter!(p, xs, ys; marker = :circle, markersize = 6, label = ds,
            markerstrokewidth = 0.7, color = COLORS[mod1(k, length(COLORS))])
    end
    savepng(style_enriched!(p), "part2_fairness_tradeoff_paths_D2.png")
end

function generate_part3(df)
    println("\n── Partie 3 ──")
    ds_list = DS_LIST

    xlabs  = String[]
    sans_e = Float64[]; avec_e = Float64[]
    sans_t = Float64[]; avec_t = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(xlabs, "$ds D=$D")
        push!(sans_e, val(df, :err_test,  (:dataset, ds), (:depth, D), (:config, "sans_nouvelles_features")))
        push!(avec_e, val(df, :err_test,  (:dataset, ds), (:depth, D), (:config, "avec_nouvelles_features")))
        push!(sans_t, val(df, :time_sec,  (:dataset, ds), (:depth, D), (:config, "sans_nouvelles_features")))
        push!(avec_t, val(df, :time_sec,  (:dataset, ds), (:depth, D), (:config, "avec_nouvelles_features")))
    end

    # Erreurs test sans/avec
    p = groupedbar(xlabs, [sans_e avec_e];
        label = ["Sans features dérivées" "Avec features dérivées"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Erreurs test",
        title = "Erreurs test : sans vs avec features dérivées",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.5)
    savepng(p, "part3_errors_comparison.png")

    # Temps sans/avec
    p = groupedbar(xlabs, [sans_t avec_t];
        label = ["Sans features dérivées" "Avec features dérivées"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Temps (s)",
        title = "Temps : sans vs avec features dérivées",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.5)
    savepng(p, "part3_time_comparison.png")

    # —— Enrichi : gain net sur le test (sans − avec) : positif = moins d’erreurs avec features dérivées
    xlabs4 = String[]; gain = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(xlabs4, "$ds D=$D")
        s = val(df, :err_test, (:dataset, ds), (:depth, D), (:config, "sans_nouvelles_features"))
        a = val(df, :err_test, (:dataset, ds), (:depth, D), (:config, "avec_nouvelles_features"))
        push!(gain, s - a)
    end
    cols_gain = [g >= 0 ? :seagreen : :tomato for g in gain]
    p = bar(xlabs4, gain; label = "Δ err. test (sans − avec)", color = cols_gain,
        xlabel = "Dataset, profondeur", ylabel = "Baisse d’erreurs test (points)",
        title = "Partie 3 — efficacité des features dérivées sur le généralisation",
        size = (880, 520), dpi = 600, xrotation = 16, bar_width = 0.65, legend = false)
    hline!(p, [0]; color = :black, linestyle = :dot, label = "", linewidth = 1)
    savepng(style_enriched!(p), "part3_test_error_delta_features.png")
end

function generate_part4(df)
    println("\n── Partie 4 ──")
    ds_list = DS_LIST
    cfgs = ["5.1_standard", "5.2_ES", "5.3_alt_replace",
            "5.3_alt_both", "5.3_lazy", "formulation_F"]
    cfg_labels = ["Standard", "ES", "Alt replace", "Alt both", "Lazy", "Form. F"]
    nc = length(cfgs)

    # Temps par config D=3
    mat = zeros(length(ds_list), nc)
    for (i, ds) in enumerate(ds_list), (j, cfg) in enumerate(cfgs)
        mat[i, j] = val(df, :time_sec, (:dataset, ds), (:depth, 3), (:config, cfg))
    end
    p = groupedbar(ds_list, mat;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Temps (s)",
        title = "Temps de résolution par configuration (D=3, données binaires)",
        size = (800, 500), dpi = 600, bar_width = 0.52, legend = :topleft)
    savepng(p, "part4_time_by_config.png")

    # Speedup Form.F / Standard
    xlabs = String[]; speedups = Float64[]
    for ds in ds_list, D in [2, 3]
        t_f   = val(df, :time_sec, (:dataset, ds), (:depth, D), (:config, "formulation_F"))
        t_std = val(df, :time_sec, (:dataset, ds), (:depth, D), (:config, "5.1_standard"))
        push!(xlabs, "$ds D=$D")
        push!(speedups, t_std > 0 ? t_f / t_std : 0.0)
    end
    p = bar(xlabs, speedups;
        label = "time(Form. F) / time(Standard)",
        color = :mediumpurple,
        xlabel = "Dataset et profondeur", ylabel = "Ratio de temps",
        title = "Accélération de la formulation binaire vs F",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.6, legend = :topleft)
    savepng(p, "part4_speedup.png")

    # —— Enrichi : erreurs test par formulation (D=3) — complète le diagnostic “temps”
    mat_e = zeros(length(ds_list), nc)
    for (i, ds) in enumerate(ds_list), (j, cfg) in enumerate(cfgs)
        mat_e[i, j] = val(df, :err_test, (:dataset, ds), (:depth, 3), (:config, cfg))
    end
    p = groupedbar(ds_list, mat_e;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Erreurs test",
        title = "Partie 4 — qualité prédictive par configuration (D=3)",
        size = (900, 540), dpi = 600, bar_width = 0.5, legend = :outertopright)
    savepng(style_enriched!(p), "part4_err_test_by_config_D3.png")

    # Carte gap solveur (MIP non terminé) : utile pour contextualiser les temps
    gap_m = zeros(length(ds_list), nc)
    for (i, ds) in enumerate(ds_list), (j, cfg) in enumerate(cfgs)
        gap_m[i, j] = val(df, :gap_pct, (:dataset, ds), (:depth, 3), (:config, cfg))
    end
    p = heatmap(cfg_labels, ds_list, gap_m;
        xlabel = "Configuration", ylabel = "Dataset",
        title = "Partie 4 — gap MIP CPLEX % (D=3 ; 0 = optimal prouvé)",
        clims = (0, max(0.01, maximum(gap_m))), color = :inferno,
        size = (840, 500), dpi = 600, xrotation = 25)
    savepng(style_enriched!(p), "part4_mip_gap_heatmap_D3.png")
end

function main()
    println("Génération des figures")
    println("Racine : $PROJECT_ROOT")
    mkpath(FIG_DIR)
    println("Figures → $FIG_DIR\n")

    n_generated = 0

    for (fname, gen) in [
        ("part1_results_v3.csv", generate_part1),
        ("part2_results.csv", generate_part2),
        ("part3_results.csv", generate_part3),
        ("part4_results.csv", generate_part4),
    ]
        df = read_csv_safe(fname)
        if df !== nothing
            try
                gen(df)
            catch e
                println("  ✗ Erreur lors de la génération ($fname) : ", e)
            end
        end
    end

    figs_png = filter(f -> endswith(f, ".png"), readdir(FIG_DIR))
    figs_pdf = filter(f -> endswith(f, ".pdf"), readdir(FIG_DIR))
    println("$(length(figs_png)) figures PNG + $(length(figs_pdf)) figures PDF → $FIG_DIR")
end

main()
