package t::MojoTestServer;
use Mojolicious::Lite;
use Data::Dumper;
#use MojoX::Plugin::PHP;

plugin 'MojoX::Plugin::PHP';

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

1;
