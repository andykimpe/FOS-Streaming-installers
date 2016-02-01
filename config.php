<?php
include('_start.php');
$databasemanagar->addConnection([
    'driver'    => 'mysql',
    'host'      => 'localhost',
    'database'  => 'FOS-Streaming',
    'username'  => 'root',
    'password'  => 'YOUR_ROOT_MYSQL_PASSWORD',
    'charset'   => 'utf8',
    'collation' => 'utf8_unicode_ci',
    'prefix'    => '',
]);
$debug = false;
include('_load.php');
