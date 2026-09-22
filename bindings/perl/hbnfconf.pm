# FFI::Platypus binding for the hbnf C config parser (tests/server.hbnf
# schema).  Install the module first:  cpanm FFI::Platypus
#
#   use hbnfconf;
#   my $c = hbnfconf::parse_config("valid.conf");
package hbnfconf;

use strict;
use warnings;
use FindBin;
use FFI::Platypus 2.00;

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib("$FindBin::Bin/libhbnfconf.so");

# Records mirror conf.h.  `listen` is embedded by value in `server`, so it is
# inlined into the server record's members.
$ffi->type('record(server_t)' => 'struct server' => [
    name      => 'string',       # char* @ 0
    iface     => 'string',       # listen.iface, char* @ 8
    port      => 'uint16',       # listen.port,  uint16 @ 16
    root      => 'string',       # char* @ 24
    redirects => 'opaque',       # redirects_t* @ 32
    aliases   => 'opaque',       # aliases_t* @ 40
    tls       => 'bool',         # bool @ 48
]);

$ffi->attach(parse_config => ['string'] => 'int');
$ffi->attach(conf_ptr    => []        => 'opaque');   # server_t*

sub parse_config {
    my ($path) = @_;
    return undef unless parse_config($path) == 0;

    my $s = $ffi->cast('opaque' => 'record(server_t)', conf_ptr());
    return { name => $s->{name}, iface => $s->{iface}, port => $s->{port},
             root => $s->{root}, tls  => $s->{tls} };
}

1;
