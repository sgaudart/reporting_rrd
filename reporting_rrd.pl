#!/usr/bin/perl
#======================================================================
# Auteur : sgaudart@capensis.fr
# Date   : 22/10/2014
# But    : This script can read the RRD file from Centreon, and calculate the average for
#          all the values. TimeRange could be possible (you can calculate average during Working Hours).
#          mysql client and rrdtool needed.
#
# INPUT : 
#          host group name or hosts file + specific service + [metric + start time & end time]
# OUTPUT :
#          average values report (ASCII)
#
#======================================================================
#   Date      Version    Auteur       Commentaires
# 22/10/2014  1          SGA          initial version
# 23/10/2014  3          SGA          function get_average_value created
# 30/10/2014  4          SGA          reading the host file and create the sql request
# 30/10/2014  5          SGA          reading the sql result and calculate the avg value
# 31/10/2014  6          SGA          fix a bug in the function get_average_value
# 31/10/2014  7          SGA          add sort for the output value + fix bug with the chr "," in xml values
# 03/11/2014  8          SGA          reading the conf centreon.conf.php
# 04/11/2014  9          SGA          add library Getopts::Long
# 06/11/2014 10          SGA          add options --start --end and --sort=(ascending|descending)
# 07/11/2014 11          SGA          format the output value with ShowValueWithColumn
# 07/11/2014 12          SGA          add option --top 
# 08/11/2014 13          SGA          modify input date format : DD-MM-YYYY
# 14/11/2014 14          SGA          add function ShowBorder + using @maxsizecolumn
# 14/11/2014 15          SGA          add function get_percentile_value
# 24/11/2014 16          SGA          add unit in the output report
# 28/11/2014 17          SGA          add option --timerange
# 24/12/2014 18          SGA          add option --csv
# 20/04/2015 19          SGA          get the name of the centreon_storage database
# 27/04/2015 20          SGA          change for the options --start --end optional
# 31/08/2015 21          SGA          add the option --hostgroup
# 05/01/2016 22          SGA          add function ChangeDateToUnixTime
#======================================================================

use strict;
use warnings;
use Getopt::Long;
use Time::Local;

my $hostfile=""; # option --hostfile
my $hostgroup=""; # option --hostgroup
my $servicefilter=""; # option --service
my $metricfilter=""; # option --metric
my $start=""; # option --start
my $end=""; # option --end
our $csv="";
our $start_epoch=0;
our $end_epoch=0;
our $timerange=".*"; # regex for workinghours (ex for workinghours "^(Mon|Tue|Wed|Thu|Fri) ... .. (08|09|10|11|12|13|14|15|16|17|18):..:.. 2015$")
our %UnixTimeBoolHash; # 0 => value needed, 1 => outside, not needed
our @maxsizecolumn=(10,9,8,7); # column size for : hostname, service, metric, value

my $sort="";
my $top=0;
my $percentile=0;
my $verbose;
my $help;


GetOptions (
"hostfile=s" => \$hostfile, # string
"hostgroup=s" => \$hostgroup, # string
"service=s" => \$servicefilter, # string
"metric=s" => \$metricfilter, # string
"start=s" => \$start, # integer
"end=s" => \$end, # string
"sort=s" => \$sort, # string
"top=i" => \$top, # integer
"timerange=s" => \$timerange, # string
"percentile=i" => \$percentile, # integer
"csv=s" => \$csv, # string
"verbose" => \$verbose, # flag
"help" => \$help) # flag
or die("Error in command line arguments\n");

my $line;
my $avg;
my $workdirectory="/tmp";
my $rrd_directory="/var/lib/centreon/metrics/"; # Directory with RRD files, PLEASE CHANGE IF NECESSARY
my $centreon_conf="/etc/centreon/centreon.conf.php"; 

my $hostCentstorage; # sql information 
my $user; # sql information 
my $password; # sql information 
my $dbcstg; # sql information 
my $db; # sql information
my $sqlprefix = "";

my $sqlline=0; # line counter
my ($hostname, $service, $metric, $unit, $metric_id); # for reading the sql result
my $value;
my %v; # hash table for values
my %h; # hash table for the hostname
my %s; # hash table for the service names
my %m; # hash table for the metrics names
my $key;

###############################
# HELP
###############################

if (($help) || ($servicefilter eq "") || (($hostfile eq "") && ($hostgroup eq "")))
{
	print"reporting_rrd.pl --hostgroup <host_group_name> (if option --hostfile not used)
                 [--hostfile <myhosts.txt> (text file with one hostname by line)]
                 --service <name_of_the_service>
                 [--metric <name_of_the_metric>]
                 [--start <date>] default : start & end date is the last month
                 [--end <date]    default : start & end date is the last month
                 [--timerange <regex with date format (date format: Fri Nov 28 14:15:33 2014)]
                 [--sort ascending|descending]
                 [--top N]
                 [--percentile XX]
                 [--csv <split chr>]
                 [--verbose]\n";
	exit;
}

###############################
# TRANSFORM DATE => unix time
###############################

if (($start eq "") || ($end eq ""))
{
	# default : start & end date is the last month
	my @now = localtime(time);
	my $end_month=$now[4]+1;
	my $year = $now[5]+1900;
	my $start_month = $end_month-1;
	my $start_year=$year;
 
	if ($now[4] eq 0)
	{
		print "DEBUG : EXCEPTION => January detected !!\n" if $verbose;
		$start_month=12;
		$start_year=$year-1;
	}
	
	if ($start_month < 10) { $start_month = "0" . $start_month; }
	if ($end_month < 10) { $end_month = "0" . $end_month; }
	
	$start = "01-". $start_month . "-" . $start_year;
	$end = "01-". $end_month . "-" . $year;
}

$start_epoch = ChangeDateToUnixTime($start);
print "DEBUG : start=$start => start_epoch=$start_epoch\n" if $verbose;

$end_epoch = ChangeDateToUnixTime($end);
print "DEBUG : end=$end => end_epoch=$end_epoch\n" if $verbose;

if ($start_epoch > $end_epoch)
{
	print "ERROR: start date > end date, please check your value...\n";
	exit;
}

###############################
# READING THE CENTREON CONF FILE
###############################

#$conf_centreon['hostCentstorage'] = "XX.YY.ZZ.XX";
#$conf_centreon['user'] = "centreon";
#$conf_centreon['password'] = "XXXXXXXXX";
#$conf_centreon['db'] = "centreon2";
#$conf_centreon['dbcstg'] = "centreon2_storage";
open (CENTREONFD, "$centreon_conf") or die "Can't open centreon conf  : $centreon_conf\n" ; # reading
while (<CENTREONFD>)
{
	$line=$_;
	chomp($line); # delete the carriage return
	if ($line =~ /^\$conf_centreon\['hostCentstorage'\] = "(.*)";$/) { $hostCentstorage = $1; }
	if ($line =~ /^\$conf_centreon\['user'\] = "(.*)";$/) { $user = $1; }
	if ($line =~ /^\$conf_centreon\['password'\] = "(.*)";$/) { $password = $1; }
	if ($line =~ /^\$conf_centreon\['db'\] = "(.*)";$/) { $db = $1; }
	if ($line =~ /^\$conf_centreon\['dbcstg'\] = "(.*)";$/) { $dbcstg = $1; }
}
close CENTREONFD;

###############################
# READING THE HOST FILE + PREPARING THE SQL QUERY
###############################

my $sqlhostlist = "("; # var usefull for the sql request
my $sqlrequest;

if ($hostgroup ne "")
{
	# we work with a host group
	$sqlrequest = "select host_name from hostgroup_relation, host,hostgroup where hostgroup.hg_name='$hostgroup' and hostgroup_relation.host_host_id=host.host_id and hostgroup.hg_id=hostgroup_relation.hostgroup_hg_id and host_activate='1'";
	$sqlprefix = "mysql --batch -h $hostCentstorage -u $user -p$password -D $db -e";
	print "DEBUG : sqlrequest = $sqlrequest\n" if $verbose;
	print "DEBUG : sql request processing ($user\@$hostCentstorage)..." if $verbose;
	system "$sqlprefix \"$sqlrequest;\" > $hostgroup";
	$hostfile=$hostgroup;
}

$sqlprefix = "mysql --batch -h $hostCentstorage -u $user -p$password -D $dbcstg -e";
open (HOSTFD, "$hostfile") or die "Can't open hostfile : $hostfile\n" ; # reading
while (<HOSTFD>)
{
	$line=$_;
	chomp($line); # delete the carriage return
	if ($line eq "host_name") { next; } # case for hostgroup
	$sqlhostlist = $sqlhostlist . "'$line', ";
}
close HOSTFD;
chop($sqlhostlist);
chop($sqlhostlist);
$sqlhostlist = $sqlhostlist . ")";

#SELECT host_name,service_description,metric_name,metric_id FROM index_data,metrics WHERE host_name IN ('host1', 'host2', 'host3', 'host4', 'host5')  and service_description like 'Traffic%' and index_data.id=metrics.index_id;
if ($metricfilter eq "")
{
	$sqlrequest = "SELECT host_name,service_description,metric_name,unit_name,metric_id FROM index_data,metrics WHERE host_name IN $sqlhostlist and service_description like '$servicefilter' and index_data.id=metrics.index_id";
}
else
{
	$sqlrequest = "SELECT host_name,service_description,metric_name,unit_name,metric_id FROM index_data,metrics WHERE host_name IN $sqlhostlist and service_description like '$servicefilter' and metric_name like '$metricfilter' and index_data.id=metrics.index_id";
}

###############################
# RUN THE SQL QUERY
###############################

print "DEBUG : sqlrequest = $sqlrequest\n" if $verbose;
print "sql request processing ($user\@$hostCentstorage)..." if $verbose;
system "$sqlprefix \"$sqlrequest;\" > sqlresult";
print "finished\n" if $verbose;

###############################
# READING THE SQL RESULT AND PROCESSING THE VALUES
###############################

open (SQLFD, "sqlresult") or die "Can't open sqlresult\n" ; # reading the metric id
while (<SQLFD>)
{
	$sqlline++; # line counter
	$line=$_;
	chomp($line); # delete the carriage return
	# HOST1   Traffic_GigabitEthernet1/0      traffic_in   Bits/s   10845
	($hostname, $service, $metric, $unit, $metric_id) = split('\t', $line);
	
	if ($sqlline eq 1) { next; } # next if the first line
	if (! -f "$rrd_directory/$metric_id.rrd") { next; } # no rrd file => next
	if ($sqlline eq 2)
	{
		$maxsizecolumn[3]=$maxsizecolumn[3]+length($unit)+3; # size of the value column with the (unit)
		&PopulateUnixTimeBoolHash($metric_id);
	}
	
	if ($percentile ne 0)
	{
		$value=&get_percentile_value($metric_id, $percentile); # percentile case
	}
	else
	{
		$value=&get_average_value($metric_id); # example => 42482
	}
	
	if ($value eq "nan")
	{
		next; # next if no value data
	} 
	else
	{
		$v{$metric_id}=$value;
	}
	if (length($v{$metric_id})+2 > $maxsizecolumn[3]) { $maxsizecolumn[3]=length($v{$metric_id})+2; }  # VALUE
	
	$h{$metric_id}=$hostname;
	if (length($h{$metric_id})+2 > $maxsizecolumn[0]) { $maxsizecolumn[0]=length($h{$metric_id})+2; } # HOSTNAME

	$s{$metric_id}=$service;
	if (length($s{$metric_id})+2 > $maxsizecolumn[1]) { $maxsizecolumn[1]=length($s{$metric_id})+2; } # SERVICE

	$m{$metric_id}=$metric;
	if (length($m{$metric_id})+2 > $maxsizecolumn[2]) { $maxsizecolumn[2]=length($m{$metric_id})+2; } # METRIC

}
close SQLFD;


###############################
# VIEW THE RESULT
###############################
my $j=0; # using for TOP

if ($csv eq "") { print "$hostfile\tservice:$servicefilter\tFrom:$start to $end\n"; ShowBorder(); }
ShowValueWithColumn ("hostname", $maxsizecolumn[0]);
ShowValueWithColumn ("service", $maxsizecolumn[1]);
ShowValueWithColumn ("metric", $maxsizecolumn[2]);
ShowValueWithColumn ("value ($unit)", $maxsizecolumn[3]);
if ($csv eq "")
{
	print "|\n"; ShowBorder();
}
else
{
	print "\n";
}

if ($sort eq "ascending")
{

	foreach $key (sort hashValueAscendingNum (keys(%v)))
	{
	   $j++;
	   ShowValueWithColumn ($h{$key}, $maxsizecolumn[0]);
	   ShowValueWithColumn ($s{$key}, $maxsizecolumn[1]);
	   ShowValueWithColumn ($m{$key}, $maxsizecolumn[2]);
	   ShowValueWithColumn ($v{$key}, $maxsizecolumn[3]);
	   if ($csv eq "") { print "|"; }
	   print "\n";
	   if (($j >= $top) && ($top ne 0)) { if ($csv eq "") { ShowBorder(); } exit; }
	}
}
elsif ($sort eq "descending")
{
	foreach $key (sort hashValueDescendingNum (keys(%v)))
	{
	   $j++;
	   ShowValueWithColumn ($h{$key}, $maxsizecolumn[0]);
	   ShowValueWithColumn ($s{$key}, $maxsizecolumn[1]);
	   ShowValueWithColumn ($m{$key}, $maxsizecolumn[2]);
	   ShowValueWithColumn ($v{$key}, $maxsizecolumn[3]);
	   if ($csv eq "") { print "|"; }
	   print "\n";
	   if (($j >= $top) && ($top ne 0)) { if ($csv eq "") { ShowBorder(); } exit; }
	}
}
else
{
	foreach $key (keys(%v))
	{
	   $j++;
	   ShowValueWithColumn ($h{$key}, $maxsizecolumn[0]);
	   ShowValueWithColumn ($s{$key}, $maxsizecolumn[1]);
	   ShowValueWithColumn ($m{$key}, $maxsizecolumn[2]);
	   ShowValueWithColumn ($v{$key}, $maxsizecolumn[3]);
	   if ($csv eq "") { print "|"; }
	   print "\n";
	   if (($j >= $top) && ($top ne 0)) { if ($csv eq "") { ShowBorder(); } exit; }
	}
}
if ($csv eq "") { ShowBorder(); }


#############  FONCTIONS  #################
sub get_average_value
{
	# 1 ARG : metric id
	my(@args) = @_;
	my $xmldata=0;
	my $rrdid = $args[0];
	my $avgvalue=0;
	my $result="nan";
	my $i=0; # counter = number of valid value in the RRD file
	
	system "cp $rrd_directory/$rrdid.rrd $workdirectory"; # copy rrd file
	system "rrdtool fetch /tmp/$rrdid.rrd AVERAGE -r 3600 -s $start_epoch -e $end_epoch > $workdirectory/$rrdid.xml"; # cleaning file
	#system "rrdtool fetch /tmp/$rrdid.rrd AVERAGE -s 1409522400 -e 1412114399 > $workdirectory/$rrdid.xml"; # cleaning file

	# READING THE XML FILE
	open (XMLFD, "$workdirectory/$rrdid.xml") or die "Can't open $workdirectory/$rrdid.xml\n" ; # reading
	while (<XMLFD>)
	{
		$line=$_;
		#chomp($line);
		
		# 1409526000: 5.7362002778e+04
		if ($line =~ /^(.*): (.*)$/)
		{
			if ($2 eq "nan") { next; }
			if ($UnixTimeBoolHash{$1}) { next; } # next if not the right timerange
			$i++;
			$xmldata=$2;
			#print "DEBUG : xmldata{$1}=$xmldata{$1} [$i]\n";
			$xmldata =~ s/,/\./; # substitution "," => "."
			$avgvalue = $xmldata + $avgvalue;
		}
	}
	close XMLFD;
	
	if ($i ne 0) 
	{
		$result = sprintf("%.2f", $avgvalue/$i); # average here with formatting number	
	}
	
	system "rm -f $workdirectory/$rrdid.xml $workdirectory/$rrdid.rrd"; # cleaning files
	return $result;
}


sub get_percentile_value
{
	# 1 ARG : metric id
	my(@args) = @_;
	my $xmldata=0;
	my @datatab=();
	my $rrdid = $args[0];
	my $percentile = $args[1];
	my $tabsize=0;
	my $result="nan";
	
	system "cp $rrd_directory/$rrdid.rrd $workdirectory"; # copy rrd file
	system "rrdtool fetch /tmp/$rrdid.rrd AVERAGE -r 3600 -s $start_epoch -e $end_epoch > $workdirectory/$rrdid.xml"; # cleaning file
	#system "rrdtool fetch /tmp/$rrdid.rrd AVERAGE -s $start_epoch -e $end_epoch > $workdirectory/$rrdid.xml"; # cleaning file

	# READING THE XML FILE
	open (XMLFD, "$workdirectory/$rrdid.xml") or die "Can't open $workdirectory/$rrdid.xml\n" ; # reading
	while (<XMLFD>)
	{
		$line=$_;
		chomp($line);
		
		# 1409526000: 5.7362002778e+04
		if ($line =~ /^(.*): (.*)$/)
		{
			if ($2 eq "nan") { next; }
			if ($UnixTimeBoolHash{$1}) { next; } # next if not the right timerange
			$xmldata=$2;
			$tabsize++;
			$xmldata =~ s/,/\./; # substitution "," => "."
			push @datatab,$xmldata;
		}
	}
	close XMLFD;
	
	system "rm -f $workdirectory/$rrdid.xml $workdirectory/$rrdid.rrd"; # cleaning files
	@datatab = sort { $a <=> $b } @datatab; # SORT HERE
	
	#for (my $i=0; $i < 360; $i++) { # DEBUG
	#print "datatab[$i] : $datatab[$i]\n"; # DEBUG
	#} # DEBUG
	
	$result = sprintf("%.2f", $datatab[($percentile/100)*$tabsize]);
	#my $index=($percentile/100)*$tabsize; # DEBUG
	#print "index datatab = $index / $tabsize\n" if $verbose; # DEBUG
	#print "value of index datatab = $datatab[$index]\n" if $verbose; # DEBUG

	return $result;
}

sub hashValueAscendingNum
{
   $v{$a} <=> $v{$b};
}

sub hashValueDescendingNum
{
   $v{$b} <=> $v{$a};
}

sub ShowValueWithColumn
{
	my $value = $_[0]; # 1 ARG : the value
	my $size = $_[1]; # 2 ARG : size of the column
	
	if ($csv eq "") # no csv
	{
		print "| $value";
		for (my $i = length($value); $i <= $size-2; $i++)
		{
			print " ";
		}
	}
	else # csv=yes
	{
		print "$value$csv";
	}
}

sub ShowBorder
{
	print "+";
	for (my $i=0; $i < $#maxsizecolumn+1; $i++)
	{
		for (my $j=1; $j <= $maxsizecolumn[$i]; $j++)
		{
			print "-";
		}
		print "+";
	}
	print "\n";
}

sub TimeRangeBoolean
{
	my $unix_timestamp = $_[0]; # 1 ARG : unixtime
	my $converted_timestamp = scalar localtime $unix_timestamp;

	if ($converted_timestamp =~ /$timerange/)
	{
			print "DEBUG : $unix_timestamp = $converted_timestamp => 0\n" if $verbose;
			return 0;
	}
	else
	{
			print "DEBUG : $unix_timestamp = $converted_timestamp => 1\n" if $verbose;
			return 1;
	}
}

sub PopulateUnixTimeBoolHash
{
	# 1 ARG : metric id
	my(@args) = @_;
	my $xmldata=0;
	my $boolean;
	my $rrdid = $args[0];
	
	system "cp $rrd_directory/$rrdid.rrd $workdirectory"; # copy rrd file
	system "rrdtool fetch /tmp/$rrdid.rrd AVERAGE -r 3600 -s $start_epoch -e $end_epoch > $workdirectory/$rrdid.xml"; # cleaning file
	#system "rrdtool fetch /tmp/$rrdid.rrd AVERAGE -s 1409522400 -e 1412114399 > $workdirectory/$rrdid.xml"; # cleaning file

	# READING THE XML FILE
	open (XMLFD, "$workdirectory/$rrdid.xml") or die "Can't open $workdirectory/$rrdid.xml\n" ; # reading
	while (<XMLFD>)
	{
		$line=$_;
		#chomp($line);
		
		# 1409526000: 5.7362002778e+04
		if ($line =~ /^(.*): (.*)$/)
		{
			$UnixTimeBoolHash{$1} = &TimeRangeBoolean($1);
		}
	}
	close XMLFD;
	
	system "rm -f $workdirectory/$rrdid.xml $workdirectory/$rrdid.rrd"; # cleaning files
}

sub ChangeDateToUnixTime
{
	my $date = $_[0]; # 1 ARG : unixtime
	$date =~ s/\./-/g; # global substitution "." => "-"
	$date =~ s/\//-/g; # global substitution "/" => "-"
	
	my ($day, $month, $year)=split("-",$date);
	if (!(defined $year))
	{
		my @now = localtime(time);
		$year = $now[5]+1900;
	}
	my $epoch = timelocal(0,0,0,$day,$month-1,$year);
	
	return $epoch;
}
