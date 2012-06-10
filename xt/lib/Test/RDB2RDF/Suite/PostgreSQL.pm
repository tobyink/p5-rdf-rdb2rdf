package Test::RDB2RDF::Suite::PostgreSQL;

use 5.010;
use strict;

use base qw[Test::RDB2RDF::Suite];

sub excuses
{
	my %excuses = shift->SUPER::excuses;

	$excuses{R2RMLTC0003a} =
	$excuses{R2RMLTC0003b} =
	$excuses{R2RMLTC0009d} = 
	$excuses{R2RMLTC0011a} = 
		qq [Column case sensitivity.];
		
	$excuses{R2RMLTC0016a} =
	$excuses{R2RMLTC0016b} =
	$excuses{R2RMLTC0016c} =
	$excuses{R2RMLTC0016d} =
	$excuses{R2RMLTC0016e} =
	$excuses{DirectGraphTC0016} =
		qq [PostgreSQL doesn't support VARBINARY.];

	return %excuses;
}

sub blank_db
{
	my ($self, $num, $iri) = @_;
	
	if (not $num)
	{
		my $dbh = DBI->connect($self->{dsn}, $self->{username}, $self->{password});
		my $sth = $dbh->table_info(undef, 'public', undef, undef);
		my @tables;
		while (my $row = $sth->fetchrow_hashref)
		{
			push @tables, $row->{TABLE_NAME};
		}
		$dbh->do("DROP TABLE IF EXISTS $_ CASCADE") for @tables;
		return $dbh;
	}
	
	$self->SUPER::blank_db($num, $iri);
}

1