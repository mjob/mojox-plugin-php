#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 2;

BEGIN {
    use_ok( 'MojoX::Plugin::PHP' ) || print "Bail out!\n";
    use_ok( 'MojoX::Template::PHP' ) || print "Bail out!\n";
}

diag( "Testing MojoX::Plugin::PHP $MojoX::Plugin::PHP::VERSION, Perl $], $^X" );
