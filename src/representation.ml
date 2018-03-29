(*
 *	dashc, client emulator for DASH video streaming
 *	Copyright (c) 2016-2018, Aleksandr Reviakin, University College Cork
 *
 *	This program is free software; you can redistribute it and/or
 *	modify it under the terms of the GNU General Public License
 *	as published by the Free Software Foundation; either version 2
 *	of the License, or (at your option) any later version.
 *
 *	This program is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *
 *	You should have received a copy of the GNU General Public License
 *	along with this program; if not, write to the Free Software
 *	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 *	02110-1301, USA.
*)

open Core
open Async
open Cohttp
open Cohttp_async
open Xml

type media_url =
  | Template_url of string
  | List_url of string List.t

type representation = {
  width : int;
  height : int;
  bandwidth : int;
  media : media_url;
  startNumber : int;
  segment_duration : int;
}

let calculate_average_chunk_size_per_repr chunk_sizes_per_repr =
  let rec hashtbl_iteri ~index ~average_chunk_size_per_repr =
    match index > Hashtbl.length chunk_sizes_per_repr with
    | true -> List.rev average_chunk_size_per_repr
    | false ->
      let sum_of_segm_sizes = List.length (Hashtbl.find_exn chunk_sizes_per_repr index) in
      let mean = sum_of_segm_sizes / List.length (Hashtbl.find_exn chunk_sizes_per_repr index) in
      hashtbl_iteri ~index:(index + 1) ~average_chunk_size_per_repr:(mean :: average_chunk_size_per_repr)
  in
  hashtbl_iteri ~index:1 ~average_chunk_size_per_repr:[]

let link_of_media media segmentNumber =
  match media with
  | Template_url media -> (String.chop_suffix_exn media ~suffix:"$Number$.m4s") ^ (string_of_int segmentNumber) ^ ".m4s"
  | List_url list_url -> List.nth_exn list_url (segmentNumber - 1)

let media_presentation_duration_from_mpd (mpd : xml) =
  match mpd with
  | Element ("MPD", attrs, clist) ->
    let duration_str = (Caml.List.assoc "mediaPresentationDuration" attrs) in
    begin match (String.split_on_chars duration_str ~on:['P'; 'Y'; 'M'; 'W'; 'D'; 'T'; 'H'; 'M'; 'S']) with
    | [_; _; sec; _] -> float_of_string sec
    | [_; _; min; sec; _] -> (float_of_string min *. 60.) +. float_of_string sec
    | [_; _; hours; min; sec; _] ->
      (float_of_string hours *. 60. *. 60.) +. (float_of_string min *. 60.) +. float_of_string sec
    | [_; days; _; hours; min; sec; _] ->
      (float_of_string days *. 24. *. 60. *. 60.) +.
      (float_of_string hours *. 60. *. 60.) +. (float_of_string min *. 60.) +. float_of_string sec
    | [_; months; days; _; hours; min; sec; _] ->
      (float_of_string months *.30. *. 24. *. 60. *. 60.) +. (float_of_string days *. 24. *. 60. *. 60.) +.
      (float_of_string hours *. 60. *. 60.) +. (float_of_string min *. 60.) +. float_of_string sec
    | [_; years; months; days; _; hours; min; sec; _] ->
      (float_of_string years *. 365. *. 24. *. 60. *. 60.) +.
      (float_of_string months *.30. *. 24. *. 60. *. 60.) +. (float_of_string days *. 24. *. 60. *. 60.) +.
      (float_of_string hours *. 60. *. 60.) +. (float_of_string min *. 60.) +. float_of_string sec
    | _ -> failwith "Incorrect mediaPresentationDuration attribute"
    end
  | _ -> failwith "mediaPresentationDuration attribute was not found"

let get_last_segment_index xml_str segment_duration last_segment_index =
  let duration = media_presentation_duration_from_mpd xml_str in
  let total_number_of_segments = int_of_float (round ~dir:`Up (duration /. float_of_int segment_duration)) in
  match last_segment_index with
  | Some last_segment_index ->
    if last_segment_index < total_number_of_segments then last_segment_index
    else total_number_of_segments
  | None -> total_number_of_segments

let repr_table_from_mpd (mpd : xml) =
  let adaptationSets = Xml.fold (fun acc x ->
      match x with
      | Element ("Period", attrs, clist) -> clist
      (* skip ProgramInformation attribute *)
      | _ -> acc
    ) [] mpd in
  let total_number_of_repr_per_adaptation_set = List.fold adaptationSets ~init:[] ~f:(fun acc adaptationSetTag ->
    let repr_total_number = Xml.fold (fun acc xml_ ->
        acc +
        match xml_ with
        | Element ("Representation", _, _) -> 1
        | _ -> 0
      ) 0 adaptationSetTag in
    acc @ [repr_total_number]
  ) in
  let total_number_of_repr = List.length total_number_of_repr_per_adaptation_set in
  let representations : (int, representation) Hashtbl.t =
    Hashtbl.Poly.create ~size:total_number_of_repr () in
  let index = ref total_number_of_repr in
  List.iter adaptationSets (fun adaptationSetTag ->
    Xml.iter (fun nextChild ->
      match nextChild with
      | Element ("Representation", attrs, clist) ->
      (* timescale attribute is used in template based MPD in SegmentTemplate tag *)
        let timescale = match (List.hd_exn clist) with
          | Element ("SegmentTemplate", attrs, clist) ->
            int_of_string @@ Caml.List.assoc "timescale" attrs;
          | _ -> 0;
        in
        (* duration attribute is used in template based MPD in SegmentTemplate tag *)
        let duration = match (List.hd_exn clist) with
          | Element ("SegmentTemplate", attrs, clist) ->
            int_of_string @@ Caml.List.assoc "duration" attrs;
          | _ -> 0;
        in
        let width = int_of_string (Caml.List.assoc "width" attrs) in
        let height = int_of_string (Caml.List.assoc "height" attrs) in
        let bandwidth = int_of_string (Caml.List.assoc "bandwidth" attrs) in
        let startNumber = match (List.hd_exn clist) with
          | Element ("SegmentTemplate", attrs, clist) ->
            int_of_string @@ Caml.List.assoc "startNumber" attrs;
          | _ -> 1;
        in
        let media, duration_new = List.fold ~init:(Template_url "", 0) clist ~f:(fun acc x ->
          match x with
          | Element ("SegmentTemplate", attrs, clist) ->
            Template_url (Caml.List.assoc "media" attrs), 0
          | Element ("SegmentList", attrs, clist) ->
            let duration_from_segment_list = int_of_string @@ Caml.List.assoc "duration" attrs in
            let media_url_list = List.fold ~init:[] clist ~f:(fun acc x ->
              match x with
              | Element ("SegmentURL", attrs, clist) ->
                Caml.List.assoc "media" attrs :: acc
              | _ -> acc
            ) in
            List_url (List.rev media_url_list), duration_from_segment_list
          | _ -> acc
        ) in
        let duration_final = if timescale = 0 || duration = 0 then duration_new else duration / timescale in
        Hashtbl.add_exn representations
          (* the key here is a representation id, however, in some MPD the representations starts from the highest one
            in the other from the lowest one, so this calculations below is not the generic way,
            it should probably based on sorted by bandwidth order *)
          ~key:(if timescale = 0 || duration = 0 then (total_number_of_repr + 1 - !index) else !index)
          ~data:{
            width = width;
            height = height;
            bandwidth = bandwidth;
            (* go inside SegmentTemplate tag as well *)
            media = media;
            (* there is no startNumber in the old MPD standard, at least in our examples *)
            startNumber = startNumber;
            segment_duration = duration_final;
          };
        index := !index - 1
      | _ -> ()
    ) adaptationSetTag;
  );
  representations

let download_chunk_sizes_per_repr ?conn ~root_link ~representations ~last_segment_index =
  let chunk_sizes_per_repr : (int, int List.t) Hashtbl.t = Hashtbl.Poly.create ~size:10 () in
  let rec download_next_chunk ~curr_index ~media ~chunks =
    match curr_index > last_segment_index with
    | true -> return @@ List.rev chunks
    | false ->
      Client.head ?conn:conn (Uri.of_string (root_link ^ (link_of_media media curr_index))) >>= fun resp ->
      match (Header.get (Response.headers resp) "content-length") with
      | Some cont_len -> download_next_chunk ~curr_index:(curr_index + 1) ~media:media ~chunks:(int_of_string cont_len :: chunks)
      | None -> failwith "Server does not include content-length field"
  in
  let rec download_next_repr ~curr_index =
    match curr_index < (Hashtbl.length representations + 1) with
    | true ->
      let curr_repr = Hashtbl.find_exn representations curr_index in
      print_string "Starting of downloading headers for representation ";
      print_int curr_index;
      print_endline "";
      download_next_chunk ~curr_index:1 ~media:curr_repr.media ~chunks:[] >>= fun chunk_list ->
      Hashtbl.add_exn chunk_sizes_per_repr ~key:curr_index ~data:chunk_list;
      download_next_repr ~curr_index:(curr_index + 1)
    | false -> Deferred.unit
  in
  download_next_repr ~curr_index:1 >>= fun () -> return chunk_sizes_per_repr

let open_connection link = function
  | true -> Client.Net.connect_uri (Uri.of_string link)
    >>= fun (ic,oc) -> return (Some (ic,oc))
  | false -> return None

let make_segment_size_file ~link ~persist =
  try_with (fun () ->
      let _, segmlist_mpd = String.rsplit2_exn link ~on:'/' in
      let outc = Out_channel.create @@ "segmentlist_" ^ segmlist_mpd ^ ".txt" in
      open_connection link persist >>= fun conn ->
      Client.get ?conn:conn (Uri.of_string link) >>= fun (resp, body) ->
      body |> Cohttp_async.Body.to_string >>= fun body ->
      let mpd = Xml.parse_string body in
      let representations : (int, representation) Hashtbl.t = repr_table_from_mpd mpd in
      let segment_duration = (Hashtbl.find_exn representations 1).segment_duration in
      let last_segment_index = get_last_segment_index mpd segment_duration None in
      let root_link, _ = String.rsplit2_exn link '/' in
      let root_link = root_link ^ "/" in
      download_chunk_sizes_per_repr
        ?conn:conn
        ~root_link:root_link
        ~representations:representations
        ~last_segment_index:last_segment_index
      >>= fun chunk_sizes_per_repr ->
      print_endline "All segment sizes were successfully downloaded";
      let rec hashtbl_iteri index =
        let segm_list = Hashtbl.find_exn chunk_sizes_per_repr index in
        Out_channel.output_string outc @@ string_of_int index ^ " ";
        Out_channel.output_string outc @@ string_of_int @@ List.length segm_list;
        Out_channel.newline outc;
        List.iter segm_list ~f:(fun data ->
            Out_channel.output_string outc @@ string_of_int data;
            Out_channel.newline outc;
          );
        match index = Hashtbl.length chunk_sizes_per_repr with
        | true -> ()
        | false -> hashtbl_iteri (index + 1)
      in
      hashtbl_iteri 1;
      Out_channel.close outc;
      Deferred.unit
    )
  >>| function
  | Ok () -> ()
  | Error e ->
    match (String.is_substring (Exn.to_string e) "connection attempt timeout") with
    | true -> print_endline @@ "Connection attempt timeout (10 sec default) to " ^ link
    | false -> print_endline @@ Exn.to_string e

(* read segment sizes from segmentlist%mpd%.txt compatible file which can be created by download_chunk_sizes_per_repr function,
   if remote_string is passed then it means the files was downloaded from remote location and passed as a string *)
let read_segment_size_file ?remote_string ~link ~number_of_representations ~last_segment_index =
  let chunk_sizes_per_repr : (int, int List.t) Hashtbl.t = Hashtbl.Poly.create ~size:10 () in
  let string_file =
    match remote_string with
    | Some line -> ref line
    | None -> ref ""
  in
  let possible_in_channel =
    match remote_string with
    | Some _ -> None
    | None ->
      let _, segmlist_mpd = String.rsplit2_exn link ~on:'/' in
      Some (In_channel.create @@ "segmentlist_" ^ segmlist_mpd ^ ".txt")
  in
  let rec read_next_repr () =
    let info_line =
      match possible_in_channel with
      | Some in_channel -> In_channel.input_line in_channel
      | None ->
        (* think about moving to option function instead of exception variant *)
        let hd_line, tl_line = String.lsplit2_exn !string_file ~on:'\n' in
        string_file := tl_line;
        Some hd_line
    in
    let (repr_index, total_segment_number) =
      match info_line with
      | Some line -> let separate_values = String.split line ~on:' ' in
        (int_of_string @@ List.hd_exn separate_values, int_of_string @@ List.last_exn separate_values)
      | None -> failwith "Incorrect segmentlist.txt"
    in
    (* check if the passed parameter last_segment_index is higher than the number of segment sizes in file then something is wrong *)
    if total_segment_number < last_segment_index then failwith "total segment number in file is less than the expected number of segments for playing";
    let rec read_next_segm_list ~curr_index ~chunks =
      match curr_index > total_segment_number with
      | true -> List.rev chunks
      | false ->
        let raw_string =
          match possible_in_channel with
          | Some in_channel -> In_channel.input_line in_channel
          | None ->
            (* think about moving to option function instead of exception variant *)
            let hd_line, tl_line = String.lsplit2_exn !string_file ~on:'\n' in
            string_file := tl_line;
            Some hd_line
        in
        let segm_size =
          match raw_string with
          | Some line -> int_of_string line
          | None -> failwith "Incorrect segmentlist.txt"
        in
        read_next_segm_list ~curr_index:(curr_index + 1) ~chunks:(segm_size :: chunks)
    in
    let chunk_list = read_next_segm_list ~curr_index:1 ~chunks:[] in
    Hashtbl.add_exn chunk_sizes_per_repr ~key:repr_index ~data:chunk_list;
    match repr_index < number_of_representations with
    | true -> read_next_repr ()
    | false -> ()
  in
  read_next_repr ();
  let () =
    match possible_in_channel with
    | Some in_channel -> In_channel.close in_channel
    | None -> ()
  in
  return chunk_sizes_per_repr

(* this function was made for debug purposes, delete it in future *)
let print_reprs representations =
  Hashtbl.iteri representations ~f:(fun ~key ~data ->
      print_int key;
      print_endline "";
      print_int data.width;
      print_endline "";
      print_int data.height;
      print_endline "";
      print_int data.bandwidth;
      print_endline "";
      let media_template =
        match data.media with
        | Template_url media -> media
        | List_url list_url -> "list_based_mpd"
      in
      print_string media_template;
      print_endline "";
      print_int data.startNumber;
      print_endline "";
      print_int data.segment_duration;
      print_endline "";
      print_endline "";
    )
