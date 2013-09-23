package t::MojoTestServer;
use Mojolicious::Lite;
#use MojoX::Plugin::PHP;

plugin 'MojoX::Plugin::PHP';

get '/' => sub { $_[0]->render( text => 'This is t::MojoTestServer' ); };

1;
