#!/usr/bin/env python
import click
import sys, os
import shutil
from os import listdir
from os.path import isfile, join


@click.command()
@click.option('-i', '--inputpaths', prompt='input path',
              help='Location where the files should be sorted',
              required=False, default=".")
def main(inputpaths):
    all_files = get_file_paths(inputpaths)

    if not os.path.exists('singleEnd'):
        os.makedirs('singleEnd')
    if not os.path.exists('pairedEnd'):
        os.makedirs('pairedEnd')
    if not os.path.exists('pairedEnd/unmatched_reads'):
        os.makedirs('pairedEnd/unmatched_reads')

    # get all unpaired files / only one biological replicate
    work_dir = os.getcwd()

    if len(all_files) == 1:  # singleEnd reads
        file_name = all_files[0].split("/")[-1]
        os.symlink(all_files[0], "singleEnd/" + file_name)
    elif len(all_files) == 2:  # pairedEnd reads
        for single_fastq in all_files:
            file_name = single_fastq.split("/")[-1]
            os.symlink(single_fastq, "pairedEnd/" + file_name)
    elif len(all_files) == 3:  # pairedEnd with unmatched reads
        for single_fastq in all_files:
            file_name = single_fastq.split("/")[-1]
            if "_1.fastq.gz" in single_fastq or "_2.fastq.gz" in single_fastq:
                os.symlink(single_fastq, "pairedEnd/" + file_name)
            else:
                os.symlink(single_fastq, "pairedEnd/unmatched_reads/" + file_name)


def get_file_paths(inputpaths):
    """
    :param inputpath:
    :return:
    """
    list_of_paths = inputpaths.replace("[", "").replace("]", "").split(", ")
    return list_of_paths


if __name__ == "__main__":
    sys.exit(main())
