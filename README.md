# centreon reporting rrd

The script report_rrd.pl generates a specific ascii report about a host group + specific service (and metric) during a specified time range. <br>
The output report shows the average value (or percentile) and is based from data of the RRD files generated by Centreon (the script must be running on the machine hosting the RRD files).

  - INPUT : text file with hostnames or name of the hostgroup + name of the focus service + (start & end date)
  - OUTPUT : ascii report with average value


## Requirements

  - Perl
  - mysql client
  - rrdtool

## Tested with

  - Centreon 2.5.4
  - perl 5.10.1
  - rrdtool 1.4.7

## Options
option --hostfile or --hostgroup, and --service are compulsory, others are optional. <br>
option --timerange allows to calculate average values during several hours, for example during Working Hours. <br>
If no options --start or --end, the last mounth is used as the default time range.

```erb
./reporting_rrd.pl --hostgroup <host_group_name> (if option --hostfile not used)
                   --hostfile <myhosts.txt> (text file with one hostname by line)
                   --service <name_of_the_service>
                   [--metric <name_of_the_metric>]
                   [--start <DD-MM-YYYY>]
                   [--end <DD-MM-YYYY>]
                   [--timerange <regex with date format> (date format: Fri Nov 28 14:15:33 2014)]
                   [--sort ascending|descending]
                   [--top N]
                   [--csv <chr>] (for csv output)
                   [--percentile XX]
```
## Performance

For 231 devices + one selected service + one metric + time range of one month: <br>
real    0m9.179s <br>
user    0m1.099s <br>
sys     0m1.183s <br>

For 1000 devices + one selected service + one metric + time range of one month: <br>
real    1m8.093s <br> ==> 6 or 7 secondes since the version 23
user    0m7.454s <br>
sys     0m10.865s <br>

## Examples 

```erb
reporting_rrd.pl --hostfile myhosts.txt --service CPU
--start 01-11-2014 --end 01-12-2014 --sort descending

myhosts.txt     service:CPU     from:01-11-2014 to 01-12-2014
+-----------------------+------------+---------------+-----------------+
| hostname              | service    | metric        | value (%)       |
+-----------------------+------------+---------------+-----------------+
| TOTO_host1            | CPU        | load_5_min    | 6.29            |
| TOTO_host1            | CPU        | load_1_min    | 6.14            |
| TOTO_host1            | CPU        | load_5_sec    | 6.09            |
| TOTO_host2            | CPU        | load_1_min    | 5.97            |
| TOTO_host2            | CPU        | load_5_min    | 5.97            |
| TOTO_host2            | CPU        | load_5_sec    | 5.82            |
| TOTO_host3            | CPU        | load_1_min    | 4.01            |
| TOTO_host3            | CPU        | load_5_min    | 4.01            |
| TOTO_host3            | CPU        | load_5_sec    | 4.00            |
| TOTO_host4            | CPU        | load_5_min    | 3.01            |
| TOTO_host4            | CPU        | load_1_min    | 3.01            |
| TOTO_host4            | CPU        | load_5_sec    | 3.01            |
+-----------------------+------------+---------------+-----------------+
```

```erb
reporting_rrd.pl --hostfile myhosts.txt --service CPU --metric load_5_min
--start 01-11-2014 --end 01-12-2014 --sort descending

myhosts.txt     service:CPU     from:01-11-2014 to 01-12-2014
+-----------------------+------------+---------------+-----------------+
| hostname              | service    | metric        | value (%)       |
+-----------------------+------------+---------------+-----------------+
| TOTO_host1            | CPU        | load_5_min    | 6.29            |
| TOTO_host2            | CPU        | load_5_min    | 5.97            |
| TOTO_host3            | CPU        | load_5_min    | 4.01            |
| TOTO_host4            | CPU        | load_5_min    | 3.01            |
+-----------------------+------------+---------------+-----------------+
```

```erb
reporting_rrd.pl --hostfile myhostnames.txt --service Traffic% --metric traffic_out
--start 01-11-2014 --end 10-11-2014 --sort descending --percentile 95
           
myhostnames.txt     service:Traffic%        From:01-11-2014 to 10-11-2014
+----------+-----------------------------------+-------------+----------------+
| hostname | service                           | metric      | value (Bits/s) |
+----------+-----------------------------------+-------------+----------------+
| HOST1    | Traffic Gi0/0/0 - Tronc COMMUN    | traffic_out | 201363140.88   |
| HOST1    | Traffic Te0/1/0 - vers HOST2 eth3 | traffic_out | 29108307.05    |
| HOST1    | Traffic Te0/1/0.17 - vers HOST3   | traffic_out | 24642008.87    |
| HOST1    | Traffic Gi0/0/1 - Tronc ADSL      | traffic_out | 7147156.44     |
| HOST1    | Traffic Te0/1/0.10 - vers HOST4   | traffic_out | 5215652.37     |
| HOST1    | Traffic Te0/1/0.9 - vers HOST5    | traffic_out | 1490047.99     |
| HOST1    | Traffic Gi0/0/5 - vers TRONC FT56 | traffic_out | 1457569.49     |
+----------+-----------------------------------+-------------+----------------+
```
Example with --timerange (target : only the working hours) :

```erb
reporting_rrd.pl --hostfile TOTO.txt --service "Traffic Te0/3/0 - vers WORLD"
--start 01-11-2014 --end 01-12-2014
--timerange "^(Mon|Tue|Wed|Thu|Fri) ... .. (08|09|10|11|12|13|14|15|16|17|18):..:.. 2014$"

TOTO.txt     service:Traffic Te0/3/0 - vers WORLD  From:01-11-2014 to 01-12-2014
+-----------------+------------------------------+-------------+----------------+
| hostname        | service                      | metric      | value (Bits/s) |
+-----------------+------------------------------+-------------+----------------+
| TOTO1           | Traffic Te0/3/0 - vers WORLD | traffic_in  | 106005763.81   |
| TOTO2           | Traffic Te0/3/0 - vers WORLD | traffic_in  | 38992621.03    |
| TOTO1           | Traffic Te0/3/0 - vers WORLD | traffic_out | 28826598.06    |
| TOTO2           | Traffic Te0/3/0 - vers WORLD | traffic_out | 85628434.92    |
+-----------------+------------------------------+-------------+----------------+

