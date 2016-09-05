#!/usr/bin/perl
# rsync backup v2.0
#
# GPLv2
#
#	https://github.com/tryggvi/rbackup
#
# Author: Tryggvi Farestveit <trygvi@ok.is>
#############################
use strict;
use Data::Dumper;
use Getopt::Long;

#### Settings
# Global excludes
my @exclude = (
	"/proc",
	"/sys",
	"/dev",
);

## Hosts to backup
my %hosts = (
	"test.example.com" => {
		"user" => "root",
		"include" => {
			"/etc/",
			"/home/"
		},
		"exclude" => {
			"/tmp/",
		}
	},
	"temp.example.com" => {
		"user" => "backup",
		"include" => {
			"/",
		},
		"exclude" => {
			"/tmp/",
		}
	}
);


# Server information
my $ssh_key = ""; # Use other than default SSH key
my $ssh_known_hosts = ""; # Use other known host file than default
my $backup_dir = "/data/backup";

# Logging
my $logdir = "/var/log/rbackup";
my $logfile = $logdir."/rbackup.log"; # Log file

# Misc
my $options = "-v --info=BACKUP,COPY,DEL -a -R -z --delete --force --ignore-errors";
my $debug = 0;

########### Do not edit below ###########
my ($o_verb, $o_help, $o_test, $o_debug, $o_run);

# Logging
sub printlog($){
	my($text) = @_;
	my ($sec,$min,$hour,$day,$month,$year) = gettime();
	my $out = "$year-$month-$day $hour:$min:$sec $text";

	print LOG $out."\n";
	if($o_verb){
		print $out."\n";
	} 
}

# Input validation
sub check_options {
	Getopt::Long::Configure ("bundling");
	GetOptions(
		'v'     => \$o_verb,            'verbose'	=> \$o_verb,
		'h'     => \$o_help,            'help'	=> \$o_help,
		'd'     => \$o_debug,            'debug'	=> \$o_debug,
		't'     => \$o_test,            'test'	=> \$o_test,
		'r'     => \$o_run,            'test'	=> \$o_run,
	);

	if(defined ($o_help)){
		help();
		exit 1;
	}

	if(defined($o_debug)){
		$debug=1;
	}
	if(defined($o_test)){
		$options .= " -n";
		print "Dry run\n";
	}

	if(defined($o_run)){
		# Run backup
		RunBackup();
	}
}

# Help
sub help() {
	print "$0\n";
        print <<EOT;
-v, --verbose
        print extra debugging information
-t, --test
        Do not execute, only dry run
-r, --run
        Run backup
-h, --help
	print this help message
EOT
}

sub print_usage() {
        print "Usage: $0 [-v] ]\n";
}


# Process hosts to backup
sub GetHash($){
	my ($hash) = shift;

	my @out;
	my $i=0;
	foreach my $dir (%$hash){
		if($dir){
			$out[$i] = $dir;
			$i++;
		}
	}

	return @out;
}

# Convert array to exclude string
sub ArrayToExclude(@){
	my (@dirs) = @_;

	my $out;
	foreach(@dirs){
		$out .= "--exclude=\"$_\" ";
	}
	return $out;
}

# Convert array to string
sub ArrayToString(@){
	my (@dirs) = @_;

	my $out;
	foreach(@dirs){
		$out .= "$_ ";
	}
	return $out;
}

# If dir does not exist, create it.
sub DirExists($){
	my ($dir) = @_;
	if(!-e $dir){
		printlog("Creating $dir");
		mkdir $dir, 0700;
	}
}
	
# Convert array to include string
sub ArrayToInclude(@){
	my (@dirs) = @_;

	my $out;
	foreach(@dirs){
		$out .= ":$_ ";

	}
	return $out;
}

# Get current time
sub gettime(){
	my $input = time();
	my ($sec,$min,$hour,$day,$month,$year) = (localtime($input))[0,1,2,3,4,5];
	$year = $year +1900;
	$month = $month +1 ;
	if($month < 10){
		$month = "0$month";
	}

	if($day < 10){
		$day = "0$day";
	}

	if($hour < 10){
		$hour = "0$hour";
	}

	if($min < 10){
		$min = "0$min";
	}

	return ($sec,$min,$hour,$day,$month,$year);
}

sub RunBackup(){
	# Logging starts
	open(LOG, ">>$logfile");
	printlog("===========================");
	printlog("Starting backup");

	my $ssh_extra;
	if($ssh_key || $ssh_known_hosts){
		$ssh_extra = "-e \'ssh ";
		if($ssh_known_hosts){
			$ssh_extra .= "-o UserKnownHostsFile=$ssh_known_hosts ";
		}

		if($ssh_key){
			$ssh_extra .= "-i $ssh_key ";
		}

		$ssh_extra .= "\'";
	}

	if(!-e $backup_dir){
		printlog("Creating $backup_dir");
		mkdir $backup_dir, 0700;
	}


	DirExists($logdir);
	foreach my $host (keys %hosts){
		my $user = $hosts{$host}{"user"};
		printlog("Backing up $host with user $user");
		if(!$user){
			printlog("Error: user for $host does is missing");
			next;
		} 
		my $host_backup_root = $backup_dir."/".$host;
		my $host_backup_dir = $host_backup_root."/current/";
		DirExists($host_backup_root);
		DirExists($host_backup_dir);

		my @include = GetHash($hosts{$host}{include});
		my @exclude = GetHash($hosts{$host}{exclude});
		my $include_str = ArrayToInclude(@include);
		my $exclude_str = ArrayToExclude(@exclude);

		my ($sec,$min,$hour,$day,$month,$year) = gettime();
		my $backup_suffix = "$year-$month-$day-$hour-$min";

		# Sync data
		my $cmd= "/usr/bin/rsync --delete-excluded $ssh_extra ".$exclude_str." --backup --backup-dir=$host_backup_root/differential/$backup_suffix --stats $options $user\@".$host.$include_str." $host_backup_dir > $logdir/".$host."-".$backup_suffix.".log";
		print "$cmd\n" if $debug;
		printlog("Syncing: $cmd");
		open(CMD, "$cmd|");
		close(CMD);
		printlog("Syncing: Finished");
	}
	printlog("Backup finished");
}


### Main
check_options();
