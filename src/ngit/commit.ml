module type S =
sig
  module Digest
    : Ihash.IDIGEST

  type t

  module Hash
    : Common.BASE
  module D
    : Common.DECODER  with type t = t
                       and type raw = Cstruct.t
                       and type init = Cstruct.t
                       and type error = [ `Decoder of string ]
  module A
    : Common.ANGSTROM with type t = t
  module F
    : Common.FARADAY  with type t = t
  module M
    : Common.MINIENC  with type t = t
  module E
    : Common.ENCODER  with type t = t
                       and type raw = Cstruct.t
                       and type init = int * t
                       and type error = [ `Never ]

  include Ihash.DIGEST with type t := t
                       and type hash = Hash.t
  include Common.BASE with type t := t

  val parents : t -> Hash.t list
  val tree : t -> Hash.t
  val compare_with_date : t -> t -> int
end

module Make
    (Digest : Ihash.IDIGEST with type t = Bytes.t
                             and type buffer = Cstruct.t)
  : S with type Hash.t = Digest.t
       and module Digest = Digest
= struct
  module Digest = Digest
  module Hash = Helper.BaseBytes

  (* XXX(dinosaure): git seems to be very resilient with the commit.
     Indeed, it's not a mandatory to have an author or a committer
     and for these information, it's not mandatory to have a date.

     Follow this issue if we have any problem with the commit format. *)

  type t =
    { tree      : Hash.t
    ; parents   : Hash.t list
    ; author    : User.t
    ; committer : User.t
    ; message   : string }
  and hash = Hash.t

  let hash_of_hex_string x =
    Helper.BaseBytes.of_hex (Bytes.unsafe_of_string x)
  let hash_to_hex_string x =
    Helper.BaseBytes.to_hex x |> Bytes.to_string

  module A =
  struct
    type nonrec t = t

    let sp = Angstrom.char ' '
    let lf = Angstrom.char '\x0a'
    let is_not_lf chr = chr <> '\x0a'

    let binding
      : type a. key:string -> value:a Angstrom.t -> a Angstrom.t
      = fun ~key ~value ->
      let open Angstrom in
      string key *> sp *> value <* lf <* commit

    let to_end len =
      let buf = Buffer.create len in
      let open Angstrom in

      fix @@ fun m ->
      available >>= function
      | 0 ->
        peek_char
        >>= (function
            | Some _ -> m
            | None ->
              let res = Buffer.contents buf in
              Buffer.clear buf;
              return res)
      | n -> take n >>= fun chunk -> Buffer.add_string buf chunk; m

    let decoder =
      let open Angstrom in

      binding ~key:"tree" ~value:(take_while is_not_lf) <* commit
      >>= fun tree      -> many (binding ~key:"parent"
                                         ~value:(take_while is_not_lf))
                           <* commit
      >>= fun parents   -> binding ~key:"author" ~value:User.A.decoder
                           <* commit
      >>= fun author    -> binding ~key:"committer" ~value:User.A.decoder
                           <* commit
      >>= fun committer -> to_end 1024 <* commit
      >>= fun message ->
          return { tree = hash_of_hex_string tree
                 ; parents = List.map hash_of_hex_string parents
                 ; author
                 ; committer
                 ; message }
  end

  module F =
  struct
    type nonrec t = t

    let length t =
      let string x = Int64.of_int (String.length x) in
      let ( + ) = Int64.add in

      let parents =
        List.fold_left (fun acc _ -> (string "parent") + 1L + (Int64.of_int (Digest.length * 2)) + 1L + acc) 0L t.parents
      in
      (string "tree") + 1L + (Int64.of_int (Digest.length * 2)) + 1L
      + parents
      + (string "author") + 1L + (User.F.length t.author) + 1L
      + (string "committer") + 1L + (User.F.length t.committer) + 1L
      + (string t.message)

    let sp = ' '
    let lf = '\x0a'

    let parents e x =
      let open Farfadet in
      eval e [ string $ "parent"; char $ sp; !!string ] (hash_to_hex_string x)

    let encoder e t =
      let open Farfadet in
      let sep = (fun e () -> char e lf), () in

      eval e [ string $ "tree"; char $ sp; !!string; char $ lf
             ; !!(option (seq (list ~sep parents) (fun e () -> char e lf)))
             ; string $ "author"; char $ sp; !!User.F.encoder; char $ lf
             ; string $ "committer"; char $ sp; !!User.F.encoder; char $ lf
             ; !!string ]
        (hash_to_hex_string t.tree)
        (match t.parents with [] -> None | lst -> Some (lst, ()))
        t.author
        t.committer
        t.message
  end

  module M =
  struct
    open Minienc

    type nonrec t = t

    let sp = ' '
    let lf = '\x0a'

    let parents x k e =
      (write_string "parent"
       @@ write_char sp
       @@ write_string (hash_to_hex_string x) k)
      e

    let encoder x k e =
      let rec list l k e = match l with
        | [] -> k e
        | x :: r ->
          (parents x
           @@ write_char lf
           @@ list r k) e
      in

      (write_string "tree"
       @@ write_char sp
       @@ write_string (hash_to_hex_string x.tree)
       @@ write_char lf
       @@ list x.parents
       @@ write_string "author"
       @@ write_char sp
       @@ User.M.encoder x.author
       @@ write_char lf
       @@ write_string "committer"
       @@ write_char sp
       @@ User.M.encoder x.committer
       @@ write_char lf
       @@ write_string x.message k)
      e
  end

  module D = Helper.MakeDecoder(A)
  module E = Helper.MakeEncoder(M)

  let list_pp ?(sep = (fun fmt () -> ())) pp_data fmt lst =
    let rec aux = function
      | [] -> ()
      | [ x ] -> pp_data fmt x
      | x :: r -> Format.fprintf fmt "%a%a" pp_data x sep (); aux r
    in
    aux lst

  let pp fmt { tree; parents; author; committer; message; } =
    Format.fprintf fmt
      "{ @[<hov>tree = @[<hov>%a@];@ \
                parents = [ @[<hov>%a@] ];@ \
                author = @[<hov>%a@];@ \
                committer = @[<hov>%a@];@ \
                message = @[<hov>%S@];@] }"
      Hash.pp tree
      (list_pp ~sep:(fun fmt () -> Format.fprintf fmt ";@ ") Hash.pp) parents
      User.pp author
      User.pp committer
      message

  let digest value =
    let tmp = Cstruct.create 0x100 in
    Helper.fdigest (module Digest) (module E) ~tmp ~kind:"commit" ~length:F.length value

  let equal   = (=)
  let hash    = Hashtbl.hash

  let parents { parents; _ } = parents
  let tree { tree; _ } = tree

  let compare_with_date a b =
    Int64.compare (fst a.author.User.date) (fst b.author.User.date)

  let compare = compare_with_date

  module Set = Set.Make(struct type nonrec t = t let compare = compare end)
  module Map = Map.Make(struct type nonrec t = t let compare = compare end)
end