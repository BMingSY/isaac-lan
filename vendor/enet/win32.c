/** 
 @file  win32.c
 @brief ENet Win32 system specific functions
*/
#ifdef _WIN32

#define ENET_BUILDING_LIB 1
#include "enet/enet.h"
#include <windows.h>
#include <mmsystem.h>
#include <ws2tcpip.h>

static enet_uint32 timeBase = 0;

int
enet_initialize (void)
{
    WORD versionRequested = MAKEWORD (2, 2);
    WSADATA wsaData;
   
    if (WSAStartup (versionRequested, & wsaData))
       return -1;

    if (LOBYTE (wsaData.wVersion) != 2 ||
        HIBYTE (wsaData.wVersion) != 2)
    {
       WSACleanup ();
       
       return -1;
    }

    timeBeginPeriod (1);

    return 0;
}

void
enet_deinitialize (void)
{
    timeEndPeriod (1);

    WSACleanup ();
}

enet_uint32
enet_host_random_seed (void)
{
    return (enet_uint32) timeGetTime ();
}

enet_uint32
enet_time_get (void)
{
    return (enet_uint32) timeGetTime () - timeBase;
}

void
enet_time_set (enet_uint32 newTimeBase)
{
    timeBase = (enet_uint32) timeGetTime () - newTimeBase;
}

int
enet_address_equal_host (const ENetAddress * first, const ENetAddress * second)
{
    if (first -> family != second -> family)
      return 0;
    if (first -> family == ENET_ADDRESS_IPV6)
      return first -> scopeID == second -> scopeID &&
             memcmp (first -> host6, second -> host6, sizeof (first -> host6)) == 0;
    return first -> host == second -> host;
}

int
enet_address_is_broadcast (const ENetAddress * address)
{
    return address -> family == ENET_ADDRESS_IPV4 && address -> host == ENET_HOST_BROADCAST;
}

int
enet_address_set_sockaddr (ENetAddress * address, const struct sockaddr * source, int length)
{
    ENetAddress result = { 0 };
    if (source == NULL || length < (int) sizeof (source -> sa_family))
      return -1;
    if (source -> sa_family == AF_INET && length >= (int) sizeof (struct sockaddr_in))
    {
        const struct sockaddr_in * sin = (const struct sockaddr_in *) source;
        result.host = sin -> sin_addr.s_addr;
        result.port = ENET_NET_TO_HOST_16 (sin -> sin_port);
    }
    else if (source -> sa_family == AF_INET6 && length >= (int) sizeof (struct sockaddr_in6))
    {
        const struct sockaddr_in6 * sin = (const struct sockaddr_in6 *) source;
        result.family = ENET_ADDRESS_IPV6;
        memcpy (result.host6, & sin -> sin6_addr, sizeof (result.host6));
        result.scopeID = sin -> sin6_scope_id;
        result.port = ENET_NET_TO_HOST_16 (sin -> sin6_port);
    }
    else
      return -1;
    * address = result;
    return 0;
}

static int
enet_address_sockaddr (const ENetAddress * address, struct sockaddr_storage * storage)
{
    memset (storage, 0, sizeof (* storage));
    if (address != NULL && address -> family == ENET_ADDRESS_IPV6)
    {
        struct sockaddr_in6 * sin = (struct sockaddr_in6 *) storage;
        sin -> sin6_family = AF_INET6;
        sin -> sin6_port = ENET_HOST_TO_NET_16 (address -> port);
        memcpy (& sin -> sin6_addr, address -> host6, sizeof (address -> host6));
        sin -> sin6_scope_id = address -> scopeID;
        return sizeof (* sin);
    }
    else
    {
        struct sockaddr_in * sin = (struct sockaddr_in *) storage;
        sin -> sin_family = AF_INET;
        if (address != NULL)
        {
            sin -> sin_port = ENET_HOST_TO_NET_16 (address -> port);
            sin -> sin_addr.s_addr = address -> host;
        }
        return sizeof (* sin);
    }
}

static int
enet_address_lookup (ENetAddress * address, const char * name, int flags)
{
    struct addrinfo hints = { 0 }, * found = NULL;
    ENetAddress result;
    int status;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;
    hints.ai_flags = flags;
    if (getaddrinfo (name, NULL, & hints, & found) != 0)
      return -1;
    status = found != NULL ? enet_address_set_sockaddr (& result, found -> ai_addr, (int) found -> ai_addrlen) : -1;
    freeaddrinfo (found);
    if (status != 0)
      return -1;
    /* These APIs change only the host; a caller may set the port afterwards. */
    address -> host = result.host;
    address -> family = result.family;
    memcpy (address -> host6, result.host6, sizeof (result.host6));
    address -> scopeID = result.scopeID;
    return 0;
}

int
enet_address_set_host_ip (ENetAddress * address, const char * name)
{
    return enet_address_lookup (address, name, AI_NUMERICHOST);
}

int
enet_address_set_host (ENetAddress * address, const char * name)
{
    return enet_address_lookup (address, name, 0);
}

int
enet_address_get_host_ip (const ENetAddress * address, char * name, size_t nameLength)
{
    struct sockaddr_storage storage;
    int length = enet_address_sockaddr (address, & storage);
    return getnameinfo ((struct sockaddr *) & storage, length, name, (DWORD) nameLength,
                        NULL, 0, NI_NUMERICHOST) == 0 ? 0 : -1;
}

int
enet_address_get_host (const ENetAddress * address, char * name, size_t nameLength)
{
    struct sockaddr_storage storage;
    int length = enet_address_sockaddr (address, & storage);
    if (getnameinfo ((struct sockaddr *) & storage, length, name, (DWORD) nameLength,
                     NULL, 0, NI_NAMEREQD) == 0)
      return 0;
    return enet_address_get_host_ip (address, name, nameLength);
}

int
enet_socket_bind (ENetSocket socket, const ENetAddress * address)
{
    struct sockaddr_storage storage;
    int length = enet_address_sockaddr (address, & storage);
    return bind (socket, (struct sockaddr *) & storage, length) == SOCKET_ERROR ? -1 : 0;
}

int
enet_socket_get_address (ENetSocket socket, ENetAddress * address)
{
    struct sockaddr_storage sin;
    int sinLength = sizeof (sin);

    if (getsockname (socket, (struct sockaddr *) & sin, & sinLength) == -1)
      return -1;

    return enet_address_set_sockaddr (address, (struct sockaddr *) & sin, sinLength);
}

int
enet_socket_listen (ENetSocket socket, int backlog)
{
    return listen (socket, backlog < 0 ? SOMAXCONN : backlog) == SOCKET_ERROR ? -1 : 0;
}

ENetSocket
enet_socket_create (ENetSocketType type)
{
    return enet_socket_create_family (type, ENET_ADDRESS_IPV4);
}

ENetSocket
enet_socket_create_family (ENetSocketType type, enet_uint16 family)
{
    SOCKET result = socket (family == ENET_ADDRESS_IPV6 ? AF_INET6 : AF_INET,
                            type == ENET_SOCKET_TYPE_DATAGRAM ? SOCK_DGRAM : SOCK_STREAM, 0);
    if (result != INVALID_SOCKET && family == ENET_ADDRESS_IPV6)
    {
        DWORD onlyV6 = 0;
        if (setsockopt (result, IPPROTO_IPV6, IPV6_V6ONLY, (const char *) & onlyV6, sizeof (onlyV6)) != 0)
        {
            int error = WSAGetLastError ();
            closesocket (result);
            WSASetLastError (error);
            return ENET_SOCKET_NULL;
        }
    }
    return result;
}

int
enet_socket_set_option (ENetSocket socket, ENetSocketOption option, int value)
{
    int result = SOCKET_ERROR;
    switch (option)
    {
        case ENET_SOCKOPT_NONBLOCK:
        {
            u_long nonBlocking = (u_long) value;
            result = ioctlsocket (socket, FIONBIO, & nonBlocking);
            break;
        }

        case ENET_SOCKOPT_BROADCAST:
            result = setsockopt (socket, SOL_SOCKET, SO_BROADCAST, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_REUSEADDR:
            result = setsockopt (socket, SOL_SOCKET, SO_REUSEADDR, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_RCVBUF:
            result = setsockopt (socket, SOL_SOCKET, SO_RCVBUF, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_SNDBUF:
            result = setsockopt (socket, SOL_SOCKET, SO_SNDBUF, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_RCVTIMEO:
            result = setsockopt (socket, SOL_SOCKET, SO_RCVTIMEO, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_SNDTIMEO:
            result = setsockopt (socket, SOL_SOCKET, SO_SNDTIMEO, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_NODELAY:
            result = setsockopt (socket, IPPROTO_TCP, TCP_NODELAY, (char *) & value, sizeof (int));
            break;

        case ENET_SOCKOPT_TTL:
            result = setsockopt (socket, IPPROTO_IP, IP_TTL, (char *) & value, sizeof (int));
            break;

        default:
            break;
    }
    return result == SOCKET_ERROR ? -1 : 0;
}

int
enet_socket_get_option (ENetSocket socket, ENetSocketOption option, int * value)
{
    int result = SOCKET_ERROR, len;
    switch (option)
    {
        case ENET_SOCKOPT_ERROR:
            len = sizeof(int);
            result = getsockopt (socket, SOL_SOCKET, SO_ERROR, (char *) value, & len);
            break;

        case ENET_SOCKOPT_TTL:
            len = sizeof(int);
            result = getsockopt (socket, IPPROTO_IP, IP_TTL, (char *) value, & len);
            break;

        default:
            break;
    }
    return result == SOCKET_ERROR ? -1 : 0;
}

int
enet_socket_connect (ENetSocket socket, const ENetAddress * address)
{
    struct sockaddr_storage sin;
    int length = enet_address_sockaddr (address, & sin);
    int result = connect (socket, (struct sockaddr *) & sin, length);
    if (result == SOCKET_ERROR && WSAGetLastError () != WSAEWOULDBLOCK)
      return -1;

    return 0;
}

ENetSocket
enet_socket_accept (ENetSocket socket, ENetAddress * address)
{
    SOCKET result;
    struct sockaddr_storage sin;
    int sinLength = sizeof (sin);

    result = accept (socket, 
                     address != NULL ? (struct sockaddr *) & sin : NULL, 
                     address != NULL ? & sinLength : NULL);

    if (result == INVALID_SOCKET)
      return ENET_SOCKET_NULL;

    if (address != NULL)
    {
        if (enet_address_set_sockaddr (address, (struct sockaddr *) & sin, sinLength) != 0)
        {
            closesocket (result);
            return ENET_SOCKET_NULL;
        }
    }

    return result;
}

int
enet_socket_shutdown (ENetSocket socket, ENetSocketShutdown how)
{
    return shutdown (socket, (int) how) == SOCKET_ERROR ? -1 : 0;
}

void
enet_socket_destroy (ENetSocket socket)
{
    if (socket != INVALID_SOCKET)
      closesocket (socket);
}

int
enet_socket_send (ENetSocket socket,
                  const ENetAddress * address,
                  const ENetBuffer * buffers,
                  size_t bufferCount)
{
    struct sockaddr_storage sin;
    int sinLength = address != NULL ? enet_address_sockaddr (address, & sin) : 0;
    DWORD sentLength = 0;

    if (WSASendTo (socket, 
                   (LPWSABUF) buffers,
                   (DWORD) bufferCount,
                   & sentLength,
                   0,
                   address != NULL ? (struct sockaddr *) & sin : NULL,
                   sinLength,
                   NULL,
                   NULL) == SOCKET_ERROR)
    {
       if (WSAGetLastError () == WSAEWOULDBLOCK)
         return 0;

       return -1;
    }

    return (int) sentLength;
}

int
enet_socket_receive (ENetSocket socket,
                     ENetAddress * address,
                     ENetBuffer * buffers,
                     size_t bufferCount)
{
    struct sockaddr_storage sin;
    INT sinLength = sizeof (sin);
    DWORD flags = 0,
          recvLength = 0;

    if (WSARecvFrom (socket,
                     (LPWSABUF) buffers,
                     (DWORD) bufferCount,
                     & recvLength,
                     & flags,
                     address != NULL ? (struct sockaddr *) & sin : NULL,
                     address != NULL ? & sinLength : NULL,
                     NULL,
                     NULL) == SOCKET_ERROR)
    {
       switch (WSAGetLastError ())
       {
       case WSAEWOULDBLOCK:
       case WSAECONNRESET:
          return 0;
       case WSAEMSGSIZE:
          return -2;
       }

       return -1;
    }

    if (flags & MSG_PARTIAL)
      return -2;

    if (address != NULL)
    {
        if (enet_address_set_sockaddr (address, (struct sockaddr *) & sin, sinLength) != 0)
          return -1;
    }

    return (int) recvLength;
}

int
enet_socketset_select (ENetSocket maxSocket, ENetSocketSet * readSet, ENetSocketSet * writeSet, enet_uint32 timeout)
{
    struct timeval timeVal;

    timeVal.tv_sec = timeout / 1000;
    timeVal.tv_usec = (timeout % 1000) * 1000;

    return select (maxSocket + 1, readSet, writeSet, NULL, & timeVal);
}

int
enet_socket_wait (ENetSocket socket, enet_uint32 * condition, enet_uint32 timeout)
{
    fd_set readSet, writeSet;
    struct timeval timeVal;
    int selectCount;
    
    timeVal.tv_sec = timeout / 1000;
    timeVal.tv_usec = (timeout % 1000) * 1000;
    
    FD_ZERO (& readSet);
    FD_ZERO (& writeSet);

    if (* condition & ENET_SOCKET_WAIT_SEND)
      FD_SET (socket, & writeSet);

    if (* condition & ENET_SOCKET_WAIT_RECEIVE)
      FD_SET (socket, & readSet);

    selectCount = select (socket + 1, & readSet, & writeSet, NULL, & timeVal);

    if (selectCount < 0)
      return -1;

    * condition = ENET_SOCKET_WAIT_NONE;

    if (selectCount == 0)
      return 0;

    if (FD_ISSET (socket, & writeSet))
      * condition |= ENET_SOCKET_WAIT_SEND;
    
    if (FD_ISSET (socket, & readSet))
      * condition |= ENET_SOCKET_WAIT_RECEIVE;

    return 0;
} 

#endif

