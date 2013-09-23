package MojoX::Template::PHP;
use 5.010;
use Mojo::Base -base;
use Carp 'croak';
use PHP 0.15;
use Mojo::ByteStream;
use Mojo::Exception;
use Mojo::Util qw(decode encode monkey_patch slurp);
use constant DEBUG => 
    $ENV{MOJO_TEMPLATE_DEBUG} || $ENV{MOJOX_TEMPLATE_PHP_DEBUG} || 0;

#has [qw(auto_escape compiled)];
has [qw(code)] => '';
has encoding => 'UTF-8';
has escape => sub { \&Mojo::Util::xml_escape };
has name => 'template.php';
has namespace => 'MojoX::Template::PHPSandbox';


sub build {
    my $self = shift;
    return $self;
}

sub interpret {
    my $self = shift;
    local $SIG{__DIE__} = sub {
	CORE::die($_[0]) if ref $_[0];
	Mojo::Exception->throw( shift, [ $self->template, $self->code ] );
    };
    my $OUTPUT;
    my $ERROR;
    my $HEADER;
    PHP::options( stdout => sub { $OUTPUT .= $_[0]; } );
    PHP::options( stderr => sub { $ERROR .= $_[0]; } );
    PHP::options( header => sub { $HEADER .= "$_[0]\n" } );

#   print STDERR "PHP interpreter receiving code: ", $self->code, "\n\n";

    my $z = PHP::eval( "?>" . $self->code . "<?php ");
    my $output = $OUTPUT;

    return $output unless $@;
    return Mojo::Exception->new( $@, [$self->template, $self->code] );
}

sub render {
    my $self = shift;
    my $c = pop if @_ && ref $_[-1];
    $self->code( join '', @_ );
    return $self->interpret;
}

sub render_file {
    my ($self, $path) = (shift, shift);
    $self->name($path) unless defined $self->{name};
    my $template = slurp $path;
    my $encoding = $self->encoding;
    return $self->render($template);
}

unless (caller) {
    my $mt = MojoX::Template::PHP->new;
    my $output = $mt->render(<<'EOF');
<html>
    <head><title>Simple</title><head>
    <body>
        Time: <?php echo "figuring out the time in PHP is too hard!"; ?>
    </body>
</html>
EOF
    say $output;

    open my $fh, '>/tmp/test.php' or die;
    print $fh <<'EOF';
<?php echo "hello world\n"; ?>
HeLlO WoRlD!
<?php echo "HELLO WORLD\n"; ?>
EOF
    close $fh;
    $output = $mt->render_file( '/tmp/test.php' );
    say $output;
    unlink '/tmp/test.php';
}

1;

=encoding utf8

=head1 NAME

MojoX::Template::PHP - Use PHP as templating system in Mojolicious

=head1 WTF

Keep reading.

=head1 SYNOPSIS

    use MojoX::Template::PHP;
    my $mt = MojoX::Template::PHP->new;
    my $output = $mt->render(<<'EOF');
    <html>
        <head><title>Simple</title><head>
        <body>Time: 
            <?php ?>
        </body>
    </html>
    EOF
    say $output;

=head1 DESCRIPTION

L<MojoX::Template::PHP> is a way to use PHP as a templating
system for your PHP application. Why would anyone, anywhere,
ever want to do this? Here are two that I can think of

=over 4

=item 1. You can put a Mojolicious wrapper around some decent
PHP application (say, WordPress)

=item 2. You are on a development project with Perl and PHP
programmers, and you want to use Mojolicious as a backend
without scaring the PHP developers.

=back

=head1 ATTRIBUTES

L<MojoX::Template::PHP> implements the following attributes:

=head2 code

    my $code = $mt->code;
    $mt = $mt->code($code);

PHP code for template.

=head2 name

    my $name = $mt->name;
    $mt = $mt->name('foo.php');

Name of the template currently being processed. Defaults to
C<template.php>. This value should not contain quotes or
newline characters, or error messages might end up being wrong.

=head2 namespace

    my $namespace = $mt->namespace;
    $mt = $mt->namespace('PHP::Sandbox');

Namespace used to compile templates, defaults to
C<MojoX::Template::PHPSandbox>. 

=head1 METHODS

L<MojoX::Template::PHP> inherits all methods from
L<Mojo::Base>, and the following new ones:

=head2 interpret

    my $output = $mt->interpret;

Interpret compiled template code.

=head2 render

    my $output = $mt->render($template);

Render a PHP template.

=head2 render_file

    my $output = $mt->render_file( $php_file_path );

Render template file.

=head1 DEBUGGING

You can set either the C<MOJO_TEMPLATE_DEBUG> or
C<MOJOX_TEMPLATE_PHP_DEBUG> environment variable to enable
some diagnostics information printed to C<STDERR>.

=head1 SEE ALSO

L<MojoX::Plugin::PHP>, L<Mojo::Template>, L<PHP>,
L<Catalyst::View::Template::PHP>

=head1 AUTHOR

Marty O'Brien E<lt>mob@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2013, Marty O'Brien. All rights reserved.

This library is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Sortware Foundation; or the Artistic License.

See http://dev.perl.org/licenses for more information.

=cut
