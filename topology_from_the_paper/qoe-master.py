import os
import sys
import subprocess

#delays = [10, 100, 250]
delays = [250]
#rate_limits = [0.375, 0.75, 1.5, 3.0, 4.5]
rate_limits = [4.5]
algs = ['arbiter']
#number_of_clients = [2, 4, 6, 8, 10, 20, 40, 80, 100]
number_of_clients = [100]
#number_of_clients_skip = [20, 40, 80, 100]
count = 1

for curr in range(count):
    for alg in algs:
        for client_number in number_of_clients:
            # make full 10 tests for clients not in number_of_clients_skip
            #if (curr > 2 and client_number in number_of_clients_skip):
            #    continue
            for rate_limit in rate_limits:
                for delay in delays:
                    run_top_script = 'sudo python qoe-top.py ' + str(client_number) + ' ' + str(rate_limit) + ' ' + str(delay) + ' ' + alg + ' ' + str(curr)
                    print(run_top_script)
                    subprocess.run(run_top_script.split(' '))