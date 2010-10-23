#!/usr/bin/perl -w 
# serverfork.pl - a server that forks a child 
# process to handle client connections 
# usage perl fork_server.pl param1 param2
# 	param1 - port number
# 	param2 - file name with response.
use strict; 
use Socket; 
use Sys::Hostname; 
use POSIX qw(:sys_wait_h strftime); 
#use LWP::Socket

my $i_port=shift @ARGV || 7000;
my $i_configfile=shift @ARGV || 'config_file.dat';
my $fh; #file handler for output

my $logfile;
my $errlog_file;

my $servers={};

my $now_string = strftime "%a%b%e_%H:%M:%S%Y", localtime;
my $main_log_name="main_$$_$now_string.log";
my $main_errlog_name="main_err_$$_$now_string.log";
open $logfile,">",$main_log_name ||  die "can not open log file for main process $!";
open $errlog_file,">",$main_errlog_name ||  die "can not open error og file for main process $!";


$servers=read_main_config($i_configfile);
die "No servers found in config" if !defined($servers) || scalar(keys %$servers)<1;


for my $child_server (keys %$servers){
	my $child_pid=open(CHILDHANDLE,"|-");
	if ($child_pid){
		$SIG{INT}=\&parent_got_message;
		logmsg $logfile "$$";
		$servers->{$child_server}->{pid}=$child_pid;
		$servers->{$child_server}->{handle}= &CHILDHANDLE;
	}else{ # in child forked process.
		my $parent_pid=0;
		chomp($parent_pid=<>);
		$servers->{$child_server}->{parent_pid}=$parent_pid;
		child_process_server($child_server,$servers->{$child_server});
		exit();
	}

}
main_process($i_port);
sub logmsg
{
	my $file_handler=shift;
	print $file_handler "Pid=[$$],msg'@_\n'";
}
# this process will be executed after starting all active child servers and will be awaiting for following commands:
# LIST - will return list all running servers
# LISTALL will return list of all configured servers
# RUN:srv_name - will start mentioned server if not started
# STOP:srv_name - will stop mentioned server if it's running
# QUIT - will stop all child servers and exit
sub main_process{
	my $main_port=shift;
	
	my $main_proto=getprotobyname('tcp');

	socket(main_Server,PF_INET,SOCK_STREAM,$main_proto)				||die "main:socket: $!";
	setsockopt(main_Server,SOL_SOCKET,SO_REUSEADDR,pack("1",1))	||die "main:setsockopt: $!";
	bind (main_Server,sockaddr_in($main_port, INADDR_ANY))			||die "main:bind: $!";
	listen(main_Server,SOMAXCONN)								||die "main:listen $!";

	logmsg $logfile, "main server started at $main_port";

	my $main_paddr;

	for ( ; $main_paddr = accept(main_Client,main_Server); close main_Client) {
		my($port,$iaddr) = sockaddr_in($main_paddr);
		my $cli_name=gethostbyaddr($iaddr,AF_INET);
		logmsg $logfile, "got connection from $cli_name";
		my $main_command=<main_Client>;
		logmsg $logfile, "got command ($main_command) from $cli_name. going to execute";
	}

}
sub parent_got_message
{
}
sub read_main_config
{
	my $config_file=shift || "main_config.dat";
	my %config;
	my $config_fh;
	open ($config_fh,'<',$config_file) or die "Cann't open main config $config_file ...\n";
	
	while (<$config_fh>)
	{
		my @config_arr=split /=>/; # here we split each row of config file as ServerID=>configfile => portID=>Status
		#log("device $config_arr[0] is duplicated"),next if exists($config{$config_arr[0]});
		logmsg $logfile, "Read device $_";
		logmsg $errlog_file, "device $config_arr[0] is duplicated",next if exists($config{$config_arr[0]});
		$config{$config_arr[0]}={'ConfigFile'=>$config_arr[1],'portID'=>$config_arr[2],'Status'=>$config_arr[3]};
	}
	return \%config;
}

# this function will expect parameter as:
# 0(default) - list all (active unactive) servers
# 1 - list only active servers
# 2 - list only inactive servers
sub parent_list_all_servers
{ 
	my $type=shift || 0;
	my $servers=shift;
	for (my ($servId,$data)=each (%$servers))
	{
		print "Serv-($servId),Config-($data->{ConfigFile}),portID-($data->{protID}),Status-($data->{Status})\n" 
				if ($data->{status}==$type || $type ==0);
	}
}
sub child_sigint
{
}
sub child_sigquit
{

}

# this function will be executedas separate children process - this will keep connection on $port
# and wait for message. after msg received - it must be checked with patterns from config file.
# 1. read server config and list of patterns responses.
sub child_read_config
{
	my $conf_file_name = shift || return -1;
	my %conf; # this will have structure - ind->[pattern->{success_msg->"message for SUCCESS",failure_msg->"message for FAILURE}]
	
	if (-f $conf_file_name and open FILE ,'<', $conf_file_name){
		my $responses=<FILE>;
		my @resp;
		@resp=split /:/, $responses;
		$conf{1}={success_msg=>$resp[0],failure_msg=>$resp[1]};
		my $ind=2;
		while (!eof(FILE)) { 
			my $pattern=<FILE>;
			# commented for future use
			# $conf{$ind}=[$pattern,{success_msg=>$resp[0],failure_msg=>$resp[1]}];
			print "[$$] DEBUG read pattern = ($pattern)\n";
			$conf{$ind}=$pattern;
			$ind++;
		}
		close FILE;
	}
	return \%conf;
}

sub child_validate_command{
	my $command=shift;
	my $child_config=shift;
	my $resp='FAILURE';
	my $responses=$child_config->{1};
	while (my ($ind,$pattern)=each %$child_config){
		next if $ind==1;
		$resp=$responses->[1]->{success_msg} , last if $command =~ /$pattern/;
	}
	return $resp;
}

sub child_main_body{
	my $port=shift || die "child did'nt get port number";
	my $config=shift || die "child didn't get config-hash";
	
	my $proto=getprobyname('tcp');

	socket(Server, PF_INET, SOCK_STREAM, $proto)					|| die "socket: $!";
	setsockopt(Server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) 		|| die "setsockopt: $!";
	bind(Server, sockaddr_in($port, INADDR_ANY))					|| die "bind: $!";
	listen(Server,SOMAXCONN) 										|| die "listen: $!";
	#after port is opened and binded - print debug message
	print "Child server started at $port";
	
	my $paddr;
	for ( ; $paddr = accept(Client,Server); close Client) {
		my($port,$iaddr) = sockaddr_in($paddr);
		my $name = gethostbyaddr($iaddr,AF_INET);
		print "received connection from $name\n";
		my $command=join "", <Client>;
		print "[$$] command received:[$command]\n";
		my $resp=child_validate_command($command,$config);
		print "[$$] response after validation:[$resp]\n";
		print Client $resp;
	}


	return 0;
}


sub child_process_server
{
	my $server=shift;
	my $server_data=shift;

	my $log_filename="chld_$server.$now_string.log";
	my $errlog_filename="chld_err_$server.$now_string.log";
	
	close $logfile if defined $logfile;
	close $errlog_file if defined $errlog_file;

	open ($logfile, ">", $log_filename) or die "Cann't open logfile $log_filename $!";
	open ($errlog_file, ">", $errlog_filename) or die "Cann't open err log file $errlog_filename $!";
	if (!defined ($server) || !defined($server_data)) {
		print STDERR "not defined server or server_data\n Exiting";
		close STDOUT;
		close STDERR;
		die  "not defined server or server_data";
	}
	$SIG{SIGINT}=\&child_sigint; #will answe to parent with alive message
	$SIG{SIGQUIT}=\&child_sigquit; # will raise an exit from child process
	# execute reading of configuration for child
	my $chld_conf=child_read_config($server_data->{ConfigFile});
	#execute a main body of child server
	child_main_body($server_data->{portID},$chld_conf);
		
	close $logfile;
	close $errlog_file;
}
