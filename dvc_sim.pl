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
my $i_respfile=shift @ARGV || 'resp_file.txt';
my $fh; #file handler for output
my $response;

my $devices={};

open ($fh,'<',$i_respfile) or die $!; # Open a file for reading or exit with an error message
while (<$fh>) {$response .= $_ };
$response='STANDART RESPONSE' unless defined($response);
sub REAP { 1 until (-1 == waitpid(-1, WNOHANG)); $SIG{CHLD} = \&REAP; }
$SIG{CHLD} = \&REAP; 
my $sock = new IO::Socket::INET( 
         LocalHost => 'localhost', 
         LocalPort => $i_port, 
        Listen => SOMAXCONN, 
        Proto => 'tcp', 
        Reuse => 1); 
$sock or die "no socket :$!"; 
STDOUT->autoflush(1); 
my($new_sock, $buf, $kid); 
print "Main server awiting orders at 'localhost' port $i_port ...\n";
while ($new_sock = $sock->accept()) { 
 # execute a fork, if this is # the parent, its work is done, 
 # go straight to continue 
 next if $kid = fork; 
 die "fork: $!" unless defined $kid; 
 # child now... 
 # close the server - not needed 
 close $sock; 
 while (defined($buf = <$new_sock>)) { 
  chop $buf; 
  foreach ($buf) { 
   /^HELLO$/ and print($new_sock "Hi\n"), last; 
   /^NAME$/ and print($new_sock hostname(),"\n"), last; 
   /^DATE$/ and print($new_sock scalar(localtime), "\n"), last;
	/^list$/i and list_all_devices;
   # default case: 
   print $new_sock $response; 
  } 
 } 
 exit; 
} continue { # parent closes the client since # it is not needed 
 close $new_sock; 
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
# 0(default) - list all (active unactive) devices
# 1 - list only active devices
# 2 - list only inactive devices
sub list_all_devices
{ 
	my $type=shift || 0;
	my $devices=shift;
	for (my ($servId,$data)=each (%$devices))
	{
		print "Serv-($servId),Config-($data->{ConfigFile}),portID-($data->{protID}),Status-($data->{Status})\n" 
				if ($data->{status}==$type || $type ==0);
	}
}



