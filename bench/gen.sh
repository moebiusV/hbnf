#!/bin/sh
# gen.sh toy|pfctl N  ->  N rules on stdout, deterministic.
#
# toy: the §6 toy shape, 84 bytes for the example
#   pass in on em0 proto tcp from 192.168.3.7 port 51234 to 192.168.9.1 port 443
# pfctl: real pf syntax, 105 bytes for the example
#   pass in quick on em0 inet proto tcp from 10.1.2.3 port 1234 to 10.4.5.6 port 80 keep state
#
# The source port cycles 1000..65535 so no two consecutive rules are
# identical (a small amount of real variation, still deterministic).

mode=${1:?usage: gen.sh toy|pfctl N}
n=${2:?usage: gen.sh toy|pfctl N}

case $mode in
toy)
	awk -v n="$n" 'BEGIN {
		for (i = 1; i <= n; i++)
			printf "pass in on em0 proto tcp from 192.168.3.7 port %d to 192.168.9.1 port 443\n",
			       1000 + (i % 64536);
	}'
	;;
pfctl)
	awk -v n="$n" 'BEGIN {
		for (i = 1; i <= n; i++)
			printf "pass in quick on em0 inet proto tcp from 10.1.2.3 port %d to 10.4.5.6 port 80 keep state\n",
			       1000 + (i % 64536);
	}'
	;;
*)
	echo "gen.sh: unknown mode $mode" >&2
	exit 2
	;;
esac
