#!/usr/bin/env python3
"""Linux stand-in for Create ML's MaxEnt text classifier: TF-IDF + logistic regression.

    pip install scikit-learn
    python3 Tools/eval/proxy_fast.py Tools/data/work/train [more export dirs ...]

Reads the train.json/test.json that `lofi-train export` writes and prints
exact agreement, macro-F1 and Cohen's kappa on the held-out books for a few
settings. It is only a quick check of how much a bag-of-words classifier can
learn from the labels; the shipped Fast engine is trained by `lofi-train`.
"""
import json, sys
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score, cohen_kappa_score

def load(p): return json.load(open(p))
for d in sys.argv[1:]:
    tr, te = load(f"{d}/train.json"), load(f"{d}/test.json")
    for ngram in [(1, 1), (1, 2)]:
        for C in [1, 4, 16]:
            vec = TfidfVectorizer(ngram_range=ngram, sublinear_tf=True, min_df=2)
            X = vec.fit_transform([r["text"] for r in tr]); y = [r["label"] for r in tr]
            clf = LogisticRegression(C=C, max_iter=2000, class_weight="balanced").fit(X, y)
            p = clf.predict(vec.transform([r["text"] for r in te])); t = [r["label"] for r in te]
            print(f"{d.split('/')[-1]:9} n={len(tr):5} ngram={ngram} C={C:2}  exact {accuracy_score(t,p)*100:5.1f}%  macroF1 {f1_score(t,p,average='macro'):.3f}  kappa {cohen_kappa_score(t,p):.3f}")
