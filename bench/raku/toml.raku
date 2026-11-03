# toml: `raku toml.raku FILE` prints "ok toml MS RSS_KIB" for one cold parse of FILE;
# `raku toml.raku -c FILE` prints "FILE 1" when the module accepts FILE and "FILE 0" when it refuses it.
use TOML;
sub rss { my $m = '/proc/self/status'.IO.slurp; ($m ~~ /VmHWM ':' \s* (\d+)/)[0].Int }
my $check = @*ARGS[0] eq '-c';
my $file = $check ?? @*ARGS[1] !! @*ARGS[0];
my $text = $file.IO.slurp;
my $r;
my $t0 = now;
# from-toml reports an error by returning an undefined value (no exception, no Failure); a document is always a Hash
my $ok = so try { $r = from-toml($text); $r.defined };
my $ms = (now - $t0) * 1000;
if $check { say "$file {+$ok}"; exit 0 }
unless $ok { note 'the module refused the document'; exit 1 }
say "ok toml {$ms.round(0.1)} {rss()}";
