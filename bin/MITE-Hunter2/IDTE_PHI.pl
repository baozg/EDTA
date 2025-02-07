#!/usr/local/bin/perl -w
# Written by vehell
# 12/22/2009
# 1) When there are too many copies, only handle 10 times of the $Max_Output of them: last if($Num > $Max_Output * 10); 
# 2) Add Max overlap as a new parameter and set default value as 30
# 3) Add 0.01 to start or end positions to avoid mutiple matches use the same position: $S_Begin_Adjusted and $S_End_Adjusted
# 12/10/2009
# delete the function of "check whether there is another homolog copy at the same locus" because for IDTE, there always is only querry sequnce at one time
# This part is also the slowest part when there are many copies, improve it later...
# 11/26/2009
# sort the homologs before output
# 2009-11-23
# add the missing last base pair
# 11/22/2009
# update it to accept 0 flanking length
# 11/10/2009 Add a parameter: Sub_Region_Len. Before that, it was always 100, which caused problem
# 10/30/2009 modify e value comparier
# 6/8/107
#------
# update to make it can find data for both protein and DNA alignment
#------
# write a single vertion to get rid of long introns, improve it later
#
#-----------------------------------------------------
use Getopt::Std;
#-----------------------------------------------------
getopts("i:q:D:e:M:d:I:n:l:r:s:L:o:h:");

$Input          = defined $opt_i ? $opt_i : "";
$Query_File     = defined $opt_q ? $opt_q : "soymar1.aa";
$Sbjct_File     = defined $opt_D ? $opt_D : "/scratch/vehell/Data_Room/Rice/rice";
$Max_Evalue     = defined $opt_e ? $opt_e : 0.01; 
$Min_Pro        = defined $opt_M ? $opt_M : 0.7;
$Max_Intron     = defined $opt_d ? $opt_d : 8000;
$ID_Tag         = defined $opt_I ? $opt_I : "ZMmar";
$Max_Output     = defined $opt_n ? $opt_n : 30;
$Flank_L        = defined $opt_l ? $opt_l : 60;
$Flank_R        = defined $opt_r ? $opt_r : 60;
$Sub_Region_Len = defined $opt_s ? $opt_s : 0;
$Max_Overlap    = defined $opt_L ? $opt_L : 30;
$Output         = defined $opt_o ? $opt_o : "protein_copies";
$Help           = defined $opt_h ? $opt_h : "";

usuage() if((!$Input)||($Help));

#--------------------------------------------------------
#--------------- In this script, given E value is parsed into scitisfic notion if it < 1. 
#--------------- if given E >= 1 will be kept the same
#--------------- an e evalue that has "e" would be considered smaller than one doesn't
if($Max_Evalue =~ /e/) {
	
}elsif($Max_Evalue =~ /^0\./){
	$Power_Num = 0;
	while($Max_Evalue < 1) {
		$Max_Evalue *= 10;
		$Power_Num ++;
	}
	$Max_Evalue = $Max_Evalue."e-".$Power_Num;
}

#--------------------------------------------------------


#-------------- load query sequences --------------------
open(QF, "$Query_File")||die "$!\n";
while(<QF>) {
	$Line = $_;
	if(/^>(\S+)/) {
		$Name = $1;
	}else{
		$Line =~ s/\s+$//g;
		$Query_Name_Seq{$Name} .= $Line;
	}
}
close(QF);

foreach(keys(%Query_Name_Seq)) {
	$Query_Length{$_} = length($Query_Name_Seq{$_});
}

#-----------------Load blast result---------------------------------
print "Load blast result\n";
tblastn_loader($Input);

#------------------------------------ find the putative connections among blast hits -------------
print "find the putative connections among blast hits\n";
foreach(keys(%Query_Sbjcts)) {  
	$Query = $_;
	@Matched_Sbjcts = split(/ /, $Query_Sbjcts{$_});
	foreach(@Matched_Sbjcts) {
		$Sbjct           = $_;

		%B_E_For         = ();
		%B_E_Rev         = ();
		@S_Begins_Plus   = ();
		@S_Begins_Minus  = ();
		@Begins_Sorted   = ();
		%First_Score     = ();
		$Plus_Match_Num  = 0;
		$Minus_Match_Num = 0;

		@Match_Pairs = split(/   /, $Query_Sbjct_Matches{$Query." ".$Sbjct});

		foreach(@Match_Pairs) {

			($Query_Info, $Sbjct_Info)  = split(/  /, $_);             # $Match_Info = $Q_Begin." ".$Q_Match." ".$Q_End."  ".$S_Begin." ".$S_Match." ".$S_End."   ";
			($Q_Begin, $Q_Match, $Q_End) = split(/ /, $Query_Info);    # $Q_Begin." ".$Q_Match." ".$Q_End
			($S_Begin, $S_Match, $S_End, $Frame, $Score) = split(/ /, $Sbjct_Info);
			
			if($Frame > 0) {
				$S_Begin_Adjusted = $S_Begin;
				while(defined($B_E_For{$S_Begin_Adjusted})) {
					$S_Begin_Adjusted += 0.01;
				}
				$B_E_For{$S_Begin_Adjusted} = $Q_Begin." ".$Q_Match." ".$Q_End." ".$S_Begin_Adjusted." ".$S_Match." ".$S_End." ".$Frame." ".$Score;

				push(@S_Begins_Plus, $S_Begin_Adjusted);
				$Plus_Match_Num ++;
			}else{
				$S_End_Adjusted = $S_End;
				while(defined($B_E_For{$S_End_Adjusted})) {
					$S_End_Adjusted += 0.01;
				}
				$B_E_Rev{$S_End_Adjusted} = $Q_Begin." ".$Q_Match." ".$Q_End." ".$S_Begin." ".$S_Match." ".$S_End_Adjusted." ".$Frame." ".$Score;
				
				push(@S_Begins_Minus, $S_End_Adjusted); 
				$Minus_Match_Num ++;
			}
		}

		# Plus Direction: sort the matched segments in small to big order, using sbjct matched locations as hash keys
		@Begins_Sorted = sort {$a <=> $b} @S_Begins_Plus;   
		$Copy_Start = 0;
		for($i = 0; $i < $Plus_Match_Num; $i ++) {
			$Begin_Adj = $Begins_Sorted[$i];
			($Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Score) = split(/ /, $B_E_For{$Begin_Adj});

			if($Copy_Start == 0) {
				#-------------------------------- find the beginning part of each copy 
				$New_Start  = 1;
				$Copy_Start = 1;
			}else{
				if($S_Begin - $Pre_S_End > $Max_Intron) {
					# ---------------------------------- end of the putative copy, reason: sbjct locs too far away
					$New_Start = 1;
				}elsif($Q_Begin + $Max_Overlap > $Pre_Q_End) {
					# ---------------------------------- connect plus seperated matches(exons)
					$New_Start = 0;
				 }else{
					# ---------------------------------- end of the putative copy, reason: new copy start begins
					$New_Start = 1;
				}
			 }
			
			if($New_Start == 1) {
#				print "New Start: $S_Begin\t$Begins_Sorted[$i]\t$S_Begin\t$S_Match\t$S_End\t$Frame\n";
				$Start_Loc = $S_Begin;
				if(defined($Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc})) {
					if($Score > $First_Score{$Start_Loc}) {
						$Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc} = $B_E_For{$Begin_Adj}."  ";
						$First_Score{$Start_Loc} = $Score;
					}
				}else{
					if(!(defined($B_E_For{$Begin_Adj}))) {
						print "not defined: $S_Begin\t$Begins_Sorted[$i]\t$S_Begin\t$S_Match\t$S_End\t$Frame\n";
					}
					$Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc} = $B_E_For{$Begin_Adj}."  ";
					$First_Score{$Start_Loc} = $Score;
				}
			}else{
				$Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc} .= $B_E_For{$Begin_Adj}."  ";
#				print "$B_E_For{$Begin_Adj}\n";
			}

			$Pre_Q_Begin = $Q_Begin;
			$Pre_S_Begin = $S_Begin;
			$Pre_Q_End   = $Q_End;
			$Pre_S_End   = $S_End;
			$Pre_Dir     = $Dir;
		}

		# Minus Direction: sort the matched segments in small to big order, using sbjct matched locations as hash keys
		@Begins_Sorted = sort {$a <=> $b} @S_Begins_Minus;   
		$Copy_Start = 0;
		for($i = 0; $i < $Minus_Match_Num; $i ++) {
			$Begin_Adj = $Begins_Sorted[$i];

			($Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Score) = split(/ /, $B_E_Rev{$Begin_Adj});
#			print "$Begins_Sorted[$i]: $Q_Begin, $Q_End, $S_Begin, $S_End, $Frame, $Score\n";
			
			if($Copy_Start == 0) {
				#-------------------------------- find the beginning part of each copy 
				$New_Start  = 1;
				$Copy_Start = 1;
			}else{
				if($S_End - $Pre_S_Begin > $Max_Intron) {
					# ---------------------------------- end of the putative copy, reason: sbjct locs too far away
					$New_Start = 1;
				}elsif($Pre_Q_Begin + $Max_Overlap > $Q_End) {
					# ---------------------------------- connect minus seperated matches(exons)
					$New_Start = 0;
				 }else{
					# ---------------------------------- end of the putative copy, reason: new copy start begins
					$New_Start = 1;
				  }
			 }
			
			if($New_Start == 1) {
				$Start_Loc = $S_End;
				if(defined($Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc})) {
					if($Score > $First_Score{$Start_Loc}) {
						$Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc} = $B_E_Rev{$Begin_Adj}."  ";
						$First_Score{$Start_Loc} = $Score;
					}
				}else{
					$Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc} = $B_E_Rev{$Begin_Adj}."  ";
					$First_Score{$Start_Loc} = $Score;
				}
			}else{
				$Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Start_Loc} .= $B_E_Rev{$Begin_Adj}."  ";
			}

			$Pre_Q_Begin = $Q_Begin;
			$Pre_S_Begin = $S_Begin;
			$Pre_Q_End   = $Q_End;
			$Pre_S_End   = $S_End;
			$Pre_Dir     = $Dir;
		}
	}
}

#----------------------- read the location information for reading DNA sequences later ------------------------------
print "read the location information for reading DNA sequences later\n";
open(SF, "$Sbjct_File")||die "Can not open database!\n";
open(IF, $Sbjct_File.".index")||die "The sbject fasta file has not been indexed?!\n";

while(<IF>) {
      chomp;
      ($Name, $Loc) = split(/ /, $_);
      $Location_Info{$Name} = $Loc;
}      
close(IF);   

#----------------------find the longest/best homolog for each loc in genome (when there are mutiple queries) ...
print "find the longest/best homolog for each loc in genome\n";
$Num = 0;
foreach(keys(%Query_Sbjct_Copy_Infor)) {
#	print "$_ -> $Query_Sbjct_Copy_Infor{$_}\n";
	($Query, $Sbjct, $Start_Loc) = split(/ /, $_);
	$Query_Len = $Query_Length{$Query};
	$Copy_Score = 0;
	$Copy_Len   = 0;
	@Matches = split(/  /, $Query_Sbjct_Copy_Infor{$_});
	
	@Query_Match_Region = ();
	for($i = 0; $i < $Query_Len; $i++) {
		$Query_Match_Region[$i] = 0;
	}

	foreach(@Matches) {
		($Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Score) = split(/ /, $_);

		$Copy_Score += $Score;

		for($i = $Q_Begin; $i < $Q_End; $i ++) {
			$Query_Match_Region[$i-1] = 1;
		}
	}
	$Stop_Loc = $S_Begin < $S_End ? $S_End : $S_Begin;
	
	foreach(@Query_Match_Region) {
		$Copy_Len ++ if($_ == 1);
	}

	next if($Copy_Len/$Query_Len < $Min_Pro);

	if(defined($Sbjct_Copies{$Sbjct})) {
		$Sbjct_Copies{$Sbjct} .= $Query." ".$Copy_Len." ".$Start_Loc." ".$Stop_Loc." ".$Copy_Score."  ";
	}else{
		$Sbjct_Copies{$Sbjct} = $Query." ".$Copy_Len." ".$Start_Loc." ".$Stop_Loc." ".$Copy_Score."  ";
	}

	$Num ++;
	last if($Num > $Max_Output * 10);
}

#--------------------------- output files -----------------
open(OF, ">$Output.flank")||die"$!\n";

#----------------  for each sbjct ------------------
print "dealing with each sbjct\n";
foreach(keys(%Sbjct_Copies)) {
	$Sbjct = $_;
	$Sbjct_Len = $Sbjct_Length{$Sbjct};
	#----------------- for each copy --------------------
	@Copies = split(/  /, $Sbjct_Copies{$Sbjct});
#	print "Sbjct: $Sbjct\n";
	foreach(@Copies) {
#		print "Copy: $_\n";
		($Query, $Copy_Len, $Copy_Begin, $Copy_End, $Copy_Score) = split(/ /, $_);
		$Query_Len = $Query_Length{$Query};
		#---------------------- filter out low quality copies --------------------------------
		next if($Copy_Len/$Query_Len < $Min_Pro);

		@Matches = split(/  /, $Query_Sbjct_Copy_Infor{$Query." ".$Sbjct." ".$Copy_Begin});

		#----------------------------- sorting exons. in this step, it will find the most reliable path along the query, neglect those false matches ------------
		$Empty = 1;
		foreach(@Matches) {
			$Empty = 0;
		}
		if($Empty == 1) {
			print "it is empty!\n";
			exit(0);
		}
#		print "Finding path ... \n";
		$Most_Possible_Path = path_finder();
#		print "Path found!\n";
		@Matches = ();
		@Sorted_Alignments = split(/ +/, $Most_Possible_Path);
		foreach(@Sorted_Alignments) {
			next if(($_ eq "Begin")||($_ eq "End"));
			$Match_Infor = $ID_Match{$_};
			push(@Matches, $Match_Infor);
		}

		$Begin_Fix = 0;
		$End_Fix   = 0;
		$Copy_Len  = 0;
		foreach(@Matches) {
			next if($_ eq "none");
			($Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame) = split(/ /, $_);
			$S_Begin = int($S_Begin);
			$S_End   = int($S_End);
			if($S_Begin < $S_End) {
				if($S_Begin == $Copy_Begin) {
					$Begin_Fix = $Q_Begin - 1;
				}
				if($S_End == $Copy_End) {
					$End_Fix = $Query_Len - $Q_End;
				}
			}else{
				if($S_Begin == $Copy_End) {
					$End_Fix = $Q_Begin - 1;
				}
				if($S_End == $Copy_Begin) {
					$Begin_Fix = $Query_Len - $Q_End;
				}
			}
			$Copy_Len += length($Q_Match);
		}

		# ------------------------- filter out short copies ---------------------
		next if($Copy_Len/$Query_Len < $Min_Pro);
		# -------------------------------- find corrosposing DNA sequences  ---------------------------------
		$Copy_Begin -= $Begin_Fix;
		$Copy_End   += $End_Fix;

		#--------------------------- find DNA copies with flanking regions ----------------------
		if(($Copy_Begin - $Flank_L < 0)||($Copy_End + $Flank_R > $Sbjct_Len)) {

		}else{
			if(($Sub_Region_Len == 0)||($Copy_End - $Copy_Begin < 2 * $Sub_Region_Len)) {
				if($S_Begin < $S_End) {
					$S_Flank_DNA = sbject_fasta_picker($Sbjct, $Copy_Begin - $Flank_L, $Copy_End - $Copy_Begin + $Flank_L + $Flank_R + 1);
				}else{
					$S_Flank_DNA = sbject_fasta_picker($Sbjct, $Copy_Begin - $Flank_R, $Copy_End - $Copy_Begin + $Flank_L + $Flank_R + 1);
					$S_Flank_DNA = DNA_reverser($S_Flank_DNA);
				}
			}else{
				if($S_Begin < $S_End) {
					$S_Flank_DNA_L = sbject_fasta_picker($Sbjct, $Copy_Begin - $Flank_L, $Sub_Region_Len + $Flank_L);
					$S_Flank_DNA_R = sbject_fasta_picker($Sbjct, $Copy_End - $Sub_Region_Len, $Sub_Region_Len + $Flank_R);
					$S_Flank_DNA   = $S_Flank_DNA_L.$S_Flank_DNA_R;
				}else{
					$S_Flank_DNA_L = sbject_fasta_picker($Sbjct, $Copy_Begin - $Flank_R + 1, $Sub_Region_Len + $Flank_R);
					$S_Flank_DNA_R = sbject_fasta_picker($Sbjct, $Copy_End - $Sub_Region_Len + 1, $Sub_Region_Len + $Flank_L);
					$S_Flank_DNA   = DNA_reverser($S_Flank_DNA_L.$S_Flank_DNA_R);
				}
			}
		}

#		print "$Sbjct, $Copy_Begin, $Begin_Fix, $Copy_End, $End_Fix, $Flank_L, $Flank_R\n";

		#------------------------------------------------------------------
		$Nomalized_Copy_Score = int($Copy_Score * $Copy_Len / $Query_Len * 100)/100;
		push(@OF_Info, "Query:".$Query." Sbjct:".$Sbjct." Length:".$Copy_Len." Location:(".$Copy_Begin." - ".$Copy_End.") Direction:".$Dir." Score:".$Nomalized_Copy_Score);
		push(@OF_Flank, $S_Flank_DNA);
	}
}

#--------------------------------- sort the homologs from score high to low ------------
print "sort the homologs from score high to low\n";
%Homolog_Used  = ();
$Sort_Finished = 0;
$Homolog_Num   = 0;

while($Sort_Finished == 0) {
	$Sort_Finished = 1;
	$Highest_Score = 0;
	for($i = 0; $i < @OF_Info; $i ++) {
		next if(defined($Homolog_Used{$i}));
		if($OF_Info[$i] =~ /Score:(\d+)/) {
			$Score = $1;
			if($Score > $Highest_Score) {
				$Highest_Score_Homolog = $i;
				$Highest_Score = $Score;
				$Sort_Finished = 0;
			}
		}else{
			print "$_ can't be interpreted\n";
		}
	}

	if($Sort_Finished == 0) {
		$Homolog_Num ++;
		$Full_Name = $ID_Tag."_".$Homolog_Num;
		$Homolog_Used{$Highest_Score_Homolog} = 1;
		print (OF ">$Full_Name $OF_Info[$Highest_Score_Homolog]\n$OF_Flank[$Highest_Score_Homolog]\n");
		last if($Homolog_Num >= $Max_Output);
	}
}

close(OF);
close(SF);
#-----------------------------------------------------
#-----------------------------------------------------
sub usuage {
    print "\nHi, need some help?\n";
    print STDERR <<"    _EOT_";

    Usage :tblastn_copy_finder.pl <options> <specification> <default>

	\$Input          = defined \$opt_i ? \$opt_i : "";
	\$Query_File     = defined \$opt_q ? \$opt_q : "";
	\$Sbjct_File     = defined \$opt_D ? \$opt_D : "/scratch/vehell/Data_Room/Rice/rice";
	\$Max_Evalue     = defined \$opt_e ? \$opt_e : 0.01; 
	\$Min_Pro        = defined \$opt_M ? \$opt_M : 0.7;
	\$Distance       = defined \$opt_d ? \$opt_d : 8000;
	\$ID_Tag         = defined \$opt_I ? \$opt_I : "ZMmar";
	\$Max_Output     = defined \$opt_n ? \$opt_n : 30;
	\$Flank_L        = defined \$opt_l ? \$opt_l : 60;
	\$Flank_R        = defined \$opt_r ? \$opt_r : 60;
	\$Sub_Region_Len = defined \$opt_s ? \$opt_s : 0;
	\$Max_Overlap    = defined \$opt_L ? \$opt_L : 30;
	\$Output         = defined \$opt_o ? \$opt_o : "protein_copies";
	\$Help           = defined \$opt_h ? \$opt_h : "";

    _EOT_
    exit(1)
}

#-----------------------------------------------------
sub tblastn_loader {
	my($Input) = @_;
	my($Head, $Q_Match, $S_Match, $Line, $Query, $No_Hits, $Query_Len, $Sbjct, $Sbject_Len, $Database);
	my($E_Value, $Alignment_Loader, $Blast_Align, $Frame, $Match_Begin, $Q_Begin, $S_Begin, $Q_End, $S_End);
	open(IF, $Input)||die"$!\n";
	$Head = 1;
	$Q_Match = "";
	$S_Match = "";
	while(<IF>) {
		$Line = $_;
		if($Line =~ /Query= (\S+)/) {
			$New_Query = $1;
			 if($Head == 0) {
				Query_Sbject_Info_Loader($E_Value, $No_Hits, $Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Blast_Align, $Query, $Sbjct, $Score);
				$Head = 1;
			 }
			$Query = $New_Query;
			$No_Hits = 0;
		}
		if($Line =~ /No hits found/) {
			$No_Hits = 1;
		}

		if($Line =~ /^>(\S+)/) {
			if($Head == 0) {
				Query_Sbject_Info_Loader($E_Value, $No_Hits, $Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Blast_Align, $Query, $Sbjct, $Score);
				$Head = 1;
			}
			$Sbjct = $1;
			$Head = 1;
		}
		if($Line =~ /Length = (\d+)/) {
			$Sbject_Len = $1;
			$Sbjct_Length{$Sbjct} = $Sbject_Len;
		}
		if($Line =~ /Database: (\S+)/) {
			$Database = $1;
		}
		if($Line =~ /Score =/) {
			if($Head == 0) {
				Query_Sbject_Info_Loader($E_Value, $No_Hits, $Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Blast_Align, $Query, $Sbjct, $Score);
			}else{
				$Head = 0;
			}
			
			if($Line =~ /Score = +(\S+) +/) {
				$Score = $1;
			}else{
				print "error while loading score\n$_\n";
				exit();
			}

			if($Line =~ /Expect/) {
				if($Line=~ /Expect\s+=\s+(\S+)/) {
					$E_Value = $1;
				}elsif($Line=~ /Expect\(\d+\)\s+=\s+(\S+)/){
					$E_Value = $1;
				}else{
					print "error while loading e value\n$_\n";
					exit();
				}
				$E_Value =~ s/\,//;
			}
		
			$Alignment_Loader = 1;
			$Blast_Align = $_;

			$Match_Begin = 1;
			$Q_Match = "";
			$S_Match = "";
		}

		if($Line =~ /Strand/) {
			if($Line =~ /Minus/) {
				$Frame = 0;
			}elsif($Line =~ /Plus/) {
				$Frame = 1;
			}else{
				print "unknown frame\n";
			}
		}

		if($Line =~ /Query: (\d+)\s+(\S+) (\d+)/) {
			if($Match_Begin == 1) {
				$Q_Begin     = $1;
			}
			$Q_Match .= $2;
			$Q_End   = $3;
		}
		if(($Line =~ /Sbjct: (\d+)\s+(\S+) (\d+)/)||($Line =~ /Sbjct: (\d+)(\S+) (\d+)/)) {
			if($Match_Begin == 1) {
				$S_Begin     = $1;
				$Match_Begin = 0;
			}
			$S_Match .= $2;
			$S_End   = $3;
		}
		
		if(($Line =~ /TBLASTN/)||($Line =~ /BLASTN/)) {
			$Alignment_Loader = 0;
		}
	
		$Blast_Align .= $_ if($Alignment_Loader == 1);
	}
	Query_Sbject_Info_Loader($E_Value, $No_Hits, $Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Blast_Align, $Query, $Sbjct, $Score);
	close(IF);
}

#-----------------------------------------------------
sub Query_Sbject_Info_Loader {
	my($E_Value, $No_Hits, $Q_Begin, $Q_Match, $Q_End, $S_Begin, $S_Match, $S_End, $Frame, $Blast_Align, $Query, $Sbjct, $Score) = @_;
	my($E_Qualify, $E_Head, $E_Tail);
	$E_Qualify = 0;
	
	$E_Qualify = E_value_comparison($Max_Evalue, $E_Value);

	if(($No_Hits == 0)&&(($E_Qualify eq ">")||($E_Qualify eq "="))) {
		if(($Query eq "TQ")&&($Sbjct eq "TS")) {
			$Query_Sbjct_Matches{"TQ TS"} = "" if($Query_Sbjct_Matches{"TQ TS"} eq "none");
		}
		# ---------------------------------------- query -> sbjcts
		if(defined($Query_Sbjcts{$Query})) {
			@Sbjcts = split(/ /, $Query_Sbjcts{$Query});
			$Have = 0;
			foreach(@Sbjcts) {
				if ($_ eq $Sbjct) {
					$Have = 1;
					last;
				}
			}
			if($Have == 0) {
				$Query_Sbjcts{$Query} .= $Sbjct." ";
			}
		}else{
			$Query_Sbjcts{$Query} = $Sbjct." ";
		}
		# ---------------------------------------- query_sbjct -> locs
		$Query_Sbjct_Matches{$Query." ".$Sbjct} .= $Q_Begin." ".$Q_Match." ".$Q_End."  ".$S_Begin." ".$S_Match." ".$S_End." ".$Frame." ".$Score."   ";	
		#----------------------------------------- query sbjct S_Start -> blast alignment
	}
}

#-----------------------------------------------------
sub sbject_fasta_picker {
    my($Name, $Loc, $Len) = @_;
	my($Seq, $Zero_Loc);
    if(!(defined($Location_Info{$Name}))) {
		print "$Name\n";
       die "can not find sbject fasta seq\n";
    }
    $Zero_Loc = $Location_Info{$Name};
    sysseek(SF, $Loc + $Zero_Loc - 1, 0); 
    sysread(SF, $Seq, $Len);

    return($Seq);
}

#-----------------------------------------------------
sub DNA_reverser {
    my($Seq) = @_;
	$Seq = reverse $Seq;
	$Seq =~ tr/ACGTacgt/TGCAtgca/;
    return($Seq);
}

#-------------------------------------------
sub E_value_comparison {
	my($E1, $E2) = @_;
	my($Compare_Result, $E1_Head, $E1_Tail, $E2_Head, $E2_Tail);
	$Compare_Result = ">";
	if((($E2 =~ /^0\.0$/)||($E2 =~ /^0$/))||($E2 =~ /^0\.00$/)) {
		$Compare_Result = ">";
	}elsif($E1 =~ /e-/) {
		if($E1 =~ /(\d+)e-(\d+)/) {
			$E1_Head = $1;
			$E1_Tail = $2;
			$E1_Tail =~ s/^0+//;
		}elsif($E1 =~ /e-(\d+)/){
			$E1_Head = 1;
			$E1_Tail = $1;
			$E1_Tail =~ s/^0+//;
		}else{
			print "Strange E value\n";
			exit(0);
		}

		if($E2 =~ /e-/) {
			if($E2 =~ /(\d+)e-(\d+)/) {
				$E2_Head = $1;
				$E2_Tail = $2;
				$E2_Tail =~ s/^0+//;
			}elsif($E2 =~ /e-(\d+)/){
				$E2_Head = 1;
				$E2_Tail = $1;
				$E2_Tail =~ s/^0+//;
			}else{
				print "Strange E value\n";
				exit(0);
			}
	
			if($E1_Tail > $E2_Tail) {
				$Compare_Result = "<";
			}elsif($E1_Tail < $E2_Tail) {
				$Compare_Result = ">";
			}else{
				if($E1_Head > $E2_Head){
					$Compare_Result = ">";
				}elsif($E1_Head < $E2_Head){
					$Compare_Result = "<";
				}else{
					$Compare_Result = "=";
				}
			}
		}else{
			$Compare_Result = "<";
		}
	}else{
		if($E2 =~ /e-/) {
			$Compare_Result = ">";
		}else{
			if($E1 > $E2) {
				$Compare_Result = ">";
			}elsif($E1 < $E2){
				$Compare_Result = "<";
			}else{
				$Compare_Result = "=";
			}
		}
	}

	return($Compare_Result);
}

# --------------------------------------
sub path_finder {
	# ---------------- find the start alignment as the seed of paths--------
	$Max_Score = 0;
	%ID_Match = ();
	%ID_Score = ();
	@Paths = ();
	for($i = 0; $i < @Matches; $i ++) {
		$ID_Match{$i} = $Matches[$i];
#		print "Path $i : $Matches[$i]\n";
		($Q_B, $Q_M, $Q_E, $S_B, $S_M, $S_E, $Dir, $Score) = split(/ /, $Matches[$i]);
		$ID_Score{$i} = $Score;
		if($Score > $Max_Score) {
			$Max_Score = $Score;
			$Seed_ID   = $i;
		}
	}
#	print "Seed: $Seed_ID\n";
	push(@Paths, " ".$Seed_ID." ");

	# ----------- extend to the begining --------
	$Head = 0;
	while($Head == 0) {
		@New_Paths = ();
		$Head = 1;
		foreach(@Paths) {
			$Path = $_;
#			print "Head Paths: $_\n";
			$Path_End = 1;
			if($Path =~ /^Begin /) {
				push(@New_Paths, $Path);
				next;
			}
			$Path =~ /^ (\d+) /;
			$Current_ID = $1;

			($Q_B, $Q_M, $Q_E, $S_B, $S_M, $S_E, $Dir, $Score) = split(/ /, $ID_Match{$Current_ID});
			$Dir = $Dir > 0 ? "plus" : "minus";
			for($i = 0; $i < @Matches; $i ++) {
				next if($Path =~ / $i /);
				($Q_BN, $Q_MN, $Q_EN, $S_BN, $S_MN, $S_EN, $Dir_N, $Score_N) = split(/ /, $Matches[$i]);
				$Dir_N = $Dir_N > 0 ? "plus" : "minus";
				next if($Dir_N ne $Dir);

				if($Dir eq "plus") {
					if($S_BN >= $S_B) {
						next;
					}elsif(($S_BN < $S_B)&&($S_EN >= $S_E)) {  # may be too loose
						next;
					}
				}else{
					if($S_BN <= $S_B) {
						next;
					}elsif(($S_BN > $S_B)&&($S_EN <= $S_E)) {  # may be too loose
						next;
					}
				}

				if($Q_EN <= $Q_B) {
					push(@New_Paths, " ".$i." ".$Path);
					$Path_End = 0;
					$Head = 0;
				}elsif(($Q_BN < $Q_B)&&($Q_EN > $Q_B)) {
					push(@New_Paths, " ".$i." ".$Path);
					$Path_End = 0;
					$Head = 0;
				}elsif(($Q_BN <= $Q_B)&&($Q_EN >= $Q_E)) {
					next;
				}elsif(($Q_BN >= $Q_B)&&($Q_EN <= $Q_E)) {
					next;
				}elsif(($Q_BN >= $Q_B)&&($Q_EN > $Q_E)) {
					next;
				}elsif($Q_BN >= $Q_E) {
					next;
				}else{
					print "unknown relationship\n$ID_Match{$Current_ID}\n$Matches[$i]\n";
					exit(0);
				}
			}

			if($Path_End == 1) {
				push(@New_Paths, "Begin ".$Path);
			}
		}
		@Paths = @New_Paths;
#		print "\n";

	}

	# ----------- extend to the end -------------
	$Tail = 0;
	while($Tail == 0) {
		@New_Paths = ();
		$Tail = 1;
		foreach(@Paths) {
			$Path = $_;
#			print "Tail Paths: $_\n";
			$Path_End = 1;
			if($Path =~ /End$/) {
				push(@New_Paths, $Path);
				next;
			}
			$Path =~ / (\d+) $/;
			$Current_ID = $1;

			($Q_B, $Q_M, $Q_E, $S_B, $S_M, $S_E, $Dir, $Score) = split(/ /, $ID_Match{$Current_ID});
			$Dir = $Dir > 0 ? "plus" : "minus";

			for($i = 0; $i < @Matches; $i ++) {
				next if($Path =~ / $i /);
				($Q_BN, $Q_MN, $Q_EN, $S_BN, $S_MN, $S_EN, $Dir_N, $Score_N) = split(/ /, $Matches[$i]);
				$Dir_N = $Dir_N > 0 ? "plus" : "minus";
				next if($Dir_N ne $Dir);

				if($Dir eq "plus") {
					if($S_EN <= $S_E) {
						next;
					}elsif(($S_EN > $S_E)&&($S_BN <= $S_B)) {  # may be too loose
						next;
					}
				}else{
					if($S_EN >= $S_E) {
						next;
					}elsif(($S_EN < $S_E)&&($S_BN >= $S_B)) {  # may be too loose
						next;
					}
				}

				if($Q_EN <= $Q_B) {
					next;
				}elsif(($Q_BN < $Q_B)&&($Q_EN >= $Q_B)) {
					next;
				}elsif(($Q_BN <= $Q_B)&&($Q_EN >= $Q_E)) {
					next;
				}elsif(($Q_BN >= $Q_B)&&($Q_EN <= $Q_E)) {
					next;
				}elsif(($Q_BN >= $Q_B)&&($Q_EN > $Q_E)) {
					push(@New_Paths, $Path." ".$i." ");
					$Path_End = 0;
					$Tail = 0;
				}elsif($Q_BN >= $Q_E) {
					push(@New_Paths, $Path." ".$i." ");
					$Path_End = 0;
					$Tail = 0;
				}else{
					print "unknown relationship\n";
					exit(0);
				}
			}

			if($Path_End == 1) {
				push(@New_Paths, $Path." End");
			}
		}
		@Paths = @New_Paths;
	}

	# ----------- find the path that has the highest score -------------
	$Most_Reliable_Path = "";
	$Highest_Score = 0;
	foreach(@Paths) {
		$Path = $_;
		@Content = split(/ +/, $Path);
		$Total_Score = 0;
		foreach(@Content) {
			next if(($_ eq "Begin")||($_ eq "End"));
			$Score = $ID_Score{$_};
			$Total_Score = $Total_Score + $Score;
		}

		if($Total_Score > $Highest_Score) {
			$Most_Reliable_Path = $Path;
			$Highest_Score = $Total_Score;
		}
	}
	return($Most_Reliable_Path);
}
