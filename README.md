# dashc, client emulator for DASH video streaming

## Description

dashc is an emulator of the video player, it is intended to be used as a test tool. The original goal was to have a lightweight test tool for network performance experiments with a real DASH video streaming traffic.

dashc has several options which can be changed through the command line arguments:
* video adaptation algorithm (Conventional, BBA-0/BBA-1/BBA-2, ARBITER)
* initial buffer size (in segments)
* last segment index for play
* log file and folder name (the log file can be on/off)
* maximum buffer size (in seconds)
* persistent connection (on/off)
* generation of the meta information for BBA-2 and ARBITER (file with segment sizes)

## Installation


dashc was tested in Ubuntu 16.04/16.10/17.04/17.10 with x64 architecture and in Ubuntu 16.04.3 with ARM architecture (Raspberry Pi 2/3)

To install (./configure will ask for a sudo password to install opam package manager):
```
./configure
make
```

To run tests (not necessary):
```
make test
```

## Usage

dashc can be run as simple as:
```
./dashc.exe play http://10.0.0.1/bbb.mpd
```

or:
```
./dashc.exe play http://10.0.0.1/bbb.mpd [-adapt conv] [-initb 2] [-maxbuf 60] [-persist true] [-turnlogon true] [-logname now] [-subfolder qwe]
```
Where all flags except the link to the MPD file are optional. Possible flags are:
* [-adapt], adaptation algorithm (conv; bba-0; bba-1; bba-2; arbiter)
* [-initb], initial buffer (in segments)
* [-lastsegmindex], last segment index for play
* [-logname], name of the log file ("now" means usage of the current time stamp and it is used by default)
* [-maxbuf], maximum buffer size (in seconds)
* [-persist], persistent connection (true/false)
* [-segmentlist], this parameter is used to tell where to get meta data infromation (segment sizes, for example, for BBA-2 and ARBITER). Possible options are head (dashc will send head requests before starting to stream), local (file with segment size should be at the same folder with dashc), remote (file with segment size should be at the same location where target MPD file is stored) get segment sizes from  local - local segmentlist_%mpd_name%.txt file. The default option is head.
* [-subfolder], subfolder for the file
* [-turnlogon], turn on logging to file
* [-gensegmfile], generate segmentlist_%mpd_name%.txt file only (it will be rewritten if exists)
* [-help],  print this help text and exit, (alias: -?)


The detailed help can be found by running it with the -help flag:
```
./dashc.exe play -help
```

The typical log file will look like the example below (here the data only for the first 30 segments is shown, ARBITER adaptation algorithm is used):
```
Seg_#  Arr_time  Del_Time  Stall_Dur  Rep_Level  Del_Rate  Act_Rate  Byte_Size  Buff_Level
    1       810       810          0        232      1225       248     124131       4.000  
    2      1554       744          0        232      1487       276     138452       8.000  
    3      2283       728          0        232      1496       272     136272      11.272  
    4      3696      1413          0        374      1591       562     281170      13.858  
    5      4273       576          0        752      1884       271     135890      17.282  
    6      5571      1298          0        752      1963       637     318725      19.983  
    7     10756      5184          0       1060      1322      1713     856959      18.799  
    8     15020      4263          0        752       823       877     438974      18.535  
    9     16572      1551          0        560      1350       523     261860      20.983  
   10     17832      1260          0        560      1212       381     190970      23.723  
   11     19904      2072          0        752      1117       578     289478      25.651  
   12     22951      3046          0        752      1032       786     393344      26.605  
   13     26412      3461          0        752      1019       882     441029      27.143  
   14     28438      2026          0        752      1536       778     389046      29.117  
   15     29046       607          0        752      1732       263     131513      32.510  
   16     29996       949          0        752      2105       499     249943      35.560  
   17     32062      2066          0       1060      2034      1050     525440      37.494  
   18     34956      2893          0       1060      1111       803     401864      38.601  
   19     39174      4218          0       1060      1232      1299     649641      38.382  
   20     44807      5631          0       1060      1560      2196    1098391      36.750  
   21     46942      2134          0       1060      1357       723     361990      38.616  
   22     48440      1498          0       1060      1071       401     200595      41.118  
   23     51428      2987          0       1060      1055       788     394241      42.130  
   24     53142      1713          0       1060      1036       443     221995      44.416  
   25     55589      2446          0       1060      1185       724     362490      45.970  
   26     57293      1704          0        752      1590       677     338960      48.265  
   27     59909      2615          0        752      1200       784     392369      49.649  
   28     63206      3297          0       1060      1254      1034     517165      50.352  
   29     66206      2999          0       1060      1740      1305     652588      51.353  
   30     70260      4053          0       1060      1822      1847     923626      51.299  
```
# Support

If you have an issue, please create a new one in github with necessary information (type of MPD file, OS version and etc.).

# Citation

Aleksandr Reviakin, Ahmed H. Zahran, Cormac J. Sreenan. dashc : a highly scalable client emulator for DASH video. The paper was submitted in March 2018 in MMSys 2018 Open Dataset & Software Track, this information will be updated if it will be accepted.

# Licence

This software has emanated from research conducted with the financial support of Science Foundation Ireland (SFI) under Grant Number 13/IA/1892.

University College Cork

GPL-2 License