#!/usr/bin/perl

#
# Extract files from chromium cache
#
# By Jean-Francois Stenuit, 
# Tested under Ubuntu 16.04
#
# File format reference :
#  https://chromium.googlesource.com/chromium/src/+/master/net/disk_cache/simple/simple_entry_format.h
#

use strict;
use warnings;

use Compress::Raw::Zlib;
use File::Basename;
use File::Path qw(make_path);
use Getopt::Long;
use Pod::Usage;

my $cachedir=$ENV{'HOME'}.'/.cache/chromium/Default/Cache';
my $filter='';
my $destination='.';
my $help=0;

GetOptions('cachedir=s'=>\$cachedir ,
	'filter=s'=>\$filter,
	'destination=s'=>\$destination,
	'help|?'=>\$help);

pod2usage(1) if $help;

my $re=($filter ne '')?qr/$filter/:undef;

opendir(my $dh, $cachedir) || die "Can't open $cachedir: $!";
my @files = grep { /_[01]$/ && -f "$cachedir/$_" } readdir($dh);
closedir $dh;

foreach my $f (@files) {
	process("$cachedir/$f");
}

exit(0);

sub process {
	my ($fn)=@_;

	open(my $fh,"<",$fn) or die "Can't open $fn : $!";
	read $fh,my $buffer,8;
	if ($buffer ne "\x30\x5c\x72\xa7\x1b\x6d\xfb\xfc") {
		print STDERR "Not a cache entry $fn\n";
		close($fh);
		return;
	}
	read $fh,$buffer,16;
	my ($ver,$sz,$hash,$void)=unpack("VVVV",$buffer);

	read $fh,$buffer,$sz;
	my ($host, $port, $path) = $buffer =~ m!https?://([^:/]+)(:\d+/)?(/[^\?]+)!;

#	return unless (defined($host) && ($host eq 'sample.org'));

	if ($re) {
		return unless ( $buffer =~ /$re/ ) ;
	}

	my ($filename, $dirs, $suffix) = fileparse($host.$path);
	print STDERR "$dirs   >>>   $filename\n";

	undef $buffer; my $content; my $end_of_stream=-1;
	while(($end_of_stream<0) && (read($fh,$buffer,1024)>0)) {
		$content.=$buffer;
		$end_of_stream=index($content,"\xd8\x41\x0d\x97\x45\x6f\xfa\xf4");
		undef $buffer;
	}
	if ((length($content)-$end_of_stream)<16) {
		read($fh,$buffer,16-(length($content)-$end_of_stream));
		$content.=$buffer;
	}
	$buffer=substr($content,$end_of_stream+8,16);
	($ver,$hash,$sz,$void)=unpack("VVVV",$buffer);

	$content=substr($content,0,$end_of_stream);

	my ($d, $status) = new Compress::Raw::Zlib::Inflate( -ConsumeInput => 0, -WindowBits => WANT_GZIP_OR_ZLIB );
	$status = $d->inflate($content, my $output) ;

	close($fh);

	make_path($dirs);
	open($fh,">".$dirs.$filename);
	print $fh $output;
	close($fh);
}

__END__

=head1 NAME

chromcache - Export content of Chromium cache

=head1 SYNOPSIS

chromcache.pl [--cachedir=dir] [--filter=filter] [--destination=dir]

=head1 OPTIONS

=over 8

=item B<--cachedir>

Location of chromium cache - defaults to ${HOME}/.cache/chromium/Default/Cache

=item B<--filter>

Only save cache items whose URL match this regexp

=item B<--destination>

Save content to this directory (default to current directory - '.')

=back

=head1 DESCRIPTION

B<This program> will save chromium cache content to specific location

=cut
