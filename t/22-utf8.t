use Test::More;
use Test::Mojo;
use strict;
use warnings;

my $t = Test::Mojo->new( 't::MojoTestServer' );
$t->get_ok('/')->status_is(200)->content_is( 'This is t::MojoTestServer' );

use utf8;
use Data::Dumper;
use Encode;

{

    $t->get_ok( '/hello_utf8.php' )->status_is(200);
    my $content = $t->tx->res->body;
    my $content2 = Encode::decode("utf-8", $content);
    ok($content ne $content2, 'PHP output contains wide chars' );
    $t->content_is( "Xin chào thế giới" );
}

done_testing();
