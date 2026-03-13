# Preuve de la proposition (Section 4) – Opposite box corners equalities

## Contexte

- **Formulation F** (univarié) : flot par donnée, conservation du flot, contraintes de séparation à la racine et aux nœuds.
- **Flux unitaire** : on adapte F pour que chaque donnée \(i\) envoie exactement 1 unité de flot (vers une feuille). Ainsi \(\sum_{t \in \mathcal{L}} u^i_{t,w} = 1\) pour tout \(i\).
- **Boîte** \(B(p^-, p^+)\) : \(B(p^-, p^+) = \{ v \in \mathbb{R}^{|J|} : v_j \in [p^-_j, p^+_j] \ \forall j \}\).
- **Coins opposés** \((v^1, v^2)\) de \(B(p^-, p^+)\) : pour tout \(j\), \(\{v^1_j, v^2_j\} = \{p^-_j, p^+_j\}\) (en chaque dimension, une coordonnée vaut le min et l’autre le max).

## Proposition

*Sous flux unitaire*, pour toute paire distincte de paires de coins opposés \((i_1, i_2)\) et \((i_3, i_4)\) d’une même boîte \(B(p^-, p^+)\), l’égalité suivante est **valide** pour F (cas univarié) :

\[
u^{i_1}_{r,\ell(r)} + u^{i_2}_{r,\ell(r)} = u^{i_3}_{r,\ell(r)} + u^{i_4}_{r,\ell(r)}
\]

où \(r\) est la racine et \(\ell(r)\) le fils gauche de \(r\). (Dans notre code : \(r=1\), \(\ell(r)=2\), donc \(u^{i}_{1,2}\).)

## Preuve (esquisse du cours)

Soit \(\bar{j} \in J\) la variable sur laquelle se fait la séparation à la racine \(r\) (univarié : une seule variable active).

On raisonne selon la position de \(b_r\) par rapport à l’intervalle \([p^-_{\bar{j}} + \mu^-, p^+_{\bar{j}} + \mu^-]\) (avec \(\mu^- = \min_j \mu_j\)).

1. **Cas \(b_r \in [0, p^-_{\bar{j}} + \mu^-[\)**  
   Tous les points \(i_1, i_2, i_3, i_4\) ont \(x_{i,\bar{j}} \ge p^-_{\bar{j}}\), donc tous vont à droite :  
   \(u^i_{r,\ell(r)} = 0\) pour \(i \in \{i_1,i_2,i_3,i_4\}\).  
   Donc les deux membres de l’égalité valent 0.

2. **Cas \(b_r \in [p^-_{\bar{j}} + \mu^-, p^+_{\bar{j}} + \mu^-]\)**  
   Pour chaque **paire** de coins opposés, exactement un des deux points a \(x_{i,\bar{j}} = p^-_{\bar{j}}\) (donc à gauche) et l’autre \(x_{i,\bar{j}} = p^+_{\bar{j}}\) (à droite). Donc  
   \(u^{i_1}_{r,\ell(r)} + u^{i_2}_{r,\ell(r)} = 1\) et \(u^{i_3}_{r,\ell(r)} + u^{i_4}_{r,\ell(r)} = 1\).  
   L’égalité est vérifiée.

3. **Cas \(b_r \in ]p^+_{\bar{j}} + \mu^-, 1]\)**  
   Tous les points ont \(x_{i,\bar{j}} \le p^+_{\bar{j}}\), donc tous vont à gauche :  
   \(u^i_{r,\ell(r)} = 1\) pour \(i \in \{i_1,i_2,i_3,i_4\}\).  
   Les deux membres valent 2, l’égalité est vérifiée.

Dans tous les cas, l’égalité est donc valide pour toute solution entière réalisable de F (univarié) avec flux unitaire.

## Implémentation

- **Flux unitaire** : contrainte \(\sum_{t \in \mathcal{L}} u^i_{t,w} = 1\) pour tout \(i\), et objectif « nombre de bien classés » (linéarisé avec \(z_{i,t}\)).
- **Égalités** : pour chaque 4-uplet \((i_1,i_2,i_3,i_4)\) issu de l’algorithme de boîtes/coins opposés, on ajoute  
  \(u_{i_1,2} + u_{i_2,2} = u_{i_3,2} + u_{i_4,2}\) (indice 2 = fils gauche de la racine).

Voir `src/box_equalities.jl` et `src/building_tree.jl` (options `unitary_flow`, `box_equalities`, `box_equalities_list`).
