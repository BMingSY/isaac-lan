# ENet

C sources and public headers based on
[ENet v1.3.18](https://github.com/lsalzman/enet/tree/v1.3.18),
commit `2662c0de09e36f2a2030ccc2c528a3e4c9e8138a`. License: `LICENSE` (MIT).

Statically linked; no separate DLL, Steam service, OpenSSL or Protobuf runtime.
The network worker owns each host and peer after setup. Protocol channels and
application bounds belong to `src/net/udp_io.cpp`, not to this vendor copy.

The Windows backend has a local IPv6 extension: `ENetAddress` retains IPv4
fields and adds a family, 128-bit IPv6 address and numeric scope ID. Socket
creation follows the requested family; IPv6 sockets disable `IPV6_V6ONLY`
before binding. IPv4 clients received on a dual-stack listener retain their
IPv4-mapped IPv6 address for replies. Peer matching compares the full address
and scope, and only IPv4 addresses can use the broadcast exception.

These fields are local socket metadata, never serialized. ENet packet layouts
are unchanged. Callers must zero-initialize addresses, use the address setters,
and create a host with the destination's family; a null bind address still
creates an IPv4 socket. Numeric address parsing does not query DNS. Application
DNS resolution and candidate fallback belong to `src/net/host_resolution.cpp`
and `src/net/session.cpp`. The unused Unix backend retains upstream IPv4 behavior.
