module Arg = Cmdliner.Arg
module Cmd = Cmdliner.Cmd
module Term = Cmdliner.Term
module H = Cmdliner_
module SC = Scan_CLI

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* 'semgrep ci' command-line parsing.
 *
 * Translated from ci.py
 *
 * coupling: https://semgrep.dev/docs/cli-reference#semgrep-ci-command-options
 * updated automatically by update-help-command.yml in the semgrep-docs repo
 *)

(*****************************************************************************)
(* Types and constants *)
(*****************************************************************************)

(* TODO: we should redesign the CLI flags of semgrep ci and reduce
 * them to the minimum; if you want flexibility, use semgrep scan,
 * otherwise semgrep ci should be minimalist and take no
 * args at all in most cases.
 *
 * We probably still want though conf_runner flags like:
 *  - --max-memory, -j, --timeout (even though iago want to remove it)
 *  - the pro-engine flags --pro, --oss-only, etc (even though again
 *    we're going towards remove --pro for more precise --interfile,
 *    --secrets, etc)
 *  - --include, --exclude
 *  - maybe also --output? (even though I don't understand why people
 *    just don't simply use shell redirection)
 *
 * Note though that now osemgrep is called first by cli/bin/semgrep, so
 * we must accept here all flags and then fallback to pysemgrep.
 *)
type conf = {
  (* TODO? is this still used? *)
  audit_on : string list;
  dry_run : bool;
  suppress_errors : bool;
  (* --code/--sca/--secrets/ *)
  (* products : Semgrep_output_v1_t.product list; *)
  (* for monorepos *)
  subdir : string;
  (* BIG ONE: 'semgrep ci' shares most of its flags with 'semgrep scan'
   * TODO: we should reduce it actually, maybe just accept the core_runner
   * opti flags.
   *)
  scan_conf : Scan_CLI.conf;
  x_distributed_scan_conf : Distributed_scan_stub.conf;
}
[@@deriving show]

(*************************************************************************)
(* 'ci' only Command-line flags *)
(*************************************************************************)

(* ------------------------------------------------------------------ *)
(* Products *)
(* ------------------------------------------------------------------ *)

(* ------------------------------------------------------------------ *)
(* Other *)
(* ------------------------------------------------------------------ *)

let o_audit_on : string list Term.t =
  let info = Arg.info [ "audit-on" ] ~env:(Cmd.Env.info "SEMGREP_AUDIT_ON") in
  Arg.value (Arg.opt_all Arg.string [] info)

(* ugly: we also have a --dryrun in semgrep scan *)
let o_dry_run : bool Term.t =
  let info =
    Arg.info [ "dry-run" ]
      ~doc:
        {|When set, will not start a scan on semgrep.dev and will not report
findings. Instead will print out json objects it would have sent.|}
  in
  Arg.value (Arg.flag info)

let o_internal_ci_scan_results : bool Term.t =
  let info =
    Arg.info [ "internal-ci-scan-results" ] ~doc:{|<internal, do not use>|}
  in
  Arg.value (Arg.flag info)

(* for monorepos *)
let o_subdir : string Term.t =
  let info =
    Arg.info [ "subdir" ]
      ~doc:
        {|Scan only a subdirectory of this folder. This creates a project
specific to the subdirectory unless SEMGREP_REPO_DISPLAY_NAME is set. Expects a
relative path. (Note that when two scans have the same SEMGREP_REPO_DISPLAY_NAME
but different targeted directories, the results of the second scan overwrite
the first.)|}
  in
  Arg.value (Arg.opt Arg.string (Sys.getcwd ()) info)

let o_suppress_errors : bool Term.t =
  H.negatable_flag_with_env [ "suppress-errors" ]
    ~neg_options:[ "no-suppress-errors" ]
    ~env:(Cmd.Env.info "SEMGREP_SUPPRESS_ERRORS")
    ~default:true
    ~doc:
      {|Configures how the CI command reacts when an error occurs.
If true, encountered errors are suppressed and the exit code is zero (success).
If false, encountered errors are not suppressed and the exit code is non-zero
(failure).|}

(* we support a --config just so we can give a good error message *)
let o_config : string list Term.t =
  let info =
    Arg.info [ "c"; "f"; "config" ] ~doc:{|Not supported in 'ci' mode|}
  in
  Arg.value (Arg.opt_all Arg.string [] info)

(* internal *)
let o_x_dump_n_rule_partitions : int Term.t =
  let info = Arg.info [ "x-dump-rule-partitions" ] ~doc:{|Internal flag.|} in
  Arg.value (Arg.opt Arg.int 0 info)

(* internal *)
let o_x_dump_rule_partitions_dir : string Term.t =
  let info =
    Arg.info [ "x-dump-rule-partitions-dir" ] ~doc:{|Internal flag.|}
  in
  Arg.value (Arg.opt Arg.string "" info)

(* internal *)
let o_x_partial_config : string Term.t =
  let info = Arg.info [ "x-partial-config" ] ~doc:{|Internal flag.|} in
  Arg.value (Arg.opt Arg.string "" info)

(* internal *)
let o_x_partial_output : string Term.t =
  let info = Arg.info [ "x-partial-output" ] ~doc:{|Internal flag.|} in
  Arg.value (Arg.opt Arg.string "" info)

(* internal *)
let o_x_merge_partial_results_dir : string option Term.t =
  let info =
    Arg.info [ "x-merge-partial-results-dir" ] ~doc:{|Internal flag.|}
  in
  Arg.value (Arg.opt (Arg.some' Arg.dir) None info)

(* internal *)
let o_x_merge_partial_results_output : string option Term.t =
  let info =
    Arg.info [ "x-merge-partial-results-output" ] ~doc:{|Internal flag.|}
  in
  Arg.value (Arg.opt (Arg.some' Arg.string) None info)

(* internal *)
let o_x_validate_partial_results_expected : string option Term.t =
  let info =
    Arg.info [ "x-validate-partial-results-expected" ] ~doc:{|Internal flag.|}
  in
  Arg.value (Arg.opt (Arg.some' Arg.string) None info)

(* internal *)
let o_x_validate_partial_results_actual : string option Term.t =
  let info =
    Arg.info [ "x-validate-partial-results-actual" ] ~doc:{|Internal flag.|}
  in
  Arg.value (Arg.opt (Arg.some' Arg.string) None info)

(*************************************************************************)
(* 'scan' subset supported by 'ci' *)
(*************************************************************************)

(* Started as a copy paste of Scan_CLI.cmdline_terms but no:
 * target_roots, test/test_ignore_todo, ...
 *)
let scan_subset_cmdline_term : Scan_CLI.conf Term.t =
  (* !The parameters must be in alphabetic orders to match the order
   * of the corresponding '$ o_xx $' further below! *)
  let combine allow_local_builds allow_untrusted_validators autofix inline_metavariables
      baseline_commit common config dataflow_traces diff_depth dryrun
      _dump_command_for_core emacs emacs_outputs exclude_ exclude_minified_files
      exclude_rule_ids files_with_matches force_color gitlab_sast
      gitlab_sast_outputs gitlab_secrets gitlab_secrets_outputs
      _historical_secrets ignore_semgrepignore_files include_ incremental_output
      incremental_output_postprocess json json_outputs junit_xml junit_xml_outputs
      matching_explanations max_chars_per_line max_lines_per_finding max_log_list_entries
      max_memory_mb max_target_bytes metrics num_jobs no_secrets_validation
      nosem optimizations oss output output_enclosing_context pro pro_intrafile pro_lang
      pro_path_sensitive rewrite_rule_ids sarif sarif_outputs
      scan_unknown_extensions secrets semgrepignore_filename text text_outputs timeout
      _timeout_interfileTODO timeout_threshold (* trace trace_endpoint *) use_git
      version_check vim vim_outputs =
    if output_enclosing_context && not json then
      Logs.warn (fun m ->
          m
            "The --output-enclosing-context option has no effect without --json.");
    let output_format : Output_format.t =
      Scan_CLI.output_format_conf ~text ~files_with_matches ~json ~emacs ~vim
        ~sarif ~gitlab_sast ~gitlab_secrets ~junit_xml
    in
    (* TODO: Actually handle additional output files *)
    (* _outputs is currently just parsed to support pysemgrep *)
    let _outputs =
      Scan_CLI.outputs_conf ~text_outputs ~json_outputs ~emacs_outputs
        ~vim_outputs ~sarif_outputs ~gitlab_sast_outputs ~gitlab_secrets_outputs
        ~junit_xml_outputs
    in
    let output_conf : Output.conf =
      {
        output_format;
        max_chars_per_line;
        max_lines_per_finding;
        force_color;
        show_dataflow_traces = dataflow_traces;
        (* TODO: default value in semgrep ci? *)
        strict = false;
        fixed_lines = dryrun;
        skipped_files =
          (match common.CLI_common.logging_level with
          | Some (Info | Debug) -> true
          | _else_ -> false);
        max_log_list_entries;
      }
    in

    let engine_type : Engine_type.t =
      Scan_CLI.engine_type_conf ~oss ~pro_lang ~pro_intrafile ~pro ~secrets
        ~no_secrets_validation ~allow_untrusted_validators ~pro_path_sensitive
    in
    let rules_source = Rules_source.Configs config in
    let core_runner_conf =
      {
        Core_runner.num_jobs;
        optimizations;
        timeout;
        timeout_threshold;
        max_memory_mb;
        dataflow_traces;
        nosem;
        (* TODO: default value in semgrep ci? *)
        strict = false;
        time_flag = false;
        inline_metavariables;
        matching_explanations;
        engine_config = Engine_config.default;
      }
    in
    let include_ =
      match include_ with
      | [] -> None
      | nonempty -> Some nonempty
    in
    let targeting_conf : Find_targets.conf =
      {
        force_project_root = None;
        force_novcs_project = false;
        exclude = exclude_;
        include_;
        apply_includes_excludes_to_file_targets = false; (* no explicit targets anyway *)
        baseline_commit;
        diff_depth;
        max_target_bytes;
        always_select_explicit_targets = scan_unknown_extensions;
        explicit_targets = Find_targets.Explicit_targets.empty;
        respect_gitignore = use_git;
        respect_semgrepignore_files = not ignore_semgrepignore_files;
        semgrepignore_filename;
        exclude_minified_files;
      }
    in
    let rule_filtering_conf =
      {
        Rule_filtering.exclude_rule_ids =
          List_.map Rule_ID.of_string_exn exclude_rule_ids;
        severity = [];
        exclude_products = [];
      }
    in
    let matching_conf =
      {Match_patterns.track_enclosing_context = output_enclosing_context}
    in
    (* warnings.
     * ugly: TODO: remove the Default guard once we get the warning message
     * in osemgrep equal to the one in pysemgrep or when we remove
     * this sanity checks in pysemgrep and just rely on osemgrep to do it.
     *)
    if include_ <> None && exclude_ <> [] && common.maturity <> Maturity.Default
    then
      Logs.warn (fun m ->
          m
            "Paths that match both --include and --exclude will be skipped by \
             Opengrep.");
    Scan_CLI.
      {
        rules_source;
        target_roots = [];
        rule_filtering_conf;
        targeting_conf;
        core_runner_conf;
        error_on_findings = true;
        autofix;
        metrics;
        version_check;
        output;
        output_conf;
        incremental_output;
        incremental_output_postprocess;
        engine_type;
        rewrite_rule_ids;
        matching_conf;
        common;
        (* trace;
           trace_endpoint; *)
        (* ugly: *)
        version = false;
        show = None;
        validate = None;
        test = None;
        allow_local_builds;
        ls = false;
        ls_format = Ls_subcommand.default_format;
      }
  in
  (* Term defines 'const' but also the '$' operator *)
  Term.(
    (* !the o_xxx must be in alphabetic orders to match the parameters of
     * combine above! *)
    const combine $ SC.o_allow_local_builds $ SC.o_allow_untrusted_validators
    $ SC.o_autofix $ SC.o_inline_metavariables  $ SC.o_baseline_commit
    $ CLI_common.o_common $ o_config $ SC.o_dataflow_traces $ SC.o_diff_depth
    $ SC.o_dryrun $ SC.o_dump_command_for_core $ SC.o_emacs $ SC.o_emacs_outputs
    $ SC.o_exclude $ SC.o_exclude_minified_files $ SC.o_exclude_rule_ids
    $ SC.o_files_with_matches $ SC.o_force_color $ SC.o_gitlab_sast
    $ SC.o_gitlab_sast_outputs $ SC.o_gitlab_secrets
    $ SC.o_gitlab_secrets_outputs $ SC.o_historical_secrets
    $ SC.o_ignore_semgrepignore_files $ SC.o_include
    $ SC.o_incremental_output $ SC.o_incremental_output_postprocess
    $ SC.o_json $ SC.o_json_outputs $ SC.o_junit_xml $ SC.o_junit_xml_outputs
    $ SC.o_matching_explanations $ SC.o_max_chars_per_line
    $ SC.o_max_lines_per_finding $ SC.o_max_log_list_entries
    $ SC.o_max_memory_mb $ SC.o_max_target_bytes $ SC.o_metrics $ SC.o_num_jobs
    $ SC.o_no_secrets_validation $ SC.o_nosem $ SC.o_optimizations $ SC.o_oss
    $ SC.o_output $ SC.o_output_enclosing_context $ SC.o_pro $ SC.o_pro_intrafile $ SC.o_pro_languages
    $ SC.o_pro_path_sensitive $ SC.o_rewrite_rule_ids $ SC.o_sarif
    $ SC.o_sarif_outputs $ SC.o_scan_unknown_extensions $ SC.o_secrets
    $ SC.o_semgrepignore_filename $ SC.o_text $ SC.o_text_outputs $ SC.o_timeout
    $ SC.o_timeout_interfile $ SC.o_timeout_threshold $ (* SC.o_trace $ SC.o_trace_endpoint $ *) SC.o_use_git
    $ SC.o_version_check $ SC.o_vim $ SC.o_vim_outputs)

(*************************************************************************)
(* Turn argv into conf *)
(*************************************************************************)

let cmdline_term : conf Term.t =
  (* Note that we ignore the _xxx_meta; The actual environment variables
   * grabbing is done in Ci_subcommand.generate_meta_from_env, but we pass
   * it below so we can get a nice man page documenting those environment
   * variables (Romain's idea).
   *)
  let combine scan_conf audit_on (* code secrets *) dry_run _internal_ci_scan_results
      _x_dump_n_rule_partitions _x_dump_rule_partitions_dir
      x_merge_partial_results_dir x_merge_partial_results_output
      _x_partial_config _x_partial_output x_validate_partial_results_actual
      x_validate_partial_results_expected subdir (*  supply_chain *) suppress_errors
      _git_meta _github_meta =
    {
      scan_conf;
      audit_on;
      dry_run;
      suppress_errors;
      subdir;
      x_distributed_scan_conf =
        {
          merge_partial_results_dir =
            Option.map Fpath.v x_merge_partial_results_dir;
          merge_partial_results_output =
            Option.map Fpath.v x_merge_partial_results_output;
          validate_partial_results_expected =
            Option.map Fpath.v x_validate_partial_results_expected;
          validate_partial_results_actual =
            Option.map Fpath.v x_validate_partial_results_actual;
        };
    }
  in
  Term.(
    const combine $ scan_subset_cmdline_term $ o_audit_on
    $ o_dry_run $ o_internal_ci_scan_results
    $ o_x_dump_n_rule_partitions $ o_x_dump_rule_partitions_dir
    $ o_x_merge_partial_results_dir $ o_x_merge_partial_results_output
    $ o_x_partial_config $ o_x_partial_output
    $ o_x_validate_partial_results_actual
    $ o_x_validate_partial_results_expected $ o_subdir
    $ o_suppress_errors $ Git_metadata.env $ Github_metadata.env)

let doc = "the recommended way to run opengrep in CI"

let man : Cmdliner.Manpage.block list =
  [
    `S Cmdliner.Manpage.s_description;
    `P
      "In pull_request/merge_request (PR/MR) contexts, `opengrep ci` will only \
       report findings that were introduced by the PR/MR.";
    `P "Only displays findings that were marked as blocking.";
  ]
  @ CLI_common.help_page_bottom

let cmdline_info : Cmd.info = Cmd.info "opengrep ci" ~doc ~man

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let parse_argv (argv : string array) : conf =
  (* mostly a copy of Scan_CLI.parse_argv with different doc and man *)
  let cmd : conf Cmd.t = Cmd.v cmdline_info cmdline_term in
  CLI_common.eval_value ~argv cmd
