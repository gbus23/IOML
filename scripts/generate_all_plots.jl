# Génère les figures du rapport → doc/figures/

using Pkg
for pkg in ["Plots", "CSV", "DataFrames"]
    haskey(Pkg.project().dependencies, pkg) || Pkg.add(pkg)
end

using Plots, CSV, DataFrames
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
    legend           = :best,
    background_color = :white,
)

const COLORS = [:steelblue, :darkorange, :forestgreen, :indianred,
                :mediumpurple, :sienna, :hotpink, :gray, :olive, :teal]

to_float(x) = x isa Number ? Float64(x) : (try parse(Float64, string(x)) catch; 0.0 end)

function savepng(p, name)
    path = joinpath(FIG_DIR, name)
    savefig(p, path)
    println("  ✓ $path")
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
    p = bar(xlabs, [sans_t avec_t];
        label = ["Sans égalités" "Avec égalités"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Temps (s)",
        title = "Temps de résolution avec/sans égalités",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.7)
    savepng(p, "part1_time_comparison.png")

    # Nœuds B&B
    sans_n = Float64[]; avec_n = Float64[]
    for ds in ds_list, D in [2, 3]
        push!(sans_n, val(df, :nodes_bb,
            (:dataset, ds), (:depth, D), (:config, "sans_egalites"), (:round_digits, "none")))
        push!(avec_n, val(df, :nodes_bb,
            (:dataset, ds), (:depth, D), (:config, "avec_egalites"), (:round_digits, "none")))
    end
    p = bar(xlabs, [sans_n avec_n];
        label = ["Sans égalités" "Avec égalités"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Nœuds B&B",
        title = "Nœuds B&B avec/sans égalités",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.7)
    savepng(p, "part1_nodes_comparison.png")

    # Égalités vs arrondi
    rd_order = ["none", "2", "1"]
    mat = zeros(length(ds_list), length(rd_order))
    for (i, ds) in enumerate(ds_list), (j, rd) in enumerate(rd_order)
        mat[i, j] = val(df, :n_equalities,
            (:dataset, ds), (:depth, 2), (:config, "avec_egalites"), (:round_digits, rd))
    end
    p = bar(ds_list, mat;
        label = permutedims(["Arrondi : $r" for r in rd_order]),
        color = reshape(COLORS[1:3], 1, :),
        xlabel = "Dataset", ylabel = "Nombre d'égalités",
        title = "Nombre d'égalités selon l'arrondi",
        size = (800, 500), dpi = 600, bar_width = 0.7)
    savepng(p, "part1_equalities_by_rounding.png")
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
    p = bar(ds_list, mat;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Erreurs d'entraînement",
        title = "Erreurs train selon la configuration d'équité (D=2)",
        size = (800, 500), dpi = 600, bar_width = 0.7)
    savepng(p, "part2_accuracy_vs_fairness.png")

    # Parity gap
    mat_pg = zeros(length(ds_list), nc)
    for (i, ds) in enumerate(ds_list), (j, cfg) in enumerate(cfgs)
        mat_pg[i, j] = val(df, :parity_gap, (:dataset, ds), (:depth, 2), (:config, cfg))
    end
    p = bar(ds_list, mat_pg;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Parity gap",
        title = "Parity gap par configuration (D=2)",
        size = (800, 500), dpi = 600, bar_width = 0.7)
    savepng(p, "part2_parity_gap.png")
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
    p = bar(xlabs, [sans_e avec_e];
        label = ["Sans features dérivées" "Avec features dérivées"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Erreurs test",
        title = "Erreurs test : sans vs avec features dérivées",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.7)
    savepng(p, "part3_errors_comparison.png")

    # Temps sans/avec
    p = bar(xlabs, [sans_t avec_t];
        label = ["Sans features dérivées" "Avec features dérivées"],
        color = [:steelblue :darkorange],
        xlabel = "Dataset et profondeur", ylabel = "Temps (s)",
        title = "Temps : sans vs avec features dérivées",
        size = (800, 500), dpi = 600, xrotation = 15, bar_width = 0.7)
    savepng(p, "part3_time_comparison.png")
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
    p = bar(ds_list, mat;
        label = permutedims(cfg_labels),
        color = reshape(COLORS[1:nc], 1, :),
        xlabel = "Dataset", ylabel = "Temps (s)",
        title = "Temps de résolution par configuration (D=3, données binaires)",
        size = (800, 500), dpi = 600, bar_width = 0.7, legend = :topleft)
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

    figs = filter(f -> endswith(f, ".png"), readdir(FIG_DIR))
    println("$(length(figs)) figures → $FIG_DIR")
end

main()
