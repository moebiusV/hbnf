/* compat.h -- what OpenBSD's sbin/pfctl/parse.y expects of its platform, for building it
 * unchanged on Linux (musl).  Force-included (-include).  Nothing here changes what the
 * parser does; it supplies BSD names and the kernel types net/pfvar.h mentions. */
#ifndef BENCH_PF_COMPAT_H
#define BENCH_PF_COMPAT_H
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
typedef uint8_t u_int8_t; typedef uint16_t u_int16_t; typedef uint32_t u_int32_t; typedef uint64_t u_int64_t;
/* BSD's sa_family_t is a byte; parse.y and its headers agree on that */
#define sa_family_t uint8_t
#define sin_len  sin_zero[0]
#define sin6_len sin6_flowinfo
#define __packed __attribute__((__packed__))
#define RTLABEL_LEN 32
#define RT_TABLEID_MAX 255
struct rt_tableinfo { int rti_tableid; };
struct refcnt { unsigned int r_refs; };
struct timeout { int t; };
struct radix_node { char pad[32]; };
struct radix_node_head { int h; };
#ifndef IPTOS_DSCP_CS0
#define IPTOS_DSCP_CS0 0x00
#define IPTOS_DSCP_CS1 0x20
#define IPTOS_DSCP_CS2 0x40
#define IPTOS_DSCP_CS3 0x60
#define IPTOS_DSCP_CS4 0x80
#define IPTOS_DSCP_CS5 0xa0
#define IPTOS_DSCP_CS6 0xc0
#define IPTOS_DSCP_CS7 0xe0
#define IPTOS_DSCP_VA  0xb0
#endif
long long strtonum(const char *, long long, long long, const char **);
size_t strlcpy(char *, const char *, size_t);
size_t strlcat(char *, const char *, size_t);
#define CTL_NET 4
#define NET_RT_TABLE 5
#define AF_LINK 18
#define IFQ_MAXPRIO 15
#define HTONL(x) ((x) = htonl(x))
#define HTONS(x) ((x) = htons(x))
#define NTOHL(x) ((x) = ntohl(x))
#define NTOHS(x) ((x) = ntohs(x))
int sysctl(const int *, unsigned, void *, size_t *, void *, size_t);
int uid_from_user(const char *, uid_t *);
int gid_from_group(const char *, gid_t *);
uint32_t arc4random(void);
#endif
