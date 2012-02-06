#------------------------------------------------------------------------------
#    mwForum - Web-based discussion forum
#    Copyright (c) 1999-2008 Markus Wichitill
#
#    MwfPlgNaviSQL.pm - SQL Generation
#    Copyright (c) 2010 Tobias Jaeggi, modified for SQL 2010 by Murray Colpman
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#------------------------------------------------------------------------------

package MwfPlgNaviSQL;
use strict;
use warnings;
our $VERSION = "2.22.1";

use Net::FTP;

# Infixes we care about
my @INFIXTYPES = qw(pcw affixN alloffixN markerN derivingaffixN infixN infixcwN);

sub create {
  my %params = @_;
  my $m = $params{m};
  my $cfg = $m->{cfg};
  my @words = @{$params{words}};
  my $ftp = $params{ftp};
  my @lcs = @{$params{languages}};

	# Clean up
  `rm -f $cfg->{EE}{tmpDir}/*.sql`;

	# Open file handles to avoid iterating X times through @words
  my $file;
  open($file, '>::utf8', "$cfg->{EE}{tmpDir}/NaviData.sql") or $m->error("Could not open file! ($! for $cfg->{EE}{tmpDir}/NaviData.sql)");
  $file or $m->error("could not open file");

  print $file <<EOSQL;
-- IMPORTANT notices about this SQL file
-- Eana Eltu SQL data by Tobias Jaeggi (Tuiq, tuiq\@clonk2c.ch), Richard Littauer (Taronyu, richard\@learnnavi.org) and others is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License ( http://creativecommons.org/licenses/by-nc-sa/3.0/ ).
-- The full license text is available at http://creativecommons.org/licenses/by-nc-sa/3.0/legalcode .

CREATE TABLE IF NOT EXISTS `metaWords` (`id` int(11) NOT NULL, `navi` varchar(100) NOT NULL,`ipa` varchar(100) NOT NULL,`infixes` varchar(100) NULL,`partOfSpeech` varchar(100) NOT NULL,PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8;
CREATE TABLE IF NOT EXISTS `metaInfixes` (`id` int(11) NOT NULL, `navi` varchar(50) NOT NULL, `ipa` varchar(100) NOT NULL, `shorthand` varchar(50) NOT NULL, `position` int(1) NULL, PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8;
CREATE TABLE IF NOT EXISTS `localizedWords` (`id` int(11) NOT NULL,`languageCode` varchar(5) NOT NULL,`localized` text NULL,`partOfSpeech` varchar(100) NULL, UNIQUE KEY `idlc` (`id`,`languageCode`)) DEFAULT CHARSET=utf8;
CREATE TABLE IF NOT EXISTS `localizedInfixes` (`id` int(11) NOT NULL, `languageCode` varchar(5) NOT NULL, `meaning` text NULL, `habitat` text NULL, UNIQUE KEY `idlc` (`id`, `languageCode`)) DEFAULT CHARSET=utf8;
TRUNCATE TABLE `metaWords`;
TRUNCATE TABLE `localizedWords`;
TRUNCATE TABLE `metaInfixes`;
TRUNCATE TABLE `localizedInfixes`;
EOSQL

	my $dbh = $m->{dbh};
	
	# Iterate through @words
  for my $word (@words) {
    print $file "INSERT INTO `metaWords` (`id`,`navi`,`ipa`,`infixes`,`partOfSpeech`) VALUES ('", $word->{id}, "',", $dbh->quote($word->{nav}), ",", $dbh->quote($word->{ipa}), ",", $dbh->quote($word->{svnav}), ",", $dbh->quote($word->{type}), ");";
		# And now for each language...
		for my $lc (@lcs) {
			next if !$word->{$lc};
      my $type = $word->{"type$lc"} ? $word->{"type$lc"} : $word->{type};
      print $file "INSERT INTO `localizedWords` (`id`,`languageCode`,`localized`,`partOfSpeech`) VALUES ('", $word->{id}, "','", $lc, "',", $dbh->quote($word->{$lc}), ",", $dbh->quote($type), ");";
		}
		# We don't show mercy to poor editors.
		#~ print $file "\n";
	}

	# Fetch all real words for the SQL file.
	my $infixWords = $m->fetchAllHash('SELECT * FROM dictWordMeta WHERE `type` IN (' . join(', ', map { "'$_'" } @INFIXTYPES) . ')');
	
	for my $word (@$infixWords) {
		# Now the fun begins.
		my $type = $word->{type};
		
		my $sI = undef; # shorthand index
		my $pI = undef; # position index
		my $mI = undef; # meaning index
		my $wtI = undef; # "word type"
		
		if ($type eq 'pcw') {
			$mI = 4; $sI = 10;
		}
		elsif ($type eq 'affixN') {
			$wtI = 4; $mI = 3; $sI = 8;
		}
		elsif ($type eq 'alloffixN') {
			$wtI = 5; $mI = 4; $sI = 9;
		}
		elsif ($type eq 'markerN' || $type eq 'derivingaffixN') {
			$mI = 3; $sI = 7;
		}
		elsif ($type eq 'infixN') {
			$mI = 3; $pI = 4; $sI = 8;
		}
		elsif ($type eq 'infixcwN') {
			$mI = 3; $pI = 4; $sI = 10;
		}
		
		my $shorthand = defined($sI) ? $dbh->quote($word->{'arg' . $sI}) : 'NULL';
		my $position = defined($pI) ? $dbh->quote($word->{'arg' . $pI}) : 'NULL';
		my $meaning = defined($mI) ? $dbh->quote($word->{'arg' . $mI}) : 'NULL';
		my $wordType = defined($wtI) ? $dbh->quote($word->{'arg' . $wtI}) : 'NULL';
		
		print $file sprintf("INSERT INTO `metaInfixes` (`id`, `navi`, `ipa`, `shorthand`, `position`) VALUES ('%d', %s, %s, %s, %s);", $word->{id}, $dbh->quote($word->{arg1}), $dbh->quote($word->{arg2}), $shorthand, $position);
		# Cheat for English.
		print $file sprintf("INSERT INTO `localizedInfixes` (`id`, `languageCode`, `meaning`, `habitat`) VALUES ('%d', '%s', %s, %s);", $word->{id}, 'en', $meaning, $wordType);
		
		my $locWords = $m->fetchAllHash('SELECT * FROM dictWordLoc WHERE id = ? && lc IN (' . join(', ', map { "'$_'" } @lcs) . ')', $word->{id});
		
		for my $word (@$locWords) {
			my $meaning = defined($mI) ? $dbh->quote($word->{'arg' . $mI}) : 'NULL';
			my $wordType = defined($wtI) ? $dbh->quote($word->{'arg' . $wtI}) : 'NULL';	
			print $file sprintf("INSERT INTO `localizedInfixes` (`id`, `languageCode`, `meaning`, `habitat`) VALUES ('%d', '%s', %s, %s);", $word->{id}, $word->{lc}, $meaning, $wordType);
		}
	}
	
  close $file;
  
	# FTP
  $ftp->delete("NaviData.sql");
  $ftp->put("$cfg->{EE}{tmpDir}/NaviData.sql", "NaviData.sql") or $m->error("could not ftp: $!");
}

#-----------------------------------------------------------------------------
1;

