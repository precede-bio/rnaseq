process BAM_FINGERPRINT {
    tag "$meta.id"
    label "process_medium"

    container 'biocontainers/picard:3.1.1--hdfd78af_0'

    input:
    tuple val(meta), path(bam)
    path fingerprint_map
    path fasta

    output:
    tuple val(meta), path("*.fp.vcf.gz"), emit: fingerprint

    script:
    def name = meta.id
    genome_name = fasta.getBaseName()
    """
    picard CreateSequenceDictionary R=${fasta} O=${genome_name}.dict

    picard ExtractFingerprint \\
    -REFERENCE_SEQUENCE ${fasta} \\
    -VALIDATION_STRINGENCY SILENT \\
    -HAPLOTYPE_MAP ${fingerprint_map} \\
    -INPUT ${bam} \\
    -OUTPUT ${name}.fp.vcf.gz \\
    -SAMPLE_ALIAS "${name}"

    cat <<-END_VERSIONS > versions.yml  
    "${task.process}":
        picard: \$(picard ExtractFingerprint --version 2>&1 | cut -d":" -f2)
        samtools: \$(samtools --version | head -1 | cut -d' ' -f2)
    END_VERSIONS
    """
}

