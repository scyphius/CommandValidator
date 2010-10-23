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
my $i_configfile=shift @ARGV || 'config_file.txt';
my $fh; #file handler for output

my $servers={};

$servers=read_main_config($i_configfile);
die "No servers found in config" if !defined($servers) || scalar(keys %$servers)<1;


for my $child_server (keys %$servers){
	my $child_pid=open(CHILDHANDLE,"|-");
	if ($child_pid){
		$SIG{INT}=\&parent_got_message;
		print CHILDHANDLE "$$";
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
sub log
{
	my $file_handler=shift;
	print $file_handler "Pid=[$$],msg'@_\n'";
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
# 2. establish listener on port
sub child_read_config
{
	my $conf_file_name = shift || return -1;
	my %conf; # this will have structure - ind->[pattern->{success_msg->"message for SUCCESS",failure_msg->"message for FAILURE}]
	
	if (-f $conf_file_name and open FILE ,'<', $conf_file_name){
		my $ind=1;
		while (!eof(FILE)) { # even(÷åòíûé) $ind - for responses, others for patterns.
			my $pattern=<FILE>;
			my $responses=<FILE> || 'SUCCESS:FAILURE';
			my @resp;
			@resp=split /:/, $responses;
			next if scalar(@resp)<2;
			$conf{$ind}=[$pattern,{success_msg=>$resp[0],failure_msg=>$resp[1]}];
		}
	}
	return \%conf;
}

sub child_validate_command{
	my $command=shift;
	my $child_config=shift;
	my $resp='FAILURE';
	while (my ($ind,$data)=each %$child_config){
	my ($pattern,$responses)=$data;
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
	#after port isopened and binded - print debug message
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
	my $now_string = strftime "%a%b%e_%H:%M:%S%Y", localtime;

	my $log_filename="child_$$_$now_string.log";
	my $errlog_filename="child_err_$$_$now_string.log";
	my $logfile;
	my $errlog_file;

	#open OUT, '>&STDOUT' or die "cann't backup STDOUT";
	#open ERR, '>&STDERR' or die "cann't backup STDERR";
	close STDOUT;
	close STDERR;
	open (STDOUT, ">", $log_filename) or die "Cann't redirect STDOUT ".$!;
	open (STDERR, ">", $errlog_filename) or die "Cann't redirect STDERR ".$!;
	if (!defined ($server) || !defined($server_data)) {
		print STDERR "not defined server or server_data\n Exiting";
		close STDOUT;
		close STDERR;
		die  "not defined server or server_data";
	}
	$SIG{SIGINT}=\&child_sigint; #will answe to parent with alive message
	$SIG{SIGQUIT}=\&child_sigquit; # will raise an exit from child process
	# open a socket
		
}
