#!/usr/bin/env python3
"""Learning curve for the bag-of-words stand-in: how much do more labels help?

    pip install scikit-learn
    python3 Tools/eval/learning_curve.py Tools/data/work/train

Trains TF-IDF + logistic regression on random 25/50/75/100% subsets of the
distinct training windows (and, separately, of the training books), 8 subsets
each, and prints the mean agreement on the held-out books. Repeated rows from
`--balance` are dropped first; class weights do the balancing here.
"""
import json, random, statistics as st, sys
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score, cohen_kappa_score
d = sys.argv[1]
tr = {r["id"]: r for r in json.load(open(f"{d}/train.json"))}.values()
tr = list(tr); te = json.load(open(f"{d}/test.json"))
t = [r["label"] for r in te]
books = sorted({r["book"] for r in tr})
print("distinct train", len(tr), "books", len(books))
def fit(rows):
    vec = TfidfVectorizer(sublinear_tf=True, min_df=2)
    X = vec.fit_transform([r["text"] for r in rows])
    clf = LogisticRegression(C=4, max_iter=2000, class_weight="balanced").fit(X, [r["label"] for r in rows])
    p = clf.predict(vec.transform([r["text"] for r in te]))
    return accuracy_score(t, p), f1_score(t, p, average="macro"), cohen_kappa_score(t, p)
for mode in ["windows", "books"]:
    for frac in [0.25, 0.5, 0.75, 1.0]:
        res = []
        for seed in range(8 if frac < 1 else 1):
            rnd = random.Random(seed)
            if mode == "windows":
                rows = rnd.sample(tr, int(len(tr) * frac))
            else:
                bs = set(rnd.sample(books, max(1, round(len(books) * frac))))
                rows = [r for r in tr if r["book"] in bs]
            res.append((len(rows),) + fit(rows))
        n = st.mean(r[0] for r in res); a = [r[1] for r in res]; f = [r[2] for r in res]; k = [r[3] for r in res]
        sd = st.pstdev(a) * 100
        print(f"{mode:7} {frac:4.2f} n~{n:6.0f}  exact {st.mean(a)*100:5.1f}% (sd {sd:3.1f})  F1 {st.mean(f):.3f}  kappa {st.mean(k):.3f}")
