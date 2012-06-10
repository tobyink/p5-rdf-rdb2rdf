package Test::RDB2RDF::Suite::SQLite;

use 5.010;
use strict;

use base qw[Test::RDB2RDF::Suite];

sub excuses
{
	my %excuses = shift->SUPER::excuses;

	$excuses{R2RMLTC0009d} =
		[failed => qq [SQLite appears to datatype COUNT() columns as VARCHAR. WTF?]];
		
	$excuses{DirectGraphTC0009} =
	$excuses{DirectGraphTC0011} =
	$excuses{DirectGraphTC0014} =
		[failed => qq [Missing feature in DBD::SQLite.], q<https://rt.cpan.org/Ticket/Display.html?id=50779>];
		
	$excuses{DirectGraphTC0010} =
		[failed => qq [Bug in DBD::SQLite.], q<https://rt.cpan.org/Ticket/Display.html?id=77724>];
		
	$excuses{DirectGraphTC0021} =
	$excuses{DirectGraphTC0022} =
	$excuses{DirectGraphTC0023} =
	$excuses{DirectGraphTC0024} =
	$excuses{DirectGraphTC0025} =
		[untested => qq [SQLite doesn't like create.sql.]];

	return %excuses;
}

1