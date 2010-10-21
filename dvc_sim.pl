	#!/usr/bin/perl -w 
# serverfork.pl - a server that forks a child 
# process to handle client connections 
# usage perl fork_server.pl param1 param2
# 	param1 - port number
# 	param2 - file name with response.
use strict; 
use IO::Socket; 
use Sys::Hostname; 
use POSIX qw(:sys_wait_h); 

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
		$servers->{$child_server}->{handle}=CHILDHANDLE;
	}else{ # in child forked process.
		my $parent_pid=0;
		chomp($parent_id=<>);
		$servers{$child_server}->{parent_pid}=$parent_pid;
		child_process_server($child_server,$servers->{$child_server});
		exit();
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
		errlog("device $config_arr[0] is duplicated"),next if exists($config{$config_arr[0]});
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
	my $devices=shift;
	for (my ($servId,$data)=each (%$devices))
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
sub child_process_server
{
	$SIG{SIGINT}=\&child_sigint; #will answe to parent with alive message
	$SIG{SIGQUIT}=\&child_sigquit; # will raise an exit from child process
	
}
