use lib 'lib';
use Mojolicious::Lite;

#push @{app->static->paths}, 't/public';
#push @{app->renderer->paths}, 't/templates';

plugin 'MojoX::Plugin::PHP' => { name => 'foo' };

app->secret('spike');
app->start;

__DATA__
@@ hello.php.html.php
<?php echo "Hello world"; ?>

@@ hello2.php.html.php
hello world!

@@ hello3.php.html.php
<?php
    $w = "world";
    $h = "hello";
?>
<?php echo $h;?>&nbsp;<?php echo $w; ?>

@@ hello4.php
<?php echo "hello world #4\n"; ?>

