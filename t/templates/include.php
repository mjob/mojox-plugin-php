<?php
/* a php file that includes other php files */

include("./include1.php");

echo "x is $x\n";

require_once("./include2/include3.php");

echo "y is $y\n";

echo get_include_path();