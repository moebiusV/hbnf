| daemon | `parse.y` total | lexer, keywords, C | actions | rule notation | hbnf grammar |
|---|---:|---:|---:|---:|---:|
| bgpd | 5,540 | 2,530 | 2,494 | 516 | 501 |
| dhcpleased | 733 | 542 | 159 | 32 | 22 |
| httpd | 2,490 | 1,185 | 1,057 | 248 | 185 |
| ldpd | 1,498 | 868 | 484 | 146 | 114 |
| ntpd | 731 | 377 | 292 | 62 | 22 |
| pfctl | 5,885 | 2,524 | 2,777 | 584 | 492 |
| relayd | 3,426 | 1,266 | 1,814 | 346 | 323 |
| snmpd | 1,867 | 900 | 813 | 154 | 121 |
| unwind | 831 | 593 | 166 | 72 | 67 |
| shared `obconf.hbnf` | | | | | 30 |
| **nine daemons** | **23,001** | **10,785** | **10,056** | **2,160** | **1,877** |

Only the rule notation is directly comparable with the hbnf grammar; the
lexer is replaced by hbnf's reader, and the actions only where they are bound:

| daemon | `parse.y` total | hbnf grammar + bound actions | saved |
|---|---:|---:|---:|
| ntpd | 731 | 22 + 331 = 353 | **52%** |
| unwind | 831 | 67 + 264 = 331 | **60%** |
