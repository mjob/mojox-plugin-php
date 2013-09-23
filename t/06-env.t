use Test::More;
use Test::Mojo;
use strict;
use warnings;

sub array {
    return { @_ };
}

{

    my $z1 = sprintf "VAR%08x", rand(0x7FFFFFFF);
    my $z2 = sprintf "VAL%08x", rand(0x7FFFFFFF);
    $ENV{$z1} = $z2;

    my $t = Test::Mojo->new( 't::MojoTestServer' );
    $t->get_ok('/vars.php')->status_is(200);
    my $content = $t->tx->res->body;

    my ($env) = $content =~ /\$_ENV = array *\((.*)\)\s*\$_COOKIE/s;
    my @env = split /\n/, $env;

    my $key_count = 0;
    while (my ($k,$v) = each %ENV) {
	$key_count++;
	next if $v =~ /\n/;
	ok( grep(/\Q$k\E.*=>.*\Q$v\E/,@env), "ENV $k ok" );
    }
    ok( $key_count > 2, "at least some env vars found ($key_count)" );
}

done_testing();
