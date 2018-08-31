#!/usr/bin/python
from mininet.net import Mininet
from mininet.node import Controller,OVSKernelSwitch
from mininet.link import TCLink
from mininet.cli import CLI

import time
import os
import sys
import math

def roundup(x):
    return int(math.ceil(x / 100.0)) * 100

def topology():
    if len(sys.argv) != 6:
        print('Usage: qoe-top.py number_of_clients rate_limit delay alg r_number')
        exit()
    number_of_clients = int(sys.argv[1])
    rate_limit = float(sys.argv[2])
    delay = int(sys.argv[3])
    alg = sys.argv[4]
    r_number = sys.argv[5]
    total_rate_limit = number_of_clients * rate_limit

    number_of_hosts = number_of_clients
    subfolder = 'results' + r_number + '/dashc_' + alg +  '_' + str(number_of_hosts).zfill(3) + '_' + str(rate_limit) + 'Mbps_' + str(delay).zfill(3) + 'ms'
    #subfolder = 'results' + r_number
    if (os.path.isdir(subfolder)):
        exit()

    print "Create a network."
    net = Mininet( controller=Controller, link=TCLink, switch=OVSKernelSwitch )
    
    print "*** Creating nodes"

    h1 = net.addHost( 'h1', mac='00:00:00:00:00:01', ip='10.0.0.1/8' )

    c1 = net.addController( 'c1', controller=Controller, ip='127.0.0.1' )
    s1 = net.addSwitch( 's1' )

    number_of_hosts = number_of_clients
    hosts = range(number_of_hosts)
    for i in range(number_of_hosts):
        host = 'host' + str(i).zfill(3)
        # hex is wrong here, [:-2] part
        hosts[i] = net.addHost(host, mac='00:00:00:00:00:' + hex(i)[:-2], ip='10.0.0.' + str(i + 2) + '/8')

    print "*** Associating and Creating links"
    queue_size = (total_rate_limit * delay * 1000) / (1500 * 8)
    queue_size = roundup(queue_size)
    link_main = net.addLink(s1, h1, bw=total_rate_limit, delay=(str(delay) + 'ms'), max_queue_size=queue_size)
    #link_main = net.addLink(s1, h1, bw=total_rate_limit, delay=(str(delay) + 'ms'))
    host_links = []
    for i in range(number_of_hosts):
        host_links.append(net.addLink(s1, hosts[i], bw=100))
    
    print "*** Starting network"
    net.build()
    c1.start()
    s1.start( [c1] )

    h1.cmdPrint('./caddy -host 10.0.0.1 -port 8080 -root ~/Downloads &')
    #h1.cmdPrint('iperf -s &')

    os.system('sleep 3')

    #alg = 'iperf'
    
    #subfolder = "results/dashc_bba-2_4_3Mbps_250ms"
    subfolder = 'results' + r_number + '/dashc_' + alg +  '_' + str(number_of_hosts).zfill(3) + '_' + str(rate_limit) + 'Mbps_' + str(delay).zfill(3) + 'ms'
    #subfolder = 'results' + r_number
    os.system('mkdir -p ' + subfolder)
    for i in range(number_of_hosts):
        #hosts[i].cmdPrint('cd ~/Downloads/tapas-master; /usr/bin/time -o results.txt -a python play.py -a conventional -m fake -u http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash_old.mpd &')
        #hosts[i].cmdPrint('cd ~/Downloads/tapas-master; /usr/bin/time -f \"%U %S %e %M\" -o results.txt -a python play.py -a conventional -m fake -u http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash_old.mpd &')
        #hosts[i].cmdPrint('/usr/bin/time -o results.txt -a ./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt conv -initb 2 -maxbuf 60 -persist true -lastsegmindex 75 -logname sta1 -v 20 -turnlogon false &')
        #hosts[i].cmdPrint('/usr/bin/time -f \"%U %S %e %M\" -o results.txt -a ./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt conv -initb 2 -maxbuf 60 -persist true -lastsegmindex 75 -logname sta' + str(i).zfill(3) + ' -v 20 -turnlogon true -subfolder ' + subfolder + ' &')
        
        #hosts[i].cmdPrint('iperf -c 10.0.0.1 -t 300 | tee -a ' + subfolder + '/results' + str(number_of_clients).zfill(3) + '.txt &')
        #hosts[i].cmdPrint('iperf -c 10.0.0.1 -t 300 | tee -a ' + subfolder + '/' + alg +  '_' + str(number_of_hosts).zfill(3) + '_' + str(rate_limit) + 'Mbps_' + str(delay).zfill(3) + 'ms' + '.txt &')
        hosts[i].cmdPrint('./dashc.native play http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt ' + alg + ' -initb 2 -maxbuf 60 -persist true -segmentlist remote -lastsegmindex 75 -logname sta' + str(i).zfill(3) + ' -v 20 -r ' + r_number + ' -turnlogon true -subfolder ' + subfolder + ' &')
        
        #hosts[i].cmdPrint('cd ~/Downloads/tapas-master; python play.py -a conventional -m fake -u http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash_old.mpd &')
        #hosts[i].cmdPrint('./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt conv -initb 2 -maxbuf 60 -persist true -lastsegmindex 75 -logname sta1 -v 20 -turnlogon true &')

    print "*** Sleep for 400 seconds (300 video + 100 for everything else)"
    os.system('sleep 400')

    print "*** Stopping network"
    net.stop()

if __name__ == '__main__':
    topology()

