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

#has [qw(auto_escape)];
has [qw(code include_file)] => '';
has encoding => 'UTF-8';
has name => 'template.php';
has namespace => 'MojoX::Template::PHPSandbox';
has template => "";

sub interpret {
    no strict 'refs';  # let callbacks be fully qualified subroutine names

    my $self = shift;
    my $c = shift // {};
    local $SIG{__DIE__} = sub {
	CORE::die($_[0]) if ref $_[0];
	Mojo::Exception->throw( shift, 
		[ $self->template, $self->include_file, $self->code ] );
    };

    PHP::__reset;

    my $callbacks = $c && $c->app->config->{'MojoX::Template::PHP'};
    $callbacks ||= {};

    # prepare global variables for the PHP interpreter
    my $variables_order = PHP::eval_return( "ini_get('variables_order')" );
    my $cookie_params = { };
    my $params = $c ? { %{$c->{stash}}, c => $c } : { };

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

    $params->{_FILES} = $self->_files_params($c);

    $self->_set_get_post_request_params( $c, $params, $variables_order );

    if (ref $c->req->body eq 'File::Temp') {
	my $input = join qq//, readline($c->req->body);
	if (my $len = length($input)) {
	    PHP::set_php_input( $input );
	    $params->{HTTP_RAW_POST_DATA} = $input;
	    if ($len < 500) {
		$c->app->log->debug('$HTTP_RAW_POST_DATA: ' . $input);
	    } else {
		$c->app->log->debug('$HTTP_RAW_POST_DATA: ' . $len . ' bytes');
	    }
	}
    } elsif (1) {
	# XXX - should we always set $HTTP_RAW_POST_DATA?
	my $input = $c->req->body;
	if (my $len = length($input)) {
	    PHP::set_php_input( $input );
	    $params->{HTTP_RAW_POST_DATA} = $input;
	}
    }

    # hook to make adjustments to  %$params
    if ($callbacks && $callbacks->{php_var_preprocessor}) {
	$callbacks->{php_var_preprocessor}->($params);
    }

    while (my ($param_name, $param_value) = each %$params) {
	next if 'CODE' eq ref $param_value;
	PHP::assign_global($param_name, $param_value);
    }
    $c && $c->stash( 'php_params', $params );

    my $OUTPUT;
    my $ERROR;
    my $HEADER;
    PHP::options( stdout => sub { $OUTPUT .= $_[0]; } );
    PHP::options(
	stderr => sub { 
	    $ERROR .= $_[0];
	    if ($callbacks && $callbacks->{php_stderr_processor}) {
		$callbacks->{php_stderr_processor}->($_[0]);
	    }
	} );
    PHP::options(
	header => sub { 
	    my ($keyval, $replace) = @_;
	    my ($key,$val) = split /: /, $keyval, 2;
	    my $keep = 1;
	    if ($callbacks && $callbacks->{php_header_processor}) {
		$keep &&= $callbacks->{php_header_processor}->($key, $val, $replace);
	    }
	    return if !$keep;
	    if ($replace) {

		$c->res->headers->header($key,$val);
	    } else {
		$c->res->headers->add($key,$val);
	    }
	    if ($key =~ /^[Ss]tatus$/) {
		my ($code) = $val =~ /^\s*(\d+)/;
		if ($code) {
		    $c->res->code($code);
		} else {
		    $c->app->log->error("Unrecognized Status header: '"
					. $keyval . "' from PHP");
		}
	    }
	} );

#    $c->app->log->debug("CODE TO EXECUTE:");
#    $c->app->log->debug( $self->code );

    if (my $ipath = $c->stash("__php_include_path")) {
	PHP::set_include_path( $ipath );
	$c->app->log->info("include path: $ipath");
    }

    if ($self->include_file) {
	$c->app->log->info("executing " . $self->include_file
			   . " in PHP engine");
	eval { PHP::include( $self->include_file ) };
    } else {
	my $len = length($self->code);
	if ($len < 1000) {
	    $c->app->log->info("executing code:\n\n" . $self->code
			       . "\nin PHP engine");
	} else {
	    $c->app->log->info("executing $len bytes of code in PHP engine");
	}
	eval { PHP::eval( "?>" . $self->code ); };
    }

    if ($@) {
	$c->app->log->error("PHP error: $@");
	$c->app->log->error("Output from PHP engine:\n-------------------");
	$c->app->log->error( $OUTPUT || "<no output>" );
	$c->res->code(500);
	undef $@;
    }

    my $output = $OUTPUT;

    if ($callbacks && $callbacks->{php_output_postprocessor}) {
	$callbacks->{php_output_postprocessor}->(
	    \$output, $c && $c->res->headers, $c);
    }
    if ($c->res->headers->header('Location')) {

	# this is disappointing.
	# if the $output string is empty, Mojo will automatically
	# set a 404 status code?
	if ("" eq ($output // "")) {
	    $output = chr(0);
	}
	if (!$c->res->code) {
	    $c->res->code(302);
	} elsif (500 == $c->res->code) {
	    $c->app->log->info("changing response code from 500 to 302 because there's a location header");
	    $c->res->code(302);
	    $c->app->log->info("output is\n\n" . $output);
	    $c->app->log->info("active exception msg is: $@");
	    undef $@;
	}
    }

    return $output unless $@;
    return Mojo::Exception->new( $@, [$self->template, $self->code] );
}

sub _files_params {
    my ($self, $c) = @_;
    my $_files = {};

    # Find all parameters whose values are Mojo::Upload?
    # XXX - what if there is an array of files using the same 'foo[]' key?
    foreach my $key ($c->param) {
	if ($key =~ /\[\]/) {
	    # what do multiple uploads on the same key look like?
	    foreach my $upload ($c->param($key)) {
		next unless ref $upload eq 'Mojo::Upload';

		# do we have to make our own temp file? ok.
		use File::Temp;
		my ($temp_fh,$tmpname) = File::Temp::tempfile(UNLINK => 1);
		close $temp_fh;
		$upload->move_to($tmpname);

		my $name = scalar($upload->headers->header('name'));
		$key =~ s/\[\]//;

		push @{$_files->{$key}{name}}, $name || $upload->name;
		push @{$_files->{$key}{size}}, $upload->size;
		push @{$_files->{$key}{error}}, 0;
		push @{$_files->{$key}{type}}, $upload->headers->content_type;
		push @{$_files->{$key}{tmp_name}}, $tmpname;
		PHP::_spoof_rfc1867( $tmpname || "" );
	    }
	} else {
	    foreach my $upload ($c->param($key)) {
		next unless ref $upload eq 'Mojo::Upload';

		# do we have to make our own temp file? ok.
		use File::Temp;
		my ($temp_fh,$tmpname) = File::Temp::tempfile(UNLINK => 1);
		close $temp_fh;
		$upload->move_to($tmpname);

		$_files->{$key} = {
		    name => scalar($upload->headers->header("name"))
			|| $upload->name,
			size => $upload->size,
			error => 0,
			type => scalar $upload->headers->content_type ,
			tmp_name => $tmpname,
		};
		PHP::_spoof_rfc1867( $_files->{$key}{tmp_name} || "" );
	    }
	}
    }
    return $_files;
}

sub _cookie_params {
    my ($self, $c) = @_;
    if (@{$c->req->cookies}) {
	$DB::single = 'cookies!';
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
	PATH_INFO => $req->{__old_path} || $req->url->path->to_string,
	QUERY_STRING => $req->url->query->to_string,
	REMOTE_ADDR => $tx->remote_address,
	REMOTE_HOST => gethostbyaddr( inet_aton( $tx->remote_address ), AF_INET ) || '',
	REMOTE_PORT => $tx->remote_port,
	REQUEST_METHOD => $req->method,
	REQUEST_URI => $req->url->path->to_string,
	SERVER_NAME => hostname,
	SERVER_PORT => $tx->local_port,
	SERVER_PROTOCOL => $req->is_secure ? 'HTTPS' : 'HTTP',
	SERVER_SOFTWARE => __PACKAGE__
    };
}

sub _mojoparams_to_phpparams {
    my ($query, @order) = @_;
    my $existing_params = {};
    foreach my $name ($query->param) {
	my @p = $query->param($name);
	$existing_params->{$name} = @p > 1 ? [ @p ] : $p[0];
    }

    # XXX - what if parameter value is a Mojo::Upload ? Do we still
    #       save it in the $_GET/$_POST array?


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
    delete $new_params->{ MojoX::Plugin::PHP->_php_template_pname };
    return $new_params;
}

sub _set_get_post_request_params {
    my ($self, $c, $params, $var_order) = @_;
    my $order = PHP::eval_return( 'ini_get("request_order")' ) || $var_order;
    $params->{$_} = {} for qw(_GET _POST _REQUEST);
    if ($var_order =~ /G/) {
	my $query = $c->req->url && $c->req->url->query;
	if ($query) {
	    $query =~ s/%(5[BD])/chr hex $1/ge;
	    my @order = map { s/=.*//; $_ } split /&/, $query;
	    $params->{_GET} = _mojoparams_to_phpparams(
		 $c->req->url->query, @order );
	}
    }

    if ($var_order =~ /P/ && $c->req->method eq 'POST') {
	my $order = [ $c->req->body_params->param ];
	$params->{_POST} = _mojoparams_to_phpparams(
	    $c->req->body_params, @$order );
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
    $self->include_file('');
    return $self->interpret($c);
}

sub render_file {
    my ($self, $path) = (shift, shift);
    $self->name($path) unless defined $self->{name};
    $self->include_file($path);
    return $self->interpret(@_);
#    my $template = slurp $path;
#    my $encoding = $self->encoding;
#    return $self->render($template, @_);
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

Inline PHP code for template. The L<"interpret"> method
will check the L<"include_file"> attribute first, and then
this attribute to decide what to pass to the PHP interpreter.

=head2 encoding

    my $encoding = $mt->encoding;
    $mt = $mt->encoding( $charset );

Encoding used for template files.

=head2 include_file

    my $file = $mt->include_file;
    $mt = $mt->include_file( $path );

PHP template file to be interpreted. The L<"interpret"> method
will check this attribute, and then the L<"code"> attribute
to decide what to pass to the PHP interpreter.

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

=head2 template

    my $template = $mt->template;
    $mt = $mt->template( $template_name );

Should contain the name of the template currently being processed,
but I don't think it is ever set to anything now. This value will
appear in exception messages.

=head1 METHODS

L<MojoX::Template::PHP> inherits all methods from
L<Mojo::Base>, and the following new ones:

=head2 interpret

    my $output = $mt->interpret($c)

Interpret template code. Starts the PHP engine and evaluates the
template code with it. See L<"CONFIG"/MojoX::Plugin::PHP> for
information about various callbacks that can be used to change
and extend the behavior of the PHP templating engine.

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
