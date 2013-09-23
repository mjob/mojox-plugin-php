use Test::More;
use Test::Mojo;
use Data::Dumper;
use strict;
use warnings;

$Data::Dumper::Indent = $Data::Dumper::Sortkeys = 1;

my $t = Test::Mojo->new( 't::MojoTestServer' );
$t->get_ok('/')->status_is(200)->content_is('This is t::MojoTestServer');

# vars.php: dump PHP $_GET, $_POST, $_REQUEST, $_SERVER, $_ENV, $_COOKIE, $_FILES vars
$t->get_ok('/vars.php')->status_is(200, 'data returned for vars.php')
    ->content_like( qr/_GET = array *\(\s*\)/, '$_GET is empty' )
    ->content_like( qr/_POST = array *\(\s*\)/, '$_POST is empty' )
    ->content_like( qr/_REQUEST = array *\(\s*\)/, '$_REQUEST is empty' )
    ->content_like( qr/_SERVER =/, '$_SERVER spec found' )
    ->content_unlike( qr/_SERVER = array *\(\s*\)/, '$_SERVER not empty')
    ->content_like( qr/_ENV =/, '$_ENV spec found' )
    ->content_unlike( qr/_ENV = array *\(\s*\)/, '$_ENV not empty')
    ->content_like( qr/_COOKIE = array *\(\s*\)/, '$_COOKIE is empty' )
    ->content_like( qr/_GET = array *\(\s*\)/, '$_GET is empty' );

$t->get_ok('/vars.php?abc=123&def=456')->status_is(200, 'vars.php request with query');
my $content = $t->tx->res->body;
ok( $content !~ /_GET = array *\(\s*\)/, '$_GET not empty' );
ok( $content =~ /_GET.*abc.*=.*123.*_POST/s, '$_GET["abc"] ok');
ok( $content =~ /_GET.*def.*=.*456.*_POST/s, '$_GET["def"] ok');
ok( $content =~ /_POST = array *\(\s*\)/, '$_POST is empty' );
ok( $content !~ /_REQUEST = array *\(\s*\)/, '$_REQUEST not empty' );
ok( $content =~ /_REQUEST.*abc.*=.*123.*_SERVER/s &&
    $content =~ /_REQUEST.*def.*=.*456.*_SERVER/s, '$_REQUEST mimics $_GET'
    );
ok( $content =~ /_SERVER = array/ &&
    $content !~ /_SERVER = array *\(\s*\)/, '$_SERVER not empty' );
ok( $content =~ /_ENV = array/ &&
    $content !~ /_ENV = array *\(\s*\)/, '$_ENV not empty' );
ok( $content =~ /_COOKIE = array *\(\s*\)/, '$_COOKIE is empty' );



done_testing();
