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

#### Defaults (overridden by rbackup.conf)
my %hosts;

my $ssh_key         = "";
my $ssh_known_hosts = "";
my $backup_dir      = "/data/backup";
my $logdir          = "/var/log/rbackup";
my $logfile         = $logdir."/rbackup.log";
my $options         = "-v --info=BACKUP,COPY,DEL -a -R -z --delete --force --ignore-errors";
my $debug           = 0;

########### Do not edit below ###########
sub script_dir {
	my $dir = $0;
	$dir =~ s|/[^/]+$||;
	return ($dir eq $0) ? '.' : $dir;
}
my ($o_verb, $o_help, $o_test, $o_debug, $o_run, $o_config, $o_stats, $o_hosts, $o_host,
    $o_list_files, $o_list_active_files, $o_list_archived_files);

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

# Load config file
sub LoadConfig($){
	my ($file) = @_;

	open(my $fh, '<', $file) or die "Cannot open config file $file: $!\n";

	my $section = '';
	while(my $line = <$fh>){
		chomp $line;
		$line =~ s/^\s+|\s+$//g;
		next if $line =~ /^#/ || $line eq '';

		if($line =~ /^\[(.+)\]$/){
			$section = $1;
		} elsif($line =~ /^(\S+)\s*=\s*(.*)$/){
			my ($key, $val) = ($1, $2);
			$val =~ s/\s+$//;

			if($section eq 'global'){
				if    ($key eq 'backup_dir')      { $backup_dir = $val }
				elsif ($key eq 'logdir')          { $logdir = $val; $logfile = "$logdir/rbackup.log" }
				elsif ($key eq 'ssh_key')         { $ssh_key = $val }
				elsif ($key eq 'ssh_known_hosts') { $ssh_known_hosts = $val }
				elsif ($key eq 'options')         { $options = $val }
			} elsif($section ne ''){
				if($key eq 'include' || $key eq 'exclude'){
					my @vals = split(/\s*,\s*/, $val);
					@vals = map { my $v = $_; $v =~ s/^\s+|\s+$//g; $v } @vals;
					$hosts{$section}{$key} = \@vals;
				} else {
					$hosts{$section}{$key} = $val;
				}
			}
		}
	}
	close($fh);
}

# Input validation
sub check_options {
	Getopt::Long::Configure ("bundling");
	GetOptions(
		'v'     => \$o_verb,    'verbose' => \$o_verb,
		'h'     => \$o_help,    'help'    => \$o_help,
		'd'     => \$o_debug,   'debug'   => \$o_debug,
		't'     => \$o_test,    'test'    => \$o_test,
		'r'     => \$o_run,     'run'     => \$o_run,
		's'     => \$o_stats,   'stats'   => \$o_stats,
		'H'     => \$o_hosts,   'hosts'   => \$o_hosts,
		'host=s'             => \$o_host,
		'list-files'         => \$o_list_files,
		'list-active-files'  => \$o_list_active_files,
		'list-archived-files'=> \$o_list_archived_files,
		'c=s'                => \$o_config,  'config=s' => \$o_config,
	);

	if(defined($o_help)){
		help();
		exit 1;
	}

	my $config_file = $o_config || script_dir()."/rbackup.conf";
	LoadConfig($config_file);

	if(defined($o_debug)){
		$debug=1;
	}
	if(defined($o_test)){
		$options .= " -n";
		print "Dry run\n";
	}

	if(defined($o_run)){
		RunBackup();
	} elsif(defined($o_stats)){
		RunStats();
	} elsif(defined($o_hosts)){
		ListHosts();
	} elsif(defined($o_list_files)){
		RunListFiles('all');
	} elsif(defined($o_list_active_files)){
		RunListFiles('active');
	} elsif(defined($o_list_archived_files)){
		RunListFiles('archived');
	} else {
		help();
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
-s, --stats
        Show backup statistics per host
-H, --hosts
        List configured hosts with include/exclude paths
--host=HOSTNAME
        Limit -r, -s, or file listing to a single host
--list-files
        List all files (active and archived) per host
--list-active-files
        List files in the current/active backup per host
--list-archived-files
        List archived/differential files grouped by revision per host
-c, --config
        Path to config file (default: rbackup.conf in script directory)
-h, --help
	print this help message
EOT
}

sub print_usage() {
        print "Usage: $0 [-v] [-c config] -r\n";
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

	if($sec < 10){
		$sec = "0$sec";
	}

	return ($sec,$min,$hour,$day,$month,$year);
}

sub ListHosts(){
	my @hosts = sort keys %hosts;

	if(!@hosts){
		print "No hosts configured.\n";
		return;
	}

	print "Configured Hosts\n";
	print "=" x 50 . "\n\n";

	foreach my $host (@hosts){
		print "Host: $host\n";

		my $ipaddr = $hosts{$host}{ipaddr};
		printf("  Connect        : %s\n", $ipaddr) if $ipaddr;
		printf("  Backup dir     : %s/%s\n", $backup_dir, $host);

		my @include = @{$hosts{$host}{include} || []};
		printf("  Include        : %s\n", join(", ", @include)) if @include;

		my @exclude = @{$hosts{$host}{exclude} || []};
		printf("  Exclude        : %s\n", join(", ", @exclude)) if @exclude;

		print "\n";
	}
}

sub FormatSize($){
	my ($bytes) = @_;
	return "0 B" unless $bytes;
	my @units = ('B', 'KB', 'MB', 'GB', 'TB');
	my $i = 0;
	while($bytes >= 1024 && $i < $#units){
		$bytes /= 1024;
		$i++;
	}
	return sprintf("%.1f %s", $bytes, $units[$i]);
}

sub Commify($){
	my ($n) = @_;
	$n = int($n);
	$n =~ s/(\d)(?=(\d{3})+$)/$1,/g;
	return $n;
}

sub RunStats(){
	if(!-d $backup_dir){
		print "Backup directory $backup_dir does not exist.\n";
		return;
	}

	my @hosts;
	if($o_host){
		if(!-d "$backup_dir/$o_host"){
			print "No backup found for $o_host in $backup_dir.\n";
			return;
		}
		@hosts = ($o_host);
	} else {
		opendir(my $dh, $backup_dir) or die "Cannot open $backup_dir: $!\n";
		@hosts = sort grep { !/^\./ && -d "$backup_dir/$_" } readdir($dh);
		closedir($dh);
	}

	if(!@hosts){
		print "No backups found in $backup_dir.\n";
		return;
	}

	print "Backup Statistics\n";
	print "=" x 50 . "\n\n";

	foreach my $host (@hosts){
		my $current_dir      = "$backup_dir/$host/current";
		my $differential_dir = "$backup_dir/$host/differential";

		print "Host: $host\n";
		printf("  Backup dir     : %s/%s\n", $backup_dir, $host);

		if(-d $current_dir){
			my $size_raw = `du -sb "$current_dir" 2>/dev/null`;
			my ($size)   = $size_raw =~ /^(\d+)/;
			$size ||= 0;

			my $file_count = `find "$current_dir" -type f 2>/dev/null | wc -l`;
			$file_count =~ s/^\s+|\s+$//g;

			my $newest_epoch = `find "$current_dir" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1`;
			chomp $newest_epoch;
			my $newest_str = "n/a";
			if($newest_epoch){
				my ($sec,$min,$hour,$day,$month,$year) = (localtime(int($newest_epoch)))[0,1,2,3,4,5];
				$newest_str = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $month+1, $day, $hour, $min, $sec);
			}

			printf("  Current backup : %s, %s files\n", FormatSize($size), Commify($file_count));
			printf("  Newest file    : %s\n", $newest_str);
		} else {
			print "  Current backup : not found\n";
		}

		if(-d $differential_dir){
			opendir(my $ddh, $differential_dir) or next;
			my @revisions = sort grep { !/^\./ && -d "$differential_dir/$_" } readdir($ddh);
			closedir($ddh);

			my $rev_count  = scalar @revisions;
			my $diff_size_raw = `du -sb "$differential_dir" 2>/dev/null`;
			my ($diff_size)   = $diff_size_raw =~ /^(\d+)/;
			$diff_size ||= 0;

			my $diff_files = `find "$differential_dir" -type f 2>/dev/null | wc -l`;
			$diff_files =~ s/^\s+|\s+$//g;

			printf("  Revisions      : %d (total %s, %s files)\n", $rev_count, FormatSize($diff_size), Commify($diff_files));
		} else {
			print "  Revisions      : none\n";
		}

		print "\n";
	}
}

sub PrintDirFiles($$){
	my ($dir, $indent) = @_;
	my @lines = `find "$dir" -type f -printf '%s\t%T@\t%P\n' 2>/dev/null | sort -k3`;
	if(!@lines){
		print "${indent}  (empty)\n";
		return;
	}
	foreach my $line (@lines){
		chomp $line;
		my ($size, $epoch, $path) = split(/\t/, $line, 3);
		my ($sec,$min,$hour,$day,$month,$year) = (localtime(int($epoch)))[0,1,2,3,4,5];
		my $date = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $month+1, $day, $hour, $min, $sec);
		printf("%s%-60s  %8s  %s\n", $indent, $path, FormatSize($size), $date);
	}
}

sub RunListFiles($){
	my ($type) = @_;

	if(!-d $backup_dir){
		print "Backup directory $backup_dir does not exist.\n";
		return;
	}

	my @hosts;
	if($o_host){
		if(!-d "$backup_dir/$o_host"){
			print "No backup found for $o_host in $backup_dir.\n";
			return;
		}
		@hosts = ($o_host);
	} else {
		opendir(my $dh, $backup_dir) or die "Cannot open $backup_dir: $!\n";
		@hosts = sort grep { !/^\./ && -d "$backup_dir/$_" } readdir($dh);
		closedir($dh);
	}

	if(!@hosts){
		print "No backups found in $backup_dir.\n";
		return;
	}

	foreach my $host (@hosts){
		my $current_dir      = "$backup_dir/$host/current";
		my $differential_dir = "$backup_dir/$host/differential";

		print "Host: $host\n";

		if($type eq 'active' || $type eq 'all'){
			print "  [active]\n" if $type eq 'all';
			if(-d $current_dir){
				PrintDirFiles($current_dir, "  ");
			} else {
				print "  No active backup found.\n";
			}
		}

		if($type eq 'archived' || $type eq 'all'){
			print "  [archived]\n" if $type eq 'all';
			if(-d $differential_dir){
				opendir(my $ddh, $differential_dir) or next;
				my @revisions = sort grep { !/^\./ && -d "$differential_dir/$_" } readdir($ddh);
				closedir($ddh);
				if(@revisions){
					foreach my $rev (@revisions){
						print "  [$rev]\n";
						PrintDirFiles("$differential_dir/$rev", "    ");
					}
				} else {
					print "  No archived files.\n";
				}
			} else {
				print "  No archived files.\n";
			}
		}

		print "\n";
	}
}

sub RunBackup(){
	open(LOG, ">>$logfile") or die "Cannot open log $logfile: $!\n";
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

	my @run_hosts;
	if($o_host){
		if(!exists $hosts{$o_host}){
			die "Host '$o_host' not found in config.\n";
		}
		@run_hosts = ($o_host);
	} else {
		@run_hosts = keys %hosts;
	}

	foreach my $host (@run_hosts){
		my $user = $hosts{$host}{"user"};
		printlog("Backing up $host with user $user");
		if(!$user){
			printlog("Error: user for $host is missing");
			next;
		}

		my $target = $hosts{$host}{"ipaddr"} || $host;

		my $host_backup_root = $backup_dir."/".$host;
		my $host_backup_dir = $host_backup_root."/current/";
		DirExists($host_backup_root);
		DirExists($host_backup_dir);

		my @include = @{$hosts{$host}{include} || []};
		my @exclude = @{$hosts{$host}{exclude} || []};
		my $include_str = ArrayToInclude(@include);
		my $exclude_str = ArrayToExclude(@exclude);

		my ($sec,$min,$hour,$day,$month,$year) = gettime();
		my $backup_suffix = "$year-$month-$day-$hour-$min";

		my $cmd = "/usr/bin/rsync --delete-excluded $ssh_extra ".$exclude_str." --backup --backup-dir=$host_backup_root/differential/$backup_suffix --stats $options $user\@".$target.$include_str." $host_backup_dir > $logdir/".$host."-".$backup_suffix.".log";
		print "$cmd\n" if $debug;
		printlog("Syncing: $cmd");
		open(CMD, "$cmd|");
		close(CMD);
		printlog("Syncing: Finished");
	}
	printlog("Backup finished");
	close(LOG);
}


### Main
check_options();
