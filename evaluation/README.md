# 00 · Shared evaluation harness

Every approach gets scored here: same images, same metrics, same results format. That's what makes the approaches comparable.

- **The images, splits and manifest** are defined in [dataset/README.md](../dataset/README.md).
- **Build:** ~1 prompt.

## Results CSV format

Every approach writes one row per image, whether it ran in Python or on a phone. The Flutter app's batch-eval screen writes exactly this format, so one report covers both.

| Column | Example |
|---|---|
| `image` | `eval/test/recaptured/0042.jpg` |
| `label` | `recaptured` |
| `split` | `test` |
| `approach` | `01` |
| `variant` | `blazeface-short` |
| `runtime` | `python` or `android` |
| `device` | `MacBook M2` or `Redmi 9A` |
| `passed` | `false` |
| `score` | `0.31` |
| `reasons` | `NO_FACE` (several separated by `;`) |
| `latency_ms` | `12.4` |
| `config` | `T_conf=0.7;A_min=0.05` or `prompts=v2;T=0.6` |

Results go in `approaches/<NN-name>/results/`.

## Metrics

| Metric | Definition |
|---|---|
| Genuine reject rate (BPCER) | % of `live/` images that fail |
| Fake accept rate (APCER), per class | % of each fake class that passes |
| ACER | mean of BPCER and the worst-class APCER |
| ROC-AUC | from `score`, live vs. all fakes; threshold-independent |
| Latency | p50 and p95 of `latency_ms` |

BPCER, APCER and ACER are the presentation-attack metrics from ISO/IEC 30107-3.

## Planned code

```
evaluation/
  dataset.py      reads data/manifest.csv; iterates images by split and class
  metrics.py      the metrics above
  report.py       one or more results CSVs → markdown table for plan.md
  validate.py     checks a results CSV (including ones from the phone) against the format
```
