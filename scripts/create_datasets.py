"""Create glass.txt and ecoli.txt datasets in data/ folder (Julia format)."""
import numpy as np
from sklearn.datasets import fetch_openml

import os
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")

def normalize_01(X):
    mn, mx = X.min(axis=0), X.max(axis=0)
    rng = mx - mn
    rng[rng == 0] = 1.0
    return (X - mn) / rng

def write_julia(name, X, Y):
    path = f"{DATA_DIR}/{name}.txt"
    rows = []
    for i in range(X.shape[0]):
        rows.append(" ".join(f"{v}" for v in X[i]))
    x_str = "X=[" + "; ".join(rows) + "]"
    y_str = "Y=Vector{Any}([" + ", ".join(str(int(y)) for y in Y) + "])"
    with open(path, "w") as f:
        f.write(x_str + "\n")
        f.write(y_str + "\n")
    print(f"  {name}: {X.shape[0]} samples, {X.shape[1]} features, {len(set(Y))} classes -> {path}")

# --- Glass (UCI #41) ---
print("Fetching glass...")
glass = fetch_openml(data_id=41, as_frame=False, parser="auto")
X_g = glass.data.astype(float)
Y_g_raw = glass.target
classes_g = sorted(set(Y_g_raw))
label_map_g = {c: i+1 for i, c in enumerate(classes_g)}
Y_g = np.array([label_map_g[y] for y in Y_g_raw])
X_g = normalize_01(X_g)
write_julia("glass", X_g, Y_g)

# --- Ecoli (UCI #39) - filter to top 3 classes ---
print("Fetching ecoli...")
ecoli = fetch_openml(data_id=39, as_frame=False, parser="auto")
X_e = ecoli.data.astype(float)
Y_e_raw = ecoli.target
from collections import Counter
counts = Counter(Y_e_raw)
top3 = [c for c, _ in counts.most_common(3)]
mask = np.isin(Y_e_raw, top3)
X_e = X_e[mask]
Y_e_raw = Y_e_raw[mask]
classes_e = sorted(set(Y_e_raw))
label_map_e = {c: i+1 for i, c in enumerate(classes_e)}
Y_e = np.array([label_map_e[y] for y in Y_e_raw])
X_e = normalize_01(X_e)
write_julia("ecoli", X_e, Y_e)

print("Done.")
