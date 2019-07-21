#!/usr/bin/perl -w
use strict;
use threads;
use Thread::Queue;

my $usage = "\nFilter HelitronScanner fasta candidates
	perl flanking_filter_.pl -genome genome.fa -query candidate.fa [options]
		-genome	[file]	The multifasta file that used to generate the -query
		-query	[file]	The candidate TE sequence to be filtered by this script
		-extlen	[int]	The length of extended flanking sequence in -query. Default: 30 (bp)
		-tgt_out	[int]	Output taget site with [int] length on each terminal. Default: 15 (bp)
		-miniden	[int]	Minimum identity for flanking sequence alignment. Default: 80 (%)
		-mincov	[float]	Minimum coverage for flanking sequence alignment that counts as full match. Default: 0.8
		-maxct	[int]	Maximum allowed copy number for flanking sequence for a true element. Default: 1.
		-blastplus	[path]	Path to the blastn program. Defalut: read from \$ENV
		-t|-threads	[int]	Number of threads to run this program. Default: 4
		-h|-help	Display this help messege and exit.
\n";

my $genome = '';
my $query = '';
my $ext_len = 30; #extend 30 bp on each end
my $tgt_out = 15; #output taget site with this length on each terminal
my $min_iden = 80; #minimum identity for flanking sequence alignment (%)
my $min_cov = 0.8; #minimum coverage for flanking sequence alignment that counts as full match
my $max_ct = 1; #maximum allowed copy number for flanking sequence. Either side exceeding this number will expire the candidate
my $blastplus = ''; #path to the blastn program
my $threads = 4; #threads to run this program

my $k=0;
foreach (@ARGV){
	$genome = $ARGV[$k+1] if /^-genome$/i;
	$query = $ARGV[$k+1] if /^-query$/i;
	$ext_len = $ARGV[$k+1] if /^-extlen$/i;
	$tgt_out = $ARGV[$k+1] if /^-tgt_out$/i;
	$min_iden = $ARGV[$k+1] if /^-miniden$/i;
	$min_cov = $ARGV[$k+1] if /^-mincov$/i;
	$max_ct = $ARGV[$k+1] if /^-maxct$/i;
	$blastplus = $ARGV[$k+1] if /^-blastplus$/i;
	$threads = $ARGV[$k+1] if /^-t$|^-threads$/i;
	die $usage if /^-h$|^-help$/i;
	$k++;
	}

die "The genome file $genome is not found!\n$usage" unless -e $genome;
die "The query file $query is not found!\n$usage" unless -e $query;

## make blast db for $genome
`${blastplus}makeblastdb -in $genome -out $genome -dbtype nucl 2> /dev/null`;

open Query, "<$query" or die $usage;
open Out, ">$query.cov${min_cov}iden$min_iden.tabout";
open Seq, ">$query.pass.fa";
print Out "#Decision\t5'count\t3'count\tflank_count\tChr\tStart\tEnd\tLOC\t5'flank\t5'seq\t3'seq\t3'flank\n";

## Store sequence information
my @FA;
$/ = "\n>";
while (<Query>){
	chomp;
	s/>//g;
	my ($name, $seq) = (split /\n/, $_, 2);
	$seq =~ s/\s+//g;
	$seq = uc $seq;
	push @FA, [$name, $seq];
	}
$/ = "\n";
close Query;

## multi-threading using queue, put candidate LTRs into queue for parallel computation
my $queue = Thread::Queue->new();
my $i = 0;
while ($i <= $#FA) {
	last unless defined $FA[$i]->[0];
	my ($name, $seq) = @{$FA[$i]}[0,1];
	$queue->enqueue([$name, $seq]);
	$i++;
	}

## initiate a number of worker threads
my @threads = ();
foreach (1..$threads){
	push @threads,threads->create(\&filter);
	}
foreach (@threads){
	$queue->enqueue(undef);
	}
foreach (@threads){
	$_->join();
	}

## fixing the formatting error created by simutaniously writing the same file
`perl -i -nle 's/>/\\n>/g unless /^>/; print \$_' $query.pass.fa`;

## remove database
`rm $genome.nhr $genome.nin $genome.nsq 2> /dev/null`;




## subrotine for helitron candidate analyses
sub filter(){
	while (defined($_ = $queue->dequeue())){
	my ($name, $seq) = (@{$_}[0], @{$_}[1]);
	my ($chr, $str, $end) = ($1, $2, $3) if $name =~ /^(.*):([0-9]+)\.\.([0-9]+)/;
	my $loc = "$chr:$str..$end";

	my ($flank5, $flank3, $seq5, $seq3, $ori_seq, $tgt_ste) = ('','','','','','');
	$flank5 = substr $seq, 0, $ext_len;
	$flank3 = substr $seq, -$ext_len;
	$seq5 = substr $seq, $ext_len, 30;
	$seq3 = substr $seq, -($ext_len+30), 30;
	$ori_seq = substr $seq, $ext_len, -$ext_len;
	$tgt_ste = (substr $flank5, -$tgt_out)."*".(substr $flank3, 0, $tgt_out);
	$tgt_ste = uc $tgt_ste;

	# filter out candidates based on repetitiveness of flanking sequence
	my $decision = "true";

	# count copy number of the 5' end
	my $end5_repeat = "false";
	my $end5 = ">end5\\n$flank5"."$seq5";
	my $end5_len = length "$flank5"."$seq5";
	my $exec = "${blastplus}blastn -db $genome -query <(echo -e \"$end5\") -outfmt 6 -word_size 7 -evalue 1e-5 -dust no";
#	my $exec = "${blastplus}blastn -subject $genome -query <(echo -e \"$end5\") -outfmt 6 -word_size 7 -evalue 1e-5 -dust no";
	my @blast_end5 = ();
	my $try = 0;
	while ($try < 100){ #try 100 times to guarantee the blast is run correctly
		@blast_end5 = qx(bash -c '$exec' 2> /dev/null) if defined $end5;
		last if $? == 0;
		$try++;
		}
	my $end5_count = 0;
	foreach (@blast_end5){
		my ($iden, $len) = (split)[2,3];
		$end5_count++ if $iden >= $min_iden and $len >= $end5_len * $min_cov;
		($end5_repeat = "true", $decision = "false") if $end5_count > $max_ct;
		}

	# count copy number of the 3' end
	my $end3_repeat = "false";
	my $end3 = ">end3\\n$seq3"."$flank3";
	my $end3_len = length "$seq3"."$flank3";
	$exec = "${blastplus}blastn -db $genome -query <(echo -e \"$end3\") -outfmt 6 -word_size 7 -evalue 1e-5 -dust no";
#	$exec = "${blastplus}blastn -subject $genome -query <(echo -e \"$end3\") -outfmt 6 -word_size 7 -evalue 1e-5 -dust no";
	my @blast_end3 = ();
	$try = 0;
	while ($try < 100){
		@blast_end3 = qx(bash -c '$exec' 2> /dev/null) if defined $end3;
		last if $? == 0;
		$try++;
		}
	my $end3_count = 0;
	foreach (@blast_end3){
		my ($iden, $len) = (split)[2,3];
		$end3_count++ if $iden >= $min_iden and $len >= $end3_len * $min_cov;
		($end3_repeat = "true", $decision = "false") if $end3_count > $max_ct;
		}

	# count copy number of the 5' and 3' flanking. If $count>=1, then this candidate locates at a TE and should be a true helitron
	my $flank_count = "NA";
	if ($end5_repeat eq "true" and $end3_repeat eq "true"){
		my $flank = ">flank\\n$flank5"."$flank3";
		my $flank_len = length "$flank5"."$flank3";
		$exec = "${blastplus}blastn -db $genome -query <(echo -e \"$flank\") -outfmt 6 -word_size 7 -evalue 1e-5 -dust no";
#		$exec = "${blastplus}blastn -subject $genome -query <(echo -e \"$flank\") -outfmt 6 -word_size 7 -evalue 1e-5 -dust no";
		my @blast_flank = ();
		$try = 0;
		while ($try < 100){
			@blast_flank = qx(bash -c '$exec' 2> /dev/null) if defined $flank;
			last if $? == 0;
			$try++;
			}
		$flank_count = 0;
		foreach (@blast_flank){
			my ($iden, $len) = (split)[2,3];
			$flank_count++ if $iden >= $min_iden and $len >= $flank_len * $min_cov;
			}
		$decision = "true" if $flank_count >= 1;
		}

	print Out "$decision\t$end5_count\t$end3_count\t$flank_count\t$chr\t$str\t$end\t$loc\t$tgt_ste\t$flank5\t$seq5\t$seq3\t$flank3\n";
	print Seq ">$chr:$str..$end\n$ori_seq\n" if $decision eq "true";
	}
	}
close Out;
close Seq;

