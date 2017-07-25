module type S =
sig
  module Digest
    : Ihash.IDIGEST
  (** The [Digest] module used to make the module. *)

  type t
  (** A Git Tag object. The tag object is very much like a {!Commit.t} object -
      it contains a {i tagger}, a date, a message, and a pointer. Generally, the tag
      points to a commit rather than a tree. It's like a branch reference, but it
      never moves - it always points to the same commit but gives it a friendlier
      name. *)

  module Hash
    : Common.BASE
  (** The Hash module. *)

  module D
    : Common.DECODER  with type t = t
                       and type raw = Cstruct.t
                       and type init = Cstruct.t
                       and type error = [ `Decoder of string ]
  (** The decoder of the Git Tag object.
      We constraint the input to be a
      {Cstruct.t}. This decoder needs a
      {Cstruct.t} as an internal buffer. *)

  module A
    : Common.ANGSTROM with type t = t
  (** The Angstrom decoder of the Git Tag object. *)

  module F
    : Common.FARADAY  with type t = t
  (** The Faraday encoder of the Git Tag object. *)

  module M
    : Common.MINIENC  with type t = t
  (** The {!Minienc} encoder of the Git Tag object. *)

  module E
    : Common.ENCODER  with type t = t
                       and type raw = Cstruct.t
                       and type init = int * t
                       and type error = [ `Never ]
  (** The encoder (which uses a {!Minienc.encoder}) of the Git Tag object. We
      constraint the output to be a {Cstruct.t}. This encoder needs the Tag OCaml
      value and the memory consumption of the encoder (in bytes). The encoder can
      not fail.

      NOTE: we can not unspecified the error type (it needs to be concrete) but,
      because the encoder can not fail, we define the error as [`Never]. *)

  include Ihash.DIGEST with type t := t and type hash = Hash.t
  include Common.BASE with type t := t

  val obj : t -> Hash.t
  (** [obj t] returns the pointed hash of the Tag [t]. *)
end

module Make
    (Digest : Ihash.IDIGEST with type t = Bytes.t
                             and type buffer = Cstruct.t)
  : S with type Hash.t = Digest.t
       and module Digest = Digest
(** The {i functor} to make the OCaml representation of the Git Tag object by a
    specific hash implementation. We constraint the {!IDIGEST} module to generate a
    {!Bytes.t} and compute a {Cstruct.t}. *)