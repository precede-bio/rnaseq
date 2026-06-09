# Syncing the fork with upstream nf-core/rnaseq

This repository is a fork of [nf-core/rnaseq](https://github.com/nf-core/rnaseq).
We track upstream releases and re-apply a small set of Precede-specific
customizations on top. We do **not** merge upstream — we snapshot it and replay
our layer (a "clean re-apply"), because upstream periodically restructures files
(e.g. in 3.20–3.26 the monolithic `workflows/rnaseq/nextflow.config` was deleted
and split into per-topic files under `conf/modules/`).

## The Precede customization layer

Everything Precede changes, kept deliberately small and isolated:

1. **Additive files** (no upstream overlap):
   - `modules/local/bam_fingerprint/main.nf` — Picard ExtractFingerprint process
   - `assets/hg19_chr.map` — Picard haplotype map (~59k lines; never open it, just restore)
   - `tests/precede_bio_test.csv` — smoke-test samplesheet
2. **`conf/modules/bam_fingerprint.config`** — `publishDir` for the fingerprint process
   (dedicated file so it survives upstream config restructuring).
3. **`workflows/rnaseq/main.nf`** — three inline edits: the `BAM_FINGERPRINT`
   include, `meta.id = meta.id.toString()` in the samplesheet `.map` closure, and the
   `BAM_FINGERPRINT(...)` call after `BAM_MARKDUPLICATES_PICARD`.
4. **`nextflow.config`** — `precede_bio`, `precede_bio_smoke`, `fusion` profiles;
   ECR `wave` override; the `bam_fingerprint.config` include.
5. **`assets/schema_input.json`** — `sample` accepts `["string","integer"]`.

The full Precede footprint should be visible with:

```bash
git diff --stat <upstream-tag>..HEAD | grep -v 'docs/superpowers'
```

and should list only the files above (plus any docs).

## Procedure for a new upstream release `X.Y.Z`

```bash
# 1. Fetch upstream
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/nf-core/rnaseq.git
git fetch upstream tag X.Y.Z

# 2. Backup current tip, then branch
#    (use the CURRENT upstream version we are leaving, e.g. 3.26.0)
git branch pre-sync-<current>-backup master
git tag   pre-sync-<current>
git switch -c sync/X.Y.Z master

# 3. Snapshot upstream onto the working tree
git checkout X.Y.Z -- .
#    Remove files that exist locally but are ABSENT in X.Y.Z. NOTE the filter
#    direction: `git diff --diff-filter=A X.Y.Z -- .` lists paths ADDED relative
#    to the tag = present here but not upstream. EXCLUDE planning docs so this
#    sync's own spec/plan survive.
git diff --name-only --diff-filter=A X.Y.Z -- . \
  | grep -v '^docs/superpowers/' \
  | xargs -r git rm -q --ignore-unmatch
#    Verify the tree now equals X.Y.Z except for kept docs:
git diff --name-only X.Y.Z -- . | grep -vc '^docs/superpowers/'   # expect 0
git add -A && git commit -m "chore: snapshot upstream nf-core/rnaseq X.Y.Z"

# 4. Re-apply the Precede layer as separate commits:
#    a) restore additive files from the backup branch
git checkout pre-sync-<current>-backup -- \
  modules/local/bam_fingerprint/main.nf assets/hg19_chr.map tests/precede_bio_test.csv
#    b) re-create conf/modules/bam_fingerprint.config and add its includeConfig
#       line to nextflow.config (after the conf/modules/quantify_pseudo_alignment.config include)
#    c) re-apply the three main.nf edits (re-read the file for current line numbers;
#       the BAM_FINGERPRINT call uses the FOUR separate channels
#       ch_genome_bam / ch_genome_bam_index / ch_fasta / ch_fai — NOT a combined
#       ch_fasta_fai channel)
#    d) re-apply the schema_input.json sample-type change (one line)
#    e) re-add the precede_bio / precede_bio_smoke / fusion profiles and the ECR
#       wave override in nextflow.config (replay from the backup branch's copy)

# 5. Validate (nextflow must be installed)
nextflow config -profile precede_bio_smoke,docker >/dev/null && echo "config OK"
nextflow config -profile precede_bio_smoke 2>/dev/null | grep -A4 BAM_FINGERPRINT | grep -i fingerprint
nextflow run . -profile precede_bio_smoke,docker -stub-run --outdir /tmp/rnaseq_stub_out
#    A stub-run that compiles and runs (or skips samples at the trimmed-read
#    threshold, which is expected with stub data) confirms the channel wiring.
#    It does NOT exercise the fingerprint on real data — that is the Tower check.

# 6. PR sync/X.Y.Z -> master, then run the precede_bio_smoke profile on Seqera
#    Platform / AWS Batch with real S3 data and confirm a *.fp.vcf.gz lands under
#    <outdir>/fingerprint/. Paste the run URL into the PR.
```

## Isolation principle

To keep future syncs cheap, push new Precede config into **dedicated files**
under `conf/modules/` rather than editing upstream files inline. The unavoidable
inline edits are the `BAM_FINGERPRINT` call in `main.nf` and the one-line
`schema_input.json` change. The deployment profiles are kept inline in
`nextflow.config` by choice — re-apply them from the backup branch's version of
that file.

## Rollback

Each sync tags the previous tip (`pre-sync-<version>`). To abandon a sync,
`git switch master` and `git reset --hard pre-sync-<version>` (or just discard the
`sync/X.Y.Z` branch before merging).
