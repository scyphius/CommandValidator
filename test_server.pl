#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  test_server.pl
#
#        USAGE:  ./test_server.pl  
#
#  DESCRIPTION:  this script is supposed to be automatically connected to ip/port, send predefined messages  and get answers.
# also is supposed to write all in log file.
#
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  YOUR NAME (), 
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  06/05/2011 08:10:50 PM
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Getopt::Long;
use IO::Socket;

my $config_fname='test_config.dat';
my $test_fname='test.dat';
my $log_fname='test_server.log';

my $silent=0;
my $help=0;
my $EOL = "\015\012";

my $result=	GetOptions("config=s"=>\$config_fname,
						"test=s"=>\$test_fname,
						"silent"=>\$silent,
						"log=s"=>\$log_fname,
						"help"=>\$help);
if ($help){
	print "s script is supposed to be automatically connected to ip/port, send predefined messages  and get answers.
 also is supposed to write all in log file.
	use as
		perl test_server.pl --help --config=<config_file_name> --test=<test_data_file_name> --silent --log=<log file name>

		--help - prints this help
		--silent - will print to log file only
		--config - filename of file with config like ip,port. default test_config.dat
		{--test  - filename for testing data. default = test.dat
		--log - filename for log output. default = test_server.log
";
	exit(0);
}


open (my $log_file,'>',$log_fname) or die "cannot open $log_fname for writing";

open (my $config_file,'<',$config_fname) or die "cannot open config file $config_fname\n";
my $config={};
while (<$config_file>){
	my ($par, $val)=split /=/;
	chomp $val;
	$config->{$par}=$val;
}

close $config_file; 

die "no parameters IP or PORT in config $config_fname\n" unless defined($config->{PORT}) or defined($config->{IP});
printlog ("port=$config->{PORT}\nip=$config->{IP}");

open (my $test_file,'<',$test_fname) or die "cannot open test data file $test_fname\n";
my $test_data=();
while (<$test_file>){
	chomp $_;
	push @$test_data,$_;
}
close $test_file;
die "no data in $test_fname file" if scalar(@$test_data)<1;

printlog ("test data:\n", join("\n",@$test_data));


#my $socket=IO::Socket::INET->new(Proto=>'tcp',LocalPort=>$config->{PORT},LocalAddr=>$config->{IP}) or die "cannot open connection '$!'";
my $socket=IO::Socket::INET->new(Proto=>'tcp',PeerAddr=>"$config->{PORT}:$config->{IP}") or die "cannot open connection '$!'";
my $resp;  
foreach my $command (@$test_data){
	printlog("sending command '$command'");
	$socket->send($command.$EOL);
	$resp='';
	$socket->recv($resp,256);
	printlog("got response '$resp'");
}

close $log_file;

sub printlog{
	print $log_file "@_\n";
	print "@_\n" if !$silent;
}

sub log_hash{
	my $inhash=shift or return;
	foreach my $key (keys %$inhash){
		print $log_file "$key=>$inhash->{$key}\n";
		print "$key=>$inhash->{$key}\n" if !$silent;
	}
}
