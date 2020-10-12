#!/usr/bin/env nextflow
/*
========================================================================================
                         steffenlem/sradownloader
========================================================================================
 steffenlem/sradownloader Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/steffenlem/sradownloader
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info """

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run steffenlem/sradownloader --run_acc_list '<path_to_acc_list.txt>' --ngc '<path_to_key.ngc>' -profile docker

    Mandatory arguments:
      --run_acc_list                List of SRA run accessions (newline separated)
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Optional arguments:
      --ngc                         dbGAP repository key for files with controlled-access

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail               Same as --email, except only send mail if the workflow is not successful
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}


// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
    custom_runName = workflow.runName
}

if (workflow.profile.contains('awsbatch')) {
    // AWSBatch sanity checking
    if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
    // Check outdir paths to be S3 buckets if running on AWSBatch
    // related: https://github.com/nextflow-io/nextflow/issues/813
    if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
    // Prevent trace files to be stored on S3 since S3 does not support rolling files.
    if (params.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)

/*
 * Create a channel for input read files
 */

params.ngc = 'NO_FILE'
ngc_file = file(params.ngc)

if (!params.run_acc_list || params.run_acc_list == true) {
    exit 1, "Please provide a newline-separated list of SRA run accessions"
}

// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name'] = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
summary['run_acc_list'] = params.run_acc_list
summary['ngc'] = params.ngc
summary['Max Resources'] = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir'] = params.outdir
summary['Launch dir'] = workflow.launchDir
summary['Working dir'] = workflow.workDir
summary['Script dir'] = workflow.projectDir
summary['User'] = workflow.userName
if (workflow.profile.contains('awsbatch')) {
    summary['AWS Region'] = params.awsregion
    summary['AWS Queue'] = params.awsqueue
    summary['AWS CLI'] = params.awscli
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact) summary['Config Contact'] = params.config_profile_contact
if (params.config_profile_url) summary['Config URL'] = params.config_profile_url
if (params.email || params.email_on_fail) {
    summary['E-mail Address'] = params.email
    summary['E-mail on failure'] = params.email_on_fail
}
log.info summary.collect { k, v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// Check the hostnames against configured profiles
checkHostname()

Channel.from(summary.collect { [it.key, it.value] })
        .map { k, v -> "<dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }
        .reduce { a, b -> return [a, b].join("\n            ") }
        .map { x ->
            """
    id: 'nf-core-sradownloader-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'steffenlem/sradownloader Workflow Summary'
    section_href: 'https://github.com/steffenlem/sradownloader'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
            $x
        </dl>
    """.stripIndent()
        }
        .set { ch_workflow_summary }

/*
 * Parse software version numbers

process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
            saveAs: { filename ->
                if (filename.indexOf(".csv") > 0) filename
                else null
            }

    output:
    file 'software_versions_mqc.yaml' into software_versions_yaml
    file "software_versions.csv"

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    prefetch --version > v_prefetch.txt
    pigz --version 2> v_pigz.txt
    fasterq-dump --version > v_fasterq-dump.txt
    echo \$(pip freeze | grep Click 2>&1) > v_click.txt
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}
*/

process certificate {
    output:
    //val 'user-settings.mkfg'
    stdout result

    script:
    """
    uuid > user-settings.mkfg
    vdb-config --cfg-dir \$PWD
    #vdb-config --all
    prefetch --help
    #echo \$PWD
    """
}





/*
 * STEP 1 - prefetch
 */
process prefetch {
    maxForks 3
    errorStrategy 'retry'
    maxRetries 3

    input:
    val run_acc from Channel.fromPath(params.run_acc_list).splitText()
    file ngc from ngc_file

    output:
    stdout result
    //file "[S,E,D]RR*[0-9]" into sra_files

    script:
    output_file = run_acc.trim()
    def ngc_parameter = ngc.name != 'NO_FILE' ? "--ngc $ngc" : ''
    """
    echo \$PWD
    echo ls
    #cat /root/.ncbi/user-settings.mkfg
    #vdb-config --all
    #which prefetch
    prefetch -o $output_file $ngc_parameter --max-size 500000000 $run_acc
    """
}

/*
 * STEP 2 - fasterqdump

process fasterqdump {
    maxForks 3

    input:
    val sra_file from sra_files
    file ngc from ngc_file

    output:
    path "*.fastq.gz" into fastq_files

    script:
    def ngc_parameter = ngc.name != 'NO_FILE' ? "--ngc $ngc" : ''
    """
    fasterq-dump $ngc_parameter --split-3 $sra_file
    pigz *.fastq
    """
}
*/
/*
 * STEP 3 - sort_fastq_files

process sort_fastq_files {
    publishDir "${params.outdir}/sorted_output_files", mode: 'copy'

    maxForks 3

    input:
    val fastq_files from fastq_files

    output:
    file "**.fastq.gz" into outfiles

    script:
    """
    sort_reads.py -i "$fastq_files"
    """
}
*/
/*
 * STEP 4 - Output Description HTML

process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    file output_docs from ch_output_docs

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.py $output_docs -o results_description.html
    """
}
*/
/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[steffenlem/sradownloader] Successful: $workflow.runName"
    if (!workflow.success) {
        subject = "[steffenlem/sradownloader] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp


    // Check if we are only sending emails on failure
    email_address = params.email
    if (!params.email && params.email_on_fail && !workflow.success) {
        email_address = params.email_on_fail
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir"]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (email_address) {
        try {
            if (params.plaintext_email) {
                throw GroovyException('Send plaintext e-mail, not HTML')
            }
            // Try to send HTML e-mail using sendmail
            ['sendmail', '-t'].execute() << sendmail_html
            log.info "[steffenlem/sradownloader] Sent summary e-mail to $email_address (sendmail)"
        } catch (all) {
            // Catch failures and try with plaintext
            ['mail', '-s', subject, email_address].execute() << email_txt
            log.info "[steffenlem/sradownloader] Sent summary e-mail to $email_address (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File("${params.outdir}/pipeline_info/")
    if (!output_d.exists()) {
        output_d.mkdirs()
    }
    def output_hf = new File(output_d, "pipeline_report.html")
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File(output_d, "pipeline_report.txt")
    output_tf.withWriter { w -> w << email_txt }

    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
        log.info "-${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}-"
        log.info "-${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}-"
        log.info "-${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}-"
    }

    if (workflow.success) {
        log.info "-${c_purple}[steffenlem/sradownloader]${c_green} Pipeline completed successfully${c_reset}-"
    } else {
        checkHostname()
        log.info "-${c_purple}[steffenlem/sradownloader]${c_red} Pipeline completed with errors${c_reset}-"
    }

}


def nfcoreHeader() {
    // Log colors ANSI codes
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";

    return """    -${c_dim}--------------------------------------------------${c_reset}-
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  steffenlem/sradownloader v${workflow.manifest.version}${c_reset}
    -${c_dim}--------------------------------------------------${c_reset}-
    """.stripIndent()
}

def checkHostname() {
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}

result.view { it.trim() }
