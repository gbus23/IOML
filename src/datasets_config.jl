# Jeux par défaut : 3 fournis (iris, seeds, wine) + 2 au choix (glass, ecoli), cf. sujet (Requested work).
const DEFAULT_DATASETS = ["iris", "seeds", "wine", "glass", "ecoli"]

# Temps limite CPLEX (secondes). Tests rapides : mettre 30 / 60 dans l'environnement.
# Rapport : défaut 180 s pour main(), 300 s pour run_part1…4 (voir sujet : « quelques minutes »).
const DEFAULT_TIME_LIMIT_MAIN = parse(Int, get(ENV, "IOML_TL_MAIN", "180"))
const DEFAULT_TIME_LIMIT_PARTS = parse(Int, get(ENV, "IOML_TL_PARTS", "300"))
