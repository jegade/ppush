#!/usr/bin/env perl

use 5.008007;

use strict;
use warnings;

use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

WriteMakefile(
    NAME         => 'PPush',
    VERSION_FROM => 'lib/PPush.pm',
    ABSTRACT     => 'Websocket Plack app',
    AUTHOR       => 'Jens Gassmann <jegade@cpan.org>',

    ($mm < 6.3002 ? () : ('LICENSE' => 'artistic_2')),

    (   $mm < 6.46
        ? ()
        : ( META_MERGE => {
                requires  => {perl => '5.008007'},
                resources => {
                    license => 'http://dev.perl.org/licenses/',
                    repository =>
                      'http://github.com/jegade/ppush',
                    bugtracker =>
                      'http://github.com/jegade/ppush/issues'
                },
                no_index => {directory => [qw/t/]}
            },
            META_ADD => {
                build_requires     => {},
                configure_requires => {}
            },
        )
    ),

    PREREQ_PM => {
        'AnyEvent'            => 0,
        'HTTP::Body'          => 0,
        'JSON'                => 0,
        'Plack'               => 0,
        'Protocol::WebSocket' => 0.009004,
        'Scalar::Util'        => 0,
        'Try::Tiny'           => 0
    },
    test => {TESTS => 't/*.t t/*/*.t'}
);
