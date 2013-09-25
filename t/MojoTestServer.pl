package t::MojoTestServer;
use lib 'lib', '../lib';
use t::MojoTestServer;

app->secret('x');
app->start;

__END__

=head1 NAME

t/MojoTestServer.pl - command line access to test PHP templates

=head1 DESCRIPTION

There are several PHP templates under C<t/templates> and
C<t/public/php> for testing the L<MojoX::Plugin::PHP> distribution.
Many of these are used by the L<MojoX::Plugin::PHP>
unit tests. For module and test development, it is helpful to
have a command-line tool to see what the output and other results
are for executing a template. This is that tool.

Typical usage:

    perl t/MojoTestServer.pl get /foo.php


