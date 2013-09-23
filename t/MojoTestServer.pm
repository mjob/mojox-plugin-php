package t::MojoTestServer;
use Mojolicious::Lite;
use Data::Dumper;
use MojoX::Template::PHP;
use PHP;

plugin 'MojoX::Plugin::PHP';

MojoX::Template::PHP::register_header_callback( qr/^X-compute: /,
						\&_compute );

get '/' => sub { $_[0]->render( text => 'This is t::MojoTestServer' ); };
post '/body' => sub {
    my $self = shift;
    my $content_type = 'text/plain';
    if (ref $self->req->body eq 'File::Temp') {
	$self->render( "content-type" => $content_type,
		       text => join q//, readline($self->req->body) );
    } else {
	$self->render( "content-type" => $content_type,
		       text => Data::Dumper::Dumper($self->req->body) );
    }
};

sub _compute {
    use Mojo::JSON;
    my ($key, $payload) = @_;
    $payload = eval { Mojo::JSON->new->decode($payload) };
    if ($@) {
	PHP::assign_global( 'Perl_compute_result', $@ );
	return;
    }
    my $expr = $payload->{expr};
    my $output = $payload->{output} // 'Perl_compute_result';
    my $result = eval $expr;
    if ($@) {
	PHP::assign_global( $output, $@ );
	return;
    }
    PHP::assign_global( $output, $result );
    return 0;  # don't include header with response
}

1;
