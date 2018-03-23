Known issues
--------------------
* full_by_range, main_byte_range, onDemand_byte_range profiles (created by GPAC) are not supported
* Parsing of MPD won't be successfull if the representation qualities will be mixed
* Currently last segment index by default is 150, however it should be read from MPD file
  For example, mediaPresentationDuration="PT0H9M56.458S" means 9 minutes, 56.458 seconds


Changelog

0.1.* (*)
--------------------
* Cohttp master 2018.03.23, version 1.1.0 is used now instead of the master 2018.01.07, version 1.0.2
* Add specific versions core.v0.10.0 and async.v0.10.0 in configure (temporarily)

0.1.18 (2018.03.02)
--------------------
* Update to OCaml 4.06.1 from 4.06.0
* Initial test was added (alcotest package is used)

0.1.17 (2018.01.07)
--------------------
* Necessary changes were applied for compatibility with core/async v0.10.0
  (v0.10.0 has support of glibc-2.26 which is used in Ubuntu 17.10)
* Cohttp master 2018.01.07, version 1.0.2 is used now instead of the master 2017.11.21, version 1.0.0

0.1.16 (2017.11.23)
--------------------
* now representations hash table is created according to the number of representations in the MPD file
* Added support of variable number of AdaptationSet tags in an MPD file
  (GPAC 0.7.2 creates several of them in comparison with GPAC 0.5.2 based on aspect ratio of video)

0.1.15 (2017.11.21)
--------------------
* Update cohttp from 0.99 to 1.0.0 (to be precise to the commit from 2017.11.21)
* Update to OCaml 4.06.0 from 4.05.0

0.1.14 (2017.11.20)
--------------------
* Fix in BBA-2: prev_time_for_delivery previously was calculated by dividing int by int (us / 1_000_000), what gave incorrect result (it was technically correct, but precision of 1 second is useless). Previously the previous representation level would be determined incorrectly based on an approximate representation rate. This changed was applied in BBA-1 (in calculate_reservoir as well), BBA-2, ARBITER
* full, live, main profiles (created by GPAC) are supported. They were supported before, but checked only now

0.1.13 (2017.09.29)
--------------------
* Fixes in ARBITER, Conventional algorithms and in print_result related to possible overflow of int in 32 bit OS.
It happens for sure in Raspberry Pi 3 in 32 bit OS. The 64 bit float will help to avoid it.

0.1.12 (2017.09.27)
--------------------
* Support of SegmentList type of MPD was added

0.1.11 (2017.09.26)
--------------------
* Fixes in throughput mean and throughput variance calculation in ARBITER:
previously results starting from the beginning were used for calculations instead of the most recent one

0.1.10 (2017.09.25)
--------------------
* Fix in BBA-1 (BBA-2 uses BBA-1 code) in selection of the next requested representation,
previously the representation level could've been changed only by one level up/down

0.1.9 (2017.08.24)
--------------------
* Added flag to change an implementation of conventional algorithm to an alternative one
* Port to Jbuilder

0.1.8 (2017.08.14)
--------------------
* Conventional algorithm coefficients were changed from 0.2 to 0.4 and from 0.8 to 0.6

0.1.7 (2017.07.25)
--------------------
* Update to OCaml 4.05.0 from 4.02.2 (4.02.2 was set by mistake instead of 4.04.2 in 0.1.5)

0.1.6 (2017.07.25)
--------------------
* Update to cohttp/cohttp-async 0.99

0.1.5 (2017.07.16)
--------------------
* default OCaml version is set back to 4.04.2
conduit and cohttp depend on ppx_deriving, ppx_deriving 4.1 has
Available	ocaml-version >= "4.02.1" & ocaml-version < "4.05" & opam-version >= "1.2"

0.1.4 (2017.07.15)
--------------------
* default OCaml version is set to 4.05.0
* change back to opam-based core library (in 0.9.3 there was an important for Raspberry Pi build fix)
https://github.com/janestreet/base/issues/15

0.1.3 (2017.06.07)
--------------------
* new repository from janestreet, mentioned in 0.1.2, was not added actually,
and it is not now, because these libraries were recently updated in opam, so, no need
* ocaml-cohttp folder added to .gitignore

0.1.2 (2017.05.03)
--------------------
* Update to the new janestreet repository:
opam repo add janestreet-dev https://ocaml.janestreet.com/opam-repository

0.1.1 (2017.04.26)
--------------------
* ARBITER now has 60 seconds maxbuf instead of taking it from command line parameters
* ARBITER was added somewhen in January 2017 (right after 0.1.0)

0.1.0 (2016.12.30)
--------------------
* Initial release
* implemented algorithms: Conventional (Probe and Adapt: Rate Adaptation for HTTP Video Streaming At Scale, https://arxiv.org/abs/1305.0510), bba-0, bba-1, bba-2 (A Buffer-Based Approach to Rate Adaptation: Evidence from a Large Video Streaming Service, http://yuba.stanford.edu/~nickm/papers/sigcomm2014-video.pdf)