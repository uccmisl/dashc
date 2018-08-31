# Topologies from the paper

The original files (topologies) used for getting the results has been lost, however, these files are close approximations restored from the backup.

Most of the tests were made during the summer 2017, the code of the dashc was slightly different in comparison to the current one in the repository. The tapas_impl variable should be set to true (in the adapt_algo.ml file), if TAPAS version of the conventional algorithm is required.

## The 1st test, scalability

Files: scalability_tests.py.

To be able to measure CPU load and RAM usage /usr/bin/time application was used. It was run as “/usr/bin/time -f \"%U %S %e %M\" -o results.txt -a” and then video client with necessary parameters. The CPU load was calculated as (%U + %S) / %e, where %U is a total number of CPU-seconds that the process used directly (in a user mode), in seconds; %S is a total number of CPU-seconds used by the system on behalf of the process (in a kernel mode), in seconds; %e is an elapsed real (wall clock) time used by the process, in seconds. %M is maximum resident set size of the process during its lifetime.

## The 2nd one, QoE

Files: qoe-master.py, qoe-top.py.