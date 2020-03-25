# steffenlem/sradownloader: Output

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

<!-- TODO nf-core: Write this documentation describing your workflow's output -->

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/)
and processes data using the following steps:

* [Prefetch](#prefetch) - download of SRA data
* [Fasterq-dump](#fasterq-dump) - converts SRA files to FastQ files
* [sort_fastq_files](#sort_fastq_files) - sorts fastq files into single-end and paired-end

## Prefetch

[Prefetch](https://github.com/ncbi/sra-tools) is a tool of the SRA-tools package. It downloads and saves a .sra file for each SRA run accession. 

For further reading and documentation see the [SRA-Tools documentation](https://ncbi.github.io/sra-tools/).

<!-- > **NB:** The FastQC plots displayed in the MultiQC report shows _untrimmed_ reads. They may contain adapter sequence and potentially regions with low quality. To see how your reads look after trimming, look at the FastQC reports in the `trim_galore` directory. -->


## Fasterq-dump

[sort_fastq_files](https://github.com/ncbi/sra-tools) is another tool of the SRA-tools package. It converts .sra files to FastQ files in a multithreaded manner. The files are automatically split during the conversion process into forward and reverse reads according to the sequencing strategy. The FastQ files are compressed to .fastq.gz files by pigz, to reduce the file size of the output.

For further reading and documentation see the [SRA-Tools documentation](https://ncbi.github.io/sra-tools/).



## sort_fastq_files

[sort_fastq_files~~~~](https://github.com/ncbi/sra-tools) sorts the reads according to their orientation, which is either singleEnd or pairedEnd. During the conversion step to FastQ files in paired-end experiments, in some cases, unmatched reads are produced, which are sorted into a separate output directory called 'unmatched_reads'.

**Output directory: `results/sorted_output_files`**

