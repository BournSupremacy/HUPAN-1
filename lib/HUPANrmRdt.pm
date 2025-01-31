use strict;
use warnings;

package rmRDT;

sub rmRDT{
my $usage="hupan rmRedundant [commands]

hupan rmRedundant is used to cluster sequences and extract the representative ones.

Available commands:
      cdhitCluster      Clustering with CDHIT, fast but only accept identity >0.8
      blastCluster      Clustering with Blastn

";

    die $usage if @ARGV<1;
    my $com=shift @ARGV;
    if($com eq "cdhitCluster"){
	cdhitCl(@ARGV);
    }
    elsif($com eq "blastCluster.pl"){
	blastCl(@ARGV);
    }
    else{
	print STDERR "Unknown command: $com\n";
	die($usage);
    }
}

sub cdhitCl{
use Getopt::Std;
use vars qw($opt_h $opt_t $opt_c);
getopts("ht:c:");

my $usage="\nUsage: hupan rmRedundant cdhitCluster [options] <input_fasta_file> <output_directory> <cdhit_directory>

hupan rmRedundant cdhitCluster is used to cluster contigs and remove the redundant ones.

Necessary input description:

  input_fasta_file        <string>    Contig sequences to be clustereed.

  output_directory        <string>    Output directory.

  cdhit_directory         <string>    directory where cdhit-est locates. 

Options:
     -h                               Print this usage page.

     -t                   <int>       Threads used.
                                      Default: 1

     -c                   <float>     Sequence identity threshold
                                      Default: 0.9
";

die $usage if @ARGV!=3;
die $usage if defined($opt_h);
my ($in,$out_dir,$tool_dir)=@ARGV;

#Check existence of output directory

#check cdhit-est
$tool_dir.="/" unless $tool_dir=~/\/$/;
my $exe=$tool_dir."cd-hit-est";
die(" $exe doesn't exist!
") unless -e $exe;

if(-e $out_dir){
    die("Error: output directory \"$out_dir\" already exists.
To avoid overwriting of existing files, we kindly request that the
 output directory should not exist.
");
}
$out_dir.="/" unless $out_dir=~/\/$/;
mkdir($out_dir);

my $thread_num=1;
$thread_num=$opt_t if defined $opt_t;

my $iden=0.9;
$iden=$opt_c if defined $opt_c;

#detect adjCdhit.pl

my $exeadj="adjCdhit.pl";
my @path=split /:/,$ENV{PATH};
my $fpflag=0;
foreach my $p (@path){
    $p.="/".$exeadj;
    if(-e $p && -x $p){
	$fpflag=1;
	last;
    }
}
die("Executable adjCdhit.pl cannot be found in your PATH!\n
") unless($fpflag);

my $tmp_dir=$out_dir."tmp/";
mkdir($tmp_dir);

# rename fasta
my $fa_ordered=$tmp_dir."input_renamed.fa";
my $conversion=$tmp_dir."conversion.txt";
reName($in,$fa_ordered,$conversion);

#run cdhit
my $out_ordered=$tmp_dir."cluster";
my $fout=$out_dir."non-redundant.fa";
my $fcl=$out_dir."cluster_info.txt";
my $com="$exe -i $fa_ordered -o $out_ordered -T $thread_num -c $iden";
$com.="\n"."$exeadj $out_ordered $out_ordered".".clstr $conversion $fout $fcl";

system($com);
1;
}


sub blastCl{
use Getopt::Std;
use vars qw($opt_h $opt_t $opt_c);
getopts("hs:n:m:t:k:s:c:g");

my $usage="\nUsage: hupanLSF rmRedundant blastCluster [options] <input_fasta_file> <output_directory> <blast_directory>

hupanLSF rmRedundant blastCluster is used to cluster contigs and remove the redundant ones.

Necessary input description:

  input_fasta_file        <string>    Contig sequences to be clustereed.

  output_directory        <string>    Output directory.

  blast_directory         <string>    directory where blastn and makeblastdb locate. 

Options:
     -h                               Print this usage page.

     -t                   <int>       Threads used.
                                      Default: 1

     -c                   <float>     Sequence identity threshold
                                      Default: 0.5
";

die $usage if @ARGV!=3;
die $usage if defined($opt_h);
my ($in,$out_dir,$tool_dir)=@ARGV;

#Check existence of output directory

#check blast
$tool_dir.="/" unless $tool_dir=~/\/$/;
my $exeMk=$tool_dir."makeblastdb";
die(" $exeMk doesn't exist!
") unless -e $exeMk;

my $exeBlast=$tool_dir."blastn";
die(" $exeBlast doesn't exist!
") unless -e $exeBlast;

my $exeBC="blastCluster.pl";
my @path=split /:/,$ENV{PATH};
my $fpflag=0;
foreach my $p (@path){
  $p.="/".$exeBC;
  if(-e $p && -x $p){
      $fpflag=1;
      last;
  }
}
die("Executable blastCluster.pl cannot be found in your PATH!\n
") unless($fpflag);


die("Error: output directory \"$out_dir\" already exists.
To avoid overwriting of existing files, we kindly request that the
 output directory should not exist.
") if -e $out_dir;

$out_dir.="/" unless $out_dir=~/\/$/;
mkdir($out_dir);

my $thread_num=1;
$thread_num=$opt_t if defined $opt_t;

my $iden=0.5;
$iden=$opt_c if defined $opt_c;

#tmp output dir
my $tmp_dir=$out_dir."tmp/";
mkdir($tmp_dir);
my $errf=$tmp_dir."log.txt";

my $com;
#build index
my $index=$tmp_dir."blastdb";
print STDERR "Build blast index for $in ...\n";
$com="$exeMk -dbtype nucl -in $in -out $index 1>&2 2>$errf\n";
system($com);
#run blast;
my $bout=$tmp_dir."self_aln.out";
print STDERR "Run self-blast ...\n";
$com="$exeBlast -query $in -db $index -out $bout -evalue 1e-5 -outfmt \"6 qseqid sseqid qlen slen length qstart qend sstart send pident evalue\" -max_target_seqs 1000 -num_threads $thread_num\n";
system($com);
#cluster from blast output
my $pre=$out_dir."non-redundant";
print STDERR "Cluster from blast output ...\n";
$com="$exeBC $in $iden $bout $pre\n";
system($com);
$com.="mv $pre".".cluster"." $out_dir"."cluster_info.txt";
system($com);

1;
}

sub reName{
#rename <fasta> <out.fa> <name_convert_list>
    open(OUT,">$_[1]");
    open(STA,">$_[2]");
    open(IN,$_[0]);

    my $i=1;
    while(<IN>){
	chomp;
	if(/>(.+)$/){
	    print OUT ">$i\n";
	    print STA "$1\t$i\n";
	    $i++;
	}
	else{
	    print OUT "$_\n";
	}
    }
    close OUT;
    close STA;
    close IN;
}
1;


