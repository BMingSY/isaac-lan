# ENet

Unmodified C sources and public headers from
[ENet v1.3.18](https://github.com/lsalzman/enet/tree/v1.3.18),
commit `2662c0de09e36f2a2030ccc2c528a3e4c9e8138a`. License: `LICENSE` (MIT).

Statically linked; no separate DLL, Steam service, OpenSSL or Protobuf runtime.
The network worker owns each host and peer after setup. Protocol channels and
application bounds belong to `src/net/udp_io.cpp`, not to this vendor copy.
