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
open Playback
open Representation

let mpd_file_name_1 = "bbb_enc_10min_x264_dash.mpd"
let mpd_file_segment_duration_1 = 4
let mpdf_file_link_1 = "https://127.0.0.1/bbb_enc_10min_x264_dash.mpd"

let mpd_file_name_2 = "tearsofsteel_enc_x264_dash.mpd"
let mpd_file_segment_duration_2 = 6

let mpd_file_name_3 = "bbb_enc_10min_x264_dash_rev1.mpd"
let mpd_file_segment_duration_3 = 4
let mpd_file_name_4 = "bbb_enc_10min_x264_dash_rev2.mpd"
let mpd_file_segment_duration_4 = 4
let mpd_file_name_5 = "bbb_enc_10min_x264_dash_mixed.mpd"
let mpd_file_segment_duration_5 = 4

let input_algorithm () =
  Alcotest.check Alcotest.unit
    "BBA-2 is supported" () (check_input_algorithm_existence "bba-2")

let parse_mpd file_name =
  let body = In_channel.read_all file_name in
  let mpd = Xml.parse_string body in
  let representations : (int, representation) Hashtbl.t = repr_table_from_mpd mpd in
  representations

let mpd_parsing_bandwidth_1 () =
  let representations = parse_mpd mpd_file_name_1 in
  Alcotest.check Alcotest.int "The bandwidth value in the given mpd file is"
  4275756
  (Hashtbl.find_exn representations 10).bandwidth

let mpd_parsing_bandwidth_2 () =
  let representations = parse_mpd mpd_file_name_2 in
  Alcotest.check Alcotest.int "The bandwidth value in the given mpd file is"
  236378
  (Hashtbl.find_exn representations 1).bandwidth

let mpd_parsing_bandwidth_3 () =
  let representations = parse_mpd mpd_file_name_3 in
  Alcotest.check Alcotest.int "The bandwidth value in the given mpd file is"
  232385
  (Hashtbl.find_exn representations 1).bandwidth

let mpd_parsing_bandwidth_4 () =
  let representations = parse_mpd mpd_file_name_4 in
  Alcotest.check Alcotest.int "The bandwidth value in the given mpd file is"
  232385
  (Hashtbl.find_exn representations 1).bandwidth

let mpd_parsing_bandwidth_5 () =
  let representations = parse_mpd mpd_file_name_5 in
  Alcotest.check Alcotest.int "The bandwidth value in the given mpd file is"
  232385
  (Hashtbl.find_exn representations 1).bandwidth

let mpd_parsing_repr_number_1 () =
  let representations = parse_mpd mpd_file_name_1 in
  Alcotest.check Alcotest.int "The number of representations in the given mpd file is"
  10
  (Hashtbl.length representations)

let mpd_parsing_repr_number_2 () =
  let representations = parse_mpd mpd_file_name_2 in
  Alcotest.check Alcotest.int "The number of representations in the given mpd file is"
  13
  (Hashtbl.length representations)

let test_get_last_segment_index_1 () =
  let body = In_channel.read_all mpd_file_name_1 in
  let mpd = Xml.parse_string body in
  let last_segment_index =
    get_last_segment_index mpd mpd_file_segment_duration_1 None in
  Alcotest.check Alcotest.int "The last segment index is"
  150
  last_segment_index

let test_get_last_segment_index_2 () =
  let body = In_channel.read_all mpd_file_name_2 in
  let mpd = Xml.parse_string body in
  let last_segment_index =
    get_last_segment_index mpd mpd_file_segment_duration_2 None in
  Alcotest.check Alcotest.int "The last segment index is"
  123
  last_segment_index

let test_read_segment_size_file () =
  Thread_safe.block_on_async_exn(fun () ->
    let representations = parse_mpd mpd_file_name_1 in

    let body = In_channel.read_all mpd_file_name_1 in
    let mpd = Xml.parse_string body in
    let last_segment_index =
      get_last_segment_index mpd mpd_file_segment_duration_1 None in

    read_segment_size_file
            ?remote_string:None
            ~link:mpdf_file_link_1
            ~number_of_representations:(Hashtbl.length representations)
            ~last_segment_index:last_segment_index
    >>| fun chunk_sizes_per_repr ->
    Alcotest.check Alcotest.int
      "The number of representations in the given chunk size file is"
    10
    (Hashtbl.length chunk_sizes_per_repr)
  )

let () =
  Alcotest.run "tests" [
    "first", [
      "input algorithm availability", `Quick, input_algorithm;
      "bandwidth file 1", `Quick, mpd_parsing_bandwidth_1;
      "bandwidth file 2", `Quick, mpd_parsing_bandwidth_2;
      "bandwidth file 3", `Quick, mpd_parsing_bandwidth_3;
      "bandwidth file 4", `Quick, mpd_parsing_bandwidth_4;
      "bandwidth file 5", `Quick, mpd_parsing_bandwidth_5;
      "number of representations file 1", `Quick, mpd_parsing_repr_number_1;
      "number of representations file 2", `Quick, mpd_parsing_repr_number_2;
      "get_last_segment_index, file 1", `Quick, test_get_last_segment_index_1;
      "get_last_segment_index, file 2", `Quick, test_get_last_segment_index_2;
      "read_segment_size_file fun", `Slow, test_read_segment_size_file;
    ];
  ]