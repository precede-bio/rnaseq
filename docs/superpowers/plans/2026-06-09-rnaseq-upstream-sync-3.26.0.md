# rnaseq Upstream Sync to 3.26.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `precede-bio/rnaseq` current with upstream nf-core/rnaseq 3.26.0 by snapshotting upstream and re-applying the small Precede customization layer.

**Architecture:** Clean re-apply (not merge). Branch `sync/3.26.0` is reset to upstream 3.26.0, then six Precede customizations are re-applied as fresh commits — including relocating the fingerprint `publishDir` into a new `conf/modules/bam_fingerprint.config` (upstream split the old monolithic `workflows/rnaseq/nextflow.config` into per-topic files under `conf/modules/`).

**Tech Stack:** Nextflow DSL2, nf-core tooling, git, AWS Batch / Seqera Platform (Tower).

---

## File Structure

Files created or modified by this plan:

- **Create** `conf/modules/bam_fingerprint.config` — `publishDir` for `BAM_FINGERPRINT` (relocated from deleted `workflows/rnaseq/nextflow.config`).
- **Create** `docs/SYNCING_UPSTREAM.md` — runbook for future syncs.
- **Carry over (additive, identical to current HEAD)** `modules/local/bam_fingerprint/main.nf`, `assets/hg19_chr.map`, `tests/precede_bio_test.csv`.
- **Modify** `workflows/rnaseq/main.nf` — re-add `BAM_FINGERPRINT` include + call + `meta.id.toString()`.
- **Modify** `nextflow.config` — re-add `precede_bio` / `precede_bio_smoke` / `fusion` profiles, ECR `wave` override, and the `bam_fingerprint.config` include.
- **Modify** `assets/schema_input.json` — sample accepts `["string","integer"]`.

**Reference (read-only, do not commit):** the current pre-sync tree is preserved on branch `master` and on `pre-sync-3.19.0-backup`; use it to copy the additive files and to diff customizations.

---

## Task 1: Set up remotes, backup, and the sync branch

**Files:** none (git plumbing only)

- [ ] **Step 1: Add the upstream remote (idempotent) and fetch the 3.26.0 tag**

```bash
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/nf-core/rnaseq.git
git fetch upstream --tags
git rev-parse 3.26.0^{commit}
```

Expected: prints a commit SHA for tag `3.26.0` (no error).

- [ ] **Step 2: Confirm working tree is clean and on master**

Run: `git status --porcelain && git rev-parse --abbrev-ref HEAD`
Expected: no output from `--porcelain` (clean), branch is `master`. If dirty, stop and resolve before continuing.

- [ ] **Step 3: Create an immutable backup tag/branch of the current fork tip**

```bash
git branch pre-sync-3.19.0-backup master
git tag pre-sync-3.19.0
```

Expected: branch and tag created at current `master`. This is the rollback point.

- [ ] **Step 4: Create the sync branch from master**

```bash
git switch -c sync/3.26.0 master
```

Expected: now on `sync/3.26.0`.

- [ ] **Step 5: Commit nothing — this task is environment setup**

No commit. Verify state:
Run: `git log --oneline -1 && git remote -v | grep upstream`
Expected: HEAD at the design-doc commit; upstream remote listed.

---

## Task 2: Snapshot the working tree to upstream 3.26.0

**Files:** entire tree (replaced with 3.26.0 content)

This makes `sync/3.26.0` contain exactly the upstream 3.26.0 tree as a single commit, discarding the 3.19.0-based files and all Precede edits (which we re-apply in later tasks from the backup branch).

- [ ] **Step 1: Replace the tracked tree with 3.26.0**

```bash
# Stage 3.26.0 content for every path (adds upstream-new, modifies changed)
git checkout 3.26.0 -- .
# Remove files that exist locally but NOT in 3.26.0 (e.g. workflows/rnaseq/nextflow.config,
# aws.nextflow.config, modules/local/bam_fingerprint, assets/hg19_chr.map, tests/precede_bio_test.csv)
git diff --name-only --diff-filter=D 3.26.0 -- . | xargs -r git rm -q --ignore-unmatch
```

- [ ] **Step 2: Verify the tree now equals 3.26.0**

Run: `git diff --stat 3.26.0 -- . | tail -1`
Expected: no output (the index/worktree matches 3.26.0 exactly). If any files differ, investigate before committing.

- [ ] **Step 3: Confirm the structural markers**

```bash
test ! -e workflows/rnaseq/nextflow.config && echo "OK: old monolithic config gone"
test -d conf/modules && echo "OK: conf/modules present"
test ! -e modules/local/bam_fingerprint/main.nf && echo "OK: fingerprint not yet re-applied"
```

Expected: all three `OK:` lines print.

- [ ] **Step 4: Commit the snapshot**

```bash
git add -A
git commit -m "chore: snapshot upstream nf-core/rnaseq 3.26.0

Re-apply of Precede customizations follows in subsequent commits.
Previous 3.19.0-based fork tip preserved at tag pre-sync-3.19.0."
```

Expected: a single commit containing the full 3.26.0 tree delta.

---

## Task 3: Re-apply additive Precede files (fingerprint module, haplotype map, test CSV)

**Files:**
- Create: `modules/local/bam_fingerprint/main.nf`
- Create: `assets/hg19_chr.map`
- Create: `tests/precede_bio_test.csv`

These are byte-for-byte copies from the backup branch — no merge needed.

- [ ] **Step 1: Restore the three additive files from the backup branch**

```bash
git checkout pre-sync-3.19.0-backup -- \
  modules/local/bam_fingerprint/main.nf \
  assets/hg19_chr.map \
  tests/precede_bio_test.csv
```

- [ ] **Step 2: Verify they match the pre-sync versions exactly**

```bash
for f in modules/local/bam_fingerprint/main.nf assets/hg19_chr.map tests/precede_bio_test.csv; do
  git diff --quiet pre-sync-3.19.0-backup -- "$f" && echo "OK: $f matches backup" || echo "DIFF: $f"
done
```

Expected: three `OK:` lines.

- [ ] **Step 3: Sanity-check the fingerprint module contents**

Run: `grep -c "ExtractFingerprint" modules/local/bam_fingerprint/main.nf`
Expected: `1` (the Picard ExtractFingerprint call is present).

- [ ] **Step 4: Commit**

```bash
git add modules/local/bam_fingerprint/main.nf assets/hg19_chr.map tests/precede_bio_test.csv
git commit -m "feat: re-add bam_fingerprint module, hg19 haplotype map, smoke test CSV"
```

---

## Task 4: Re-apply the schema_input.json change (integer sample names)

**Files:**
- Modify: `assets/schema_input.json`

3.26.0 ships `"type": "string"` for the `sample` property; Precede needs `["string","integer"]`.

- [ ] **Step 1: Confirm the current (3.26.0) value**

Run: `grep -A1 '"sample"' assets/schema_input.json | grep '"type"'`
Expected: `"type": "string",`

- [ ] **Step 2: Apply the edit**

Change in `assets/schema_input.json`, inside the `"sample"` property:

```json
            "sample": {
                "type": ["string", "integer"],
                "pattern": "^\\S+$",
                "errorMessage": "Sample name must be provided and cannot contain spaces",
                "meta": ["id"]
```

(Only the `"type"` line changes — from `"string"` to `["string", "integer"]`.)

- [ ] **Step 3: Verify the JSON is still valid**

Run: `python3 -c "import json;json.load(open('assets/schema_input.json'));print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 4: Verify the value changed**

Run: `grep -A1 '"sample"' assets/schema_input.json | grep '"type"'`
Expected: `"type": ["string", "integer"],`

- [ ] **Step 5: Commit**

```bash
git add assets/schema_input.json
git commit -m "feat: allow integer sample names in schema_input (ENG-899)"
```

---

## Task 5: Create conf/modules/bam_fingerprint.config and wire it in

**Files:**
- Create: `conf/modules/bam_fingerprint.config`
- Modify: `nextflow.config` (add `includeConfig` line)

This replaces the fingerprint `publishDir` block that lived in the deleted `workflows/rnaseq/nextflow.config`.

- [ ] **Step 1: Create `conf/modules/bam_fingerprint.config`**

```groovy
process {
    withName: 'NFCORE_RNASEQ:RNASEQ:BAM_FINGERPRINT' {
        publishDir = [
            path: { "${params.outdir}/fingerprint" },
            mode: params.publish_dir_mode,
            saveAs: { filename -> filename.equals('versions.yml') ? null : filename }
        ]
    }
}
```

- [ ] **Step 2: Add the include line in `nextflow.config`**

In `nextflow.config`, find the "Pipeline-level process overrides" include group (ends with `includeConfig 'conf/modules/quantify_pseudo_alignment.config'`). Add immediately after that line:

```groovy
includeConfig 'conf/modules/quantify_pseudo_alignment.config'

// Precede: BAM fingerprinting
includeConfig 'conf/modules/bam_fingerprint.config'
```

- [ ] **Step 3: Verify the include resolves syntactically**

Run: `grep -n "conf/modules/bam_fingerprint.config" nextflow.config`
Expected: one match in the include block.

- [ ] **Step 4: Verify Nextflow can parse the config (process selector + publishDir)**

Run: `nextflow config -profile docker 2>&1 | grep -A4 "BAM_FINGERPRINT" | head`
Expected: prints the `BAM_FINGERPRINT` process block with `publishDir` pointing at `fingerprint`. (No parse error. `docker` is just a lightweight profile to force full config resolution.)

- [ ] **Step 5: Commit**

```bash
git add conf/modules/bam_fingerprint.config nextflow.config
git commit -m "feat: relocate BAM_FINGERPRINT publishDir into conf/modules"
```

---

## Task 6: Re-apply the BAM_FINGERPRINT include and call in main.nf

**Files:**
- Modify: `workflows/rnaseq/main.nf`

Re-add the module include, the `meta.id.toString()` normalization in the samplesheet map, and the `BAM_FINGERPRINT(...)` call after `BAM_MARKDUPLICATES_PICARD`.

- [ ] **Step 1: Add the module include**

In `workflows/rnaseq/main.nf`, in the `// MODULE: Loaded from modules/local/` group (currently the three `DESEQ2_QC` includes near the top), add after the last `DESEQ2_QC` include line:

```groovy
include { DESEQ2_QC as DESEQ2_QC_PSEUDO      } from '../../modules/local/deseq2_qc'
include { BAM_FINGERPRINT                    } from '../../modules/local/bam_fingerprint'
```

- [ ] **Step 2: Add `meta.id.toString()` to the samplesheet map**

Find the `.fromList(samplesheetToList(...))` block. The `.map` closure has the signature `meta, fastq_1, fastq_2, genome_bam, transcriptome_bam`. Add the normalization as the first statement inside the closure:

```groovy
        .map {
            meta, fastq_1, fastq_2, genome_bam, transcriptome_bam ->
                meta.id = meta.id.toString()
                if (!fastq_2) {
                    return [ meta.id, meta + [ single_end:true ], [ fastq_1 ], genome_bam, transcriptome_bam ]
                } else {
                    return [ meta.id, meta + [ single_end:false ], [ fastq_1, fastq_2 ], genome_bam, transcriptome_bam ]
                }
        }
```

(This guarantees integer sample names from the schema change become strings before becoming the channel key.)

- [ ] **Step 3: Add the BAM_FINGERPRINT call after markduplicates**

Find the `BAM_MARKDUPLICATES_PICARD` block (inside `if (!params.skip_markduplicates && !params.with_umi && !markdups_done) { ... }`). Immediately after that closing `}` and before the `// MODULE: StringTie` comment, add:

```groovy
    }

    //
    // PROCESS: Fingerprinting analysis on dedup BAMs
    //
    BAM_FINGERPRINT(
        ch_genome_bam.join(ch_genome_bam_index, by: [0]),
        file("$projectDir/assets/hg19_chr.map", checkIfExists: true),
        ch_fasta,
        ch_fai,
    )

    //
    // MODULE: StringTie assembly and quantification
    //
```

Note: the fingerprint module signature is `(tuple(meta,bam,bai), fingerprint_map, fasta, fai)`. In 3.26 the channels `ch_genome_bam`, `ch_genome_bam_index`, `ch_fasta`, and `ch_fai` all exist at this point (`ch_fasta`/`ch_fai` are workflow inputs; markduplicates reassigns `ch_genome_bam`/`ch_genome_bam_index` to its deduped outputs). Do **not** use `ch_fasta_fai` here — that is the combined channel markduplicates uses; this module wants the two separate channels.

- [ ] **Step 4: Verify all three edits landed**

```bash
grep -c "include { BAM_FINGERPRINT" workflows/rnaseq/main.nf   # expect 1
grep -c "meta.id = meta.id.toString()" workflows/rnaseq/main.nf # expect 1
grep -c "BAM_FINGERPRINT(" workflows/rnaseq/main.nf             # expect 2 (include + call)
```

Expected: `1`, `1`, `2`.

- [ ] **Step 5: Parse-check the workflow**

Run: `nextflow config -profile docker >/dev/null 2>parse.err; grep -i "error" parse.err || echo "no config errors"; rm -f parse.err`
Expected: `no config errors`. (Full DSL compile happens in Task 8; this catches gross syntax breakage early.)

- [ ] **Step 6: Commit**

```bash
git add workflows/rnaseq/main.nf
git commit -m "feat: re-add BAM_FINGERPRINT call after markduplicates (ENG-714)"
```

---

## Task 7: Re-apply the precede_bio / precede_bio_smoke / fusion profiles and ECR wave override

**Files:**
- Modify: `nextflow.config`

Re-add the three Precede profiles and override the upstream `wave` profile with the ECR repositories. Per design decision (b), these stay inline in `nextflow.config`.

- [ ] **Step 1: Add the three Precede profiles at the top of the `profiles {` block**

In `nextflow.config`, immediately after the `profiles {` opening line (before the upstream `debug {` profile), insert:

```groovy
    precede_bio {
        aws {
            region = 'us-east-1'
            client {
                uploadChunkSize = 10485760
            }
            batch {
                maxSpotAttempts = 3
            }
        }
        process {
            executor = 'awsbatch'
        }
        params {
            pseudo_aligner = 'salmon'
            fasta = 's3://precede-references/Homo_sapiens/hg19/v0/Homo_sapiens_hg19.fa'
            gtf = 's3://precede-references/Homo_sapiens/hg19/v0/Homo_sapiens_hg19.genes.gtf'
            star_index = 's3://precede-references/rnaseq/star'
            salmon_index = 's3://precede-references/rnaseq/salmon'
        }
    }
    precede_bio_smoke {
        params {
            input = 'tests/precede_bio_test.csv'
            pseudo_aligner = 'salmon'
            fasta = 's3://precede-references/Homo_sapiens/hg19/v0/Homo_sapiens_hg19.fa'
            gtf = 's3://precede-references/Homo_sapiens/hg19/v0/Homo_sapiens_hg19.genes.gtf'
            star_index = 's3://precede-references/rnaseq/star'
            salmon_index = 's3://precede-references/rnaseq/salmon'
        }
    }
    fusion {
        aws {
            region = 'us-east-1'
            batch {
                maxSpotAttempts = 3
                volumes = '/scratch/fusion:/tmp'
            }
        }
    }
```

- [ ] **Step 2: Override the upstream `wave` profile with ECR repositories**

Find the upstream `wave {` profile block:

```groovy
    wave {
        apptainer.ociAutoPull   = true
        singularity.ociAutoPull = true
        wave.enabled            = true
        wave.freeze             = true
        wave.strategy           = 'conda,container'
    }
```

Replace its body with the Precede version:

```groovy
    wave {
        wave.enabled               = true
        wave.freeze                = true
        wave.strategy              = 'container'
        wave.build.repository      = '714251272142.dkr.ecr.us-east-1.amazonaws.com/seqera-wave-build'
        wave.build.cacheRepository = '714251272142.dkr.ecr.us-east-1.amazonaws.com/seqera-wave-cache'
    }
```

- [ ] **Step 3: Verify the profiles are present**

```bash
for p in precede_bio precede_bio_smoke fusion; do
  grep -q "    $p {" nextflow.config && echo "OK: $p" || echo "MISSING: $p"
done
grep -c "seqera-wave-build" nextflow.config   # expect 1
```

Expected: three `OK:` lines and `1`.

- [ ] **Step 4: Verify each profile resolves**

```bash
nextflow config -profile precede_bio >/dev/null 2>&1 && echo "OK precede_bio"
nextflow config -profile precede_bio_smoke >/dev/null 2>&1 && echo "OK precede_bio_smoke"
nextflow config -profile fusion >/dev/null 2>&1 && echo "OK fusion"
nextflow config -profile wave 2>&1 | grep -q "seqera-wave-build" && echo "OK wave ECR"
```

Expected: `OK precede_bio`, `OK precede_bio_smoke`, `OK fusion`, `OK wave ECR`.

- [ ] **Step 5: Commit**

```bash
git add nextflow.config
git commit -m "feat: re-add precede_bio/precede_bio_smoke/fusion profiles and ECR wave override"
```

---

## Task 8: Full validation of the synced pipeline

**Files:** none (validation only)

- [ ] **Step 1: Confirm the full Precede footprint vs upstream 3.26.0**

```bash
git diff --stat 3.26.0..HEAD
```

Expected: only these files differ from upstream — `assets/hg19_chr.map`, `assets/schema_input.json`, `conf/modules/bam_fingerprint.config`, `docs/SYNCING_UPSTREAM.md` (added in Task 9), `docs/superpowers/...` (spec+plan), `modules/local/bam_fingerprint/main.nf`, `nextflow.config`, `tests/precede_bio_test.csv`, `workflows/rnaseq/main.nf`. No other files. If anything else appears, investigate.

- [ ] **Step 2: Lint / compile the workflow with the smoke profile**

Run: `nextflow config -profile precede_bio_smoke,docker >/dev/null 2>&1 && echo "config OK"`
Expected: `config OK` (profile composition resolves).

- [ ] **Step 3: Verify the fingerprint publishDir resolves under the smoke profile**

Run: `nextflow config -profile precede_bio_smoke 2>/dev/null | grep -A4 "BAM_FINGERPRINT" | grep -i "fingerprint"`
Expected: a `path` line containing `fingerprint`.

- [ ] **Step 4: Dry-run stub compile of the workflow DSL (catches process/channel errors)**

Run:
```bash
nextflow run . -profile precede_bio_smoke,docker -stub-run -ansi-log false 2>&1 | tail -30
```
Expected: the workflow compiles and begins/launches stub processes (or fails only on data/AWS access, not on a Nextflow compile error referencing `BAM_FINGERPRINT`, `ch_fasta`, `ch_fai`, or undefined channels). If it errors on an undefined channel, revisit Task 6 Step 3.

- [ ] **Step 5: No commit — record the result**

If steps 1–4 pass, the local validation gate is met. The authoritative functional check (Step 6) runs on AWS.

- [ ] **Step 6: Functional smoke run on Seqera Platform / AWS Batch (manual, may require credentials)**

Launch the `precede_bio_smoke` profile on Tower/AWS Batch (the same path used in commit `3016e188 "push test to tower"`). Confirm the run completes and a `*.fp.vcf.gz` lands under `<outdir>/fingerprint/`.
> If you need to run an interactive auth command yourself, type `! <command>` (e.g. `! aws sso login`) so its output lands in this session.
Expected: successful run; fingerprint VCF present in output. Record the run URL in the PR description.

---

## Task 9: Add the SYNCING_UPSTREAM.md runbook

**Files:**
- Create: `docs/SYNCING_UPSTREAM.md`

- [ ] **Step 1: Write the runbook**

Create `docs/SYNCING_UPSTREAM.md`:

```markdown
# Syncing the fork with upstream nf-core/rnaseq

This repository is a fork of [nf-core/rnaseq](https://github.com/nf-core/rnaseq).
We track upstream releases and re-apply a small set of Precede-specific
customizations on top. We do **not** merge upstream — we snapshot it and replay
our layer (a "clean re-apply"), because upstream periodically restructures files.

## The Precede customization layer

Everything Precede changes, kept deliberately small and isolated:

1. **Additive files** (no upstream overlap):
   - `modules/local/bam_fingerprint/main.nf` — Picard ExtractFingerprint process
   - `assets/hg19_chr.map` — Picard haplotype map
   - `tests/precede_bio_test.csv` — smoke-test samplesheet
2. **`conf/modules/bam_fingerprint.config`** — `publishDir` for the fingerprint process
   (dedicated file so it survives upstream config restructuring).
3. **`workflows/rnaseq/main.nf`** — three inline edits: the `BAM_FINGERPRINT`
   include, `meta.id = meta.id.toString()` in the samplesheet map, and the
   `BAM_FINGERPRINT(...)` call after `BAM_MARKDUPLICATES_PICARD`.
4. **`nextflow.config`** — `precede_bio`, `precede_bio_smoke`, `fusion` profiles;
   ECR `wave` override; the `bam_fingerprint.config` include.
5. **`assets/schema_input.json`** — `sample` accepts `["string","integer"]`.

## Procedure for a new upstream release `X.Y.Z`

```bash
# 1. Fetch upstream
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/nf-core/rnaseq.git
git fetch upstream --tags

# 2. Backup current tip and branch
git branch pre-sync-<current>-backup master
git tag pre-sync-<current>
git switch -c sync/X.Y.Z master

# 3. Snapshot upstream
git checkout X.Y.Z -- .
git diff --name-only --diff-filter=D X.Y.Z -- . | xargs -r git rm -q --ignore-unmatch
git add -A && git commit -m "chore: snapshot upstream nf-core/rnaseq X.Y.Z"

# 4. Re-apply the layer above (copy additive files from the backup branch,
#    re-create conf/modules/bam_fingerprint.config, re-apply the main.nf and
#    nextflow.config edits, re-apply the schema change). Commit each logically.

# 5. Validate
nextflow config -profile precede_bio_smoke,docker >/dev/null && echo OK
nextflow run . -profile precede_bio_smoke,docker -stub-run

# 6. PR sync/X.Y.Z -> master, run the precede_bio_smoke profile on Tower.
```

## Isolation principle

To keep future syncs cheap, push new Precede config into **dedicated files**
under `conf/modules/` rather than editing upstream files inline. The unavoidable
inline edits are the `BAM_FINGERPRINT` call in `main.nf` and the one-line
`schema_input.json` change. The profiles are kept inline in `nextflow.config` by
choice — re-apply them from the backup branch's version of that file.
```

- [ ] **Step 2: Verify the file exists and references the key files**

```bash
test -f docs/SYNCING_UPSTREAM.md && grep -q "clean re-apply\|snapshot" docs/SYNCING_UPSTREAM.md && echo "OK"
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add docs/SYNCING_UPSTREAM.md
git commit -m "docs: add upstream sync runbook"
```

---

## Task 10: Open the pull request

**Files:** none

- [ ] **Step 1: Push the sync branch**

```bash
git push -u origin sync/3.26.0
```

- [ ] **Step 2: Open the PR with a summary of the sync**

```bash
gh pr create --base master --head sync/3.26.0 \
  --title "Sync fork to upstream nf-core/rnaseq 3.26.0" \
  --body "$(cat <<'EOF'
Brings the fork from upstream 3.19.0 to **3.26.0** via clean re-apply (snapshot upstream + replay the Precede layer). See \`docs/SYNCING_UPSTREAM.md\` and \`docs/superpowers/specs/2026-06-09-rnaseq-upstream-sync-3.26.0-design.md\`.

## Re-applied Precede customizations
- bam_fingerprint module + hg19 haplotype map + smoke CSV (additive)
- \`conf/modules/bam_fingerprint.config\` (relocated publishDir; upstream deleted the old monolithic workflows config)
- \`BAM_FINGERPRINT\` include/call + \`meta.id.toString()\` in main.nf
- precede_bio / precede_bio_smoke / fusion profiles + ECR wave override
- integer sample names in schema_input.json

## Validation
- \`nextflow config -profile precede_bio_smoke,docker\` resolves
- \`-stub-run\` compiles
- Tower smoke run: <PASTE RUN URL>

Rollback point: tag \`pre-sync-3.19.0\`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR created; paste the Tower run URL from Task 8 Step 6 into the body before/after creation.

- [ ] **Step 3: No commit — task complete**

The sync is delivered as PR `sync/3.26.0 → master`.
```
