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

open Representation
open Segm_result

(* Probe and Adapt: Rate Adaptation for HTTP Video Streaming At Scale:
   https://arxiv.org/abs/1305.0510 *)
module Conv : sig
  val next_representation_level :
    representations:(int, representation) Hashtbl.t ->
    results:segm_result List.t ->
    int
end = struct

  let moving_average = ref 0.
  (* The main difference in TAPAS tool implementation
     is conversion of the target rate to representation level,
     it also has buffer size of 60 seconds and
     only the first segment is downloaded in the lowest quality.
     This flag affects only conversion implementation.
     The code of the TAPAS tool
     could've been found here (https://github.com/ldecicco/tapas) during 08.2017.
     The default value is taps_impl=false, it was added for tests only. *)
  let tapas_impl = false

  let next_representation_level ~representations ~results =
    if List.length results < 2 then 1
    else
      let conv_weight = 0.85 in
      let last_result = List.hd_exn results in
      let throughput =
        ((float_of_int last_result.segment_size) *. 8. *. us_float *. us_float) /.
          float_of_int (last_result.time_for_delivery) in
      moving_average :=
        if List.length results = 3 then throughput
        else throughput *. 0.4 +. !moving_average *. 0.6;
      if tapas_impl then
        let level = last_result.repr_level in
        let r_up = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
          if (data.bandwidth < int_of_float (conv_weight *. !moving_average) &&
              data.bandwidth > (Hashtbl.find_exn representations acc).bandwidth) then
              key else acc) in
        let r_down = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
          if (data.bandwidth < int_of_float !moving_average &&
              data.bandwidth > (Hashtbl.find_exn representations acc).bandwidth) then
              key else acc) in
        let new_level =
          if level < r_up then r_up
          else if r_up <= level && level <= r_down then level
          else r_down
        in
        new_level
      else
        let next_repr = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
            if (data.bandwidth < int_of_float (conv_weight *. !moving_average) &&
                data.bandwidth > (Hashtbl.find_exn representations acc).bandwidth) then
                key else acc) in
        next_repr
end

(* A Buffer-Based Approach to Rate Adaptation:
   Evidence from a Large Video Streaming Service
   http://yuba.stanford.edu/~nickm/papers/sigcomm2014-video.pdf
   https://yuba.stanford.edu/~nickm/papers/ty-thesis.pdf *)
module BBA_0 = struct
  type t = { maxb : float }
  (*let create maxb = { maxb }*)
  let next_representation_level ~algo ~representations ~results =
    let buf_now =
      if (List.length results) = 0 then 0.
      else (List.hd_exn results).buffer_level_in_momentum in
    let rate_prev =
      if (List.length results) = 0 then (Hashtbl.find_exn representations 1).bandwidth
      else
        (List.hd_exn results).representation_rate
    in
    let repr_prev = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
        if data.bandwidth = rate_prev then key
        else acc
      ) in

    let reservoir = 90. in
    let cushion = 126. in
    let maxbuf = algo.maxb in
    (* rate_prev is used for ~init below only as a start value,
       there is no meaning in this particular value, but it cannot be less
       than the lowest rate among representations *)
    let rate_min = Hashtbl.fold representations ~init:rate_prev ~f:(fun ~key ~data acc ->
        if data.bandwidth < acc then data.bandwidth else acc) in
    let rate_max = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
        if data.bandwidth > acc then data.bandwidth else acc) in
    let f buf =
      let slope = (float_of_int (rate_max -rate_min)) /.
                  (0.9 *. maxbuf -. reservoir) in
      let target_rate = slope *. (buf_now -. reservoir) in
      int_of_float target_rate
    in
    let f_buf = f buf_now in
    let rate_plus =
      if rate_prev = rate_max then rate_max
      else (Hashtbl.find_exn representations (repr_prev + 1)).bandwidth in
    let rate_minus =
      if rate_prev = rate_min then rate_min
      else (Hashtbl.find_exn representations (repr_prev - 1)).bandwidth in
    let rate_next =
      if buf_now <= reservoir then rate_min
      else if buf_now >= (reservoir +. cushion) then rate_max
      else if f_buf >= rate_plus then
        Hashtbl.fold representations ~init:rate_min ~f:(fun ~key ~data acc ->
          if data.bandwidth > acc &&
             data.bandwidth < f_buf then data.bandwidth
          else acc)
      else if f_buf <= rate_minus then
        Hashtbl.fold representations ~init:rate_max ~f:(fun ~key ~data acc ->
          if data.bandwidth < acc &&
             data.bandwidth > f_buf then data.bandwidth
          else acc)
      else rate_prev in
    let repr_next = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
        if data.bandwidth = rate_next then key else acc) in
    repr_next
end

(* See papers from BBA_0 *)
module BBA_1 = struct
  type t = {
    maxb : float;
    chunk_sizes_per_repr : (int, int List.t) Hashtbl.t;
    average_chunk_size_per_repr : int List.t;
  }

  let calculate_reservoir
      ?(debug=false) ~algo ~representations ~results last_segment_index =
    let segment_duration = ((Hashtbl.find_exn representations 1).segment_duration) in
    let number_of_downloaded_segments = List.length results in
    let last_window_segment =
      if ((int_of_float algo.maxb) * 2) / segment_duration <
          last_segment_index - number_of_downloaded_segments then
        number_of_downloaded_segments + (int_of_float algo.maxb) * 2 / segment_duration
      else
        last_segment_index
    in

    let rate_prev =
      if (List.length results) = 0 then (Hashtbl.find_exn representations 1).bandwidth
      else
      (* when the representation rate is saved in a trace file,
         some level of precision will be lost,
         because original value of bit/s will be saved in kbit/s int type value,
         for example, 232385 will be saved as 232, and when it is read in debug mode
         it will look like 232000, so the repr_prev will be chosen based on a wrong value.
         To fix it this value 232000 (for example) will be converted into the closest
         within 5% the representation rate from the representations hash table *)
      if debug then Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
        if (float_of_int data.bandwidth *. 0.95) <
            float_of_int (List.hd_exn results).representation_rate &&
           (float_of_int data.bandwidth *. 1.05) >
            float_of_int (List.hd_exn results).representation_rate
           then data.bandwidth
        else acc
      )
      else (List.hd_exn results).representation_rate
    in
    let rate_min = Hashtbl.fold representations ~init:rate_prev ~f:(fun ~key ~data acc ->
        if data.bandwidth < acc then data.bandwidth else acc) in
    let average_chunk_size_per_min_rate = rate_min * segment_duration / 8 in

    let rec look_ahead_for_chunk_sizes
        ~curr_index (large_chunks_size, small_chunks_size) =
      (* check of equality to last_window_segment is made
         because List.nth_exn counts starting from 0 *)
      if curr_index = last_window_segment then (large_chunks_size, small_chunks_size)
      else
        (* curr_index because nth_exn starts to count from 0 *)
        let segm_size =
          List.nth_exn (Hashtbl.find_exn algo.chunk_sizes_per_repr 1) curr_index in
        (* equal chunk_sizes are included to small category *)
        if average_chunk_size_per_min_rate < segm_size then
          look_ahead_for_chunk_sizes
            ~curr_index:(curr_index + 1)
            (large_chunks_size + segm_size, small_chunks_size)
        else
          look_ahead_for_chunk_sizes
            ~curr_index:(curr_index + 1)
            (large_chunks_size, small_chunks_size + segm_size)
    in
    let large_chunks_size, small_chunks_size =
      look_ahead_for_chunk_sizes ~curr_index:number_of_downloaded_segments (0, 0) in
    (* reservoir in seconds *)
    let reservoir = (large_chunks_size - small_chunks_size) / (rate_min / 8) in
    let () =
      if debug then begin
        print_endline @@ "large_chunks_size: " ^ string_of_int large_chunks_size;
        print_endline @@ "small_chunks_size: " ^ string_of_int small_chunks_size;
        print_endline @@ "reservoir: " ^ string_of_int reservoir;
      end
    in
    (* from paper: we bound the reservoir size to be between 8 and 140 seconds.
       here the bound is between 2 segments and 35 segments *)
    let reservoir_checked =
      if reservoir < segment_duration * 2 then segment_duration * 2
      else if reservoir > segment_duration * 35 then segment_duration * 35
      else reservoir
    in
    reservoir_checked

(* the main difference from BBA_0 is usage of chunk map instead of rate map
   and dynamic reservoir *)
  let next_representation_level
      ?(debug=false) ~algo ~representations ~results last_segment_index =
    let buf_now =
      if (List.length results) = 0 then 0.
      else (List.hd_exn results).buffer_level_in_momentum in
    (* segm_number_next is next, if we agree that segment number begins from 0 *)
    let segm_number_next = List.length results in

    let rate_prev =
      if (List.length results) = 0 then (Hashtbl.find_exn representations 1).bandwidth
      else
        (* when the representation rate is saved in a trace file,
           some level of precision will be lost,
           because original value of bit/s will be saved in kbit/s int type value,
           for example, 232385 will be saved as 232, and when it is read in debug mode
           it will look like 232000,
           so the repr_prev will be chosen based on a wrong value.
           To fix it this value 232000 (for example) will be converted into the closest
           within 5% the representation rate from the representations hash table *)
        if debug then Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
          if (float_of_int data.bandwidth *. 0.95) <
              float_of_int (List.hd_exn results).representation_rate &&
             (float_of_int data.bandwidth *. 1.05) >
              float_of_int (List.hd_exn results).representation_rate
             then data.bandwidth
          else acc
        )
        else (List.hd_exn results).representation_rate
    in

    let repr_prev = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
        if data.bandwidth = rate_prev then key
        else acc
      ) in
    let () =
      if debug then begin
        print_endline @@ "rate_prev (BBA-1): " ^ string_of_int rate_prev;
        print_endline @@ "repr_prev (BBA-1): " ^ string_of_int repr_prev;
      end
    in

    let chunk_size_prev =
      if (List.length results) = 0 then
        List.nth_exn (Hashtbl.find_exn algo.chunk_sizes_per_repr 1) 0
      else
        List.nth_exn
          (Hashtbl.find_exn algo.chunk_sizes_per_repr repr_prev) (segm_number_next - 1)
    in

    (* update reservoir on each iteration *)
    let reservoir =
      float_of_int
      (calculate_reservoir
        ~debug:debug ~algo:algo ~representations ~results last_segment_index) in
    let maxbuf = algo.maxb in

    (* rate_prev is used for ~init below only as a start value,
       there is no meaning in this particular value, but it cannot be less
       than the lowest rate among representations *)
    let rate_min = Hashtbl.fold representations ~init:rate_prev ~f:(fun ~key ~data acc ->
        if data.bandwidth < acc then data.bandwidth else acc) in
    let rate_max = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
        if data.bandwidth > acc then data.bandwidth else acc) in

    let chunk_size_min = List.hd_exn algo.average_chunk_size_per_repr in
    let chunk_size_max = List.last_exn algo.average_chunk_size_per_repr in

    let rec get_chunk_sizes_per_segm_number ~curr_index ~chunk_sizes =
      if curr_index > (Hashtbl.length representations) then
        List.rev chunk_sizes
      else
        let chunk_size =
          List.nth_exn
            (Hashtbl.find_exn algo.chunk_sizes_per_repr curr_index)
            segm_number_next in
        get_chunk_sizes_per_segm_number
          ~curr_index:(curr_index + 1)
          ~chunk_sizes:(chunk_size :: chunk_sizes)
    in
    (* chunk_sizes_per_segm_number is a list of chunk sizes
       with the index as a representation number *)
    let chunk_sizes_per_segm_number =
      get_chunk_sizes_per_segm_number ~curr_index:1 ~chunk_sizes:[] in

    let f buf =
      let slope = (float_of_int (chunk_size_max - chunk_size_min)) /.
                  (0.9 *. maxbuf -. reservoir) in
      let target_chunk_size = slope *. (buf_now -. reservoir) in
      int_of_float target_chunk_size
    in
    let chunk_size_opt = f buf_now in
    let () =
      if debug then begin
        print_endline @@ "chunk_size_opt (BBA-1): " ^ string_of_int chunk_size_opt;
      end
    in
    let chunk_size_opt_discrete =
      List.fold
        chunk_sizes_per_segm_number
        ~init:(List.nth_exn chunk_sizes_per_segm_number 0) ~f:(fun acc x ->
      let () =
        if debug then begin
          print_endline @@ "List.fold chunk_sizes_per_segm_number: " ^ string_of_int x;
        end
      in
      if (x > acc) && (x < chunk_size_opt) then x
      else acc
    ) in
    let () =
      if debug then begin
        print_endline @@
          "chunk_size_opt_discrete (BBA-1): " ^ string_of_int chunk_size_opt_discrete;
      end
    in

    (* next highest chunk size for the next segment *)
    let (chunk_size_plus, repr_plus) =
      if rate_prev = rate_max then
          List.nth_exn
            (Hashtbl.find_exn algo.chunk_sizes_per_repr repr_prev)
            segm_number_next, repr_prev
      else
        List.nth_exn
          (Hashtbl.find_exn algo.chunk_sizes_per_repr (repr_prev + 1))
          segm_number_next, repr_prev + 1
    in
    let chunk_size_minus, repr_minus =
      if rate_prev = rate_min then
        List.nth_exn
          (Hashtbl.find_exn algo.chunk_sizes_per_repr 1) segm_number_next, repr_prev
      else
        List.nth_exn
          (Hashtbl.find_exn algo.chunk_sizes_per_repr (repr_prev - 1))
          segm_number_next, repr_prev - 1
    in

    (* from ty-thesis, page 68: the algorithm stays at the
       current video rate as long as the chunk size suggested by the map
       does not pass the size of
       the next upcoming chunk at the next highest available video rate (Rate + )
       or the next lowest
       available video rate (Rate ). *)
    (* the returned repr_next here begins from 0,
       but it should from 1, so it is increased later *)
    let chunk_size_next, repr_next =
      (* the old version
      if chunk_size_opt > chunk_size_plus then chunk_size_plus,repr_plus
      else if chunk_size_opt < chunk_size_minus then chunk_size_minus, repr_minus*)
      if chunk_size_opt_discrete >= chunk_size_plus then
        List.foldi
          chunk_sizes_per_segm_number ~init:(chunk_size_plus, 0) ~f:(fun idx acc x ->
            let chunk_size_curr, idx_curr = acc in
            if (x >= chunk_size_curr) && (x <= chunk_size_opt_discrete) then (x, idx)
            else acc
          )
      else if chunk_size_opt_discrete <= chunk_size_minus then
        List.foldi
          chunk_sizes_per_segm_number ~init:(chunk_size_plus, 0) ~f:(fun idx acc x ->
            let chunk_size_curr, idx_curr = acc in
            if (x <= chunk_size_curr) && (x <= chunk_size_opt_discrete) then (x, idx)
            else acc
          )
      else chunk_size_prev, repr_prev - 1
    in
    (* repr_next *)
    repr_next + 1

end

(* see papers from BBA_1 *)
(* From sigcomm2014-video.pdf about BBA-2.
Based on the preceding observation, BBA-2 works as fol-
lows. At time t = 0, since the buffer is empty, BBA-2 only
picks the next highest video rate, if the ∆B increases by
more than 0.875V s. Since ∆B = V − ChunkSize/c[k],
∆B > 0.875V also means that the chunk is downloaded
eight times faster than it is played. As the buffer grows, we
use the accumulated buffer to absorb the chunk size variation
and we let BBA-2 increase the video rate faster. Whereas at
the start, BBA-2 only increases the video rate if the chunk
downloads eight times faster than it is played, by the time
it fills the cushion, BBA-2 is prepared to step up the video
rate if the chunk downloads twice as fast as it is played. The
threshold decreases linearly, from the first chunk until the
cushion is full. The blue line in Figure 16 shows BBA-2
ramping up faster. BBA-2 continues to use this startup al-
gorithm until (1) the buffer is decreasing, or (2) the chunk
map suggests a higher rate. Afterwards, we use the f (B)
defined in the BBA-1 algorithm to pick a rate.
*)
module BBA_2 = struct
  type t = BBA_1.t

(* The termination of the startup phase will happen in case of
   1) the buffer is decreasing or 2) the chunk map suggests a higher rate.
   After that even if cushion is not full,
   the algorithms will be in steady-state all the time.*)
  let startup_phase = ref true

  let next_representation_level
      ?(debug=false) ~algo ~representations ~results last_segment_index =
    let open BBA_1 in
    let repr_next_bba_1 =
      BBA_1.next_representation_level
        ~debug:debug
        ~algo:algo
        ~representations:representations
        ~results:results
        last_segment_index in
    if List.length results = 0 then
      repr_next_bba_1
    else
      let buf_now =
        (* this condition was already checked above,
           but it will be checked again just in case this code maybe copy-pasted *)
        if (List.length results) = 0 then 0.
        else (List.hd_exn results).buffer_level_in_momentum
      in
      let segment_duration = ((Hashtbl.find_exn representations 1).segment_duration) in
      (* time_for_delivery is stored in us *)
      let prev_time_for_delivery =
        float_of_int (List.hd_exn results).time_for_delivery /. (us_float *. us_float) in
      (* positive delta_b means the buffer is increasing *)
      let delta_b = float_of_int segment_duration -. prev_time_for_delivery in
      let () =
        if debug then begin
          print_endline @@
            "prev_time_for_delivery = " ^ string_of_float @@
            float_of_int (List.hd_exn results).time_for_delivery /.
              (us_float *. us_float);
          print_endline @@ "delta_b = " ^ string_of_float delta_b;
        end
      in
      (* BBA-2 continues to use this startup algorithm until
         (1) the buffer is decreasing, or (2) the chunk map suggests a higher rate.
         If any of these conditions is false then switch to the steady-state forever. *)
      if delta_b >= 0. && !startup_phase then
        (* According to the BBA-2 paper,
           the bitrate increases only
           if the chunk is downloaded 8x (0.875 coefficient) faster than segment duration
           and this condition linearly decreases to 2x (0.5 coefficient)
           by the time cushion is full from the time when the first chunk was downloaded,
           so the coefficient can be calculated as a function of bitrate level.*)
        let f buf =
          let slope =
            (0.5 -. 0.875) /. (0.9 *. algo.maxb -. float_of_int segment_duration) in
          let target_coefficient = 0.875 +. slope *. buf in
          let () =
            if debug then begin
              print_endline @@
                "target_coefficient = " ^ string_of_float target_coefficient;
            end
          in
          target_coefficient
        in
        (* target coefficient depends on the current buffer level *)
        let target_coefficient = f buf_now in
        let rate_prev =
          if (List.length results) = 0 then (Hashtbl.find_exn representations 1).bandwidth
          else
          (* when the representation rate is saved in a trace file,
             some level of precision will be lost,
             because original value of bit/s will be saved in kbit/s int type value,
             for example, 232385 will be saved as 232, and when it is read in debug mode
             it will look like 232000,
             so the repr_prev will be chosen based on a wrong value.
             To fix it this value 232000 (for example) will be converted into the closest
             within 5% the representation rate from the representations hash table *)
          if debug then Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
            if (float_of_int data.bandwidth *. 0.95) <
                float_of_int (List.hd_exn results).representation_rate &&
               (float_of_int data.bandwidth *. 1.05) >
                float_of_int (List.hd_exn results).representation_rate
               then data.bandwidth
            else acc
          )
          else (List.hd_exn results).representation_rate
        in
        let repr_prev = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
            if data.bandwidth = rate_prev then key
            else acc
          ) in
        let () =
          if debug then begin
            print_endline @@ "rate_prev (BBA-2): " ^ string_of_int rate_prev;
            print_endline @@ "repr_prev (BBA-2): " ^ string_of_int repr_prev;
          end
        in
        let rate_max = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
            if data.bandwidth > acc then data.bandwidth else acc) in
        let repr_plus =
          if rate_prev = rate_max then repr_prev
          else repr_prev + 1
        in
        (* suggessted repr depends on how fast the buffer is growing *)
        let suggested_repr =
          let () =
            if debug then begin
              print_endline @@
                "target_coefficient *. (float_of_int segment_duration) = " ^
                string_of_float @@ target_coefficient *. (float_of_int segment_duration);
            end
          in
          if delta_b > target_coefficient *. (float_of_int segment_duration) then
            let () =
              if debug then begin
                print_endline @@
                  "repr increase based on delta_b > target_coefficient *. \
                  (float_of_int segment_duration)";
              end
            in
            repr_plus
          else
            repr_prev
        in
        if repr_next_bba_1 <= suggested_repr then
          let () =
            if debug then begin
              print_endline @@ "suggested_repr (BBA-2): " ^ string_of_int suggested_repr;
            end
          in
          suggested_repr
        else begin
          let () =
            if debug then begin
              print_endline @@
                "repr_next_bba_1 (just switched to BBA-1): " ^
                string_of_int repr_next_bba_1;
            end
          in
          startup_phase := false;
          repr_next_bba_1
        end
      else begin
        let () =
          if debug then begin
            print_endline @@ "repr_next_bba_1: " ^ string_of_int repr_next_bba_1;
          end
        in
        startup_phase := false;
        repr_next_bba_1
      end

end

(* ARBITER: Adaptive rate-based intelligent HTTP streaming algorithm
   http://ieeexplore.ieee.org/abstract/document/7574709/ *)
module ARBITER : sig
  type t = {
    maxb : float;
    chunk_sizes_per_repr : (int, int List.t) Hashtbl.t;
  }

  val next_representation_level :
    ?debug:bool ->
    algo:t ->
    representations:(int, representation) Hashtbl.t ->
    results:segm_result List.t ->
    int ->
    int
end = struct
  type t = {
    maxb : float;
    chunk_sizes_per_repr : (int, int List.t) Hashtbl.t;
  }

  let next_representation_level
      ?(debug=false) ~algo ~representations ~results last_segment_index =
    if List.length results < 2 then 1
    else
      let total_number_of_downloaded_segments = List.length results in
      (* estimation_window is static parameter according to the paper *)
      let estimation_window = 10 in
      let window_size =
        if estimation_window < total_number_of_downloaded_segments then estimation_window
        else total_number_of_downloaded_segments
      in
      let segm_number_prev = total_number_of_downloaded_segments - 1 in
      (* exponential_weight is static parameter according to the paper *)
      let exponential_weight = 0.4 in
      let rec calculate_weights ~curr_index ~acc_weights =
        if curr_index >= window_size then
          List.rev acc_weights
        else
          let numerator =
            exponential_weight *. (1. -. exponential_weight) ** float_of_int curr_index in
          let denominator =
            1. -. (1. -. exponential_weight) ** float_of_int estimation_window in
          let () =
            if debug then begin
              print_endline @@ "numerator: " ^ string_of_float numerator;
              print_endline @@ "denominator = " ^ string_of_float denominator;
            end
          in
          calculate_weights
            ~curr_index:(curr_index + 1)
            ~acc_weights:(numerator /. denominator :: acc_weights)
      in
      let weights = calculate_weights ~curr_index:0 ~acc_weights:[] in
      let rec calculate_weighted_throughput_mean ~curr_index ~acc =
        if curr_index >= window_size then
          acc
        else
          let result_ = List.nth_exn results curr_index in
          let measured_throughput =
            ((float_of_int result_.segment_size) *. 8. *. us_float *. us_float) /.
              float_of_int (result_.time_for_delivery) in
          let product = (List.nth_exn weights curr_index) *. measured_throughput in
          let () =
            if debug then begin
              print_endline @@ "segm_number_prev: " ^ string_of_int segm_number_prev;
              print_endline @@ "curr_index: " ^ string_of_int curr_index;
              print_endline @@
                "result_.segment_number: " ^ string_of_int result_.segment_number;
              print_endline @@
                "(List.nth_exn weights curr_index): " ^
                string_of_float (List.nth_exn weights curr_index);
              print_endline @@
                "measured_throughput = " ^ string_of_float measured_throughput;
            end
          in
          calculate_weighted_throughput_mean
            ~curr_index:(curr_index + 1)
            ~acc:(acc +. product)
      in
      let weighted_throughput_mean =
        calculate_weighted_throughput_mean ~curr_index:0 ~acc:0. in

      let rec calculate_throughput_variance ~curr_index ~acc =
        if curr_index >= window_size then
          float_of_int estimation_window *. acc /. (float_of_int estimation_window -. 1.)
        else
          let result_ = List.nth_exn results curr_index in
          let measured_throughput =
            ((float_of_int result_.segment_size) *. 8. *. us_float *. us_float) /.
              float_of_int (result_.time_for_delivery) in
          let () =
            if debug then begin
              print_endline @@
                "(result_.segment_size * 8 * us * us): " ^
                string_of_int (result_.segment_size * 8 * us * us);
              print_endline @@
                "result_.segment_size = " ^ string_of_int result_.segment_size;
              print_endline @@
                "result_.time_for_delivery = " ^ string_of_int result_.time_for_delivery;
              print_endline @@
                "measured_throughput = " ^ string_of_float measured_throughput;
            end
          in
          let next_sum =
            (List.nth_exn weights curr_index) *. ((measured_throughput -.
              weighted_throughput_mean) ** 2.) in
          calculate_throughput_variance
            ~curr_index:(curr_index + 1) ~acc:(acc +. next_sum)
      in
      let throughput_variance = calculate_throughput_variance ~curr_index:0 ~acc:0. in
      let variation_coefficient_theta =
        (sqrt throughput_variance) /.weighted_throughput_mean in
      (* bw_safety_factor is static parameter according to the paper *)
      let bw_safety_factor = 0.3 in
      let throughput_variance_scaling_factor =
        bw_safety_factor +.
        (1. -. bw_safety_factor) *. ((1. -. (min variation_coefficient_theta 1.)) ** 2.)
        in

      let buf_now =
        if (List.length results) = 0 then 0.
        else (List.hd_exn results).buffer_level_in_momentum
      in
      (* lower_buffer_bound,
         upper_buffer_bound are static parameters according to the paper *)
      let lower_buffer_bound, upper_buffer_bound = 0.5, 1.5 in
      let buffer_based_scaling_factor =
        lower_buffer_bound +.
        (upper_buffer_bound -. lower_buffer_bound) *. (buf_now /. algo.maxb) in

      let adaptive_throughput_estimate =
        weighted_throughput_mean *.
        throughput_variance_scaling_factor *.
        buffer_based_scaling_factor in
      let () =
        if debug then begin
          print_endline @@
            "weighted_throughput_mean (the same unit as Del_Rate) = " ^ string_of_int @@
            int_of_float @@ weighted_throughput_mean /. 1000.;
          print_endline @@
            "throughput_variance_scaling_factor = " ^
            string_of_float throughput_variance_scaling_factor;
          print_endline @@
            "buffer_based_scaling_factor = " ^
            string_of_float buffer_based_scaling_factor;
          print_endline @@
            "adaptive_throughput_estimate (the same unit as Del_Rate) = " ^
            string_of_int @@ int_of_float @@ adaptive_throughput_estimate /. 1000.;
        end
      in

      let rate_prev =
        (* this should never happen *)
        if (List.length results) = 0 then (Hashtbl.find_exn representations 1).bandwidth
        else
        (* when the representation rate is saved in a trace file,
           some level of precision will be lost,
           because original value of bit/s will be saved in kbit/s int type value,
           for example, 232385 will be saved as 232, and when it is read in debug mode
           it will look like 232000,
           so the repr_prev will be chosen based on a wrong value.
           To fix it this value 232000 (for example) will be converted into the closest
           within 5% the representation rate from the representations hash table *)
        if debug then Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
          if (float_of_int data.bandwidth *. 0.95) <
              float_of_int (List.hd_exn results).representation_rate &&
             (float_of_int data.bandwidth *. 1.05) >
              float_of_int (List.hd_exn results).representation_rate
             then data.bandwidth
          else acc
        )
        else (List.hd_exn results).representation_rate
      in
      let () =
        if debug then begin
          print_endline @@ "rate_prev = " ^ string_of_int rate_prev;
        end
      in
      let repr_prev = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
          if data.bandwidth = rate_prev then key
          else acc
        ) in
      let () =
        if debug then begin
          print_endline @@ "repr_prev = " ^ string_of_int repr_prev;
        end
      in
      let rate_min = (Hashtbl.find_exn representations 1).bandwidth in
      let () =
        if debug then begin
          print_endline @@ "rate_min = " ^ string_of_int rate_min;
        end
      in
      let s_rate = Hashtbl.fold representations ~init:rate_min ~f:(fun ~key ~data acc ->
          let () =
            if debug then begin
              print_endline @@ "data.bandwidth = " ^ string_of_int data.bandwidth;
            end
          in
          if data.bandwidth > acc &&
            data.bandwidth < int_of_float adaptive_throughput_estimate then
              data.bandwidth
          else
            acc) in
      let s_repr = Hashtbl.fold representations ~init:1 ~f:(fun ~key ~data acc ->
          if data.bandwidth = s_rate then key else acc) in
      let () =
        if debug then begin
          print_endline @@ "s_rate = " ^ string_of_int s_rate;
          print_endline @@ "s_repr = " ^ string_of_int s_repr;
        end
      in

      (* up_switch_limit is static parameter according to the paper *)
      let up_switch_limit = 2 in
      let next_repr =
        if (s_repr - repr_prev) > up_switch_limit then
          repr_prev + up_switch_limit
        else
          s_repr
      in
      (* look_ahead_window is static parameter according to the paper *)
      let look_ahead_window =
        if (last_segment_index - total_number_of_downloaded_segments) < 5 then
          (last_segment_index - total_number_of_downloaded_segments)
        else
          5
      in
      let segment_duration = ((Hashtbl.find_exn representations 1).segment_duration) in
      let rec calculate_actual_rate ~next_repr_candidate ~curr_index ~acc =
        if curr_index > look_ahead_window then
          acc * 8 / (look_ahead_window * segment_duration)
        else
          let next_segment_size =
            List.nth_exn
              (Hashtbl.find_exn algo.chunk_sizes_per_repr next_repr_candidate)
              (segm_number_prev + curr_index) in
          calculate_actual_rate
            ~next_repr_candidate:next_repr_candidate
            ~curr_index:(curr_index + 1)
            ~acc:(acc + next_segment_size)
      in
      let rec highest_possible_actual_rate ~next_repr_candidate =
        let actual_rate =
          calculate_actual_rate
            ~next_repr_candidate:next_repr_candidate
            ~curr_index:1 ~acc:0 in
        let () =
          if debug then begin
            print_endline @@ "actual_rate = " ^ string_of_int actual_rate;
          end
        in
        if next_repr_candidate > 1 &&
          not (actual_rate <= int_of_float adaptive_throughput_estimate) then
          highest_possible_actual_rate ~next_repr_candidate:(next_repr_candidate - 1)
        else
          next_repr_candidate
      in
      let actual_next_rate =
        highest_possible_actual_rate ~next_repr_candidate:next_repr in
      actual_next_rate
end

type alg =
  | Conv
  | BBA_0 of BBA_0.t
  | BBA_1 of BBA_1.t
  | BBA_2 of BBA_1.t
  | ARBITER of ARBITER.t
