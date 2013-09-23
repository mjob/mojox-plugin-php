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

sub register {
    my ($self, $app, $config) = @_;
#print STDERR "registered ", __PACKAGE__, "\n"
#    ;
    $app->types->type( php => "application/x-php" );
    $app->renderer->add_handler( php => \&_php );
    $app->routes->any( $php_req_handler_path ."/*" . $php_template_pname,
		       \&_php_controller );

    $app->hook( before_dispatch => \&_before_dispatch_hook );
#    $app->hook( after_static => \&_after_static_hook );
#    $app->hook( before_routes => \&_before_routes_hook );

    # XXX   $app->routes()  for all *.php templates ?
}

sub _before_dispatch_hook {
    use Data::Dumper;
    my $c = shift;
    if ($c->req->url->path =~ /\.php$/) {
	my $old_path = $c->req->url->path;
	$c->req->{__old_path} = $old_path;
	$c->req->url->path( $php_req_handler_path . $old_path );
#	print STDERR "Controller is ", Dumper($c);
    }
}

sub _after_static_hook {
    use Data::Dumper;
    my $c = shift;
    if ($c->req->url->path =~ /\.php$/) {
	local $Data::Dumper::Indent = 1;
	local $Data::Dumper::Sortkeys = 1;
	print STDERR "Controller is ", Dumper($c);
	delete $c->stash->{'mojo.static'};
	delete $c->stash->{'mojo.finished'};
	delete $c->stash->{'mojo.rendered'};
	$c->stash( 'mojox.php', 1 );
    }
}

sub _before_routes_hook {
    my $c = shift;
    if ($c->stash('mojox.php')) {
	$c->req->url->path('/hello11');
    }
    print STDERR "path is ", $c->req->url->path, "\n\n";
    print STDERR "stash is ", Dumper($c->stash), "\n\n";
    my $y = 512;
}

sub _php_controller {
    my $self = shift;
    my $template = $self->param( $php_template_pname );
    $self->param( $php_template_pname, undef );
    $self->req->url->path( $self->req->{__old_path} );
    $self->render( template => $template, handler => 'php' );
}

sub _template_path {
    use File::Spec::Functions 'catfile';
    my ($renderer, $c, $options) = @_;
    my $name = $options->{template};
    foreach my $path (@{$renderer->paths}, @{$c->app->static->paths}) {
	my $file = catfile($path, split '/', $name);
	return $file if -r $file;
    }
    return catfile( $renderer->paths->[0], split '/', $name );
}

sub _template_name {
    my ($renderer, $c, $options) = @_;
    my $name = $options->{template};
    return $name;
}

sub _php {
    my ($renderer, $c, $output, $options) = @_;

#   print STDERR "In _php renderer\n";

    my $inline = $options->{inline};
#   my $path = $renderer->template_path($options);
    my $path = _template_path($renderer, $c, $options);

#print STDERR "template path is $path\n"
#    ;

    $path = md5_sum encode('UTF-8', $inline) if defined $inline;
    return undef unless defined $path;

    my $mt = MojoX::Template::PHP->new;
    my $log = $c->app->log;
    if (defined $inline) {
	$log->debug('Rendering inline template.');
	$$output = $mt->name('inline template')->render($inline, $c);
    } else {
	$mt->encoding( $renderer->encoding ) if $renderer->encoding;
#	return undef unless my $t = $renderer->template_name($options);
	return undef unless my $t = _template_name($renderer, $c, $options);

	if (-r $path) {
	    $log->debug( "Rendering template '$t'." );
	    $$output = $mt->name("template '$t'")->render_file($path,$c);
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

=head1 METHODS

=head2 register

    $plugin->register(Mojolicious->new);

Register renderer in L<Mojolicious> application.

=cut
