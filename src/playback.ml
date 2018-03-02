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
open Cohttp_async

open Representation
open Segm_result
open Adapt_algo

let supported_algorithms = ["conv"; "bba-0"; "bba-1"; "bba-2"; "arbiter"]
let algorithms_with_required_chunk_sizes = ["bba-1"; "bba-2"; "arbiter"]
let log_columns = ["Seg_#"; "Arr_time"; "Del_Time"; "Stall_Dur"; "Rep_Level"; "Del_Rate"; "Act_Rate"; "Byte_Size"; "Buff_Level"]

let is_buffer_full buffer_size maxbuf segment_duration =
  buffer_size > (maxbuf -. float_of_int segment_duration)

let next_repr_number representations results last_segment_index = function
  | Conv -> Conv.next_representation_level ~representations:representations ~results:results
  | BBA_0 algo -> BBA_0.next_representation_level ~algo:algo ~representations:representations ~results:results
  | BBA_1 algo -> BBA_1.next_representation_level ~algo:algo ~representations:representations ~results:results last_segment_index
  | BBA_2 algo -> BBA_2.next_representation_level ~algo:algo ~representations:representations ~results:results last_segment_index
  | ARBITER algo -> ARBITER.next_representation_level ~algo:algo ~representations:representations ~results:results last_segment_index

let rec playback
    ?conn
    ?outc
    ~root_link
    ~representations
    ~results
    ~absolute_start_time
    ~buffer_size
    ~segment_number
    ~initb
    ~maxbuf
    ~adapt_method
    ~last_segment_index
    ~segment_duration =
  match is_buffer_full buffer_size maxbuf segment_duration with
  | true ->
    Clock.after (Time.Span.of_sec 0.1) >>= fun () ->
    playback
      ?conn:conn
      ?outc:outc
      ~root_link:root_link
      ~representations:representations
      ~results:results
      ~absolute_start_time:absolute_start_time
      ~buffer_size:(buffer_size -. 0.1)
      ~segment_number:(segment_number)
      ~initb:initb
      ~maxbuf:maxbuf
      ~adapt_method:adapt_method
      ~last_segment_index:last_segment_index
      ~segment_duration:segment_duration
  | false ->
    let start = Time.now () in
    let next_repr_number = next_repr_number representations results last_segment_index adapt_method in
    let next_repr = Hashtbl.find_exn representations next_repr_number in
    Client.get ?conn:conn (Uri.of_string (root_link ^ (link_of_media next_repr.media segment_number))) >>= fun (resp, body) ->
    body |> Cohttp_async.Body.to_string >>= fun body ->
    let current_time = Time.now () in
    let time_diff = Time.diff current_time start in
    let diff = Time.Span.to_sec time_diff  in
    let initb = match buffer_size >= (initb *. float_of_int segment_duration) with
    | true -> 0.
    | false -> initb
    in
    let buf = match buffer_size > (initb *. float_of_int segment_duration) with
    | true -> begin
      match buffer_size <= diff with
      | true -> 0.
      | false -> buffer_size -. diff
      end
    | false -> buffer_size
    in
    let stall = match buffer_size > (initb *. float_of_int segment_duration) && buffer_size < diff with
    (* check this condition for startup phaze *)
    | true -> int_of_float @@ (diff -. buffer_size) *. 1000.
    | false -> 0
    in
    let results =
      {
        segment_number = segment_number;
        arrival_time = int_of_float @@ Time.Span.to_us (Time.diff current_time absolute_start_time);
        time_for_delivery = int_of_float @@ Time.Span.to_us time_diff;
        stall_dur = stall;
        representation_rate = next_repr.bandwidth;
        actual_representation_rate = 8 * (String.length body) / segment_duration;
        segment_size = String.length body;
        buffer_level_in_momentum = (buf +. float_of_int segment_duration);
        repr_level = next_repr_number;
      } :: results
    in
    print_result (List.hd_exn results) None;
    print_result (List.hd_exn results) outc;
    match segment_number >= last_segment_index with
    | true -> return @@ print_endline "Stop after the lastsegmindex segment parameter (default is 150)"
    | false ->
      playback
        ?conn:conn
        ?outc:outc
        ~root_link:root_link
        ~representations:representations
        ~results:results
        ~absolute_start_time:absolute_start_time
        ~buffer_size:(buf +. float_of_int segment_duration)
        ~segment_number:(segment_number + 1)
        ~initb:initb
        ~maxbuf:maxbuf
        ~adapt_method:adapt_method
        ~last_segment_index:last_segment_index
        ~segment_duration:segment_duration

let check_input_algorithm_existence input_alg =
  match List.exists supported_algorithms ~f:(fun x -> x = input_alg) with
  | true -> ()
  | false -> failwith "The chosen adaptation algorithm is not supported, please check help" 

let create_log_channel logname log_folder v_number r_number = function
  | true ->
    begin match logname, v_number with
    | "now", _ ->
      begin match log_folder with
      | "" -> Some (Out_channel.create @@  Time.to_filename_string (Time.now ()) ~zone:Time.Zone.utc)
      | _ -> Some (Out_channel.create (log_folder ^ "/" ^  Time.to_filename_string (Time.now ()) ~zone:Time.Zone.utc))
      end
    | _, "-V99" ->
      begin match log_folder with
      | "" -> Some (Out_channel.create logname)
      | _ -> Some (Out_channel.create (log_folder ^ "/" ^ logname))
      end
    | _, _ ->
      begin match log_folder with
      | "" -> Some (Out_channel.create ("trace-" ^ Time.to_filename_string (Time.now ()) ~zone:Time.Zone.utc ^ "-" ^ logname ^ v_number ^ r_number ^ ".res"))
      | _ -> Some (Out_channel.create (log_folder ^ "/" ^ "trace-" ^ Time.to_filename_string (Time.now ()) ~zone:Time.Zone.utc ^ "-" ^ logname ^ v_number ^ r_number ^ ".res"))
      end
    end
  | false -> None

let check_requirement_for_chunk_sizes input_alg =
  List.exists algorithms_with_required_chunk_sizes ~f:(fun x -> x = input_alg)

let chunk_sizes adapt_alg segm_size_from_file link representations last_segment_index root_link segmlist_mpd conn =
  match check_requirement_for_chunk_sizes adapt_alg with
  | true ->
    let chunk_sizes_per_repr = match segm_size_from_file with
    | "local" ->
        read_segment_size_file
          ?remote_string:None
          ~link:link
          ~number_of_representations:(Hashtbl.length representations)
          ~last_segment_index:last_segment_index
    | "remote" ->
        let segm_list_remote_link = root_link ^ "/" ^ "segmentlist_" ^ segmlist_mpd ^ ".txt" in
        Client.get ?conn:conn (Uri.of_string segm_list_remote_link) >>= fun (resp, body) ->
        body |> Cohttp_async.Body.to_string >>= fun body_string ->
        read_segment_size_file
          ~remote_string:body_string
          ~link:link
          ~number_of_representations:(Hashtbl.length representations)
          ~last_segment_index:last_segment_index
    | _ ->
        download_chunk_sizes_per_repr
          ?conn:None
          ~root_link:root_link
          ~representations:representations
          ~last_segment_index:last_segment_index
    in
    chunk_sizes_per_repr >>| fun chunk_sizes_per_repr ->
    let average_chunk_size_per_repr = calculate_average_chunk_size_per_repr chunk_sizes_per_repr in
    (chunk_sizes_per_repr, average_chunk_size_per_repr)
  | false -> return (Hashtbl.Poly.create ~size:10 (), [])

let new_adapt_method chunk_sizes_per_repr average_chunk_size_per_repr = function
  | "conv" -> return Conv
  | "bba-0" -> return @@ BBA_0 { BBA_0.maxb = 240. }
  | "bba-1" ->
      return @@ BBA_1 {
        BBA_1.maxb = 240.;
        BBA_1.chunk_sizes_per_repr = chunk_sizes_per_repr;
        average_chunk_size_per_repr = average_chunk_size_per_repr
      }
  | "bba-2" ->
      return @@ BBA_2 {
        BBA_1.maxb = 240.;
        BBA_1.chunk_sizes_per_repr = chunk_sizes_per_repr;
        average_chunk_size_per_repr = average_chunk_size_per_repr
      }
  | "arbiter" ->
      return @@ ARBITER {
        ARBITER.maxb = 60.;
        ARBITER.chunk_sizes_per_repr = chunk_sizes_per_repr;
      }
  | _ -> failwith "The chosen adaptation algorithm is not supported"

let print_log_header_on_screen =
  List.iteri log_columns
  ~f:(fun idx x -> print_string x;
    match not @@ phys_equal idx (List.length log_columns - 1) with
    | true -> print_string "  "
    | false -> print_endline ""
  )

let print_log_header_into_file = function
  | Some outc -> List.iteri log_columns
    ~f:(fun idx x -> Out_channel.output_string outc x;
      match not @@ phys_equal idx (List.length log_columns - 1) with
      | true -> Out_channel.output_string outc "  "
      | false -> Out_channel.newline outc
    );
  | None -> ()

let get_max_muf maxbuf = function
  | BBA_0 algo -> int_of_float algo.BBA_0.maxb
  | BBA_1 algo -> int_of_float algo.BBA_1.maxb
  | BBA_2 algo -> int_of_float algo.BBA_1.maxb
  | ARBITER algo -> int_of_float algo.ARBITER.maxb
  | _ -> maxbuf

let run_client
    ~link
    ~adapt_alg
    ~initb
    ~maxbuf
    ~persist
    ~turnlogon
    ~logname
    ~v_number
    ~r_number
    ~log_folder
    ~last_segment_index
    ~segm_size_from_file =
  try_with (fun () ->
      check_input_algorithm_existence adapt_alg;
      Sys.command @@ "mkdir -p " ^ log_folder >>= fun _ ->
      let outc = create_log_channel logname log_folder ("-V" ^ v_number) ("-R" ^ r_number) turnlogon in
      open_connection link persist >>= fun conn ->
      Client.get ?conn:conn (Uri.of_string link) >>= fun (resp, body) ->
      body |> Cohttp_async.Body.to_string >>= fun body ->
      let representations : (int, representation) Hashtbl.t = Xml.parse_string body |> repr_table_from_mpd in
      let root_link, segmlist_mpd = String.rsplit2_exn link ~on:'/' in
      let root_link = root_link ^ "/" in
      chunk_sizes adapt_alg segm_size_from_file link representations last_segment_index root_link segmlist_mpd conn
      >>= fun (chunk_sizes_per_repr, average_chunk_size_per_repr) ->
      new_adapt_method chunk_sizes_per_repr average_chunk_size_per_repr adapt_alg >>= fun adapt_method ->
      print_log_header_on_screen;
      print_log_header_into_file outc;
      let maxbuf = get_max_muf maxbuf adapt_method in
      playback
        ?conn:conn
        ?outc:outc
        ~root_link:root_link
        ~representations:representations
        ~results:[]
        ~absolute_start_time:(Time.now ())
        ~buffer_size:0.
        ~segment_number:1
        ~initb:(float_of_int initb)
        ~maxbuf:(float_of_int maxbuf)
        ~adapt_method:adapt_method
        ~last_segment_index:last_segment_index
        ~segment_duration:(Hashtbl.find_exn representations 1).segment_duration
      >>= fun () ->
      match outc with
      | Some outc -> Out_channel.close outc; Deferred.unit
      | None ->  Deferred.unit
  )
  >>| function
  | Ok () -> ()
  | Error e -> begin
    match (String.is_substring (Exn.to_string e) "connection attempt timeout") with
      | true -> print_endline @@ "Connection attempt timeout (10 sec default) to " ^ link
      | false -> print_endline @@ Exn.to_string e
    end

let play =
  Command.async
    ~summary:"Dash simulation client"
    ~readme:(fun () -> "Usage example: ./dashc.native play http://10.0.0.1/bbb.mpd \
                        [-adapt conv] [-initb 2] [-maxbuf 60] [-persist true] \
                        [-turnlogon true] [-logname now] [-v 20] [-subfolder qwe]")
    (
      let open Command.Let_syntax in
      [%map_open
        let link = anon ("link_to_mpd" %: string)
        and adapt_alg = flag "-adapt" (optional_with_default "conv" string)
          ~doc:" adaptation algorithm [conv; bba-0; bba-1; bba-2; arbiter]"
        and initb = flag "-initb" (optional_with_default 2 int)
          ~doc:" initial buffer in segments"
        and maxbuf = flag "-maxbuf" (optional_with_default 60 int)
          ~doc:" maximum buffer size"
        and persist = flag "-persist" (optional_with_default true bool)
          ~doc:" persistent connection"
        and turnlogon = flag "-turnlogon" (optional_with_default true bool)
          ~doc:" turn on logging to file"
        and logname = flag "-logname" (optional_with_default "now" string)
          ~doc:" name of the log file (\"now\" means usage of the current time stamp \
                and it is used by default)"
        and v_number = flag "-v" (optional_with_default "99" string)
          ~doc:" video number according to StreamTraceAnalysis.py"
        and r_number = flag "-r" (optional_with_default "0" string)
          ~doc:" the run (R) number for the trace file"
        and subfolder = flag "-subfolder" (optional_with_default "" string)
          ~doc:" subfolder for the file"
        and last_segment_index = flag "-lastsegmindex" (optional_with_default 150 int)
          ~doc:" last segment index for play"
        and gensegmfile = flag "-gensegmfile" (optional_with_default false bool)
          ~doc:" generate segmentlist_%mpd_name%.txt file only (it will be rewritten if exists)"
        and segm_size_from_file = flag "-segmentlist" (optional_with_default "head" string)
          ~doc:" get segment sizes from \n \
                local - local segmentlist_%mpd_name%.txt file \n \
                remote - download remote segmentlist_%mpd_name%.txt file from the same folder where mpd is located \n \
                head - get segment size by sending head requests before playing for each segment per representation \
                usage of head requests works only with non-persistent connection so far and it it set by default (for this operation)"
        in
        fun () -> match gensegmfile with
        | true -> make_segment_size_file ~link:link ~persist:false ~last_segment_index:last_segment_index
        | false -> run_client
            ~link:link
            ~adapt_alg:adapt_alg
            ~initb:initb
            ~maxbuf:maxbuf
            ~persist:persist
            ~turnlogon:turnlogon
            ~logname:logname
            ~v_number:v_number
            ~r_number:r_number
            ~log_folder:subfolder
            ~last_segment_index:last_segment_index
            ~segm_size_from_file:segm_size_from_file
      ]
    )