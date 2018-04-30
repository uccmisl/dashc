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

let mpd_file_name_1 = "../../../test_mpd/bbb_enc_10min_x264_dash.mpd"
let mpd_file_segment_duration_1 = 4
let mpdf_file_link_1 = "https://127.0.0.1/bbb_enc_10min_x264_dash.mpd"

let parse_mpd file_name =
  let body = In_channel.read_all mpd_file_name_1 in
  let mpd = Xml.parse_string body in
  let representations : (int, representation) Hashtbl.t = repr_table_from_mpd mpd in
  representations

let input_algorithm () =
  Alcotest.check Alcotest.unit
    "BBA-2 is supported" () (check_input_algorithm_existence "bba-2")

let mpd_parsing_bandwidth () =
  let representations = parse_mpd mpd_file_name_1 in
  Alcotest.check Alcotest.int "The bandwidth value in the given mpd file is"
  4275756
  (Hashtbl.find_exn representations 10).bandwidth

let mpd_parsing_repr_number () =
  let representations = parse_mpd mpd_file_name_1 in
  Alcotest.check Alcotest.int "The number of representations in the given mpd file is"
  10
  (Hashtbl.length representations)

let test_get_last_segment_index () =
  let body = In_channel.read_all mpd_file_name_1 in
  let mpd = Xml.parse_string body in
  let last_segment_index =
    get_last_segment_index mpd mpd_file_segment_duration_1 None in
  Alcotest.check Alcotest.int "The last segment index is"
  150
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
      "mpd bandwidth parsing", `Quick, mpd_parsing_bandwidth;
      "mpd number of representations parsing", `Quick, mpd_parsing_repr_number;
      "get_last_segment_index fun", `Quick, test_get_last_segment_index;
      "read_segment_size_file fun", `Slow, test_read_segment_size_file;
    ];
  ]