# Projet – Arbres de décision optimaux (optimisation en nombres entiers)

Ce dépôt contient l’implémentation en **Julia** du projet de cours (arbres de classification optimaux, formulation F, égalités “linked sets” (Section 4), parties 2–4, etc.).

---

## Structure du projet

```
projet/
├── README.md                 # Ce fichier (description et mode d’emploi)
├── run_all.jl                # **Un seul script** : main + parties 1–4 (CSV) ; option env IOML_RUN_CLUSTERING
├── run_main.jl               # Lance la résolution F standard (univarié / multivarié)
├── run_part1.jl              # Partie 1 sans arrondi (flux unitaire + box equalities)
├── run_part1_with_rounding.jl # Partie 1 avec arrondi (none, 2, 3, 4 décimales)
├── run_part2.jl               # Partie 2 : arbres équitables (fairness)
├── run_part3.jl               # Partie 3 : nouvelles features dérivées
├── run_part4.jl               # Partie 4 : formulation binaire (Section 5.1)
├── data/
│   ├── iris.txt, seeds.txt, wine.txt   # jeux fournis
│   ├── glass.txt, ecoli.txt            # deux jeux supplémentaires (sujet)
├── results/
│   ├── part1_results.csv  # Partie 1 (run_part1.jl)
│   ├── part2_results.csv  # Partie 2 (run_part2.jl)
│   ├── part3_results.csv  # Partie 3 (run_part3.jl)
│   └── part4_results.csv  # Partie 4 (run_part4.jl)
├── doc/
│   ├── rapport_partie1.tex    # Rapport LaTeX Partie 1
│   ├── proof_section4_proposition.md
│   └── figures/               # Figures générées (PDF/PNG) pour le rapport
├── scripts/
│   └── generate_all_plots.jl  # Figures PNG (parties 1–4 + variantes enrichies)
└── src/
    ├── datasets_config.jl       # `DEFAULT_DATASETS`, `DEFAULT_TIME_LIMIT_MAIN` / `DEFAULT_TIME_LIMIT_PARTS` (env. `IOML_TL_*`)
    ├── main.jl                # Formulation F (uni / multivarié) — utilise `DEFAULT_DATASETS`
    ├── main_part1_box_equalities.jl   # Script Partie 1 (avec/sans égalités)
    ├── building_tree.jl       # Formulation F, flux unitaire, égalités box corners et linked sets
    ├── box_equalities.jl       # Détection opposite box corners et linked sets (Section 4)
    ├── cutting_plane_box.jl    # Algorithme à plans coupants pour les égalités
    ├── fairness.jl             # Partie 2 : métriques équité (parité démographique, equal opportunity)
    ├── main_part2_fairness.jl  # Script Partie 2 (avec/sans équité, contrainte ou pénalité)
    ├── feature_engineering.jl  # Partie 3 : génération et sélection de features dérivées
    ├── main_part3_features.jl  # Script Partie 3 (avec/sans nouvelles features)
    ├── binary_oct.jl           # Partie 4 : formulation binaire Section 5.1 (b_nf, p_n, w_nk, θ_i)
    ├── main_part4_binary.jl    # Script Partie 4 (formulation binaire vs F, binarisation)
    ├── utilities.jl            # train/test split, erreurs de prédiction, etc.
    ├── shift.jl
    ├── merge.jl
    ├── main_merge.jl
    ├── main_iterative_algorithm.jl
    └── struct/
        ├── tree.jl
        ├── cluster.jl
        ├── distance.jl
        └── ...
```

---

## Rapport Partie 1 (LaTeX)

Le rapport de la Partie 1 est dans \texttt{doc/rapport\_partie1.tex}. Il contient~: formulation F et flux unitaire, égalités linked sets (Section 4) (définitions, proposition, preuve), algorithmes (détection, cutting plane), arrondi des features, expériences et résultats (avec tableaux et figures TikZ : arbre, boîte 2D).

- **Compiler** : depuis \texttt{doc/} : \texttt{pdflatex rapport\_partie1.tex} (deux fois si besoin pour la table des matières).
- **Illustrations à partir des CSV** : placer \texttt{part1\_results\_v3.csv}, \texttt{part2\_results.csv}, \ldots{} dans \texttt{results/}, puis \texttt{julia --project=. scripts/generate\_all\_plots.jl}. Les PNG vont dans \texttt{doc/figures/} : figures « classiques » (\texttt{part1\_time\_comparison.png}, \ldots) + figures **enrichies** (impact B\&B, coût équité, delta features, heatmap gap MIP, etc.). Décommenter les \texttt{\\includegraphics} dans le rapport si besoin.

---

## Prérequis

- **Julia** (testé avec 1.x)
- **JuMP**
- **CPLEX** (optimiseur MIP)

Installer les paquets si besoin : `using Pkg; Pkg.add("JuMP"); Pkg.add("CPLEX")` (sous réserve de licence CPLEX).

**Temps CPLEX** : par défaut **180 s** pour `main()` et **300 s** pour `run_part1`…`run_part4` / `run_all.jl`. Tests rapides : `IOML_TL_MAIN=60 IOML_TL_PARTS=60 julia --project=. run_all.jl`. Rapport plus long : ex. `IOML_TL_MAIN=600 IOML_TL_PARTS=900`.

---

## Lancement

Depuis la racine du projet :

```bash
cd chemin/vers/projet
# Tout en une fois (main + parties 1–4, CSV dans results/) :
julia --project=. run_all.jl
# Variante avec clustering (FU + itératif, long) :
# IOML_RUN_CLUSTERING=1 julia --project=. run_all.jl

julia --project=. run_main.jl
julia run_part1.jl
julia run_part1_with_rounding.jl   # Partie 1 avec arrondi (none, 1, 2, 3, 4 décimales)
julia run_part2.jl                 # Partie 2 : arbres équitables (fairness)
julia run_part3.jl                 # Partie 3 : nouvelles features dérivées
julia run_part4.jl                 # Partie 4 : formulation binaire (Section 5.1)
```

**Important** : `run_part1(...)` est une **fonction Julia**. Pour l’appeler avec des options (ex. `round_digits_list`), il faut être dans le REPL Julia : lancer `julia`, puis `include("src/main_part1_box_equalities.jl")`, puis taper l’appel. Depuis PowerShell/terminal, utiliser les scripts `.jl` (ex. `julia run_part1_with_rounding.jl`) pour lancer des variantes.

- **`run_main.jl`** : appelle `main()` — formulation F sur les **cinq jeux** de `DEFAULT_DATASETS` (univarié et multivarié, D = 2…4). Temps CPLEX par défaut : **`DEFAULT_TIME_LIMIT_MAIN`** (180 s), surcharge `main(time_limit=…)` ou variable d’environnement **`IOML_TL_MAIN`**.
- **`main_merge()`** / **`main_iterative()`** : à inclure depuis `src/` ; ils bouclent aussi sur **`DEFAULT_DATASETS`** (même liste que le sujet : 3 + 2 jeux).
- **`run_part1.jl`** : Partie 1 sur les **cinq jeux**, D = 2 et 3, avec/sans égalités linked sets. Temps par défaut : **`DEFAULT_TIME_LIMIT_PARTS`** (300 s), ou **`IOML_TL_PARTS`** → **`results/part1_results.csv`**.

**Arrondi des features** : pour augmenter le nombre d’égalités “linked sets (Section 4)”, on peut arrondir les features après normalisation. Paramètre `round_digits_list` (liste de précisions) :
- `[nothing]` (défaut) : pas d’arrondi ;
- Pour **seeds / wine** (6 ou 13 features), 2 décimales donnent souvent 0 égalité ; **1 décimale** (valeurs 0.0, 0.1, …, 1.0) crée plus de coïncidences de coins → égalités possibles.
- Ex. `[nothing, 1, 2, 3, 4]` : comparer sans arrondi puis 1, 2, 3 et 4 décimales.

Exemples depuis la REPL :

```julia
include("src/main_part1_box_equalities.jl")
run_part1(save_results="results/part1_results.csv")
# avec plusieurs précisions d’arrondi (sans, 2, 3 décimales) :
run_part1(round_digits_list=[nothing, 2, 3], save_results="results/part1_results.csv")
# avec TOUTES les égalités (linked sets + opposite box corners) :
run_part1(save_results="results/part1_results.csv", use_box_corners_too=true)
# sans sauvegarde, un seul dataset, temps court :
run_part1(time_limit_sec=45, datasets=["iris"], depths=[2], save_results=nothing)
```

---

## Partie 1 – Résumé de ce qui a été fait

La Partie 1 porte sur les **égalités Section 4 (linked sets “linked sets (Section 4)” et linked sets** ; opposite box corners en option), pour les **arbres univariés** uniquement.

### 1. Adaptation de la formulation F : flux unitaire

- **Objectif** : avoir “un flux unitaire par échantillon” pour que la proposition du cours soit valide.
- **Modifications** :
  - Contrainte pour chaque point \(i\) : la somme des flots vers les feuilles vaut 1 :  
    \(\sum_{t \in \text{feuilles}} u^i_{t,w} = 1\).
  - On autorise le flot vers n’importe quelle feuille (y compris une feuille qui prédit une autre classe), sinon le problème serait souvent infaisable.
  - Objectif : maximiser le **nombre de bien classés**, linéarisé avec des variables \(z_{i,t}\) (\(z_{i,t} = u^i_{t,w} \cdot c_{k(i),t}\)).

Options dans `build_tree` : `unitary_flow=true` pour activer ce comportement.

### 2. Boîtes et coins opposés (Section 4)

- **Boîte** \(B(p^-, p^+)\) : ensemble des \(v\) tels que \(v_j \in [p^-_j, p^+_j]\) pour tout \(j\).
- **Coins opposés** : deux points dont les coordonnées sont, pour chaque \(j\), exactement \(p^-_j\) et \(p^+_j\).
- **Proposition (cours)** : avec flux unitaire, pour deux paires distinctes de coins opposés \((i_1,i_2)\) et \((i_3,i_4)\) d’une même boîte, l’égalité  
  \(u^{i_1}_{r,\ell(r)} + u^{i_2}_{r,\ell(r)} = u^{i_3}_{r,\ell(r)} + u^{i_4}_{r,\ell(r)}\)  
  est **valide** pour F (univarié).  
  Preuve détaillée : voir `doc/proof_section4_proposition.md`.

### 3. Implémentation des égalités

- **`src/box_equalities.jl`** :
  - Détection des paires de points qui sont des coins opposés d’une même boîte.
  - Énumération des opposite box corners ; détection des linked sets (Section 4). Pour les box corners “linked sets (Section 4)” **à la racine** (noeud 1, fils gauche = 2) :  
    `u_at[i1,2] + u_at[i2,2] == u_at[i3,2] + u_at[i4,2]`.
  - Fonction pour tester si une égalité est **violée** par une solution (relaxation ou MIP), utilisée dans le cutting plane.

- **`src/building_tree.jl`** :
  - Paramètres `box_equalities` / `box_equalities_list` pour les égalités opposite box corners (optionnel).
  - Paramètres `linked_set_equalities` / `linked_set_list` pour les égalités **linked sets** (Section 4). C’est cette option qui est utilisée dans le script Partie 1 pour la config « avec égalités ».
  - Si `linked_set_equalities=true` (et univarié), les égalités linked sets sont ajoutées à la formulation avant résolution.

### 4. Algorithme à plans coupants

- **`src/cutting_plane_box.jl`** :
  1. Résoudre la **relaxation linéaire** du MIP (flux unitaire, sans égalités au départ).
  2. Avec la solution de la relaxation, identifier les égalités **violées**.
  3. Ajouter ces égalités au modèle et retourner en (1) jusqu’à ce qu’aucune égalité ne soit violée.
  4. Restaurer l’intégralité et résoudre le **MIP** avec toutes les égalités ajoutées.

Utile pour ne pas surcharger le modèle dès le départ (surtout quand il y a beaucoup d’égalités).  
Nécessite JuMP récent (ex. `relax_integrality`).

### 5. Script d’évaluation Partie 1

- **`src/main_part1_box_equalities.jl`** définit `run_part1(...)` :
  - Charge chaque jeu (liste par défaut = `DEFAULT_DATASETS`), normalise, fait train/test.
  - Pour chaque profondeur (par défaut D = 2, 3) :
    - Résout **sans** égalités (avec flux unitaire).
    - Résout **avec** les égalités linked sets (Section 4) ; le nombre d'égalités dépend des coïncidences sur les features (arrondi aide pour seeds/wine).
  - Affiche : temps de résolution, gap, objectif, **valeur de la relaxation linéaire (LP)**, **nombre de nœuds du branch-and-bound**, erreurs train/test.
  - **Arrondi** : `round_digits_list` (défaut `[nothing]`) permet de tester plusieurs précisions (ex. `[nothing, 2, 3, 4]`) ; les features normalisées sont arrondies avant recherche des égalités et entraînement.
  - Si `save_results="chemin/fichier.csv"` est fourni, enregistre les résultats en CSV (colonnes : dataset, **round_digits**, depth, n_train, n_test, n_features, n_equalities, config, time_sec, gap_pct, objective, lp_value, nodes_bb, err_train, err_test).
- **`run_part1.jl`** appelle `run_part1(save_results="results/part1_results.csv")` (temps = `DEFAULT_TIME_LIMIT_PARTS`) : tous les jeux de `DEFAULT_DATASETS` et D = 2, 3 → **`results/part1_results.csv`**.
- **Comparaison LP / nœuds B&B** : pour chaque configuration (avec/sans égalités), le script résout d’abord la relaxation linéaire (sans limite de temps) pour obtenir la valeur LP, puis restaure l’intégralité et résout le MIP ; le nombre de nœuds est récupéré via les statistiques CPLEX (attribut MOI `NodeCount` dans JuMP).

### 6. Intégration MIP

Les égalités **linked sets** (et optionnellement **opposite box corners**) sont ajoutées au modèle lorsque `linked_set_equalities=true` / `box_equalities=true` dans `build_tree` (voir `building_tree.jl`).

---

## Questions ouvertes du sujet (`Project.pdf`) — état dans ce dépôt

| # | Thème (sujet) | Dans `IOML_2` |
|---|----------------|---------------|
| **1** | Section 4 : flux unitaire, preuve, détection coins / linked sets, égalités, impact LP/B&B, arrondi, cutting planes | **Fait** : `building_tree.jl`, `box_equalities.jl`, `cutting_plane_box.jl`, `main_part1_box_equalities.jl`, `doc/proof_section4_proposition.md`, `doc/rapport_partie1.tex`. Arbres **univariés** pour cette partie. |
| **2** | Fairness : objectifs/contraintes, intégration au modèle, tests | **Fait** : `fairness.jl`, `main_part2_fairness.jl`, `run_part2.jl`. |
| **3** | Nouvelles features, algorithme de sélection, métriques | **Fait** : `feature_engineering.jl`, `main_part3_features.jl`, `run_part3.jl`. |
| **4** | Section 5.1 formulation binaire ; **5.2** renforcement ES ; **5.3** borne alternative sur θ ; lazy (sujet) | **Fait** : `binary_oct.jl` (5.1, 5.2, 5.3, lazy callback) ; `main_part4_binary.jl` enchaîne les variantes (`5.1_standard`, `5.2_ES`, `5.3_*`, `formulation_F`). |
| **5** | Hypothèses de clustering proches de **H1**, solutions optimales ou proches | **Non traité comme travail autonome** : `merge.jl` / `exactMerge` restent le code de base ; pas d’étude ou de script dédié listé ici. |
| **6** | Idées diverses pour améliorer les performances | **Partiel** : couvert **indirectement** (fairness, features, renforts Partie 4), pas de section “question 6” séparée. |

**Rapport** : le sujet demande résultats (temps, précision, profondeurs, uni/multivarié) + description des questions ouvertes — voir `doc/rapport_partie1.tex` pour la Partie 1 ; pour un rapport unique, compiler ou fusionner avec les résultats des parties 2–4.

---

## Partie 2 – Arbres de classification équitables (Fair classification trees)

### Notions d’équité utilisées

- **Parité démographique (demographic parity)** : égaliser le taux de prédiction « positive » entre deux groupes sensibles : P(ŷ = positif | groupe A) = P(ŷ = positif | groupe B). Contrainte ou terme de pénalité dans l’objectif.
- **Equal opportunity** : égaliser le taux de vrais positifs (TPR) entre groupes : P(ŷ = positif | Y = positif, A) = P(ŷ = positif | Y = positif, B).

L’attribut sensible est binaire (group[i] ∈ {1, 2}). Une classe est fixée comme « positive » (`positive_class`, indice 1-based).

### Implémentation

- **`src/fairness.jl`** : métriques d’équité (parité démographique, equal opportunity) à partir d’un arbre entraîné et d’un vecteur de groupes.
- **`src/building_tree.jl`** : paramètres optionnels `sensitive_group`, `positive_class`, `fairness_type`, `fairness_constraint`, `fairness_penalty`, **`fairness_tolerance`** (si > 0, contrainte assouplie : |taux_A − taux_B| ≤ tolerance). Nécessite `unitary_flow=true`.
- **`src/main_part2_fairness.jl`** : compare **sans équité**, **contrainte stricte**, **contrainte avec tolérance** (meilleur compromis) et **pénalité** (λ réglable).

### Pourquoi la précision chute avec l’équité stricte, et comment l’améliorer

Une **contrainte stricte** (parité démographique ou equal opportunity) impose une égalité exacte des taux entre groupes ; le modèle a peu de marge, donc la précision peut fortement baisser — c’est le **compromis équité–précision**.

Pour limiter la baisse de précision tout en restant équitable :
1. **Contrainte assouplie** : utiliser `fairness_tolerance > 0` (ex. 0.15) pour autoriser un écart maximal entre les taux (ex. `|taux_A − taux_B| ≤ 0.15`). Le script lance par défaut une config « contrainte tolérance 0.15 ».
2. **Pénalité** : utiliser `fairness_penalty` (défaut 80) pour ajouter dans l’objectif un terme −λ×(écart) ; plus λ est grand, plus le solveur privilégie l’équité. Ajuster `penalty_value` (ex. 50–150) selon le compromis souhaité.

### Jeux de données et groupe sensible

Pour **iris, seeds, wine**, un groupe synthétique est construit à partir de la première feature (médiane) pour tester le pipeline ; les features utilisées par l’arbre ne contiennent pas le groupe. Pour des données « fairness » réelles (ex. Adult, avec genre ou race), fournir un vecteur `group` séparé et ne pas l’inclure dans les features.

### Lancement Partie 2

```bash
julia run_part2.jl
```

Depuis le REPL :

```julia
include("src/main_part2_fairness.jl")
run_part2(save_results="results/part2_results.csv")
# Equal opportunity au lieu de parité démographique :
run_part2(fairness_type=:equal_opportunity, save_results="results/part2_results.csv")
# Meilleur compromis : contrainte avec tolérance 0.2 ou pénalité 100 :
run_part2(fairness_tolerance=0.2, penalty_value=100)
# Uniquement contrainte stricte (précision souvent très dégradée) :
run_part2(run_penalty=false, fairness_tolerance=0.0)
```

Résultats dans **`results/part2_results.csv`** (colonnes : dataset, depth, config, time_sec, objective, err_train, err_test, parity_gap, eq_opp_gap).

---

## Partie 3 – Nouvelles features pour améliorer la classification

On augmente les jeux de données avec des **features dérivées** (combinaisons simples des features existantes) pour améliorer la classification tout en gardant des expressions **interprétables** (ratios, différences, produits).

### Idée (exemple du sujet)

Avec deux features, si une classe est à l’intérieur d’un cercle et l’autre à l’extérieur, un arbre sur les deux features brutes nécessite beaucoup de splits. En ajoutant une feature binaire « à l’intérieur du cercle » (1/0), un seul split suffit. Ici on utilise des combinaisons **linéaires simples** (rapports, différences, produits) pour rester interprétables.

### Algorithme de génération et sélection

1. **Candidats** : pour chaque paire de features \((i, j)\), \(i \neq j\), on construit trois colonnes :
   - **Ratio** : \(x_i / (x_j + \varepsilon)\)
   - **Différence** : \(x_i - x_j\)
   - **Produit** : \(x_i \times x_j\)

2. **Score** : pour chaque colonne candidate, on calcule le **gain de Gini** du meilleur split binaire (meilleur seuil sur cette colonne). Le gain mesure à quel point la feature sépare les classes.

3. **Sélection** : on garde les **top-k** candidats (défaut \(k = 5\)) selon ce gain, et on les ajoute au jeu d’entraînement. Les mêmes recettes (indices \(i, j\) et type) sont appliquées au jeu de test.

4. **Normalisation** : après ajout des nouvelles colonnes, on re-normalise en [0, 1] par colonne en utilisant les min/max **de l’entraînement** uniquement (appliqués au test pour éviter toute fuite de données).

### Implémentation

- **`src/feature_engineering.jl`** :
  - `gini_impurity`, `best_single_split_gain` : calcul du gain de Gini pour un split sur une feature continue.
  - `generate_candidate_recipes(nf)` : liste des recettes (type, i, j) pour \(nf\) features.
  - `compute_candidate_matrix(X, recipes)` : matrice des candidats.
  - `score_candidates` : gains pour chaque colonne.
  - `augment_dataset(X, y, classes; k=5)` : retourne `(X_aug, recipes, selected_indices)`.
  - `apply_augmentation(X_other, recipes, selected_indices)` : applique la même augmentation à un autre jeu (ex. test).

- **`src/main_part3_features.jl`** : pour chaque jeu (`DEFAULT_DATASETS` par défaut) et chaque profondeur (D = 2, 3) :
  - Résout l’arbre **sans** nouvelles features → temps, objectif, erreurs train/test, nombre de splits (\(2^D - 1\)).
  - Sélectionne les top-k features sur l’entraînement, augmente train et test, re-normalise, résout **avec** nouvelles features → mêmes métriques.
  - Enregistre tout dans **`results/part3_results.csv`** (dataset, depth, n_features_orig, n_features_aug, k_added, config, time_sec, gap_pct, objective, tree_n_splits, err_train, err_test).

### Lancement Partie 3

```bash
julia run_part3.jl
```

Depuis le REPL :

```julia
include("src/main_part3_features.jl")
run_part3(save_results="results/part3_results.csv", k_features=5)
# Plus de nouvelles features :
run_part3(k_features=10)
```

---

## Partie 4 – Formulation univariée pour jeux de données binaires (Section 5)

Question ouverte 4 : formulation **5.1**, renforcement **5.2**, borne **5.3** et lazy (selon le sujet), comparaison avec la formulation F sur données binarisées.

### Formulation (2a)–(2i) (Section 5.1)

- **Variables** : \(b_{nf}\) (nœud \(n\) branche sur la feature \(f\)), \(p_n\) (nœud \(n\) est une feuille), \(w_{nk}\) (nœud \(n\) prédit la classe \(k\)), \(\theta_i\) (échantillon \(i\) correctement classé).
- **Objectif** : \(\max\ \frac{1}{|I|}\sum_i \theta_i - \lambda \sum_n p_n\).
- **Contraintes** : (2b) chaque nœud interne soit branche sur une feature, soit est une feuille, soit a un ancêtre feuille ; (2c) chaque feuille prédit exactement une classe ; (2d)–(2e) majoration de \(\theta_i\) selon le chemin dans l’arbre et la prédiction des feuilles/ancêtres ; (2f)–(2i) variables binaires.
- **Ensembles** : \(A(n)\) ancêtres de \(n\), \(AL(n)\) ancêtres dont l’enfant gauche est sur le chemin, \(AR(n)\) dont l’enfant droit est sur le chemin. Convention : à un nœud qui branche sur \(f\), gauche si \(x_f=1\), droite si \(x_f=0\).

### Implémentation

- **`src/binary_oct.jl`** : `get_ancestors`, `get_AL_AR`, `binarize_threshold`, `build_tree_binary` (MIP 5.1 + options **5.2** ES, **5.3** `theta_bound_mode`, **lazy** sur \(\theta\)).
- **`src/main_part4_binary.jl`** : pour chaque jeu de la liste (défaut : `DEFAULT_DATASETS`), normalisation [0,1], binarisation (seuil médian), puis pour chaque profondeur \(D\) : variantes **5.1**, **5.2 (ES)**, **5.3** (remplacement / les deux / lazy), plus **formulation F** sur les mêmes données binarisées en référence.
- Résultats dans **`results/part4_results.csv`** (dataset, depth, config, time_sec, gap_pct, objective, err_train, err_test).

### Lancement Partie 4

```bash
julia run_part4.jl
```

Depuis le REPL :

```julia
include("src/main_part4_binary.jl")
run_part4(save_results="results/part4_results.csv")
```

Les renforcements **5.2** (Equivalent Sets), **5.3** (borne alternative sur \(\theta\)) et les **lazy callbacks** sur \(\theta\) sont implémentés dans `binary_oct.jl` et activables via les noms de config dans `main_part4_binary.jl` (voir les clés `use_es`, `theta_bound_mode`, `use_lazy_theta`).

---

## Références

- Cours : CM1 Classification trees (slides + hidden), CM2 Linear regression, CM3 From prediction to prescription.
- Formulation F, égalités “linked sets (Section 4)”, flux unitaire : Section 4 et hidden slides (Property, Preuve).
