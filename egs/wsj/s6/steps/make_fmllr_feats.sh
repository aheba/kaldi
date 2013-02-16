#!/bin/bash

# Copyright 2012  Karel Vesely
#                 Johns Hopkins University (Author: Daniel Povey),
#                 
# Apache 2.0.

# This script is for use in neural network training and testing; it dumps
# CMN+LDA+MLLT+fMLLR features in a similar format to
# conventional raw MFCC features. 

# Begin configuration section.  
nj=4
cmd=run.pl
transform_dir=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "Usage: $0 [options] <tgt-data-dir> <src-data-dir> <gmm-dir> <log-dir> <fea-dir>"
   echo "e.g.: $0 data-fmllr/train data/train exp/tri5a data-fmllr/train/_log data-fmllr/train/_data "
   echo ""
   echo "This script works on CMN+LDA+MLLT features."
   echo "You can also add fMLLR-- you have to supply the --transform-dir option."
   echo ""
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>                           # config containing options"
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --transform-dir <transform-dir>                  # where to find fMLLR transforms."
   exit 1;
fi


data=$1
srcdata=$2
gmmdir=$3
logdir=$4
feadir=$5



#srcdir=$1 -> gmmdir
#data=$2 -> srcdata
#dir=$3 -> ruzne
#tgtdata=$4 -> feadir

sdata=$srcdata/split$nj;
splice_opts=`cat $gmmdir/splice_opts 2>/dev/null`

mkdir -p $data $logdir $feadir
[[ -d $sdata && $srcdata/feats.scp -ot $sdata ]] || split_data.sh $srcdata $nj || exit 1;

for f in $sdata/1/feats.scp $sdata/1/cmvn.scp $gmmdir/final.mat; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $gmmdir/final.mat ark:- ark:- |"

if [ ! -z "$transform_dir" ]; then # add transforms to features...
  echo "Using fMLLR transforms from $transform_dir"
  [ ! -f $transform_dir/trans.1 ] && echo "Expected $transform_dir/trans.1 to exist."
  [ "`cat $transform_dir/num_jobs`" -ne $nj ] && \
     echo "Mismatch in number of jobs with $transform_dir" && exit 1;
  feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark:$transform_dir/trans.JOB ark:- ark:- |"
fi


#prepare the dir
cp $srcdata/* $data; rm $data/{feats.scp,cmvn.scp};

# make $bnfeadir an absolute pathname.
feadir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $feadir ${PWD}`

#forward the feats
$cmd JOB=1:$nj $logdir/make_fmllr_feats.JOB.log \
  copy-feats "$feats" \
  ark,scp:$feadir/feats_fmllr.JOB.ark,$feadir/feats_fmllr.JOB.scp || exit 1;
   
#merge the feats to single SCP
for n in $(seq 1 $nj); do
  cat $feadir/feats_fmllr.$n.scp 
done > $data/feats.scp

echo "$0 finished... $srcdata -> $data ($gmmdir)"

exit 0;