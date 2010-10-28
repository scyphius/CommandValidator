#!/usr/bin/perl -w 
# serverfork.pl - a server that forks a child 
# process to handle client connections 
# usage perl fork_server.pl param1 param2
# 	param1 - port number
# 	param2 - file name with response.
use strict; 
use warnings;
use Socket; 
use Sys::Hostname; 
use POSIX qw(:sys_wait_h strftime); 
use IO::Socket;

#Die on INT or QUIT:
#use sigtrap qw(die INT QUIT);
use sigtrap qw(die INT QUIT);

my $EOL = "\015\012";

my $i_port=shift @ARGV || 7000;
my $i_configfile=shift @ARGV || 'config_file.dat';
print "main: begin i_port=$i_port i_config_file=$i_configfile\n";

my $server_name;

my $servers={};
 $|=1;
#my $now_string = strftime "%a%b%e_%H%M%S%Y", localtime;
my $now_string = strftime "%Y%m%e_%H%M%S", localtime;
my $main_log_name="main_$now_string.log";
my $main_errlog_name="main_err_$now_string.log";


$servers=main_read_config($i_configfile);
die "No servers found in config" if !defined($servers) || scalar(keys %$servers)<1;


#$SIG{INT}=\&parent_got_message;
for my $child_server (keys %$servers){

	my $child_pid;
	$child_pid=main_run_child_server($child_server);
	if ($child_pid>0){
		$servers->{$child_server}->{pid}=$child_pid;
		print "Stored data for $child_server\n", main_print_server($child_server,$servers->{$child_server});
		print "main $child_server has been started\n" ;
	}elsif ($child_pid<0){
		warn "server_name was not sent to main_run_child_server... " if $child_pid==-1;
		warn "server $child_server is already running" if $child_pid==-2;
		warn "main:cannot fork for $child_server" if $child_pid==-3; 		
	}
}
main_process($i_port);


sub main_run_child_server{
	my $server_name=shift || return -1;
	#check if child_server with server_name already running
	return -2 if 	(defined ($servers->{$server_name}->{pid}) && $servers->{$server_name}->{pid}>0);
	my $child_pid;
	if (!defined($child_pid=fork)){
		return -3;
	}
	if ($child_pid){
		return $child_pid;
	}else{ # in child forked process.
		child_process_server($server_name,$servers->{$server_name});
		die;
	}

}

sub logmsg
{
	my $status=print "$server_name: @_\n";
#	print "logmsg status:$status\n";
	return $status;
}
sub main_sig_kill{
	foreach my $serv( keys %$servers){
		print "main:SIG KILL child $serv  pid=",$servers->{$serv}->{pid},"\n" if defined($servers->{$serv}->{pid});
		print "main: pid is not defined for $serv\n",next if !defined($servers->{$serv}->{pid});
		if ($servers->{$serv}->{pid}>0){
			print "sending KILL to $serv with pid $servers->{$serv}->{pid}\n";
			kill QUIT => $servers->{$serv}->{pid} ;
		}
	}
}

# this process will be executed after starting all active child servers and will be awaiting for following commands:
# LIST - will return list all running servers
# LISTALL will return list of all configured servers
# RUN:srv_name - will start mentioned server if not started
# STOP:srv_name - will stop mentioned server if it's running
# QUIT - will stop all child servers and exit
sub main_process{
	my $main_port=shift||7000;
	print "main: main_pocess start\n";
	$SIG{KILL}=\&main_sig_kill;
	$SIG{CHLD} = \&main_REAPER;
	my $server=IO::Socket::INET->new(Proto=>'tcp',
								  LocalPort=>$main_port,
								  Listen=>SOMAXCONN,
								  Reuse=>1
								 );
	die "can't setup server" unless $server;
	print "main: server is waiting for connection...\n";
	my $main_command;
	my $client;
	while ($client=$server->accept() ){
		print "main: got conection\n";
		$client->autoflush(1);
		my $cli_name= gethostbyaddr($client->peeraddr,AF_INET);
		while ($main_command=<$client>){
			$main_command=~s/$EOL//;
			print "got command ($main_command) from $cli_name going to execute\n";
			my $response=main_conversation($main_command);
			if (defined($response)){
				print $client $response,$EOL;
				print "main: response : '$response'",$EOL;
			}else {
				print $client "UNRECOGNIZED","\n";
				warn "main: command '$main_command' is UNRECOGNIZED"
			}
		}
	close $client;
	}
}
sub main_REAPER{
	my $child_pid;
	my $srv;
	while (($child_pid = waitpid(-1,WNOHANG)) > 0) {
		print "REAPER : $child_pid \n";
		for $srv (keys %$servers){
			if (defined($servers->{$srv}->{pid}) && $servers->{$srv}->{pid}==$child_pid){
				$servers->{$srv}->{pid}=0;
				$servers->{$srv}->{Status}='BL';
				print "main: REAPED $srv on pid $child_pid\n";
			}
		}
	}
	$SIG{CHLD} = \&main_REAPER;

}
sub main_conversation{
	my $command=shift || return undef;
	print "main_convrs: command ($command) received \n";
	return "OLOLEH" if $command =~ /^HELLO/;
	return parent_list_all_servers() if $command =~/LIST/;
	
	if ($command=~/QUIT/){
		main_sig_kill();	
		die "got QUIT command" ;
	}

	return undef; # default if unrecognized  command
}
sub parent_got_message
{
}
sub main_read_config
{
	my $config_file=shift || "main_config.dat";
	my %config;
	my $config_fh;
	open ($config_fh,'<',$config_file) or die "Cann't open main config $config_file ...\n";
	
	while (<$config_fh>)
	{
		chomp;
		next if /^#/;
		my @config_arr=split /=>/; # here we split each row of config file as ServerID=>configfile => portID=>Status
		#log("device $config_arr[0] is duplicated"),next if exists($config{$config_arr[0]});
		print "Read device $_\n";
		print "device $config_arr[0] is duplicated\n",next if exists($config{$config_arr[0]});
		$config{$config_arr[0]}={'ConfigFile'=>$config_arr[1],'portID'=>$config_arr[2],'Status'=>$config_arr[3],pid=>0};
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
	my $resp="";
	while (my ($servId,$data)=each (%$servers))
	{
		$resp.= "Serv-($servId):Config-($data->{ConfigFile}),portID-($data->{portID}),Status-($data->{Status}),pid=($data->{pid})\n" 
				if ($data->{status} eq 'OP' || $type ==0);
	}
	print $resp;
	return $resp;
}
sub main_print_server{
	my $server_name=shift || exit;
	my $server_data=shift || exit;
	my $resp="Server $server_name:";
	for my $param (keys %$server_data){
		 $resp.="\t$param-->$server_data->{$param}\n";
	}
	return $resp;
}
sub child_sigint
{
}
sub child_sigquit{
	my $log =shift;
	logmsg  "QUIT signal is received. stopping...";
	die;
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
			chomp $pattern; 

			# commented for future use
			# $conf{$ind}=[$pattern,{success_msg=>$resp[0],failure_msg=>$resp[1]}];
			next if($pattern =~ /^#/;
			logmsg "DEBUG read pattern = ($pattern)";
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
		$resp=$responses->{success_msg} , last if $command =~ /$pattern/;
	}
	return $resp;
}

sub child_main_body{

	my $port=shift || die "child did'nt get port number";
	my $config=shift || die "child didn't get config-hash";

	my $chld_server=IO::Socket::INET->new(Proto=>'tcp',
								  LocalPort=>$port,
								  Listen=>SOMAXCONN,
								  Reuse=>1
								 );
	die "can't setup server" unless $chld_server;
	logmsg  " server is waiting for connection...\n";
	my $command;
	my $chld_client;
	while ($chld_client=$chld_server->accept()){
		logmsg  "got conection\n";
		$chld_client->autoflush(1);
		my $cli_name= gethostbyaddr($chld_client->peeraddr,AF_INET);
		my $chld_command;
		while ($chld_command=<$chld_client>){
			$chld_command=~s/$EOL//;
			logmsg  "got command ($chld_command) from $cli_name going to execute\n";
			print $server_name, " got command ($chld_command) from $cli_name going to execute\n";
			my $response=child_validate_command($chld_command,$config);
			print $chld_client $response,$EOL;
			logmsg  "$server_name: response : '$response'",$EOL;
		}
		close $chld_client;
	}
}


sub child_process_server
{
	my $server=shift;
	my $server_data=shift;

	my $logfile;
	my $errlog_file;

	$server_name=$server; #for logmsg

	my $log_filename="chld_$server.$now_string.log";
	my $errlog_filename="chld_err_$server.$now_string.log";
	my $status=0;	

	#open ($logfile, ">", $log_filename) or die "Cann't open logfile $log_filename $!";
	open (STDOUT, ">", $log_filename) or die "Cann't open logfile $log_filename $!";
	open (STDERR, ">", $errlog_filename) or die "Cann't open err log file $errlog_filename $!";
	$|=1;
	$status=logmsg  " started...";

	#$SIG{QUIT}=\&child_sigquit(); # will raise an exit from child process
	# execute reading of configuration for child
	my $chld_conf=child_read_config($server_data->{ConfigFile},$logfile,$errlog_file);
	logmsg  "config has ",scalar keys %$chld_conf," elements";
	#$SIG{INT}=\&child_sigint; #will answe to parent with alive message
	#$SIG{QUIT}=sub {logmsg $logfile, "QUIT signal is received. stopping...";die;}; # will raise an exit from child process
	#execute a main body of child server
	logmsg  "Before executing child_main body...";
	$status=child_main_body($server_data->{portID},$chld_conf,$logfile,$errlog_file);
	logmsg "child main body returned status - $status";
	
}
