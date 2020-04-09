(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd

type t

val mk : is_driver:bool -> ClangQuotes.style -> prog:string -> args:string list -> t
(** [mk ~is_driver qs prog args] finds the type of command depending on its arguments [args]. The
    quoting style of the arguments have to be provided, so that the command may be run later on.
    Beware that this doesn't look inside argument files. This can be used to create a "clang -###
    ..." command on which to call [command_to_run], but other functions from the module will not
    work as expected unless the command has been normalized by "clang -### ...". *)
(* 将原始数据转换成 infer 能识别的数据模型，该函数本身不会往数据模型中添加额外参数 *)

val command_to_run : t -> string
(** Make a command into a string ready to be passed to a shell to be executed. Fine to call with
    clang driver commands. *)
(* 将 infer 内部的命令表达转化成可以直接在 shell 中运行的字符串。（命令行选项和参数会保存到本地临时文件中，所以生成的字符串中的参数是临时文件的路径） *)

val can_attach_ast_exporter : t -> bool
(** Whether the command is suitable for attaching the AST exporter. Must be called on normalized
    commands. *)

val may_capture : t -> bool
(** Whether the command has a chance of triggering compilation steps we can capture. *)

val with_plugin_args : t -> t
(** Add the arguments needed to attach the facebook-clang-plugins plugin. Must be called on
    normalized commands. *)

val prepend_arg : string -> t -> t

val append_args : string list -> t -> t

val get_orig_argv : t -> string list

val pp : Format.formatter -> t -> unit

val print_raw_command_argvs : t -> unit
