# json-tiny: `raku json-tiny.raku FILE` prints "ok json-tiny MS RSS_KIB" for one cold parse of FILE;
# `raku json-tiny.raku -c FILE` prints "FILE 1" when the module accepts FILE and "FILE 0" when it refuses it.
use JSON::Tiny;
sub rss { my $m = '/proc/self/status'.IO.slurp; ($m ~~ /VmHWM ':' \s* (\d+)/)[0].Int }
my $check = @*ARGS[0] eq '-c';
my $file = $check ?? @*ARGS[1] !! @*ARGS[0];
my $text = $file.IO.slurp;
my $r;
my $t0 = now;
my $ok = so try { $r = from-json($text); $r ~~ Failure ?? $r.handled && False !! True };
my $ms = (now - $t0) * 1000;
if $check { say "$file {+$ok}"; exit 0 }
unless $ok { note 'the module refused the document'; exit 1 }
say "ok json-tiny {$ms.round(0.1)} {rss()}";
