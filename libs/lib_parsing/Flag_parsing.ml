(* TODO: we should probably get rid of this file.
 * You can switch to Logs src if you want logging for your parser.
 *)

(* HACK: Needed for tools/languages_dumper/Main.ml.
 * Seems unused anyway... *)
let verbose_lexing_dummy = ref false
let verbose_parsing_dummy = ref true

let verbose_lexing = Domain.DLS.new_key (fun () -> false)
let verbose_parsing = Domain.DLS.new_key (fun () -> true)

(* see Parse_info.lexical_error helper and Lexical_error exn *)
let exn_when_lexical_error = ref true

(* Do not raise an exn when a parse error but use NotParsedCorrectly.
 * If the parser is quite complete, it's better to set
 * error_recovery to false by default and raise a true ParseError exn.
 * This can be used also in testing code, to parse a big set of files and
 * get statistics (e.g., -parse_java) and not stop at the first parse error.
 *)
let error_recovery = Domain.DLS.new_key (fun () -> false)
let debug_lexer = ref false
let debug_parser = ref false

(* TODO: definitely switch to Logs src for that *)
let show_parsing_error = Domain.DLS.new_key (fun () -> true)

(* will lexer $X and '...' tokens, and allow certain grammar extension
 * see sgrep_guard() below.
 *)
(* This is used in a non thread-safe way...
 * One quick fix is to put this in DLS, even if it incures a performance
 * penalty. It's not invoked for source code parsing. *)
let sgrep_mode = Domain.DLS.new_key (fun () -> false)

let cmdline_flags_verbose () =
  [
    ("-no_verbose_parsing", Arg.Clear verbose_parsing_dummy, "  ");
    ("-no_verbose_lexing", Arg.Clear verbose_lexing_dummy, "  ");
  ]

let cmdline_flags_debugging () =
  [
    ("-debug_lexer", Arg.Set debug_lexer, " ");
    ("-debug_parser", Arg.Set debug_parser, " ");
  ]

let sgrep_guard v =
  if Domain.DLS.get sgrep_mode (* !sgrep_mode *)
  then v
  else raise Parsing.Parse_error
