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

let measure = 1000
let measure_float = 1000.
let us = 1000
let us_float = 1000.

type segm_result = {
  segment_number : int;
  (* arrival_time is absolute time since the request of MPD or
     request of the first segment, ms *)
  arrival_time : int;
  (* time_for_delivey is request_time - response_time,
     us, because in a local network it can be less than 1 ms
     which results in 0 during conversion to int *)
  time_for_delivery : int;
  (* stall_dur is a time which was spent with buffer equal to 0
     (during waiting of the next segment), ms *)
  stall_dur : int;
  (* representation_rate is a bandwidth of this segment according to an MPD file in bits/s *)
  representation_rate : int;
  (* actual_representation_rate is equal to (segment_size / segment_duration) in K(something)bits/s *)
  actual_representation_rate : int;
  (* segment_size, bytes *)
  segment_size : int;
  (* buffer_level_in_momentum, seconds *)
  buffer_level_in_momentum : float;
  (* representation level *)
  repr_level : int;
}

let rec print_int_zeros ~number ~zeroes_number ~zero =
  let digits_number = (String.length @@ Int.to_string number) in
  if digits_number = zeroes_number then print_int number
  else if zero then begin
    print_int 0;
    print_int_zeros ~zero:zero ~number:number ~zeroes_number:(zeroes_number - 1)
  end
  else begin
    print_string " ";
    print_int_zeros ~zero:zero ~number:number ~zeroes_number:(zeroes_number - 1)
  end

let print_result result_ = function
  | None ->
    print_int_zeros ~number:result_.segment_number ~zeroes_number:5 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:(result_.arrival_time / us) ~zeroes_number:8 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:(result_.time_for_delivery / us) ~zeroes_number:8 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:result_.stall_dur ~zeroes_number:9 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:(result_.representation_rate / measure) ~zeroes_number:9 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:(int_of_float (((float_of_int result_.segment_size *. 8. *. measure_float) /. float_of_int result_.time_for_delivery) *. us_float /. measure_float)) ~zeroes_number:8 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:(result_.actual_representation_rate / measure)  ~zeroes_number:8 ~zero:false;
    print_string "  ";
    print_int_zeros ~number:(result_.segment_size) ~zeroes_number:9 ~zero:false;
    print_string "  ";
    printf "%10.3f" result_.buffer_level_in_momentum;
    print_endline ""
  | Some outc ->
    Out_channel.output_string outc @@ Printf.sprintf "%5d" result_.segment_number ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%8d" (result_.arrival_time / us) ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%8d" (result_.time_for_delivery / us) ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%9d" result_.stall_dur ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%9d" (result_.representation_rate / measure) ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%8d" (int_of_float (((float_of_int result_.segment_size *. 8. *. measure_float) /. float_of_int result_.time_for_delivery) *. us_float /. measure_float)) ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%8d" (result_.actual_representation_rate / measure) ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%9d" result_.segment_size ^ "  ";
    Out_channel.output_string outc @@ Printf.sprintf "%10.3f" result_.buffer_level_in_momentum ^ "  ";
    Out_channel.newline outc;
    Out_channel.flush outc
