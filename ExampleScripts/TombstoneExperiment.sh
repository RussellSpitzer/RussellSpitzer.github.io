#!/bin/bash
shopt -s extglob
missing=()
for prog in cqlsh nodetool sstable2json; do
    hash $prog >/dev/null || { echo "$prog Isn't present on your Path. Please add it"; exit 1; }
done

DATADIR=${CASSANDRA_DATADIR:-/var/lib/cassandra/data}
if [ ! -d $DATADIR ]; then
    echo "Couldn't find your data directory at $DATADIR. export CASSANDRA_DATADIR=your/cassandra/data/dir"
    exit 1
fi

#Quick function to display our sstables
function jsontables {
    echo " =========================================== "
    echo $1
    #We should only have one sstable from that flush
    ONECELLTABLE_1=`ls $DATADIR/tombstone_exp/onecell*/*-1-Data.db`
    ONECELLTABLE_2=`ls $DATADIR/tombstone_exp/onecell*/*-2-Data.db`
    TWOCELLTABLE_1=`ls $DATADIR/tombstone_exp/twocell*/*-1-Data.db`
    TWOCELLTABLE_2=`ls $DATADIR/tombstone_exp/twocell*/*-2-Data.db`
    echo "One Cell Table"
    sstable2json $ONECELLTABLE_1
    sstable2json $ONECELLTABLE_2
    echo "Query Trace"
    cqlsh << QT
    use tombstone_exp;
    TRACING ON;
    SELECT * FROM onecell WHERE k=1;
QT

    echo " ------------------------------------------- "
    echo "Two Cell Table"
    sstable2json $TWOCELLTABLE_1
    sstable2json $TWOCELLTABLE_2
    echo "Query Trace"
    cqlsh << QT
    use tombstone_exp;
    TRACING ON;
    SELECT * FROM twocell WHERE k=1;
QT
    echo " =========================================== "
}

cqlsh << SETUPKEYSPACE
DROP KEYSPACE IF EXISTS tombstone_exp;
CREATE KEYSPACE tombstone_exp with replication = {'class':'SimpleStrategy', 'replication_factor':1};
SETUPKEYSPACE

cqlsh << COLUMNDEL
use tombstone_exp;
DROP TABLE IF EXISTS onecell;
DROP TABLE IF EXISTS twocell;

CREATE TABLE onecell ( k int, c1 int, c2 int, c3 int, d1 int , PRIMARY KEY (k,c1,c2,c3));
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 1, 1, 1, 1);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 2, 2, 2, 2);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 3, 3, 3, 3);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 4, 4, 4, 4);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 5, 5, 5, 5);

CREATE TABLE twocell ( k int, c1 int, c2 int, d1 int, d2 int , PRIMARY KEY (k,c1,c2));
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 1, 1, 1, 1);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 2, 2, 2, 2);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 3, 3, 3, 3);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 4, 4, 4, 4);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 5, 5, 5, 5);
COLUMNDEL

nodetool flush

cqlsh << COLUMNDEL
use tombstone_exp;
DELETE FROM onecell where k = 1 AND c1 = 2;
DELETE FROM onecell where k = 1 AND c1 = 5;
DELETE FROM twocell where k = 1 AND c1 = 2;
DELETE d2 FROM twocell where k = 1 AND c1 = 5 AND c2 = 5;
COLUMNDEL

nodetool flush

jsontables "Clustering Column Delete"

cqlsh << KEYDEL
use tombstone_exp;
DROP TABLE IF EXISTS onecell;
DROP TABLE IF EXISTS twocell;

CREATE TABLE onecell ( k int, c1 int, c2 int, c3 int, d1 int , PRIMARY KEY (k,c1,c2,c3));
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 1, 1, 1, 1);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 2, 2, 2, 2);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 3, 3, 3, 3);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 4, 4, 4, 4);
INSERT INTO onecell (k, c1, c2, c3, d1) VALUES (1, 5, 5, 5, 5);


CREATE TABLE twocell ( k int, c1 int, c2 int, d1 int, d2 int , PRIMARY KEY (k,c1,c2));
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 1, 1, 1, 1);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 2, 2, 2, 2);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 3, 3, 3, 3);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 4, 4, 4, 4);
INSERT INTO twocell (k, c1, c2, d1, d2) VALUES (1, 5, 5, 5, 5);
KEYDEL

nodetool flush

cqlsh <<KEYDEL
use tombstone_exp;
DELETE FROM onecell where k = 1;
DELETE FROM twocell where k = 1;
KEYDEL

nodetool flush

jsontables "Key Delete Experiment"

cqlsh << LISTDEL
use tombstone_exp;
DROP TABLE IF EXISTS onecell;
DROP TABLE IF EXISTS twocell;

CREATE  TABLE  onecell ( k int , c1 int , d1 list <int >, PRIMARY KEY (k, c1) ) ;
INSERT INTO onecell (k, c1 , d1  ) VALUES ( 1, 1, [1,1,1,1,1] );
INSERT INTO onecell (k, c1 , d1  ) VALUES ( 1, 2, [2,2,2,2,2] );
INSERT INTO onecell (k, c1 , d1  ) VALUES ( 1, 3, [3,3,3,3,3] );
INSERT INTO onecell (k, c1 , d1  ) VALUES ( 1, 4, [4,4,4,4,4] );
INSERT INTO onecell (k, c1 , d1  ) VALUES ( 1, 5, [5,5,5,5,5] );

CREATE  TABLE twocell ( k int , c1 int , d1 list <int>, d2 list <int>,  PRIMARY KEY (k, c1) ) ;
INSERT INTO twocell (k, c1 , d1, d2  ) VALUES ( 1, 1, [1,1,1,1,1], [1,1,1,1,1] );
INSERT INTO twocell (k, c1 , d1, d2  ) VALUES ( 1, 2, [2,2,2,2,2], [2,2,2,2,2] );
INSERT INTO twocell (k, c1 , d1, d2  ) VALUES ( 1, 3, [3,3,3,3,3], [3,3,3,3,3] );
INSERT INTO twocell (k, c1 , d1, d2  ) VALUES ( 1, 4, [4,4,4,4,4], [4,4,4,4,4] );
INSERT INTO twocell (k, c1 , d1, d2  ) VALUES ( 1, 5, [5,5,5,5,5], [5,5,5,5,5] );
LISTDEL

nodetool flush

cqlsh <<KEYDEL
use tombstone_exp;
DELETE FROM onecell where k = 1 and c1 = 2;
DELETE FROM twocell where k = 1 and c1 = 2;
KEYDEL

nodetool flush

jsontables "List Delete Experiment"


