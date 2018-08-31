#!/usr/bin/python
from mininet.net import Mininet
from mininet.node import Controller,OVSKernelSwitch
from mininet.link import TCLink
from mininet.cli import CLI
import time
import os

def topology():

    "Create a network."
    net = Mininet( controller=Controller, link=TCLink, switch=OVSKernelSwitch )
    
    print "*** Creating nodes"

    h1 = net.addHost( 'h1', mac='00:00:00:00:00:01', ip='10.0.0.1/8' )

    c1 = net.addController( 'c1', controller=Controller, ip='127.0.0.1' )
    s1 = net.addSwitch( 's1' )

    number_of_hosts = 50
    hosts = range(number_of_hosts)
    for i in range(number_of_hosts):
        host = 'host' + str(i).zfill(3)
        # hex is wrong here, [:-2] part
        hosts[i] = net.addHost(host, mac='00:00:00:00:00:' + hex(i)[:-2], ip='10.0.0.' + str(i + 2) + '/8')

    print "*** Associating and Creating links"
    link_main = net.addLink(s1, h1, bw=100)
    host_links = []
    for i in range(number_of_hosts):
        host_links.append(net.addLink(s1, hosts[i], bw=3))
    
    print "*** Starting network"
    net.build()
    c1.start()
    s1.start( [c1] )

    h1.cmdPrint('./caddy -host 10.0.0.1 -port 8080 -root ~/Downloads &')

    os.system('sleep 3')
    
    subfolder = "results"
    for i in range(number_of_hosts):
        #hosts[i].cmdPrint('cd ~/Downloads/tapas-master; /usr/bin/time -o results.txt -a python play.py -a conventional -m fake -u http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash_old.mpd &')
        #hosts[i].cmdPrint('cd ~/Downloads/tapas-master; /usr/bin/time -f \"%U %S %e %M\" -o results.txt -a python play.py -a conventional -m fake -u http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash_old.mpd &')
        #hosts[i].cmdPrint('/usr/bin/time -o results.txt -a ./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt conv -initb 2 -maxbuf 60 -persist true -lastsegmindex 75 -logname sta1 -v 20 -turnlogon false &')
        #hosts[i].cmdPrint('/usr/bin/time -f \"%U %S %e %M\" -o results.txt -a ./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt conv -initb 2 -maxbuf 60 -persist true -lastsegmindex 75 -logname sta' + str(i).zfill(3) + ' -v 20 -turnlogon true -subfolder ' + subfolder + ' &')
        #hosts[i].cmdPrint('./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt arbiter -initb 2 -maxbuf 60 -persist true -segmentlist remote -lastsegmindex 75 -logname sta' + str(i).zfill(3) + ' -v 20 -turnlogon true -subfolder ' + subfolder + ' &')
        #hosts[i].cmdPrint('cd ~/Downloads/tapas-master; python play.py -a conventional -m fake -u http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash_old.mpd &')
        #hosts[i].cmdPrint('./dashc.native http://10.0.0.1:8080/bbb/bbb_enc_10min_x264_dash.mpd -adapt conv -initb 2 -maxbuf 60 -persist true -lastsegmindex 75 -logname sta1 -v 20 -turnlogon true &')
        pass

    bw = 3
    #for i in range(21):
    for i in range(16):
        print(str(i))
        os.system('sleep 20')
        if bw == 3:
            print('set bw to 1 mbps')
            for link in host_links:
                link.intf1.config( bw=1 )
            bw = 1
        else:
            print('set bw to 3 mbps')
            for link in host_links:
                link.intf1.config( bw=3 )
            bw = 3

    print "*** Stopping network"
    net.stop()

if __name__ == '__main__':
    topology()
