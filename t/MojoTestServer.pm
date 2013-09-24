package t::MojoTestServer;
use Mojolicious::Lite;
use Data::Dumper;
use MojoX::Template::PHP;
use PHP;

plugin 'MojoX::Plugin::PHP' => {
    php_var_preprocessor => \&_var_preprocessor,
    php_header_processor => \&_compute_from_header,
    php_output_postprocessor => \&_postprocess_php_output
};

# t::MojoTestServer::_postprocess can be redefined, say, in t/12-postprocess.t

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

# used in t/11-globals.t
sub _var_preprocessor {
    my $params = shift;
    while (my ($key,$val) = each %TestApp::View::PHPTest::phptest_globals) {
	$params->{$key} = $val;
    }
}

# used in t/10-compute.t
sub _compute_from_header {
    my ($key, $payload, $c) = @_;
    return 1 unless $key eq 'X-compute';
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

sub _postprocess_php_output {
    our $postprocessor;
    $postprocessor && $postprocessor->(@_);
}

1;
