(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd
(** Given a clang command, normalize it via `clang -###` if needed to get a clear view of what work
    is being done and which source files are being compiled, if any, then replace compilation
    commands by our own clang with our plugin attached for each source file. *)

module L = Logging

type action_item =
  | CanonicalCommand of ClangCommand.t  (** commands output by [clang -###] *)
  | DriverCommand of ClangCommand.t  (** commands prior to [clang -###] treatment *)
  | ClangError of string
  | ClangWarning of string

let clang_ignore_regex = Option.map ~f:Str.regexp Config.clang_ignore_regex

let check_for_existing_file args =
  match (Config.buck_mode, clang_ignore_regex) with
  | Some (ClangCompilationDB _), Some clang_ignore_regex ->
      let arg_files, args_list = List.partition_tf ~f:(String.is_prefix ~prefix:"@") args in
      let read_arg_files args_list arg_file_at =
        let file = String.slice arg_file_at 1 (String.length arg_file_at) in
        let args_list_file = In_channel.read_lines file in
        List.append args_list args_list_file
      in
      let all_args_ = List.fold_left ~f:read_arg_files ~init:args_list arg_files in
      let all_args = List.map ~f:String.strip all_args_ in
      let rec check_for_existing_file_arg args =
        match args with
        | [] ->
            ()
        | option :: rest ->
            if String.equal option "-c" then
              (* infer-capture-all flavour of buck produces path to generated file that doesn't exist.
                 Create empty file empty file and pass that to clang. This is to enable compilation to continue *)
              match List.hd rest with
              | Some arg ->
                  if Str.string_match clang_ignore_regex arg 0 && Sys.file_exists arg <> `Yes then (
                    Unix.mkdir_p (Filename.dirname arg) ;
                    let file = Unix.openfile ~mode:[Unix.O_CREAT; Unix.O_RDONLY] arg in
                    Unix.close file )
              | None ->
                  ()
            else check_for_existing_file_arg rest
      in
      check_for_existing_file_arg all_args
  | _ ->
      ()


(** Given a clang command, return a list of new commands to run according to the results of `clang
    \-### [args]`. *)
let clang_driver_action_items : ClangCommand.t -> action_item list =
 fun cmd ->
  let clang_hashhashhash =
    Printf.sprintf "%s 2>&1"
      ( ClangCommand.prepend_arg "-###" cmd
      |> (* c++ modules are not supported, so let clang know in case it was passed "-fmodules".
            Unfortunately we cannot know accurately if "-fmodules" was passed because we don't go
            into argument files at this point ("clang -### ..." will do that for us), so we also pass
            "-Qunused-arguments" to silence the potential warning that "-fno-cxx-modules" was
            ignored. Moreover, "-fno-cxx-modules" is only accepted by the clang driver so we have to
            pass it now.

            Using clang instead of gcc may trigger warnings about unsupported optimization flags;
            passing -Wno-ignored-optimization-argument prevents that.

            Clang adds "-faddrsig" by default on ELF targets. This is ok in itself, but for some
            reason that flag is the only one to show up *after* the source file name in the -cc1
            commands emitted by [clang -### ...]. Passing [-fno-addrsig] ensures that the source
            path is always the last argument. *)
      ClangCommand.append_args
        [ "-fno-cxx-modules"
        ; "-Qunused-arguments"
        ; "-Wno-ignored-optimization-argument"
        ; "-fno-addrsig" ]
      |> (* If -fembed-bitcode is passed, it leads to multiple cc1 commands, which try to read .bc
            files that don't get generated, and fail. So pass -fembed-bitcode=off to disable. *)
      ClangCommand.append_args ["-fembed-bitcode=off"]
      |> ClangCommand.command_to_run
      (* |> ClangCommand.print_raw_command_argvs; *)
      (* "'/Users/jam/Desktop/infer/infer/bin/../../facebook-clang-plugins/clang/install/bin/clang' '@/var/folders/0l/jfmpg84s005dgms3wrw7wsnc0000gn/T/clang_command_.tmp.19aa4a.txt' 2>&1" *)
      )
  in
  L.(debug Capture Medium) "clang -### invocation: %s@\n" clang_hashhashhash ;
  let normalized_commands = ref [] in
  let one_line line =
    Logging.debug_dev "一行: %s@." line;
    if String.is_prefix ~prefix:" \"" line then
      CanonicalCommand
        ( (* massage line to remove edge-cases for splitting *)
        match
          "\"" ^ line ^ " \""
          |> (* split by whitespace *)
          Str.split (Str.regexp_string "\" \"")
        with
        | prog :: args ->
            ClangCommand.mk ~is_driver:false ClangQuotes.EscapedDoubleQuotes ~prog ~args
        | [] ->
            L.(die InternalError) "ClangWrapper: argv cannot be empty" )
    else if Str.string_match (Str.regexp "clang[^ :]*: warning: ") line 0 then ClangWarning line
    else ClangError line
  in
  let commands_or_errors =
    (* commands generated by `clang -### ...` start with ' "/absolute/path/to/binary"' *)
    Str.regexp " \"/\\|clang[^ :]*: \\(error\\|warning\\): "
  in
  let ignored_errors =
    Str.regexp "clang[^ :]*: \\(error\\|warning\\): unsupported argument .* to option 'fsanitize='"
  in
  let consume_input i =
    try
      while true do
        let line = In_channel.input_line_exn i in
        (* keep only commands and errors *)
        if
          Str.string_match commands_or_errors line 0 && not (Str.string_match ignored_errors line 0)
        then normalized_commands := one_line line :: !normalized_commands
      done
    with End_of_file -> ()
  in
  (* collect stdout and stderr output together (in reverse order) *)
  Utils.with_process_in clang_hashhashhash consume_input |> ignore ;
  normalized_commands := List.rev !normalized_commands ;
  !normalized_commands


(** Given a list of arguments for clang [args], return a list of new commands to run according to
    the results of `clang -### [args]` if the command can be analysed. *)
let normalize ~prog ~args : action_item list =
  let cmd = ClangCommand.mk ~is_driver:true ClangQuotes.SingleQuotes ~prog ~args in
  Logging.debug_dev "标准化之前@.";
  let () = ClangCommand.print_raw_command_argvs cmd in
  (* 打印参数 *)
  let a = ClangCommand.may_capture cmd in
  if a then clang_driver_action_items cmd else [DriverCommand cmd]

let exec_action_item ~prog ~args = function
  | ClangError error ->
      Logging.debug_dev "一: ClangError@.";
      (* An error in the output of `clang -### ...`. Outputs the error and fail. This is because
         `clang -###` pretty much never fails, but warns of failures on stderr instead. *)
      L.(die UserError)
        "Failed to execute compilation command:@\n\
         '%s' %a@\n\
         @\n\
         Error message:@\n\
         %s@\n\
         @\n\
         *** Infer needs a working compilation command to run." prog Pp.cli_args args error
  | ClangWarning warning ->
      Logging.debug_dev "二: ClangWarning@.";
      L.external_warning "%s@\n" warning
  | CanonicalCommand clang_cmd ->
      Logging.debug_dev "三: CanonicalCommand@.";
      ClangCommand.print_raw_command_argvs clang_cmd;
      Capture.capture clang_cmd
      (* 开始走到capture流程 *)
  | DriverCommand clang_cmd ->
      Logging.debug_dev "四: DriverCommand@.";
      if
        Config.skip_analysis_in_path_skips_compilation
        || Option.exists Config.buck_mode ~f:BuckMode.is_clang_compilation_db
      then Capture.run_clang clang_cmd Utils.echo_in
      else
        L.debug Capture Quiet "Skipping seemingly uninteresting clang driver command %s@\n"
          (ClangCommand.command_to_run clang_cmd)


let exe ~prog ~args =
  let xx_suffix = match String.is_suffix ~suffix:"++" prog with true -> "++" | false -> "" in
  (* use clang in facebook-clang-plugins *)
  let clang_xx = CFrontend_config.clang_bin xx_suffix in
  check_for_existing_file args ;
  let commands = normalize ~prog:clang_xx ~args in
  (* xcodebuild projects may require the object files to be generated by the Apple compiler, eg to
     generate precompiled headers compatible with Apple's clang. *)
  Logging.debug_dev "标准化之后@.";
  let () =
  List.iter ~f:(fun item ->
    match item with
    | CanonicalCommand cmd -> ClangCommand.print_raw_command_argvs cmd
    | ClangError error ->
      Logging.debug_dev "@.";
      (* An error in the output of `clang -### ...`. Outputs the error and fail. This is because
          `clang -###` pretty much never fails, but warns of failures on stderr instead. *)
    | ClangWarning warning ->
        Logging.debug_dev "@.";
    | DriverCommand clang_cmd ->
        Logging.debug_dev "@.";
  ) commands
  in
  (* 打印我需要的信息 *)
  let prog, should_run_original_command =
    match Config.fcp_apple_clang with
    | Some bin ->
        let bin_xx = bin ^ xx_suffix in
        L.(debug Capture Medium) "Will run Apple clang %s" bin_xx ;
        (bin_xx, true)
    | None ->
        Logging.debug_dev "运行的命令: %s@." clang_xx;
        (clang_xx, false)
  in
  List.iter ~f:(exec_action_item ~prog ~args) commands ;
  if List.is_empty commands || should_run_original_command then (
    if List.is_empty commands then
      (* No command to execute after -###, let's execute the original command
         instead.

         In particular, this can happen when
         - there are only assembly commands to execute, which we skip, or
         - the user tries to run `infer -- clang -c file_that_does_not_exist.c`. In this case, this
         will fail with the appropriate error message from clang instead of silently analyzing 0
         files. *)
      L.(debug Capture Quiet)
        "WARNING: `clang -### <args>` returned an empty set of commands to run and no error. Will \
         run the original command directly:@\n\
        \  %s@\n"
        (String.concat ~sep:" " @@ (prog :: args)) ;
    Process.create_process_and_wait ~prog ~args )
