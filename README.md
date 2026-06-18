# Growth Experimentation Engine

Analyzed 290,000+ users across a live A/B test using Python, SQL, and Excel — ran statistical significance testing, diagnosed a conversion underperformance, and delivered a data-backed "do not ship" recommendation with country-level segmentation.

---

## Why This Project Exists

Most companies run A/B tests. Very few analyze them properly.

The default failure mode: a team ships a redesigned page, sees flat or negative numbers, and either (a) ignores the result and ships anyway, or (b) kills the idea without understanding *why* it failed. Both outcomes are expensive.

This project simulates the full experiment analysis workflow a Growth or Product Analyst would own — from raw data validation through statistical testing through a rollout decision. The dataset is a real 290K-user A/B test with control/treatment split, multi-country distribution, and a non-obvious result: the new page looks almost identical to the old one in conversion terms, but the difference is *not* statistically significant. That distinction matters. A lot.

**Stakeholders who care about this type of analysis:**
- Product team deciding whether to ship a redesigned page
- Growth team evaluating conversion improvement hypotheses
- Marketing team measuring campaign landing page effectiveness
- Leadership needing a clear rollout recommendation with evidence

---

## What I Was Trying to Answer

1. Did the new landing page improve conversion rates?
2. Is any observed difference real, or just noise?
3. Which countries responded differently to the new page?
4. Were there data quality issues that could invalidate the result?
5. What should the product team do next?

---

## Dataset

| File | Rows | Description |
|---|---|---|
| `clean_experiment_data.csv` | ~290,000 | User-level A/B test records |

| Column | What It Is | Why It Matters |
|---|---|---|
| `id` | Unique user identifier | Deduplication, user-level analysis |
| `time` | Timestamp of experiment exposure | Novelty effect checks, time-series validation |
| `con_treat` | Group assignment: `control` or `treatment` | Core experiment split |
| `page` | Page served: `old_page` or `new_page` | Cross-validates group assignment |
| `converted` | Binary outcome: 1 = converted, 0 = did not | Primary success metric |
| `country` | User country: US, CA, UK | Geographic segmentation |

## Final Experiment Results

| Metric | Value |
|----------|----------|
| Users | 290,585 |
| Control CVR | 12.04% |
| Treatment CVR | 11.88% |
| Absolute Lift | -0.16% |
| Relative Lift | -1.31% |
| P-Value | 0.19 |
| Decision | Do Not Roll Out |
**Data quality note:** The dataset contains mismatch rows — users assigned to `control` who were served `new_page`, and vice versa. I flagged and validated these before running any analysis. This is something a lot of people skip, and it's the kind of thing that invalidates an entire experiment if left unaddressed.
---

## Tech Stack

| Tool | Why I Used It |
|---|---|
| **Python** (pandas, matplotlib, seaborn, statsmodels) | Full experiment analysis pipeline — EDA, lift calculation, z-test, visualizations |
| **SQL** (MySQL) | Experiment KPI queries, window functions, views — mirrors how this analysis would run in a production BI environment |
| **Excel** | Dataset storage and reference |
| **Tableau** | Dashboard in progress |

---

## SQL Analysis

The SQL file contains 20+ queries organized by analytical purpose. Here's what each block does and why it exists.

---

**Experiment Split**
```sql
SELECT con_treat, COUNT(*) AS users
FROM experiment_data
GROUP BY con_treat;
```
First thing you check before any experiment analysis: is the split roughly 50/50? If not, something went wrong in randomization. This query catches it.

---

**Absolute Lift**
```sql
SELECT ROUND(
  (AVG(CASE WHEN con_treat = 'treatment' THEN converted END)
  - AVG(CASE WHEN con_treat = 'control' THEN converted END)) * 100, 2
) AS ABSOLUTE_LIFT
FROM experiment_data;
```
Absolute lift = treatment CVR minus control CVR, expressed in percentage points. This is the number a PM actually cares about. Relative lift (below) is the percentage change from baseline.

---

**Relative Lift**
```sql
SELECT ROUND(
  ((AVG(CASE WHEN con_treat = 'treatment' THEN converted END)
  - AVG(CASE WHEN con_treat = 'control' THEN converted END))
  / AVG(CASE WHEN con_treat = 'control' THEN converted END)) * 100, 2
) AS RELATIVE_LIFT
FROM experiment_data;
```
Relative lift is useful for communicating impact to non-technical stakeholders ("the new page converted 2% better than the old one" lands differently than "-0.15 percentage points"). In this case, both metrics pointed the same direction: treatment underperformed.

---

**Country Ranking — Window Function**
```sql
SELECT country,
  ROUND(AVG(converted)*100, 2) AS CONVERSION_RATE,
  RANK() OVER(ORDER BY AVG(converted) DESC) AS COUNTRY_RANK
FROM experiment_data
GROUP BY country;
```
`RANK()` here does something a simple `ORDER BY` can't: it assigns a persistent rank that survives subsequent filters and JOINs. Useful when you want to build a ranked view that gets referenced in downstream queries.

---

**Mismatch Validation**
```sql
SELECT COUNT(*) AS mismatches
FROM experiment_data
WHERE
  (con_treat='control' AND page='new_page')
  OR (con_treat='treatment' AND page='old_page');
```
This is the most important query in the file. Before you calculate any lift, you need to know whether group assignments were served correctly. A large mismatch count means the experiment was contaminated and results cannot be trusted.

---

**Executive Summary View**
```sql
CREATE VIEW executive_summary AS
SELECT
  COUNT(*) AS TOTAL_USERS,
  SUM(converted) AS TOTAL_CONVERSIONS,
  ROUND(AVG(converted)*100, 2) AS OVERALL_CVR,
  ROUND(AVG(CASE WHEN con_treat='control' THEN converted END)*100, 2) AS CONTROL_CVR,
  ROUND(AVG(CASE WHEN con_treat='treatment' THEN converted END)*100, 2) AS TREATMENT_CVR
FROM experiment_data;
```
Creating a VIEW (not just a query) matters for two reasons: (1) it's how you'd actually expose this in a production BI layer, and (2) it signals that you're building for reuse, not just ad hoc analysis. Any downstream dashboard or report can call `SELECT * FROM executive_summary` without rewriting the logic.

---

**Country Winner Analysis**
```sql
SELECT country,
  CASE
    WHEN AVG(CASE WHEN con_treat='treatment' THEN converted END)
       > AVG(CASE WHEN con_treat='control' THEN converted END)
    THEN 'Treatment Wins'
    ELSE 'Control Wins'
  END AS winner
FROM experiment_data
GROUP BY country;
```
The overall experiment result tells one story. The per-country result might tell a different one. If treatment wins in two of three countries, a geographic rollout strategy becomes worth discussing even if the global result is null.

---

## Python Analysis

Three notebooks, each with a specific analytical scope.

---

### Notebook 1 — EDA & Business Understanding

**What it does:** Loads the dataset, validates structure, checks for nulls, detects mismatches, and builds exploratory visualizations.

Key outputs:
- Experiment group distribution (control vs treatment user counts)
- Country distribution (users per country, percentage share)
- Conversion distribution (overall converted vs not)
- Conversion rate by country (bar chart)
- Mismatch count (rows where group assignment doesn't match page served)

The mismatch check is implemented before any analysis runs:
```python
mismatch = df[
    ((df['con_treat']=='treatment') & (df['page']=='old_page'))
    |
    ((df['con_treat']=='control') & (df['page']=='new_page'))
]
print("Mismatches Found:", len(mismatch))
```

This is the Python equivalent of the SQL mismatch validation. Running it in both places confirms consistency between the Python and SQL analysis layers.

---

### Notebook 2 — Experiment Analysis

**What it does:** Calculates CVR by group, computes absolute and relative lift, identifies the experiment winner, runs country-level segmentation, and generates the rollout recommendation.

Core lift calculation:
```python
absolute_lift = (treatment_cvr - control_cvr)
relative_lift = (treatment_cvr - control_cvr) / control_cvr
```

Country-level pivot heatmap (seaborn):
```python
pivot_table = pd.pivot_table(
    df, values='converted',
    index='country', columns='con_treat', aggfunc='mean'
) * 100

sns.heatmap(pivot_table, annot=True, fmt=".2f")
```

The heatmap is the most useful visual in the project for a stakeholder presentation — it shows control vs treatment CVR side by side for each country in a single glance. The `country_winner` column (treatment vs control winner per country) is derived from an `.unstack()` + `np.where()` pattern that mirrors the SQL CASE WHEN logic.

**Decision output:**
```
Do NOT roll out the new page.
Treatment underperformed Control.
```

---

### Notebook 3 — Statistical Significance & Experiment Decision

**What it does:** Runs a two-proportion z-test to determine whether the observed lift is statistically significant or within the range of random variation.

Hypothesis:
- **H0:** Control CVR = Treatment CVR (the new page has no effect)
- **H1:** Control CVR ≠ Treatment CVR (the new page does affect conversions)
- **Alpha:** 0.05 (two-tailed)

Z-test implementation:
```python
from statsmodels.stats.proportion import proportions_ztest

count = [treatment_conversions, control_conversions]
nobs = [treatment_users, control_users]

z_stat, p_value = proportions_ztest(count, nobs)
```

**Result interpretation:**
```python
if p_value < 0.05:
    print("Result is statistically significant. Reject H0.")
else:
    print("Result is not statistically significant. Fail to reject H0.")
```

The result: we fail to reject H0. The treatment did not produce a statistically significant change in conversion rate. With ~290K users in the experiment, statistical power is not the issue — the sample size is more than sufficient to detect even small lifts. The null result here is genuine: the new page simply doesn't move the needle.

**Final decision:**
```
Decision: DO NOT ROLL OUT NEW PAGE
Reason: Treatment underperformed control and the difference is not statistically significant.
```

---

## Experiment Framework

| Parameter | Value |
|---|---|
| Test type | Two-proportion z-test |
| Significance level (α) | 0.05 |
| Tails | Two-tailed |
| Groups | Control (old_page) vs Treatment (new_page) |
| Primary metric | Conversion rate |
| Sample size | ~290,000 users |
| Countries | US, CA, UK |

**Type I Error (False Positive):** Concluding the new page improved conversions when it didn't. At α = 0.05, this risk is capped at 5%.

**Type II Error (False Negative):** Concluding the new page had no effect when it actually did. With ~290K users, statistical power is high — Type II error risk is low.

**p-value interpretation:** The p-value represents the probability of observing a difference at least this large between control and treatment *if there were truly no difference*. A high p-value (above 0.05) means the observed gap is consistent with random noise — not a signal worth shipping.

---

## Key Findings

**High Impact**

1. The new page did not outperform the old page on conversion rate. The difference between control and treatment CVR is not statistically significant at the 0.05 level. With 290K+ users in the experiment, this is a genuine null — not a power problem.
2. During the data validation phase, 3,893 mismatch records were identified where experiment assignment and page served were inconsistent. These records were removed before analysis, ensuring that conversion, lift, and statistical significance calculations were performed on a clean experimental sample.
3. Country-level results show variation in how each market responded to the experiment. The pivot heatmap reveals that control and treatment performance is not uniform across US, CA, and UK — which opens the door for a geo-targeted rollout strategy if any country shows consistent treatment wins.

**Medium Impact**

4. Traffic distribution across countries is unequal. The US accounts for the majority of experiment users. Country-level conclusions for CA and UK are based on smaller sample sizes and carry higher uncertainty.

5. The `time` column in the dataset was not used in the analysis. A time-series view of daily conversion rates (control vs treatment) would allow a novelty effect check — confirming whether early treatment enthusiasm inflated or deflated results in the first few days.

**Lower Impact**

6. The overall conversion rate across both groups is below 15%, which is typical for landing page experiments in competitive digital products. The fact that the treatment couldn't move even a low baseline suggests the page redesign may not have addressed the right friction point.

---

## Recommendations

**1. Do not ship the new page globally.**
The statistical evidence doesn't support it. Shipping a change with a null result wastes engineering resources and resets the baseline, making future experiments harder to interpret.

**2. Run qualitative diagnosis before the next test.**
Before designing a follow-up experiment, use session recordings or heatmaps to understand what's happening on the new page. If users aren't clicking the CTA, the problem might be copy, placement, or trust signals — not the page layout itself.

**3. Consider a targeted rollout in markets where treatment showed better performance.**
If per-country analysis shows treatment winning in one specific geography, a limited rollout there carries lower risk and could provide additional statistical evidence.

**4. Add a time-series CVR check to the standard experiment analysis template.**
The `time` column in this dataset was not used. For future experiments, plotting daily CVR for control and treatment separately should be a standard first step — it catches novelty effects and confirms experiment stability.

**5. Pre-specify the minimum detectable effect (MDE) before the next experiment.**
This experiment had sufficient power, but the next one might not. Document the MDE up front so the team knows whether the sample size is adequate before the experiment runs.

---

## Repository Structure

```
growth-experimentation-engine/
├── README.md
├── data/
│   └── clean_experiment_data.csv
├── notebooks/
│   ├── 01_EDA_Business_Understanding.ipynb
│   ├── 02_Experiment_Analysis.ipynb
│   └── 03_Statistical_Significance_Decision.ipynb
├── sql/
│   └── growth_experimentation_queries.sql
├── excel/
│   └── Growth_Experimentation_Guide.xlsx
├── screenshots/
│   ├── cvr_comparison.png
│   ├── country_heatmap.png
│   └── experiment_kpi_summary.png
└── tableau/
    └── [dashboard in progress]
```

---

## Future Improvements

- **Time-series CVR chart** — plot daily control vs treatment conversion rates to check for novelty effects and experiment drift
- **Power analysis** — calculate what sample size would be needed to detect a given MDE (e.g., 0.5% absolute lift) at 80% power
- **Tableau dashboard** — in progress; will cover experiment KPI summary, country heatmap, and conversion funnel

---
## Tech Notes

**Libraries used:**

| Library | Purpose |
|---|---|
| `pandas` | Data loading, groupby, pivot tables, filtering |
| `numpy` | Vectorized calculations, np.where for winner logic |
| `matplotlib` | Conversion and experiment visualizations |
| `seaborn` | Country-level conversion heatmap |
| `statsmodels` | Two-proportion z-test (proportions_ztest) for statistical significance testing |

---
## License
MIT License — free to use, adapt, and reference with attribution.
---

Project by Sumit Kumar Gupta

[LinkedIn](https://www.linkedin.com/in/sumitgupta-analyst/)

[GitHub](https://github.com/Sumit-kr-Gupta)
