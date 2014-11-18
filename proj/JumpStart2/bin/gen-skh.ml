open Printf
open Evaluate

let extract rex = Pcre.extract ~full_match:false ~rex:rex

(* input: sorted list - output: sorted list with no dupes *)
let uniq sorted_list =
  let rec uniq_prev prev acc = function
    | [] -> prev :: acc
    | hd :: tl ->
	if prev = hd then uniq_prev prev acc tl
	else uniq_prev hd (prev :: acc) tl
  in
    match sorted_list with
      | [] -> raise (Failure "uniq")
      | hd :: tl -> List.rev (uniq_prev hd [] tl)

(* gets a list with aliases and if some of them have .rangestack.com
   it adds to the result the short version of those names *)
let plus_short_names lst =
  let inkt_re = Pcre.regexp "^(.*)\\.rangestack\\.com$" in
  let rec add_to_lst acc = function
      [] -> acc
    | hd :: tl ->
	try
	  let res = extract inkt_re hd in
	    add_to_lst (res.(0) :: hd :: acc) tl
	with Not_found ->
	  add_to_lst (hd :: acc) tl in
    add_to_lst [] lst

let hash_keys hash = Hashtbl.fold (fun k _ acc -> k::acc) hash []
  
let ends_with substr str =
  let l1 = String.length substr and
      l2 = String.length str in
    if l1 > l2 then false
    else
      let rightstr = String.sub str (l2 - l1) l1 in
	rightstr = substr

(* add .rangestack.com to the hostname except for hosts that
   are already fqdn *)
let fully_qualify host =
  if ends_with ".com" host then host
  else host ^ ".rangestack.com"

(* Fast read file using low level Unix calls *)
let read_file path =
  let fd = Unix.openfile path [Unix.O_RDONLY] 0 in
  let st = Unix.fstat fd in
  let size = st.Unix.st_size in
  let buf = String.create size in
  let n = Unix.read fd buf 0 size in
    Unix.close fd;
    if n < size then prerr_endline ("INCOMPLETE READ for " ^ path);
    buf

(* read the ssh-key for a given host (from file) *)
let read_ssh_key host file =
  (* given a host what's the full path for the file that should have
     its public keys *)
  let full_path host =
    let no_dot =
      try String.sub host 0 (String.index host '.')
      with Not_found -> host in
      (* use a buffer to do the string concat efficiently *)
    let buf = Buffer.create 32 in
      Buffer.add_string buf "/usr/local/jumpstart/skh/";
      Buffer.add_string buf (String.sub no_dot (String.length no_dot - 2) 2);
      Buffer.add_char buf '/';
      Buffer.add_string buf host;
      Buffer.add_char buf '/';
      Buffer.add_string buf file;
      Buffer.contents buf in
  let res = read_file (full_path host) in
  let n = String.rindex res ' ' in
    (String.sub res 0 n) ^ "\n"

(* print to the right ###.skh file the generated ssh keys for a given range
   in /etc/ssh/ssh_known_hosts format *)
let gen_ssh_keys range prefix_len =
  let missing_keys = Hashtbl.create 1021 in
  let host_aliases = Hashtbl.create 23433 in
  let ip_host = Hashtbl.create 23433 in
  let a_rec_re = Pcre.regexp "^\\+([^:]+):([^:]+):0" in
  let cname_rec_re = Pcre.regexp "^C([^:]+):([^:]+)\\.:0" in
  let domain_re = Pcre.regexp "^(.*)\\.(?:rangestack|yst\\.corp\\.yahoo)\\.com$" in

  (* the current output filename prefix *)
  let cur_prefix = ref "" in
  let cur_out_chan : out_channel ref = ref stdout in

  (* ensure that cur_filename and cur_out_chan are updated properly *)
  let prep_out_chan host =
    let right_prefix = String.sub host 0 prefix_len in
      if right_prefix <> !cur_prefix then (
	if String.length !cur_prefix > 0 then
	  close_out !cur_out_chan;
	cur_prefix := right_prefix;
	cur_out_chan := open_out_gen [Open_creat; Open_append] 0o666 (right_prefix ^ ".skh");
      ) in

  (* print one skh entry *)
  let skh_entry canon_host =
    prep_out_chan canon_host;
    try
      let aliases = String.concat ","
	(uniq
	   (List.fast_sort compare
	      (plus_short_names
		 (canon_host :: (Hashtbl.find_all host_aliases canon_host))))) in
      let short_name fqdn =
	try
	  let res = extract domain_re fqdn in res.(0)
	with Not_found -> fqdn in
      let h = short_name canon_host in
      let files = ["ssh_host_key.pub"; "ssh_host_dsa_key.pub";
		   "ssh_host_rsa_key.pub"] in
	List.iter
	  (fun file ->
	     try
	       fprintf !cur_out_chan "%s %s" aliases (read_ssh_key h file)
	     with _ -> (Hashtbl.add missing_keys h file))
	  files
    with Failure _ -> prerr_endline ("ERR: " ^ canon_host) in

  let progress_bar_ref = ref 0 in
  let progress_bar total_hosts =
    incr progress_bar_ref;
    if !progress_bar_ref mod 1000 = 0 then (
      eprintf "\rINFO: %d/%d hosts processed..." !progress_bar_ref total_hosts;
      flush stderr;
    ); in
  let ch = open_in "/etc/service/tinydns/root/data" in
  let rec parse_tinydns () =
    let ln =  input_line ch in (
	try
	  let res = extract a_rec_re ln in
	  let host = res.(0) and ip = res.(1) in
	    if Hashtbl.mem ip_host ip then
	      let canon_host = Hashtbl.find ip_host ip in
		Hashtbl.add host_aliases canon_host host;
		List.iter (fun x -> Hashtbl.add host_aliases host x)
		  (Hashtbl.find_all host_aliases canon_host)
	    else (
	      Hashtbl.add ip_host ip host;
	      Hashtbl.add host_aliases host ip;
	    );
	with
	    Not_found -> (
	      try
		let res = extract cname_rec_re ln in
		let alias = res.(0) and canon = res.(1) in
		  Hashtbl.add host_aliases canon alias
	      with Not_found -> ();
	    );
      );
      parse_tinydns () in
    try
      prerr_endline "DEBUG: Parsing tinydns data";
      parse_tinydns ();
    with End_of_file ->
      close_in ch;
      prerr_endline "DEBUG: Done";
      Hashtbl.clear missing_keys;
      let nodes = sorted_expand_range range in
      let num_nodes = Array.length nodes in
	Array.iter (fun x -> progress_bar num_nodes;
		      skh_entry (fully_qualify x)) nodes;
	eprintf "\rINFO: %d hosts processed.                      \n" num_nodes;
	let need_keys = hash_keys missing_keys in
	  if List.length need_keys > 0 then 
	    let ary = Array.of_list need_keys in
	      prerr_endline ("MISSING SSH KEYS: " ^ (compress_range ary))
let _ =
  let range = ref "" in
  let verbose = ref false in
  let prefix_len = ref 3 in
  let args = [
    ("-v", Arg.Set verbose, "\tBe verbose");
    ("-l", Arg.Set_int prefix_len, "\tSet the prefix length"); ] in
    Arg.parse args (fun r -> range := r)
      "Usage: gen-skh [options] <secorange>\nWhere options are:";
    if !range = "" then
      prerr_endline "Need a range"
    else 
      gen_ssh_keys !range !prefix_len
  
