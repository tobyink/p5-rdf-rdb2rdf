package Test::RDB2RDF::Suite::PostgreSQL;

use 5.010;
use strict;
use utf8;

use base qw[Test::RDB2RDF::Suite];

sub excuses
{
	my %excuses = shift->SUPER::excuses;
	
	$excuses{R2RMLTC0016a} =
	$excuses{R2RMLTC0016b} =
	$excuses{R2RMLTC0016c} =
	$excuses{R2RMLTC0016d} =
	$excuses{R2RMLTC0016e} =
	$excuses{DirectGraphTC0016} =
		[failed => qq [PostgreSQL doesn't support VARBINARY datatype.]];
	
	$excuses{DirectGraphTC0010} =
		[failed => qq [Cannot yet handle generating URIs for table names with spaces!]];
	
	return %excuses;
}

sub blank_db
{
	my ($self, $num, $iri) = @_;
	
	if (not $num)
	{
		my $dbh = DBI->connect($self->{dsn}, $self->{username}, $self->{password});
		$dbh->{pg_enable_utf8} = 1;
		my $sth = $dbh->table_info(undef, 'public', undef, undef);
		my @tables;
		while (my $row = $sth->fetchrow_hashref)
		{
			push @tables, $row->{TABLE_NAME};
		}
		$dbh->do("DROP TABLE IF EXISTS $_ CASCADE") for @tables;
		$dbh->{PrintWarn} = $dbh->{PrintError} = 0;
		return $dbh;
	}
	
	$self->SUPER::blank_db($num, $iri);
}

1