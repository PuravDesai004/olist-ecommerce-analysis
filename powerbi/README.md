# Olist 2.0 Power BI dashboard

Completed in Power BI Desktop on **19 October 2026**.

- [Interactive PBIX](../olist_2_0.pbix): imported data snapshot, saved to the original project filename. Stored with Git LFS; use GitHub's Download button or `git lfs pull` after cloning.
- [Three-page PDF](../Olist_2_0.pdf): exported by Desktop from the completed report and visually checked on all three pages.
- [Editable PBIP](Olist_2_0.pbip): report definitions and TMDL semantic model. Local caches and credentials are excluded.
- [Executed DAX query](validation/validate_final.dax) and [Desktop result summary](validation/desktop_final_validation_summary.json): **73 checks, 73 passed, 0 failed**.
- [Release manifest](validation/release_manifest.json): file sizes and SHA-256 hashes for the PBIX and PDF.

## Pages

| Page | Contents |
| --- | --- |
| Executive Overview | Orders, delivered orders, item sales, payment AOV, payment value and freight; monthly trend and growth; category/state rankings; payment-method shares. |
| Customer Intelligence | Selected-period people and returning rate; fixed RFM eligibility and segments; first observed acquisition; lifetime repeat split; delivered-purchase cohort matrix; state ranking. |
| Seller & Delivery Performance | Delivery duration, on-time/late rates and source-review mean; top 10 sellers; top 20 seller scatter; state delivery/freight rankings; review distribution and delay association. |

The report contains **52 measures** and **57 visual containers**, including text, navigation and slicers. The original nine raw tables remain in the model, hidden from the report field list. Analytical tables use the PostgreSQL `olist_analytics` views documented in [POWER_BI_GUIDE.md](../POWER_BI_GUIDE.md).

## Verified baselines

| Metric | Actual |
| --- | ---: |
| Orders / delivered orders | 99,441 / 96,478 |
| Item rows / payment rows / review rows | 112,650 / 103,886 / 99,224 |
| Item sales | BRL 13,591,643.70 |
| Freight | BRL 2,251,909.54 |
| Payment value | BRL 16,008,872.12 |
| Payment AOV | BRL 160.99 |
| Distinct people / returning people | 96,096 / 2,997 |
| Average source review / delivery days | 4.09 / 12.56 |
| Eligible deliveries / late deliveries | 96,470 / 7,826 |
| Late / on-time rate | 8.11% / 91.89% |

Native DAX checks cover source counts, key uniqueness, orphan relationships, independent financial reconciliation, seller/category rollups, monthly growth, payment methods, RFM, cohorts and ranking display counts. The validation summary records the actual Desktop result; the separate project-validation JSON covers report schemas and source structure.

Desktop interaction checks exercised November 2017, the High value active segment, seller state AC, filter reset and page navigation. All test slicers were cleared before the final save and PDF export. The final PDF shows all 20 displayed cohort rows and the intended seller rankings. Baselines match the previously executed PostgreSQL evidence; this release did not change the database or source CSVs.

## Filter and interpretation rules

- Item sales exclude freight. Payment value includes all original payment rows. Payment AOV divides payments by orders with a payment record, including zero-valued payments. None of these measures is profit.
- Category and seller filters affect their corresponding item/participation facts. They do not allocate whole-order payments or imply that the executive order outcomes belong exclusively to one seller.
- Customer date/state controls affect dynamic activity. Lifetime and RFM diagnostics use a fixed historical snapshot; RFM is referenced to 1 September 2018. The RFM segment control still selects people within that policy.
- Cohorts use first observed delivered purchases and observed activity before September 2018. The matrix displays January 2017-August 2018 cohorts and offsets 0-19. The pooled month-1 KPI uses all observed month-1 cohorts. Future cells remain blank. Color intensity caps at 1%; month 0 remains 100%.
- The growth chart uses February 2017-August 2018 to avoid sparse boundary comparisons. The full trend retains source months. Closing months do not establish a business collapse.
- Delivery eligibility requires delivered status and nonnegative actual elapsed time. Reviews in the headline average weight source records; delay comparisons weight reviewed orders. Seller outcomes share order-level delivery information and cannot establish seller causation. Relevant sample sizes and full seller IDs are in tooltips.
- Ranking charts show the labeled top 10/top 20 within selection. Short seller labels are for display only; full IDs remain available.

## Open and refresh

1. Download the actual PBIX through Git LFS and open it in Power BI Desktop. Its imported snapshot can be explored without connecting to PostgreSQL.
2. To refresh, make the original source tables and reporting views available in database `olist2` on `localhost:5432`. Follow the existing SQL setup and verification documentation; do not recreate a populated database.
3. Configure PostgreSQL authentication locally in Desktop's data-source settings. Credentials are not included in the repository. Keep any password out of SQL, DAX and Git.
4. Refresh in Desktop, rerun the included DAX checks in DAX query view, and repeat relevant filter checks if data or definitions change.
5. For source editing, open `Olist_2_0.pbip`. The cache is intentionally excluded, so a source checkout needs a refresh. Keep `.pbi/` local. The saved PBIX remains the portable snapshot.

The original Olist 1.0 images/PDF are preserved on the `olist-1.0` Git branch. The model-design guide includes learning examples and ideas for future extensions; this README describes the delivered report. Scratch DAX queries, temporary projects, caches and backup copies have been removed; validation/validate_final.dax is the canonical verification query.
