# Design: Fast-forward Precede `rnaseq` fork to upstream nf-core/rnaseq 3.26.0

**Date:** 2026-06-09
**Author:** Kyle (with Claude)
**Status:** Approved for planning

## Background

`precede-bio/rnaseq` is a fork of the public `nf-core/rnaseq` pipeline. The fork
was last synced with upstream at the `Merge branch 'nf-core:master'` commit
(`460485df`), which corresponds to upstream release **3.19.0**. Upstream has
since published seven minor releases and is now at **3.26.0**.

Between 3.19.0 and 3.26.0 upstream changed **724 files** (+80,554 / −39,304
lines), including a significant structural refactor: the monolithic
`workflows/rnaseq/nextflow.config` (503 lines of per-process `publishDir` /
`ext.args` directives) was **deleted** and split into ~32 per-topic files under
`conf/modules/*.config`.

The goal is to bring the fork current with 3.26.0 while preserving the small set
of Precede-specific customizations, and to establish a repeatable process so
future upstream releases are easy to fold in.

## Inventory of Precede customizations (on top of 3.19.0)

Everything Precede has changed since the last upstream sync, and its fate on 3.26.0:

| # | Customization | Type | Action on 3.26.0 |
|---|---|---|---|
| 1 | `modules/local/bam_fingerprint/main.nf` + `assets/hg19_chr.map` (59k-line Picard haplotype map) | Additive | Copy in as-is |
| 2 | `BAM_FINGERPRINT` include + call, plus `meta.id = meta.id.toString()` in `workflows/rnaseq/main.nf` | Inline edit | Re-add include; insert call after `BAM_MARKDUPLICATES_PICARD` (input channels `ch_genome_bam`, `ch_genome_bam_index`, `ch_fasta`, `ch_fai` all still exist in 3.26) |
| 3 | Fingerprint `publishDir` block (was in the now-deleted `workflows/rnaseq/nextflow.config`) | Relocate | New file `conf/modules/bam_fingerprint.config`, wired into the `conf/modules/*.config` include list |
| 4 | `precede_bio`, `precede_bio_smoke`, `fusion` profiles + ECR `wave` override in `nextflow.config` | Inline edit | Re-add profiles inline (kept in `nextflow.config` by decision); re-apply ECR wave override on top of 3.26's `conda,container` default |
| 5 | `assets/schema_input.json` — sample accepts `["string","integer"]` | Inline edit (1 line) | Re-apply |
| 6 | `tests/precede_bio_test.csv` | Additive | Copy in |
| — | ENG-697: removal of `nextflow.preview.output = true` in root `main.nf` | Moot | Upstream already removed this line in 3.26 |
| — | Deletion of `aws.nextflow.config` | Moot | File is absent upstream in 3.26 |

The effective footprint is **6 items, two of which are already resolved upstream**.

## Strategy: clean re-apply onto 3.26.0

Rather than a `git merge` of the 3.26.0 tag (which produces a delete/modify
conflict on `workflows/rnaseq/nextflow.config` plus noisy conflicts in the
1121-line `main.nf` refactor), snapshot upstream 3.26.0 as the new base and
re-apply the Precede layer as fresh, logically-grouped commits.

### Steps

1. Add `upstream` remote → `https://github.com/nf-core/rnaseq.git`; fetch tag `3.26.0`.
2. Create branch `sync/3.26.0` from current `master` (safety net; the old
   history remains reachable via `master` and the branch).
3. Bring the working tree to exactly 3.26.0 (including upstream file deletions
   and additions).
4. Re-apply the Precede layer (items 1–6 above) as fresh commits.
5. Validate (below).
6. Open PR `sync/3.26.0` → `master`.

### The one real structural adaptation

Item 3: the fingerprint `publishDir` previously lived in the deleted
`workflows/rnaseq/nextflow.config`. It moves to a new
`conf/modules/bam_fingerprint.config` following the upstream idiom, publishing to
`${params.outdir}/fingerprint` with `versions.yml` filtered out, scoped to the
`NFCORE_RNASEQ:RNASEQ:BAM_FINGERPRINT` process selector. This file is added to
the `conf/modules/*.config` include list.

## Decisions

- **(a)** Relocate the fingerprint `publishDir` into a new
  `conf/modules/bam_fingerprint.config` (upstream-idiomatic location). **Approved.**
- **(b)** Keep the `precede_bio` / `precede_bio_smoke` / `fusion` profiles and the
  ECR `wave` override **inline in `nextflow.config`** (not factored into a separate
  `conf/precede.config`). **Approved.**

## Sustainable ongoing sync

- Keep the `upstream` remote permanently.
- Write a `docs/SYNCING_UPSTREAM.md` runbook documenting: fetch the new tag, snapshot,
  re-apply the (small) Precede layer, validate, PR.
- **Isolation principle:** prefer pushing future Precede config into dedicated files
  (e.g. `conf/modules/bam_fingerprint.config`) over inline edits to upstream files, to
  minimize the shared-file surface in future syncs. The unavoidable inline edits remain:
  the `BAM_FINGERPRINT` call in `main.nf` and the 1-line `schema_input.json` change.
  (Per decision (b), the profiles stay inline in `nextflow.config` as an accepted exception.)

## Validation

- `nextflow config -profile precede_bio_smoke` resolves without error.
- The `BAM_FINGERPRINT` `publishDir` resolves to `${params.outdir}/fingerprint`.
- `nextflow config` shows the `precede_bio`, `precede_bio_smoke`, and `fusion`
  profiles present and the `wave` profile carrying the ECR repositories.
- Functional check: re-run the `precede_bio_smoke` profile on Tower/AWS Batch.

## Risks

- **`main.nf` refactor (1121 lines changed upstream):** the fingerprint call is
  inserted by re-reading the 3.26 file, not by patching. Confirmed safe — the four
  input channels it needs are all present immediately after
  `BAM_MARKDUPLICATES_PICARD`.
- **History link:** the clean re-apply does not carry a merge-commit link to
  upstream history. Accepted; the `upstream` remote + tag references preserve
  traceability, and the Precede commits are small and self-describing.
