#include "engine_save.h"
#include <algorithm>
#include <array>
#include <cstring>
#include <limits>

namespace isaac::save {
namespace {
constexpr std::size_t limit=8*1024*1024;
struct Stream {
    const void* const* vtable;
    std::vector<std::uint8_t> bytes;
    std::size_t position=0;
    bool failed=false, writing=false;
};
#define METHOD __attribute__((fastcall))
void METHOD freeStream(Stream*,void*,bool) {}
long METHOD size(Stream* s,void*) { return static_cast<long>(s->bytes.size()); }
long METHOD position(Stream* s,void*) { return static_cast<long>(s->position); }
void METHOD seek(Stream* s,void*,long offset,int origin) {
    const std::int64_t base=origin==0?0:origin==1?s->position:origin==2?s->bytes.size():-1;
    const auto next=base+offset;
    if(base<0 || next<0 || next>static_cast<std::int64_t>(s->bytes.size())) { s->failed=true;return; }
    s->position=static_cast<std::size_t>(next);
}
bool METHOD eof(Stream* s,void*) { return s->position>=s->bytes.size(); }
unsigned METHOD read(Stream* s,void*,void* buffer,unsigned element,unsigned count) {
    if(!element || !count) return 0;
    const auto available=(s->bytes.size()-s->position)/element;
    const auto n=std::min<std::size_t>(count,available);
    std::memcpy(buffer,s->bytes.data()+s->position,n*element);s->position+=n*element;
    if(n!=count) s->failed=true;
    return static_cast<unsigned>(n);
}
unsigned METHOD line(Stream* s,void*,char* buffer,unsigned maximum) {
    if(!maximum) return 0;
    unsigned n=0;
    while(n+1<maximum && s->position<s->bytes.size()) {
        buffer[n++]=static_cast<char>(s->bytes[s->position++]);
        if(buffer[n-1]=='\n') break;
    }
    buffer[n]=0;return n;
}
unsigned METHOD write(Stream* s,void*,const void* buffer,unsigned element,unsigned count) {
    const auto n=static_cast<std::uint64_t>(element)*count;
    if(!s->writing || n>limit || s->position>limit-n) { s->failed=true;return 0; }
    const auto end=s->position+static_cast<std::size_t>(n);
    if(end>s->bytes.size()) s->bytes.resize(end);
    if(n) std::memcpy(s->bytes.data()+s->position,buffer,static_cast<std::size_t>(n));
    s->position=end;return count;
}
void METHOD noop(Stream*,void*) {}
bool METHOD noOpen(Stream* s,void*,const char*) { s->failed=true;return false; }
bool METHOD isOpen(Stream*,void*) { return true; }
const char* METHOD path(Stream*,void*) { return "isaac-lan/session"; }
#undef METHOD
// Explicit MSVC-compatible vtable. C++ objects allocated by MinGW are never
// passed off as native STL containers or destroyed by the game's allocator.
const void* table[]={reinterpret_cast<void*>(freeStream),reinterpret_cast<void*>(size),
    reinterpret_cast<void*>(position),reinterpret_cast<void*>(seek),reinterpret_cast<void*>(eof),
    reinterpret_cast<void*>(read),reinterpret_cast<void*>(line),reinterpret_cast<void*>(write),
    reinterpret_cast<void*>(noop),reinterpret_cast<void*>(noOpen),reinterpret_cast<void*>(noOpen),
    reinterpret_cast<void*>(noop),reinterpret_cast<void*>(isOpen),reinterpret_cast<void*>(noop),reinterpret_cast<void*>(path)};
struct Context {
    Stream* stream;
    const char* path="isaac-lan/session";
    unsigned version=0, readChecksum=0, flag=0, writeChecksum=0xfedcba76, mode=1;
};
static_assert(sizeof(Context)==28);
std::uintptr_t state(std::uintptr_t image) {
    return *reinterpret_cast<std::uintptr_t*>(image+0x87169c)+0xfa4;
}
struct Bind {
    std::uintptr_t& field;
    std::uintptr_t previous;
    Bind(std::uintptr_t gameState,Stream& stream):field(*reinterpret_cast<std::uintptr_t*>(gameState+0x1fe24)),previous(field) {
        field=reinterpret_cast<std::uintptr_t>(&stream);
    }
    ~Bind() { field=previous; }
};
}
std::vector<std::uint8_t> encode(std::uintptr_t image) {
    return encodeAt(image,state(image));
}
std::vector<std::uint8_t> encodeAt(std::uintptr_t image,std::uintptr_t gameState) {
    Stream stream{table,{},0,false,true};Context context{&stream};
    Bind bound(gameState,stream);
    using Write=bool(__attribute__((thiscall))*)(void*,Context*);
    const bool ok=reinterpret_cast<Write>(image+0x5c9340)(reinterpret_cast<void*>(gameState),&context);
    if(!ok || stream.failed) return {};
    return std::move(stream.bytes);
}
bool decode(std::uintptr_t image,std::span<const std::uint8_t> bytes) {
    return decodeAt(image,state(image),bytes);
}
bool decodeAt(std::uintptr_t image,std::uintptr_t gameState,std::span<const std::uint8_t> bytes) {
    if(bytes.size()<20 || bytes.size()>limit) return false;
    Stream stream{table,{bytes.begin(),bytes.end()}};Context context{&stream};
    using Clear=void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Clear>(image+0x5c79a0)(reinterpret_cast<void*>(gameState));
    Bind bound(gameState,stream);
    using Read=bool(__attribute__((thiscall))*)(void*,Context*,bool);
    const bool ok=reinterpret_cast<Read>(image+0x5cc1a0)(reinterpret_cast<void*>(gameState),&context,false);
    return ok && !stream.failed;
}
std::vector<std::uint8_t> capture(std::uintptr_t image) {
    using Capture=void(__attribute__((thiscall))*)(void*,void*);
    const auto game=*reinterpret_cast<void**>(image+0x871678);
    reinterpret_cast<Capture>(image+0x2f9000)(game,reinterpret_cast<void*>(state(image)));
    return encode(image);
}
}
