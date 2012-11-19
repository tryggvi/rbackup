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

#### Settings
#
# Server information
my $server = "server.domain.com";
my $ssh_user = "user";

#
my $email=0; # Send email when finished
my $email_to = "test\@domain.com";
my $email_from = "Backup client <root\@domain.com>";
my $email_subject = "Rsync backup for {HOSTNAME}"; # {HOSTNAME} will be replaced for hostname of the server
#
my $logfile = "/var/log/rbackup.log"; # Log file
my $outfile = "/var/log/rbackup-out.log"; # Output of rsync cmd for last session
# Directories to backup
my @backup_dir = (
	"/"
);
#
# Files and directories to exclude

my @exclude = (
	"/tmp",
	"/proc",
	"/sys",
	"/dev",
);
#
# Misc
my $options = "-v -a -R -z --delete --force --ignore-errors";
my $debug = 0;

########### Do not edit below ###########
open(LOG, ">>$logfile");
printlog("===========================");
printlog("Starting backup");
my @timestruct = (localtime(time()));
my $weekday = $timestruct[6];
my $weekday_name = getWeekDay($weekday);

# Prep backup dirs
my $bdir;
for(my $i=0; $i < scalar(@backup_dir); $i++){
	my $line = $backup_dir[$i];
	if($line){
		if(!$bdir){
			$bdir = $line;
		} else {
			$bdir = "$bdir $line";
		}
	}
}

# Prep exclude
my $exclude;
for(my $i=0; $i < scalar(@exclude); $i++){
	my $line = $exclude[$i];
	if($line){
		if(!$exclude){
			$exclude = "--exclude=$line";
		} else {
			$exclude = "$exclude --exclude=$line";
		}
	}
}

# Clear last incremental directory
my $tmp = time();
my $tmpdir = "/tmp/$tmp-rback";
printlog("Incremeantal delete: Creating tmp dir $tmpdir");
if(!-d $tmpdir){
	mkdir $tmpdir, 0700;
	my $cmd = "/usr/bin/rsync --delete -a $tmpdir/ $ssh_user\@$server:$weekday_name/";
	printlog("Incremental delete: executing $cmd");
	print "Incremental delete cmd: $cmd\n" if $debug;
	open(CMD, "$cmd|");
	close(CMD);
	system("/bin/rm -rf $tmpdir");
	printlog("Incremental delete: Removing $tmpdir");
}

# Sync data
my $cmd= "/usr/bin/rsync --delete-excluded $exclude --backup --backup-dir=$weekday_name --stats $options $bdir $ssh_user\@$server:current > $outfile";
print "$cmd\n" if $debug;
printlog("Syncing: $cmd");
open(CMD, "$cmd|");
close(CMD);
printlog("Syncing: Finished");
if($email){
	open(OUT, $outfile);
	my $output = "Transfer summary:";
	my $on=0;
	while(<OUT>){
		# Search for empty line and use the rest of the file 
		# for transfer summary
		chomp($_);
		if($on){
			$output = "$output\n$_";
		}

		if($_ eq ""){
			$on=1;
		}
	}
	close(OUT);

	# Send email to backup admins
	my $hostname = get_hostname();
	$email_subject =~ s/{HOSTNAME}/$hostname/g;
	sendmail($email_to, $email_from, $email_subject, $output);
	printlog("Reporting: Sending email to $email_to from $email_from");
}

close(LOG);

sub sendmail($$$$){
	my($to, $from, $subject, $body) = @_;
	open (MAIL, "|/usr/sbin/sendmail $to");
		print MAIL "To: $to\n";
		print MAIL "From: $from\n";
		print MAIL "Subject: $subject\n\n";
		print MAIL "$body";
	close(MAIL);
}

sub getWeekDay($) {
	my $val = $_[0];
	if( $val > 6 ) {
		return 0;
	}
	return (qw(sun mon tue wed thu fri sat))[$val];
}

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

sub printlog($){
	my($text) = @_;
	my ($sec,$min,$hour,$day,$month,$year) = gettime();
	print LOG "$year-$month-$day $hour:$min:$sec $text\n";
}

sub get_hostname(){
	my $hostname = `/bin/hostname`;
	chomp($hostname);
	return $hostname;
}

