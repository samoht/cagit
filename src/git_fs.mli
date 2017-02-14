(*
 * Copyright (c) 2013-2017 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

module type S = sig
  include Git_store.S
  val create_file: t -> string -> Git_tree.perm -> Git_blob.t -> unit Lwt.t
  val entry_of_file: t -> Git_index.t -> string -> Git_tree.perm ->
    Git_hash.Blob.t -> Git_blob.t -> Git_index.entry option Lwt.t
  val reset: t -> unit Lwt.t
  val clear: unit -> unit
end

module type IO = sig

  type path = string

  (* Reads *)

  val file_exists: path -> bool Lwt.t
  val directories: path -> string list Lwt.t
  val files: path -> string list Lwt.t
  val read_file: path -> Cstruct.t Lwt.t
  val stat_info: path -> Git_index.stat_info

  (* Updates *)

  val mkdir: path -> unit Lwt.t

  type lock
  val lock_file: path -> lock

  val write_file: ?temp_dir:path -> ?lock:lock -> path -> Cstruct.t -> unit Lwt.t
  val test_and_set_file: ?temp_dir:path -> lock:lock ->
    path -> test:Cstruct.t option -> set:Cstruct.t option -> bool Lwt.t
  val remove_file: ?lock:lock -> path -> unit Lwt.t
  val chmod: ?lock:lock -> path -> [`Exec] -> unit Lwt.t

end

module Make (IO: IO) (D: Git_hash.DIGEST) (I: Git_inflate.S): S
