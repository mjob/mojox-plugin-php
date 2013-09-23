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

our $VERSION = '0.01';

#has [qw(auto_escape compiled)];
has [qw(code)] => '';
has encoding => 'UTF-8';
#has escape => sub { \&Mojo::Util::xml_escape };
has name => 'template.php';
has namespace => 'MojoX::Template::PHPSandbox';
has template => "";

sub interpret {
    my $self = shift;
    my $c = shift // {};
    local $SIG{__DIE__} = sub {
	CORE::die($_[0]) if ref $_[0];
	Mojo::Exception->throw( shift, [ $self->template, $self->code ] );
    };

    # prepare global variables for the PHP interpreter
    my $variables_order = PHP::eval_return( "ini_get('variables_order')" );
    my $cookie_params = { };
    my $params = { };
    if ($c) {
	$params = { %{$c->{stash}}, c => $c };
    }

    if ($variables_order =~ /S/) {
	$params->{_SERVER} = $self->_server_params($c);
	$params->{_ENV} = \%ENV;
    } elsif ($variables_order =~ /E/) {
	$params->{_ENV} = \%ENV;
    }
    if ($variables_order =~ /C/) {
	$cookie_params = $self->_cookie_params($c);
	$params->{_COOKIE} = $cookie_params;
    }
    # FIXME LATER: $params->{_FILES} = $self->_process_uploads($c);
    $self->_set_method_params( $c, $params, $variables_order );

    while (my ($param_name, $param_value) = each %$params) {
	PHP::assign_global($param_name, $param_value);
    }
    $c && $c->stash( 'php_params', $params );

    # TODO:  include_path

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

sub _cookie_params {
    my ($self, $c) = @_;
    if (@{$c->req->cookies}) {
	$DB::single = 1;
    }
    # Mojo: $c->req->cookies is [], in Catalyst it is {}
    my $p = { map {;
		 $_ => $c->req->cookies->{$_}{value}[0]
	      } @{$c->req->cookies} };
    return $p;
}

sub _server_params {
    use Socket;
    use Sys::Hostname;
    my ($self, $c) = @_;

    my $tx = $c->tx;
    my $req = $c->req;
    my $headers = $req->headers;

    # see  Mojolicious::Plugin::CGI
    return {
	CONTENT_LENGTH => $headers->content_length || 0,
	CONTENT_TYPE => $headers->content_type || 0,
	GATEWAY_INTERFACE => 'PHP/5.x',
	HTTP_COOKIE => $headers->cookie || '',
	HTTP_HOST => $headers->host || '',
	HTTP_REFERER => $headers->referrer || '',
	HTTP_USER_AGENT => $headers->user_agent || '',
	HTTPS => $req->is_secure ? 'YES' : 'NO',
	PATH_INFO => $req->url->path,
	QUERY_STRING => $req->url->query->to_string,
	REMOTE_ADDR => $tx->remote_address,
	REMOTE_HOST => gethostbyaddr( inet_aton( $tx->remote_address ), AF_INET ) || '',
	REMOTE_PORT => $tx->remote_port,
	REQUEST_METHOD => $req->method,
	SERVER_NAME => hostname,
	SERVER_PORT => $tx->local_port,
	SERVER_PROTOCOL => $req->is_secure ? 'HTTPS' : 'HTTP',
	SERVER_SOFTWARE => __PACKAGE__
    };
}

sub _php_method_params {
    my ($query, @order) = @_;
    my $existing_params = {};
    foreach my $name ($query->param) { # 23,29,34,35,43,44,45,49
	my @p = $query->param($name);
	$existing_params->{$name} = @p > 1 ? $p[-1] : $p[0];
    }

    # The conventional ways to parse input parameters with Perl (CGI/Catalyst)
    # are different from the way that PHP parses the input. Some examples:
    #
    # 1. foo=first&foo=second&foo=lats
    #
    #    In Perl, value for the parameter 'foo' is an array ref with 3 values
    #    In PHP, value for param 'foo' is 'last', whatever the last value was
    #    See also example #5
    #
    # 2. foo[bar]=value1&foo[baz]=value2
    #
    #    In Perl, this creates scalar parameters 'foo[bar]' and 'foo[baz]'
    #    In PHP, this creates the parameter 'foo' with an associative array
    #            value ('bar'=>'value1', 'baz'=>'value2')
    #
    # 3. foo[bar]=value1&foo=value2&foo[baz]=value3
    #
    #    In Perl, this creates parameters 'foo[bar]', 'foo', and 'foo[baz]'
    #    In PHP, this create the parameter 'foo' with an associative array
    #            with value ('baz'=>'value3'). The values associated with
    #            'foo[bar]' and 'foo' are lost.
    #
    # 4. foo[2][bar]=value1&foo[2][baz]=value2
    #
    #    In Perl, this creates parameters 'foo[2][bar]' and 'foo[2][baz]'
    #    In PHP, this creates a 2-level hash 'foo'
    #
    # 5. foo[]=123&foo[]=234&foo[]=345
    #    In Perl, parameter 'foo[]' assigned to array ref [123,234,345]
    #    In PHP, parameter 'foo' is an array with elem (123,234,345)
    #
    # For a given set of Perl-parsed parameter input, this function returns
    # a hashref that resembles what the same parameters would look like
    # to PHP.

    my $new_params = {};
    foreach my $pp (@order) {
	my $p = $pp;
	if ($p =~ s/\[(.+)\]$//) {
	    my $key = $1;
	    s/%(..)/chr hex $1/ge for $p, $pp, $key;

	    if ($key ne '' && $new_params->{$p}
		    && ref($new_params->{$p} ne 'HASH')) {
		$new_params->{$p} = {};
	    }

	    # XXX - how to generalize this from 2 to n level deep hash?
	    if ($key =~ /\]\[/) {
		$DB::single = 1;
		my ($key1, $key2) = split /\]\[/, $key;
		$new_params->{$p}{$key1}{$key2} = $existing_params->{$pp};
	    } else {
		$new_params->{$p}{$key} = $existing_params->{$pp};
	    }
	} elsif ($p =~ s/\[\]$//) {
	    # expect $existing_params->{$pp} to already be an array ref
	    $p =~ s/%(..)/chr hex $1/ge;
	    $new_params->{$p} = $existing_params->{$pp};
	} else {
	    $p =~ s/%(..)/chr hex $1/ge;
	    $new_params->{$p} = $existing_params->{$p};
	    if ('ARRAY' eq ref $new_params->{$p}) {
		$new_params->{$p} = $new_params->{$p}[-1];
	    }
	}
    }
    delete $new_params->{ MojoX::Plugin::PHP->php_template_pname };
    return $new_params;
}

sub _set_method_params {
    my ($self, $c, $params, $var_order) = @_;
    my $order = PHP::eval_return( 'ini_get("request_order")' ) || $var_order;
    $params->{$_} = {} for qw(_GET _POST _REQUEST);
    if ($var_order =~ /G/) {
	my $query = $c->req->url && $c->req->url->query;
	if ($query) {
	    $query =~ s/%(5[BD])/chr hex $1/ge;
	    my @order = map { s/=.*//; $_ } split /&/, $query;
	    $params->{_GET} = _php_method_params(
		 $c->req->url->query, @order );
	}
    }

    # TODO: $var_order =~ /P/ && method eq 'POST'
    $DB::single ||= keys %{$params->{_GET}};
    if ($var_order =~ /P/ && $c->req->method eq 'POST') {
	my $order = [ $c->req->body_params->param ];
	$params->{_POST} = _php_method_params( $c->req->body_params, @$order );
    }

    $params->{_REQUEST} = {};
    foreach my $reqvar (split //, uc $order) {
	if ($reqvar eq 'C') {
	    $params->{_REQUEST} = { %{$params->{_REQUEST}}, 
				    %{$params->{_COOKIE}} };
	} elsif ($reqvar eq 'G') {
	    $params->{_REQUEST} = { %{$params->{_REQUEST}}, 
				    %{$params->{_GET}} };
	} elsif ($reqvar eq 'P') {
	    $params->{_REQUEST} = { %{$params->{_REQUEST}}, 
				    %{$params->{_POST}} };
	}
    }
    return;
}

sub render {
    my $self = shift;
    my $c = pop if @_ && ref $_[-1];
    $self->code( join '', @_ );
    return $self->interpret($c);
}

sub render_file {
    my ($self, $path) = (shift, shift);
    $self->name($path) unless defined $self->{name};
    my $template = slurp $path;
    my $encoding = $self->encoding;
    return $self->render($template, @_);
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

=head1 VERSION

0.01

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

=head2 encoding

    my $encoding = $mt->encoding;
    $mt = $mt->encoding( $charset );

Encoding used for template files.

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
