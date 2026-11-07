#!/bin/bash
# Render every note (*.md) in SRC_DIR to HTML and pack the pages into OUT_DIR/NAME.tar.gz.
# usage: package.sh SRC_DIR OUT_DIR [NAME]
SRC=$1
OUT=$2
NAME=${3:-notes}
HERE=$(dirname $0)
STAGE=$OUT/.stage-$NAME

rm -rf $STAGE
mkdir -p $STAGE

count=0
for f in $(ls $SRC/*.md); do
  base=$(basename $f .md)
  python3 $HERE/render.py $f | sed 's/[[:space:]]*$//' > $STAGE/$base.html
  count=$((count+1))
done

cd $STAGE
tar czf $OUT/$NAME.tar.gz *.html
cd -
rm -rf $STAGE
echo "packed $count notes into $OUT/$NAME.tar.gz"
