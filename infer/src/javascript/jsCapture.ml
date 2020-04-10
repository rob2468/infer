open! IStd
module L = Logging

(** This function reads the json file in fname, validates it, and encodes in the AST data structure
    defined in Clang_ast_t. *)
(* let validate_decl_from_file fname =
  Atdgen_runtime.Util.Biniou.from_file ~len:CFrontend_config.biniou_buffer_size
    Clang_ast_b.read_decl fname

*)
(**FIXME(T54413835): Make the perf stats in the frontend work when one runs more than one frontend
   action *)
let register_perf_stats_report source_file =
  let stats_type =
    if Config.capture then PerfStats.ClangFrontend source_file
    else if Config.linters then PerfStats.ClangLinters source_file
    else if Config.process_clang_ast then PerfStats.ClangProcessAST source_file
    else
      Logging.(die UserError)
        "Clang frontend should be run in capture, linters or process AST mode."
  in
  PerfStats.register_report_at_exit stats_type

let init_global_state_for_capture_and_linters source_file =
  L.(debug Capture Medium) "Processing %s@." (Filename.basename (SourceFile.to_abs_path source_file)) ;
  Language.curr_language := Language.Clang ;
  register_perf_stats_report source_file ;
  if Config.capture then DB.Results_dir.init source_file ;
  CFrontend_config.reset_global_state ()

(*
let run_clang_frontend ast_source =
  let init_time = Mtime_clock.counter () in
  let print_elapsed () =
    L.(debug Capture Quiet) "Elapsed: %a.@\n" Mtime.Span.pp (Mtime_clock.count init_time)
  in
  let ast_decl =
    match ast_source with
    | `File path ->
        validate_decl_from_file path
    (* | `Pipe chan ->
        validate_decl_from_channel chan *)
  in
  let trans_unit_ctx =
    match ast_decl with
    | Clang_ast_t.TranslationUnitDecl (_, _, _, info) ->
        let source_file = SourceFile.from_abs_path info.Clang_ast_t.tudi_input_path in
        init_global_state_for_capture_and_linters source_file ;
        {JsFrontend_config.source_file}
    | _ ->
        assert false
  in
  let pp_ast_filename fmt ast_source =
    match ast_source with
    | `File path ->
        Format.pp_print_string fmt path
    | `Pipe _ ->
        Format.fprintf fmt "stdin of %a" SourceFile.pp trans_unit_ctx.CFrontend_config.source_file
  in
  ClangPointers.populate_all_tables ast_decl ;
  L.(debug Capture Medium)
    "我在Start %s the AST of %a好吧@\n" Config.clang_frontend_action_string pp_ast_filename ast_source ;
  (* if Config.linters then AL.do_frontend_checks trans_unit_ctx ast_decl ; *)
  (* 不要 lint 功能 *)
  (* if Config.process_clang_ast then ( ProcessAST.process_ast trans_unit_ctx ast_decl ); *)
  (* 没走到这个case  *)
  if Config.capture then (
    Logging.debug_dev "也稚行了@.";
    CFrontend.do_source_file trans_unit_ctx ast_decl
  );
  L.(debug Capture Medium)
    "End %s the AST of file %a... OK!@\n" Config.clang_frontend_action_string pp_ast_filename
    ast_source ;
  print_elapsed () *)

let capture () =
  let trans_unit_ctx =
    let source_file = SourceFile.from_abs_path "/Users/jam/Desktop/infer/examples/hello.js" in
    init_global_state_for_capture_and_linters source_file ;
    {JsFrontend_config.source_file}
  in
  JsFrontend.do_source_file trans_unit_ctx
