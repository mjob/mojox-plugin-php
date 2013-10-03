# wp-on-mojo.pl: run WordPress on Mojolicious in 34 lines of code
# (29 if you take out the stuff about bitches)
# morbo wp-on-mojo.pl [wp-dir]  or  hypnotoad wp-on-mojo.pl [wp-dir]
package MojoX::WordPress;
use Mojolicious::Lite;

# set this to the home dir of your already-configured WordPress installation
$WordPress::Home = $ARGV[0] || ".../wordpress";

plugin 'MojoX::Plugin::PHP', {
    php_var_preprocessor => sub {
	$_[0]->{_SERVER}{BITCHES} = "Yeah, WordPress on Mojolicious, bitches!";
	PHP::call('set_include_path', $WordPress::Home);
    },
    php_stderr_processor => sub { app->log->error("PHP message: $_[0]"); },
    php_output_postprocessor => sub {
	my ($oref, $headers) = @_;
	$headers->header("X-wordpress-on-mojolicious", "That's right bitches");
    },
    php_header_processor => sub {
	my ($key, $val, $replace) = @_;
	app->log->debug("Header from WordPress: \t$key => $val");
	return 1;
    }
};

get '/bitches' => sub {
    $_[0]->render( text => "Hey! WordPress on Mojolicious, bitches!\n" );
};

push @{app->static->paths}, $WordPress::Home;

app->secret('wordpress on mojolicious, bitches');
app->start;
