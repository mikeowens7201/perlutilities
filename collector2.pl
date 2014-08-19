#!/usr/bin/perl

#added shit

use CGI;
use DBI;

use lib "/var/www/cgi-bin/lib";
use perlchartdir;


sub ssql
{
	my ($sql) =  @_;
	my $res = `ssh dev.pub.dfboxes.com 'mysql monitor -e "$sql"'`;
	return $res;
}

print ssql('select date(datetime) d, avg(value) from mon where server like "web%" and stat = "cpu" group by d');

exit; 



#-------------------------------------------------------------------------------------------------------------------------

sub get_firewall_data
{
	my $counter_limit = 2**32;
	my $bip = 0;
	$snmp_data = `snmpget -v2c -c 6uPhA9abar5n 192.168.233.1 IF-MIB::ifOutOctets.1 	DISMAN-EVENT-MIB::sysUpTimeInstance      SNMPv2-SMI::enterprises.9.9.147.1.2.2.2.1.5.40.6`;
	# split into lines of data
	@line = split("\n",$snmp_data);
	# first line has octets
	@current_line = split(" ",$line[0]);
	# 4th column offset 3  has value
	$octets  = $current_line[3];
	# second line has uptime
	@current_line = split(" ",$line[1]);
	# uptime value 4th column but remove brackets from it	
        $current_line[3] =~ m/\((.+)\)/;
        $timeticks  = $1;
	# last line has connections
	@current_line = split(" ",$line[2]);
	# 4th column has value
	$connections = $current_line[3];
	@old_data = sql("select * from firewall order by timeticks desc limit 1"); 
	$old_ticks = $old_data[1];
	$old_octets = $old_data[2];
	if ($octets < $old_octets) {
		# firewall counter has wrapped
		$bip = $octets + $counter_limit - 1 - $old_octets;
	} else {
        	$bip = $octets - $old_octets;	
	}
	$bandwidth = int(($bip)*800/($timeticks-$old_ticks));
	update_firewall ($timeticks,$octets,$bip,$bandwidth,$connections);
	trend_graph("Bandwidth in mbps","bwtrend","line","select time(datetime),
								bps,
								timeticks 
								from firewall 
								order by timeticks 
								desc limit 15");
	trend_graph("Users","usertrend","bar","select time(datetime),
							connections,
							timeticks 
							from firewall 
							order by timeticks 
							desc limit 15");
	logbar("User Connections","users","currcons",$connections,0,20000);
	logbar("Firewall traffic","mbps","fw",sprintf("%.2f",$bandwidth/1000000),1, 100);
	overage_graph();
}



sub overage_graph
{
	$four_tb = 4000000000000;
	$eight_tb = 8000000000000;
	$limit   = $eight_tb;
	#$limit   = 1000000000000;
	$rate = 3; #pounds per gb
	$rate = 1.5; #pounds per gb committed 
	my @bw_data,@bw_line = ();
	@binfo = sql ("select day(datetime) as day , sum(bytesinperiod) from firewall where  month(datetime) = month(now()) group by day order by day;");
	@mth = sql("select monthname(now())");
	$b = join(" ",@binfo);
	@binfo = split("\n",$b);
	$last = 0;
	foreach $b (@binfo)
	{
		@ln = split(" ",$b);
		$last = $last+ $ln[1];
		if ($last > $limit)
		{
		 	push (@overage,sprintf("%.0f",($last-$limit)/1000000000));
			push (@bw_data,sprintf("%.0f",($limit/1000000000)));
		} else
		{
			push (@bw_data,sprintf("%.0f",$last/1000000000));
			push (@overage,0);
		}
		push (@bw_lab,$ln[0]);
	}
	my $c = new XYChart(750, 550 ,0x000000,0x000000);
	$c->setPlotArea(45,45, 430, 430,0,0,0,0,0);
	#my $layer = $c->addBarLayer(\@bw_data, 0x08006666);
	my $layer = $c->addBarLayer2($perlchartdir::Stack);
	$layer->addDataSet(\@bw_data, 0x00ff00);
	$layer->addDataSet(\@overage, 0xff0000);
	#$layer->setBarGap(0.2);
	$dayz = scalar @bw_data;
	if ($dayz < 15) {$lblsz = 8;} else { $lblsz = 8;}
	$layer->setAggregateLabelStyle("ariel.ttf", $lblsz, 0xffffff);
	$layer->setAggregateLabelFormat(" {value} GB ");
	my $textbox = $c->xAxis()->setLabels(\@bw_lab);
	$c->xAxis()->setColors(0xff0000,0xff0000);
	#$c->addTitle("GB - $mth[0]", "arial.ttf", 15,0xffffff);
	if ($last  > $limit) 
	{
	 	$overage=sprintf("%.2f",($last-$limit)*$rate/1000000000); 
	}
	#$overage = sprintf("%.2f",0);
	$box2 = $c->addText(105,5,"Overage charge for $mth[0]  £$overage", "arial.ttf",15,0xffffff);
	$box2->setBackground(0x000000,0xffffff,4);
	$c->yAxis()->setColors(0xff0000, 0xff0000);
	$c->yAxis()->setLogScale(0,8000,4000);
	$c->makeChart("overage.png");
}

sub current_connections 
{
	@labs =();
	@data = ();
	@data2 = ();
	@dat = ();
	$maxclients = 1000;
	@dat = sql(" select  server, connections from server 
			where server like 'web%' order by datetime desc limit 12");
	$data_string = join(" ",@dat);
	@vals = split("\n",$data_string);
	@vals=sort(@vals);
	@vals=sort(@vals);
	foreach $val(@vals)
	{
		@ln = split(" ",$val);
		push(@labs,$ln[0]);			
		push(@data,$ln[1]);
		push(@data2,$maxclients);
	}
	my $c = new XYChart(800, 140,0x000000,0x000000);
	$c->setPlotArea(35,22, 750, 100,0,0,0,0x000000,0);
	my $br = $c->addBarLayer(\@data,0x99ff44ff);
	my $br2 = $c->addBarLayer(\@data2,0x000000);
	my $bx = $c->xAxis()->setLabels(\@labs);
	$br2->setBorderColor(0xffffff);
	$br->setBorderColor(0xffffff);
	#$ln->setBarGap(0);
	$bx->setFontStyle("arial.ttf");
	$bx->setFontSize(8);
	#$bx->setFontAngle(90);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	#$c->xAxis()->setLabelStep(6);
	$c->addTitle("Client connections", "arial.ttf", 10,0xffffff);
	$c->makeChart("currhttpconns.png");
}

sub connection_trends
{
	$interval = 14;
	
	my @data,@data2,@fwdata,@labs = ();
	@dat = sql ("select  day(datetime),hour(datetime),
			  max(connections),month(datetime) from server
			 where server like '%web%' and  
			date(datetime)>subdate(date(now()),interval  $interval day) 
			group by   day(datetime),hour(datetime)  
			 order by  datetime,hour(datetime)");
	$data_string = join(" ",@dat);
	@vals = split("\n",$data_string);
	foreach $val(@vals)
	{
		@ln = split(" ",$val);

	#	print "\n-$ln[0]--$ln[1]---";
		
		if (length($ln[1]) == 1) {$ln[1] = "0".$ln[1];}
		push(@labs,$ln[0]."/$ln[3] ".$ln[1].":00");			
		push(@data,$ln[2]);
		push(@data2,256);
		push(@data3,512);
		push(@data4,700);
	}
	@fw = sql ("select  day(datetime),hour(datetime),
			  max(bps)/100000 from firewall
			 where date(datetime)>subdate(date(now()),interval  $interval day) 
			group by   day(datetime),hour(datetime)  
			 order by  datetime,hour(datetime)");
	$fw_string = join(" ",@fw);
	@vals = split("\n",$fw_string);
	foreach $val(@vals)
	{
		@ln = split(" ",$val);

		#print "\n-$ln[0]--$ln[1]---";
		push(@fwdata,$ln[2]);
		push(@fwdata2,1000);
	}
	if (scalar(@fwdata) < scalar(@data))
	{
		while (scalar(@fwdata) < scalar(@data))
		{
			unshift(@fwdata,0);		
			unshift(@fwdata2,1000);		
		}
	}
	my $c = new XYChart(800, 550,0x000000,0x000000);
	$c->setPlotArea(35,22, 750, 450,0,0,0,0x000000,0);
	my $ln = $c->addAreaLayer(\@data,0x99ff44ff);
	my $ln2 = $c->addLineLayer(\@data2,0xff0000);
	my $ln3 = $c->addLineLayer(\@data3,0xff0000);
	my $ln4 = $c->addLineLayer(\@data4,0xff0000);
	my $ln5 = $c->addLineLayer(\@fwdata,0x00ff00);
	my $ln5 = $c->addLineLayer(\@fwdata2,0x0000ff);
	my $bx = $c->xAxis()->setLabels(\@labs);
	#$ln->setBarGap(0);
	$bx->setFontStyle("arial.ttf");
	$bx->setFontSize(8);
	$bx->setFontAngle(90);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setLabelStep(6);
	$c->addTitle("Last $interval days", "arial.ttf", 10,0xffffff);
	$box2 = $c->addText(105,25,"Area plot of connections per web server
Plus firewall traffic in 0.1Mbps units", "arial.ttf",12,0xffffff);
	$box2->setBackground(0x000000,0xffffff,4);
	$c->makeChart("totalconns.png");
}

sub nfs_network_trends
{
	my @data,@data2,@nfsdata,@labs = ();
	$ interval = 4;
	@nfs = sql ("select  day(datetime),hour(datetime),
			  max(bpsout)/1000000, avg(bpsout)/1000000  from server
			 where date(datetime)>subdate(date(now()),interval  $interval  day) and
			server = 'imagecluster' 
			group by   day(datetime),hour(datetime)  
			 order by  day(datetime),hour(datetime)");
	$nfs_string = join(" ",@nfs);
	@vals = split("\n",$nfs_string);
	foreach $val(@vals)
	{
		@ln = split(" ",$val);

		#nprint "\n-$ln[0]--$ln[1]-$ln[2]--";
		if (length($ln[1]) == 1) {$ln[1] = "0".$ln[1];}
		push(@labs,$ln[0]."/11 ".$ln[1].":00");			
		push(@nfsmax,$ln[2]);
		push(@nfsavg,$ln[3]);

	}
	my $c = new XYChart(800, 550,0x000000,0x000000);
	$c->setPlotArea(35,22, 750, 450,0,0,0,0x000000,0);
	my $ln = $c->addLineLayer(\@nfsmax,0xff0000);
	my $ln5 = $c->addAreaLayer(\@nfsavg,0x00ff00);
	my $bx = $c->xAxis()->setLabels(\@labs);
	$bx->setFontStyle("arial.ttf");
	$bx->setFontSize(8);
	$bx->setFontAngle(90);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setLabelStep(6);
	#$c->addTitle("Last $interval days", "arial.ttf", 10,0xffffff);
	$box2 = $c->addText(105,25,"$interval day plot of average and peak outbound network utilisation on nfs server", "arial.ttf",15,0xffffff);
	$box2->setBackground(0x000000,0xffffff,4);
	$c->makeChart("totalnfs.png");
}

sub twenty_four
{#########################################################################################

	$interval = 2;
	my @data,@data2,@fwdata,@labs = ();
	@data2 = ();
	@data3 = ();
	@dat = sql ("select  day(datetime),hour(datetime),
			  max(connections),max(cpupercentbusy),min(cpupercentbusy) from server
			 where server like '%web%' and  
			date(datetime)>subdate(date(now()),interval  $interval day) 
			#and hour(datetime) > 18 
			group by   day(datetime),hour(datetime)  
			 order by  day(datetime),hour(datetime)");
	$data_string = join(" ",@dat);
	@vals = split("\n",$data_string);
	#print "\n Got here ",length(@vals);
	foreach $val(@vals)
	{
		@ln = split(" ",$val);

		#print "\n-$ln[0]--$ln[1]-$ln[2]-$ln[3]-";
		if (length($ln[1]) == 1) {$ln[1] = "0".$ln[1];}
		push(@labs,$ln[0]."/11 ".$ln[1].":00");			
		push(@data,$ln[2]);
		push(@data2,$ln[3]*10);
		push(@data3,$ln[4]*10);
	}
	#print "\nLabs---->@labs";
	#print "\nData---->@data";
	#print "\nData2---->@data2";
	#print "\nData3---->@data3";
	my $c = new XYChart(800, 550,0x000000,0x000000);
	$c->setPlotArea(35,22, 750, 450,0,0,0,0x000000,0);
	my $ln = $c->addAreaLayer(\@data,0x99ff44ff);
	my $ln2 = $c->addLineLayer(\@data2,0xff0000);
	#my $ln3 = $c->addLineLayer(\@data3,0x666666);
	my $bx = $c->xAxis()->setLabels(\@labs);
	#$ln->setBarGap(0);
	$bx->setFontStyle("arial.ttf");
	$bx->setFontSize(8);
	$bx->setFontAngle(90);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setLabelStep(1);
	$c->addTitle("Last Evening days", "arial.ttf", 10,0xffffff);
	$box2 = $c->addText(105,25,"Area plot of connections per web server
Plus line chart of CPU percent busy *10", "arial.ttf",12,0xffffff);
	$box2->setBackground(0x000000,0xffffff,4);
	$c->makeChart("lastevening.png");

} #######################################################################################
sub trend_graph
{
	my @labs,@data = ();	
	my ($title,$fn,$type,$sql_string) = @_;
	@last_ten = sql($sql_string);
	$last_str = join(" ",@last_ten);	
	@last = split("\n",$last_str);
	@last = reverse(@last);
	foreach $last(@last)
	{
		@ln = split(" ",$last);
		push(@labs,$ln[0]);			
		push(@data,$ln[1]);
	}
	foreach $dt (@labs)
	{
		 $dt =~ m/^(.+:.+):.+$/;
		 $dt = $1;
	}
		
	if ($type eq "line") 
	{
		foreach $dt (@data)
		{
			 $dt = ($dt / 1000000);
		}
		line($title,$fn,\@labs,\@data);
	} 
	else
	{
		bar($title,$fn,\@labs,\@data);
	}
}
			

sub get_server_data
{

	$total_connections = 0;
	$total_realpercent =0 ;
	$total_swappercent =0 ;
	$total_cpupercent  =0 ;
	$total_inbytes = 0 ;
	$total_outbytes =0 ;
	$cpu = "ssCpuRawIdle.0";
	$tim = "sysUpTimeInstance";
	$tcp = "tcpCurrEstab.0";
	$ioc = "ifInOctets.2";
	$ooc = "ifOutOctets.2";
	$tsw = "memTotalSwap.0";
	$asw = "memAvailSwap.0";
	$trl = "memTotalReal.0";
	$arl = "memAvailReal.0";
	@stats = ($cpu, $tim, $tcp, $ioc, $ooc, $tsw, $asw, $trl, $arl);
	#my @servers = qw(web1);
	foreach $server (@servers)
	{
	#print "\n$server";	
	$snmp_data=qx"snmpget -v 1 $server -c public @stats";
		extract_server_data($server,$snmp_data);
		#$apache_processes=`ssh $server "ps -A | grep httpd | wc -l"`;
		#extract_apache_data($server,$apache_processes)
			
	}
	$total_realpercent = $total_realpercent /12;
	$total_swappercent = $total_swappercent /12;
	$total_cpupercent  = $total_cpupercent  /12;
	$total_inbytes = $total_inbytes /12 ;
	$total_outbytes = $total_outbytes /12;
	update_web_summ($total_connections,$total_realpercent,$total_swappercent,$total_cpupercent,$total_inbytes,$total_outbytes);
	draw_web_gauges();
	draw_web_io_charts();
}

sub extract_server_data
{
	
	my ($s,$data) = @_;
	if ($s eq 'dbcluster' || $s eq 'reporting') {$divisor = 8;} else {$divisor = 4;}
	# split into lines of data
	@line = split("\n",$data);
	# first line has cpu
	@cpu_line = split(" ",$line[0]);
	# 4th column offset 3  has value
	$cpu  = $cpu_line[3];
	# ...but web servers have 4 processors and db server has 8
	$cpu = $cpu / $divisor; 
	# second line has time 
	@time_line = split(" ",$line[1]);
	# connections value 4th column but remove brackets from it	
        $time_line[3] =~ m/\((.+)\)/;
        $timeticks  = $1;
	# third line has connections
	@con_line = split(" ",$line[2]);
	# 4th column has value
	$connections = $con_line[3];
	@ioct_line = split(" ",$line[3]);
	# 4th column has value
	$ioct = $ioct_line[3];
	@ooct_line = split(" ",$line[4]);
	# 4th column has value
	$ooct = $ooct_line[3];
	@tswap_line = split(" ",$line[5]);
	# 4th column has value
	$totalswap = $tswap_line[3];
	@aswap_line = split(" ",$line[6]);
	# 4th column has value
	$availswap = $aswap_line[3];
	@treal_line = split(" ",$line[7]);
	# 4th column has value
	$totalreal = $treal_line[3];
	@areal_line = split(" ",$line[8]);
	# 4th column has value
	$availreal = $areal_line[3];
	@old_wdata = sql("select * from server where server = '$s' order by datetime desc limit 1"); 
	$old_ticks = $old_wdata[2];
	if ($timeticks < $oldticks) {$oldticks = $oldticks - 2**32;}
	$old_cpu = $old_wdata[6];

	if ($cpu  < $old_cpu) {$old_cpu  = $old_cpu - 2**32;}


	$old_ioct = $old_wdata[8];
	if ($ioct  < $old_ioct) {$old_ioct  = $old_ioct - 2**32;}
	$old_ooct = $old_wdata[10];
	if ($ooct  < $old_ooct) {$old_ooct  = $old_ooct - 2**32;}
	$ibps = int(($ioct - $old_ioct)*800/($timeticks-$old_ticks));
	$obps = int(($ooct - $old_ooct)*800/($timeticks-$old_ticks));
	$cpupercent = 100 - int(($cpu - $old_cpu)*100/($timeticks-$old_ticks));
	$realpercent = 100 - int($availreal*100/$totalreal);
	$swappercent = 100 - int($availswap*100/$totalswap);
	update_server ($s,$timeticks,$connections,$realpercent,$swappercent,$cpu,$cpupercent,$ioct,$ibps,$ooct,$obps);
	if ($s =~ m/web/)
	{
		$total_connections = $total_connections + $connections;
		$total_realpercent = $total_realpercent + $realpercent;
		$total_swappercent = $total_swappercent + $swappercent;
		$total_cpupercent  = $total_cpupercent + $cpupercent;
		$total_inbytes = $total_inbytes + $ibps ;
		$total_outbytes = $total_outbytes + $obps;
	}
}


sub draw_web_io_charts
{
	@vals = sql("select server,
			concat('#',bpsin,'#', bpsout,'#')  from server 
			where server like '%web%' 
			order by  datetime desc, server asc 
			limit 12");
	$v = join(" ",@vals);
        @vals = split("\n",$v);
	# lets have web1 always first
	foreach $val (@vals)
	{
	#	print "\n$val";
		$val =~ m/^\s*(web.) #(.+)#(.+)#/;
		#nprint "\n$1#$2#$3#";
	logbar("$1","mbps out","$1io",sprintf("%.1f",$3/1000000),0, 200);
	}
}

sub draw_web_gauges
{
	my @dt,@lb = ();
	@vals = sql(" select * from websumm order by datetime desc limit 1; ");
	$cpu =   $vals[4];
	roundgauge("Web Pool","CPU","wcpu",$cpu);
	fuelgauge("Swap","wswap",$vals[3]);
	fuelgauge("Real","wreal",$vals[2]);
	@vals = sql("select server,
			 cpupercentbusy from server 
			where server like '%web%' 
			order by  datetime desc, server asc 
			limit 12");
	$v = join(" ",@vals);
        @vals = split("\n",$v);
	# lets have web1 always first
	@vals = sort(@vals);
	foreach $val (@vals)
	{
		$val =~ m/(web.+) (.+)$/;
		push(@lb,$1);
		push(@dt,$2);
		roundgauge($1,"CPU","$1cpu",$2);	
	}
	radar("CPU % Busy",\@dt,\@lb);
}

sub fuelgauge
{	
	my ($title,$fn,$value) = @_;
	my $m = new AngularMeter(70, 90, 0, 0, 0);
	$m->setColors($perlchartdir::whiteOnBlackPalette);
	$m->setMeter(10, 45, 50, 135, 45);
	$m->setScale2(0, 100, ["E", " ", " ", " ", "F"]);
	$m->setLineWidth(2, 2);
	$m->addZone(85, 100, 0xff3333);
	$m->addPointer($value, 0xffff00);
	#$m->addTitle($title, "arialbd.ttf", 8,0xffffff);
	$m->addText(15, 35, $title);
	$m->makeChart("$fn.png");
}

sub get_timeticks
{
	($svr) = @_;
	$tim = "sysUpTimeInstance";
	$ticks = qx"snmpget -v 1 $svr -c public $tim ";
	$ticks =~ m/\((.+)\)/;
	return $1;
}

sub get_disk_data_new
{
	($server,$desc) =@_;
	$clu = $server."cluster";
	if ($server eq "nfs") {$clu = "imagecluster";}
	@line = sql("select * from server where server like '%$clu%' order by datetime desc limit 1");
	roundgauge($desc,"CPU",$server."cpu",$line[7]);
	fuelgauge("Swap",$server."swap",$line[5]);
	fuelgauge("Real",$server."real",$line[4]);
	$diskinfo = qx/ssh $clu iostat -k  | egrep -i -e 'emcpowera '/;
	@disk = split(" ",$diskinfo);
 	$diskkbr = $disk[4];
 	$diskkbw = $disk[5];
	$newtime = get_timeticks($clu);
	@old =   sql("select * from disk where server like '%$clu%' order by datetime desc limit 1");
	$oldtime = $old[1];
	$olddiskkbr = $old[3];	
        $olddiskkbw = $old[5];
	$kbpsr = 100 * ($diskkbr - $olddiskkbr) / ($newtime - $oldtime); 
	$kbpsw = 100 * ($diskkbw - $olddiskkbw) / ($newtime - $oldtime); 
	update_disk($clu,$newtime,$diskkbr,$kbpsr, $diskkbw,$kbpsw);
	#linearmeter("$desc Read KBps", $kbpsr, $server."read");
#	linearmeter("$desc Write KBps", $kbpsw, $server."write");
	
	horiz_logbar(300,70,"$desc Write ","KBps",$server."write",$kbpsw,0,100000,70); 
	horiz_logbar(300,70,"$desc Read ","KBps",$server."read",$kbpsr,0,100000,70); 
}


sub roundgauge
{
	my ($title, $st, $fn, $value) = @_;
	my $m = new AngularMeter(100, 120, 0x000000,0x000000, 0);
	$m->setMeter(50, 70, 45, -135, 135);
	$m->setScale(0, 100, 10, 5, 0);
	$m->setLabelStyle("ariel,ttf",6);
	$m->setLineWidth(0, 1, 1);
	$m->setMeterColors(0xffffff,0xffffff,0x000000);
	$m->addZone(0, 60, 0x99ff99);
	$m->addZone(60, 80, 0xffff00);
	$m->addZone(80, 100, 0xff3333);
	$m->addTitle($title, "arial.ttf", 12,0xffffff);
	$m->addText(49, 95, $st, "arial.ttf", 6 ,  0xffffff,$perlchartdir::Center);
	$m->addPointer($value, 0x0000ff);
	$m->makeChart("$fn.png");
}


sub bar
{
	my ($title,$fn,$labels,$data) = @_;
	my $c = new XYChart(550, 100 ,0x000000,0x000000);
	$c->setPlotArea(15,15, 500, 64,$perlchardir::Transparent,
    	$perlchartdir::Transparent, $perlchartdir::Transparent,
    	$perlchartdir::Transparent, $perlchartdir::Transparent);
	my $layer = $c->addBarLayer($data, 0x08006666);
	$layer->setBarGap(0.2);
	$layer->setAggregateLabelStyle("ariel.ttf", 7, 0xffffff);
	my $textbox = $c->xAxis()->setLabels($labels);
	$textbox->setFontStyle("arial.ttf");
	$textbox->setFontSize(9);
	$c->xAxis()->setColors($perlchartdir::Transparent, 0xffffff);
	#$c->yAxis()->setLogScale(0,10000,0);
	$c->addTitle($title, "arial.ttf", 10,0xffffff);
	$c->yAxis()->setColors($perlchartdir::Transparent, $perlchartdir::Transparent);
	$c->makeChart("$fn.png");
}

sub logbar
{
	my $dt = ""; 
	my ($title,$labels,$fn,$dt,$lowscale,$highscale) =  @_; 
	my $c = new XYChart(120, 250 ,0x000000,0x000000);
	$c-> setPlotArea(60,35, 50, 180,$perlchartdir::Transparent,
    					$perlchartdir::Transparent, $perlchartdir::Transparent,
    					$perlchartdir::Transparent, 0x000000);
	my $layer = $c->addBarLayer(	[$dt], 0x999900);
	$layer->setBarGap(0.4);
	$layer->setAggregateLabelStyle("arielb.ttf", 6, 0xffffff);
	my $textbox = $c->xAxis()->setLabels([$labels]);
	#$c->yAxis()->setLogScale($lowscale,$highscale,0);
	$c->yAxis()->setLinearScale($lowscale,$highscale,0);
	$textbox->setFontStyle("arial.ttf");
	$textbox->setFontSize(10);
	$c->addTitle($title, "arial.ttf", 10,0xffffff);
	$c->xAxis()->setColors($perlchartdir::Transparent, 0xffffff);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->makeChart("$fn.png");
}

sub horiz_logbar
{
	my $dt = ""; 
	my ($x,$y,$title,$labels,$fn,$dt,$lowscale,$highscale,$danger) =  @_; 
	$dt = int($dt);
	my $c = new XYChart($x,$y ,0x000000,0x000000);
	$c-> setPlotArea(0.2*$x,0.1*$y, 0.7*$x,0.6*$y,$perlchartdir::Transparent,
    					$perlchartdir::Transparent, $perlchartdir::Transparent,
    					$perlchartdir::Transparent, 0x000000);
	my $layer = $c->addBarLayer(	[$dt], 0x999900);
	$layer->setBarGap(0.4);
	$layer->setAggregateLabelStyle("arielb.ttf", 6, 0xff0000);
	my $textbox = $c->xAxis()->setLabels([$labels]);
	$c->yAxis()->setLogScale($lowscale,$highscale,10);
	$textbox->setFontStyle("arial.ttf");
	$textbox->setFontSize(10);
	$c->addTitle($title, "arial.ttf", 10,0xffffff);
	$c->xAxis()->setColors($perlchartdir::Transparent, 0xffffff);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->swapXY(1);
	$c->makeChart("$fn.png");
}

sub linearmeter
{
	$magnitude = 5;
	my($tit,$value,$fn)  = @_;
	$value = int($value );
	my $m = new LinearMeter(300, 50, 0x000000, 0, 0);
	$m->setMeter(15, 20, 250, 15, $perlchartdir::Top);
	$m->setScale(0, $magnitude, $magnitude*0.1);
	$m->setMeterColors(0x000000, 0xff0000, 0x000000);
	$m->addZone(0, 0.3*$magnitude, 0x8000ff00);
	$m->addZone(0.3*$magnitude, 0.7*$magnitude, 0x80ffff00);
	$m->addZone(0.7*$magnitude, $magnitude, 0x80ff0000);
	$m->addPointer($value, 0x0000ff);
	$m->addText(130, 36, $tit, "arial.ttf", 8, 0xffffff, $perlchartdir::TopCenter)->setBackground(0x000000);
	$m->makeChart("./$fn.png");
}

sub radar
{
	my ($title,$data,$labels) =@_;
	my $c = new PolarChart(200, 170,0xff000000,0xffff0000);
	$x = $c->setPlotArea(100,95, 55);
	$c->setGridColor(0x0000ff,1, 0x0000ff,1);
	$c->setGridStyle(0,1);
	$c->addTitle($title, "arial.ttf", 10,0xffffff);
	$c->addAreaLayer($data, 0xffee8800);
	$box = $c->angularAxis()->setLabels($labels);
	$box->setFontColor(0xffff00);
	$box->setFontSize(8);
	$box->setFontStyle("arial.ttf");
	$box->setBackground(0xffffffff,0xffffffff);
	$c->radialAxis()->setColors(0x0000ff,0x0000ff);
	$box2 = $c->radialAxis()->setLabelStyle("arial.ttf",9,0x00ff00);
	$box2->setBackground(0xffffffff,0xffffffff);
	$c->makeChart("webcpuradar.png")
}

sub line
{
	my ($title,,$fn,$labels,$data) = @_;
	my $c = new XYChart(550, 150,0x000000,0x000000);
	$c->setPlotArea(35,22, 480, 100,0,0,0,0x000000,0);
	my $ln = $c->addAreaLayer($data,0x70ff44ff);
	$ln->setLineWidth(2);
	$c->xAxis()->setLabels($labels);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	#$c->xAxis()->setLinearScale(,,10);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	$c->xAxis()->setLabelStep(3);
	$c->addTitle($title, "arial.ttf", 10,0xffffff);
	$c->makeChart("$fn.png");
}

sub create_fw_table()
{
	sql("drop table firewall");
	sql("create table firewall  (`datetime` timestamp ,
					`timeticks` bigint,
					`ifoutoctets` bigint,
					`bps` int,
					 `connections` int)");
	update_firewall(0,0,0,0);
}
sub update_load
{
	my ($sv,$one,$five,$fifteen) = @_;
	{sql("insert into loadav (server,lone,lfive,lfifteen) values ('$sv',$one,$five,$fifteen)");} 
}
sub create_load_table()
{
	sql("drop table load");
	sql("create table loadav  (`datetime` timestamp,
				 `server` varchar(20),
					`lone` decimal(10,2),
					`lfive` decimal(10,2),	
					`lfifteen` decimal(10,2))");
}

sub create_disk_table()
{
	sql("drop table disk");
	sql("create table disk (`datetime` timestamp , timeticks bigint,
			`server` varchar(20),
			`kbread` bigint,
			`kbpsread` decimal(10,2),
			 `kbwritten` bigint,
			`kbpswritten` decimal(10,2))");
	update_disk("dbcluster",0,0,0,0,0);
	update_disk("imagecluster",0,0,0,0,0);
}

sub update_disk
{
	my ($server,$timeticks,$rkb,$rkbps,$wkb,$wkbps) = @_;
	{sql ("insert into disk (timeticks,server,kbread,kbpsread,kbwritten,kbpswritten)  
		values ($timeticks,'$server',$rkb,$rkbps,$wkb,$wkbps)");} 
}

sub create_summ_table
{
	sql("drop table websumm");
	sql("create table websumm (`datetime` timestamp, 
					`conns` int,
					 `percentrealused` decimal,
					`percentswapused` decimal,
					`percentcpubusy` decimal,
					`bpsin` decimal,
					`bpsout` decimal)");
}

sub update_web_summ
{
  	my ($c,$ru,$su,$cb,$ib,$ob) = @_; 
	sql("insert into websumm (`conns`,
				`percentrealused`,
				`percentswapused`,
				`percentcpubusy`,
				`bpsin`,`bpsout`)
				values ($c,$ru,$su,$cb,$ib,$ob)");
}

sub create_server_table()
{
	sql("drop table server");
	sql("create table server (`server` varchar(14),
					`datetime` timestamp ,
					`timeticks` bigint,
					`connections` int,
					`percentrealused` int,
					`percentswapused` int,
					`cpuidleticks` bigint,
					`cpupercentbusy` int,
					`ioctals` bigint,
					`bpsin` int,
					`ooctals` bigint,
					`bpsout` int)");
	update_server("web1",0,0,0,0,0,0,0,0,0,0);
	update_server("web2",0,0,0,0,0,0,0,0,0,0);
	update_server("web3",0,0,0,0,0,0,0,0,0,0);
	update_server("web4",0,0,0,0,0,0,0,0,0,0);
	update_server("web5",0,0,0,0,0,0,0,0,0,0);
	update_server("web6",0,0,0,0,0,0,0,0,0,0);
	update_server("web7",0,0,0,0,0,0,0,0,0,0);
	sleep 5;
}

sub update_firewall()
{
	my ($tt,$bw,$bp,$bps,$cn) = @_;
	{sql("insert into firewall (timeticks,ifoutoctets,bytesinperiod,bps, connections)  values ($tt,$bw,$bp,$bps,$cn)");} 
}

sub update_server()
{
	my ($s,$tt,$cn,$ru,$su,$ct,$cpt,$io,$bpi,$oo,$bpo) = @_;
	sql("insert into server  (`server`,`timeticks`,
					`connections`,
					`percentrealused`,
					`percentswapused`,
					`cpuidleticks`,
					`cpupercentbusy`,
					`ioctals`,
					`bpsin`,
					`ooctals`,
					`bpsout`) values ('$s',$tt,$cn,$ru,$su,$ct,$cpt,$io,$bpi,$oo,$bpo)");


}


sub open_database()
{
	$dbh = DBI->connect('DBI:mysql:host=dev.pub.dfboxes.com:database=monitor','root','');
	die "\nUnable to connect: $DBI::errstr\n" unless (defined $dbh);
}

sub close_database()
{
	$dbh->disconnect();
}

sub get_disk_full()
{
	my @lbl = @dt = ();
	$dsk  = qx'ssh imagecluster df -h /san/nfs | grep san  ';
	@nfs  = split(" ",$dsk);
	push @lbl,"NFS";
	push @dt,$nfs[4];	
	$dsk  = qx'ssh dbcluster df -h /san/mysql | grep san  ';
	@db  = split(" ",$dsk);
	push @lbl,"DB";
	push @dt,$db[4];	
	$dsk  = qx'df -h / | grep /  ';
	@rep  = split(" ",$dsk);
	push @lbl,"Reporting";
	push @dt,$rep[4];
	my $c = new XYChart(250, 140,0x0,0x0);
$c->addTitle("Disk Utilisation Percentage", "ariel.ttf", 10,0xffffff);
$c->setPlotArea(20, 10, 200, 100, 0x0, 0x0,0x0,0x0,0x0);
my $layer = $c->addBarLayer3(\@dt);
	$layer->setAggregateLabelStyle("arielbd.ttf",10, 0x0);
	$layer->setAggregateLabelFormat("{value}%");
my $layer2 = $c->addBarLayer3([100,100,100],[0x666666,0x666666,0x666666]);
#$layer->set3D(10);
#$layer2->set3D(10);
$layer->setBarShape($perlchartdir::CircleShape);
$layer2->setBarShape($perlchartdir::CircleShape);
$c->xAxis()->setLabels(\@lbl);
	$c->yAxis()->setColors(0x000000, 0x0);
	$c->xAxis()->setColors(0x0, 0xffffff);
$c->makeChart("cylinderbar.png")	
}


sub get_loadaverages()
{
	@sn=();
	@la=();
	foreach $server (@servers)
	{
		if (($server ne 'reporting') and ($server ne 'web8'))
		{
			$load = qx/ssh $server "uptime "/;
	
			#print "\n$server $load";
			@loads = split (",",$load);
			$loads[3] =~ m/load average: (.+)$/;
			$l1 =$1;
			$loads[4] =~ m/ (.+)$/;
			$l2 =$1;
			$loads[5] =~ m/ (.+)$/;
			$l3 =$1;
	#print "$server\n$l1\n$l2\n$l3";
			#if ($l1 > 20) {send_text()};
			update_load($server,$l1,$l2,$l3);
			push(@la1,$l1);
			push(@la2,$l2);
			push(@la3,$l3);
			push(@sn,$server);
		}
	}
	my $c = new XYChart(800, 190,0x000000,0x000000);
	$c->setPlotArea(35,22, 750, 130,0,0,0,0x000000,0);
	my $br = $c->addBarLayer2($perlchartdir::Side, 3);
$br->addDataSet(\@la1, 0xff8080, "1");
$br->addDataSet(\@la2, 0x80ff80, "5");
$br->addDataSet(\@la3, 0x8080ff, "15");

# output the chart

	my $bx = $c->xAxis()->setLabels(\@sn);
	$br->setBorderColor(0xffffff);
	#$ln->setBarGap(0);
	$bx->setFontStyle("arial.ttf");
	$bx->setFontSize(8);
	#$bx->setFontAngle(90);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->yAxis()->setLinearScale(0,20,0);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	#$c->xAxis()->setLabelStep(6);
	$c->addTitle("1,5,15 minute Load Averages", "arial.ttf", 10,0xffffff);
	$c->makeChart("currload.png");
	
	
}		


sub current_mbps() 
{
	@labs =();
	@data = ();
	@data2 = ();
	@dat = ();
	$maxmbps = 1000;
	@dat = sql("select server, bpsout/1000000 from server where server <> 'reporting' order by datetime desc limit 14");
	$data_string = join(" ",@dat);
	@vals = split("\n",$data_string);
	@vals=sort(@vals);
	@vals=sort(@vals);
	foreach $val(@vals)
	{
		@ln = split(" ",$val);
		push(@labs,$ln[0]);			
		push(@data,$ln[1]);
		push(@data2,$maxmbps);
	}
	print "\n@labs\n@data";
	my $c = new XYChart(800, 140,0x000000,0x000000);
	$c->setPlotArea(35,22, 750, 100,0,0,0,0x000000,0);
	my $br = $c->addBarLayer(\@data,0x99ff44ff);
	my $br2 = $c->addBarLayer(\@data2,0x000000);
	my $bx = $c->xAxis()->setLabels(\@labs);
	$br2->setBorderColor(0xffffff);
	$br->setBorderColor(0xffffff);
	#$ln->setBarGap(0);
	$bx->setFontStyle("arial.ttf");
	$bx->setFontSize(8);
	#$bx->setFontAngle(90);
	$c->yAxis()->setColors(0xff0000, 0xffffff);
	$c->yAxis()->setLinearScale(0, $maxmbps+10, 200);
	$c->xAxis()->setColors(0xff0000, 0xffffff);
	#$c->xAxis()->setLabelStep(6);
	$c->addTitle("Client bandwidth", "arial.ttf", 10,0xffffff);
	$c->makeChart("currbps.png");
}

sub sql()
{
    $sql =  $_[0];
    my @answer = ();
    $dbp = $dbh->prepare($sql);
    $dbp->execute or die "Cant execute sql $sql" ;
    if ($sql =~ /select/)
    {
    	while (@ans = $dbp->fetchrow_array())
    	{	
		#$ans_string = join(" ",@ans);
		@answer = (@answer,@ans);
		push (@answer,"\n");
    	}
    }
    return @answer;
}
#sub send_text
#{
#	($msg) = @_;
#	$rpt = '447926899069@sms.world-text.com';			
#	print `echo '$msg' | mail $rpt`;
#}


exit;

