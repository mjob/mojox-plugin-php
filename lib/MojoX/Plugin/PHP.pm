package MojoX::Plugin::PHP;
use Mojo::Base 'Mojolicious::Plugin';

use MojoX::Template::PHP;
use Mojo::Util qw(encode md5_sum);

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

our $VERSION = '0.01';
my $php_req_handler_path = sprintf "/php-handler-%07x", 0x10000000 * rand();
my $php_template_pname = sprintf "template_%07x", 0x10000000 * rand();

sub _php_template_pname { return $php_template_pname; }
sub _php_req_handler_path { return $php_req_handler_path; }

sub register {
    my ($self, $app, $config) = @_;

    $app->config( 'MojoX::Template::PHP' => $config );
    $app->types->type( php => "application/x-php" );
    $app->renderer->add_handler( php => \&_php );

    my $t = "/*" . $php_template_pname;
    for my $i (1 .. 10) {
	$app->routes->any( $php_req_handler_path . $t, \&_php_controller );
	$t = "/*" . $php_template_pname . "_$i" . $t;
    }

    $app->routes->any( $php_req_handler_path ."/*" . $php_template_pname,
		       \&_php_controller );
    $app->hook( before_dispatch => \&_before_dispatch_hook );
}

sub _rewrite_req_for_php_handler {
    my ($c, $path_to_restore, $path_to_request) = @_;
    $c->req->{__old_path} = $path_to_restore;
    $c->req->url->path( $php_req_handler_path . $path_to_request );
#    print STDERR "rewrite req $path_to_restore => $php_req_handler_path.$path_to_request\n";
}

sub _path_contains_index_php {
    my ($path, $c) = @_;
    my $app = $c->app;
    foreach my $dir (@{$app->renderer->paths}, @{$app->static->paths}) {
	my $file = catfile( split('/', $dir), split('/',$path), 'index.php' );
	if (-r $file) {
	    return $file;
	}
    }
    return;
}

sub _before_dispatch_hook {
    my $c = shift;
    my $old_path = $c->req->url->path->to_string;
    if ($old_path =~ /\.php$/) {
	_rewrite_req_for_php_handler( $c, $old_path, $old_path );
    } elsif ($old_path =~ m{/$}) {
	if (_path_contains_index_php($old_path, $c)) {
	    _rewrite_req_for_php_handler($c, $old_path, $old_path.'index.php');
	}
    } else {
	if (_path_contains_index_php($old_path, $c)) {
	    _rewrite_req_for_php_handler($c,$old_path,$old_path.'/index.php');
	}
    }
}

sub _php_controller {
    my $self = shift;
    my $template = $self->param( $php_template_pname );
    # it feels a little dirty to touch the mojo.captures stash
    delete $self->stash('mojo.captures')->{ $php_template_pname };
    for my $i (1 .. 9) {
	my $dir = $self->param( $php_template_pname . "_$i" );
	last unless $dir;
	$template = "$dir/$template";
	delete $self->stash('mojo.captures')->{ $php_template_pname . "_$i" };
    }

    $self->req->url->path( $self->req->{__old_path} );
    $self->render( template => $template, handler => 'php' );
}

sub _template_path {
    use File::Spec::Functions 'catfile';
    my ($renderer, $c, $options) = @_;
    my $name = $options->{template};

    foreach my $path (@{$renderer->paths}, @{$c->app->static->paths}) {
	my $file = catfile($path, split '/', $name);
	if (-r $file) {
	    my @d = split '/', $file;
	    pop @d;
	    $c->stash( '__template_dir', join("/", @d) );
	    return $file;
	}
    }
    my @d = split '/', $renderer->paths->[0];
    pop @d;
    $c->stash( '__template_dir', join("/", @d) );
    return catfile( $renderer->paths->[0], split '/', $name );
}

sub _template_name {
    my ($renderer, $c, $options) = @_;
    my $name = $options->{template};
    return $name;
}

sub _php {
    my ($renderer, $c, $output, $options) = @_;

    my $inline = $options->{inline};
    my $path = _template_path($renderer, $c, $options);

    $path = md5_sum encode('UTF-8', $inline) if defined $inline;
    return undef unless defined $path;

    my $mt = MojoX::Template::PHP->new;
    my $log = $c->app->log;
    if (defined $inline) {
	$log->debug('Rendering inline template.');
	$$output = $mt->name('inline template')->render($inline, $c);
    } else {
	$mt->encoding( $renderer->encoding ) if $renderer->encoding;
	return undef unless my $t = _template_name($renderer, $c, $options);
	$mt->template($t);

	if (-r $path) {
	    use File::Tools qw(pushd popd);
	    my $php_dir = $c->stash('__template_dir') || ".";

	    # XXX - need more consistent way of setting the include path
	    $c->stash("__php_include_path", 
		      ".:/usr/local/lib/php:$php_dir");

	    pushd($php_dir);
	    $log->debug("chdir to: $php_dir");
	    $log->debug( "Rendering template '$t'." );
	    $$output = $mt->name("template '$t'")->render_file($path,$c);
	    popd();
	    $c->stash("__template_dir", undef);
	} elsif (my $d = $renderer->get_data_template($options)) {
	    $log->debug( "Rendering template '$t' from DATA section" );
	    $$output = $mt->name("template '$t' from DATA section")
				->render($d,$c);
	} else {
	    $log->debug("template '$t' not found.");
	    return undef;
	}
    }

    return ref $$output ? die $$output : 1;
}

1;

=encoding UTF8

=head1 NAME

MojoX::Plugin::PHP - enable PHP templates in your Mojolicious application

=head1 VERSION

0.01

=head1 SYNOPSIS

    # MyApp.pl
    app->plugin('MojoX::Plugin::PHP');

=head1 DESCRIPTION

L<MojoX::Plugin::PHP> establishes a PHP engine as the default
handler for C<php> files and templates.

=head1 CONFIG

There are four hooks in the PHP template processing engine
(L<MojoX::Template::PHP>) where you can customize or extend 
the behavior of the PHP engine. In the plugin configuration,
you can specify the code that should be run off each of these
hooks. All of these configuration are optional.

=over 4

=item php_var_preprocessor 

    php_var_preprocessor => sub { my $params = shift; ... }

L<MojoX::Template::PHP> gathers several variables from Perl
and sets them as global variables in the PHP environment. These
include the standard C<$_GET>, C<$_POST>, C<$_REQUEST>,
C<$_SERVER>, C<$_ENV>, C<$_COOKIE>, and C<$_FILES> variables,
but also includes most of the stash variables. All of these
variable values are gathered into a single hash reference.
Right before all of the variables are assigned in PHP, the
PHP engine will look for a C<php_var_preprocessor> setting,
and will invoke its code, passing that hash reference as an
argument. In this callback, you can add, remove, or edit
the set of variables that will be initialized in PHP.

=item php_stderr_processor

    php_stderr_processor => sub { my $msg = shift; ... }

When the PHP interpreter writes a message to its standard error
stream, a callback specified by the C<php_stderr_processor>
config setting can be called with the text that PHP was trying
to write to that stream. You can use this callback to log
warnings and errors from PHP.

=item php_header_processor

    php_header_processor => sub { 
        my ($field,$value,$replace) = @_; 
        ... 
        return $keep_header;
    }

When the PHP C<header()> function is invoked in the PHP interpreter,
a callback specified by the C<php_header_processor> config setting
can be called with the name and value of the header. If this callback
returns a true value (or if there is no callback), the header from
PHP will be included in the Mojolicious response headers.
If this callback returns a false value, the header will not be 
returned with the Mojolicious response.

One powerful use of the header callback is as a communication
channel between PHP and Perl. For example, the header processor
can look for a specific header field. When it sees this header,
the value can be a JSON-encoded payload which can be processed
in Perl. Perl can return the results of the processing through
a global PHP variable (again, possibly JSON encoded). The
C<t/10-headers.t> test case in this distribution has a
proof-of-concept of this kind of use of the header callback.

=item php_output_postprocessor

    php_output_postprocessor => sub {
        my ($output_ref, $headers, $c) = @_;
        ...
    }

When the PHP engine has finished processing a PHP template, and
a callback has been specified with the C<php_output_postprocessor>
config setting, then that callback will be invoked with a
I<reference> to the PHP output, the set of headers returned
by PHP (probably in a L<Mojo::Headers> object), and the current
controller/context object. You can use this
callback for postprocessing the output or the set of headers
that will be included in the Mojolicious response.

One thing that you might want to do in the output post-processing
is to look for a C<Location: ...> header, and determine if you
want the application to follow it.

=back

=head1 METHODS

=head2 register

    $plugin->register(Mojolicious->new);

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<MojoX::Template::PHP>, L<Mojolicious::Plugin::EPRenderer>,
L<Mojolicious::Plugin::EPLRenderer>,
L<Catalyst::View::Template::PHP>, L<PHP>, L<PHP::Interpreter>.

=head1 AUTHOR

Marty O'Brien E<lt>mob@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2013, Marty O'Brien. All rights reserved.

This library is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Sortware Foundation; or the Artistic License.

See http://dev.perl.org/licenses for more information.

=cut
