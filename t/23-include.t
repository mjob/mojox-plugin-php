use Test::More;
use Test::Mojo;
use strict;
use warnings;

my $t = Test::Mojo->new( 't::MojoTestServer' );
$t->get_ok('/')->status_is(200)->content_is( 'This is t::MojoTestServer' );

# include.php: a script that only works if it can include other scripts
$t->get_ok('/include.php')->status_is(200,'include.php ok')
    ->content_like( qr/x is 625/ )
    ->content_like( qr/y is 343/ )
    ->content_like( qr/z is 64/ );

my $content = $t->tx->res->body;
diag $content;


done_testing();
