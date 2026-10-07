#include "engine_rewind.h"
#include "engine_save.h"
#include "net_protocol.h"
#include "runtime_net.h"
#include <MinHook.h>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <optional>

namespace isaac::rewind {
namespace {
using Address=std::uintptr_t;
Address image;
template<class T> T& at(Address p,unsigned offset) { return *reinterpret_cast<T*>(p+offset); }
Address game() { return at<Address>(image,0x871678); }
constexpr unsigned bufferOffset=0x269ec;
struct Checkpoint {
    std::vector<std::uint8_t> game;
    std::vector<rooms::SavedLocation> locations;
    std::array<unsigned,523> counters{};
    unsigned door=0,tick=0;
};
std::array<std::optional<Checkpoint>,4> checkpoints;
std::optional<unsigned> pending;
using Store=void(__stdcall*)(int);
Store originalStore;
void __stdcall store(int door) {
    // Native room entry uses two process-wide buffers. LAN keeps one last
    // entry per controller, so background entries cannot replace another
    // player's rewind target. Native loading/restoration retains its own work.
    if(!rooms::virtualized()) originalStore(door);
}
Address actor(unsigned slot) {
    const auto first=at<Address>(game(),0x1baa8),last=at<Address>(game(),0x1baac);
    for(auto p=first;p<last;p+=4) {
        const auto player=at<Address>(p,0);
        if(at<int>(player,0x1618)==static_cast<int>(slot+1) && at<unsigned>(player,0x2c)==0) return player;
    }
    return 0;
}
std::vector<std::uint8_t> encode(const Checkpoint& checkpoint,unsigned slot) {
    const auto user=actor(slot);
    if(!user) throw std::runtime_error("Hourglass user is missing");
    lan::Writer w(lan::Message::stage);w.u8(slot);
    w.u32(at<unsigned>(user,0x1da8));w.u32(at<unsigned>(user,0x1dac));
    w.u32(checkpoint.door);w.u32(checkpoint.tick);
    for(auto value:checkpoint.counters) w.u32(value);
    w.u8(checkpoint.locations.size());
    for(auto p:checkpoint.locations) {
        w.u32(p.dimension);w.u32(p.index);w.u32(std::bit_cast<unsigned>(p.x));w.u32(std::bit_cast<unsigned>(p.y));
    }
    w.blob(checkpoint.game);w.u64(lan::snapshotHash(w.bytes));return w.bytes;
}
bool startRewind(std::span<const std::uint8_t> bytes) {
    if(bytes.size()<8) return false;
    lan::Reader checksum(bytes.last(8));
    if(checksum.u64()!=lan::snapshotHash(bytes.first(bytes.size()-8))) return false;
    lan::Reader r(bytes.first(bytes.size()-8));
    if(r.u8()!=static_cast<unsigned>(lan::Message::stage)) return false;
    const auto slot=r.u8();if(slot>=4) return false;
    const auto uses=r.u32(),floorUses=r.u32();Checkpoint checkpoint;
    checkpoint.door=r.u32();checkpoint.tick=r.u32();
    for(auto& value:checkpoint.counters) value=r.u32();
    const auto count=r.u8();if(count<2 || count>4 || slot>=count) return false;
    for(unsigned i=0;i<count;++i) {
        rooms::SavedLocation p{static_cast<int>(r.u32()),static_cast<int>(r.u32()),std::bit_cast<float>(r.u32()),std::bit_cast<float>(r.u32())};
        if(p.dimension<0 || p.dimension>2 || p.index<-20 || p.index>=169 || !std::isfinite(p.x) || !std::isfinite(p.y)) return false;
        checkpoint.locations.push_back(p);
    }
    checkpoint.game=r.blob();r.finish();
    // Rejoin the native complete roster before GameState restoration. The
    // original hourglass transition owns entities, inventory, RNG and effects.
    rooms::beforeStart();
    const auto buffer=game()+bufferOffset;
    if(!save::decodeAt(image,buffer+4,checkpoint.game)) return false;
    at<bool>(buffer,0)=true;at<bool>(game(),bufferOffset+0x20660)=false;
    at<unsigned>(buffer,0x1fe2c)=checkpoint.door;at<unsigned>(buffer,0x1fe30)=checkpoint.tick;
    for(unsigned i=0;i<checkpoint.counters.size();++i) at<unsigned>(buffer,0x1fe34+i*4)=checkpoint.counters[i];
    at<int>(game(),0x676ac)=0;
    const auto user=actor(slot);if(!user) return false;
    at<unsigned>(user,0x1da8)=uses;at<unsigned>(user,0x1dac)=floorUses;
    using Transition=void(__attribute__((thiscall))*)(void*,int,int,int,void*,int);
    const auto location=checkpoint.locations[slot];
    reinterpret_cast<Transition>(image+0x2fd7c0)(reinterpret_cast<void*>(game()),location.index,0,12,reinterpret_cast<void*>(user),location.dimension);
    rooms::resumeAfterTransition(std::move(checkpoint.locations));
    return true;
}
struct API {
    const char* (__cdecl* checkString)(lua_State*,int,std::size_t*);
    void (__cdecl* pushBoolean)(lua_State*,int);
    void (__cdecl* pushClosure)(lua_State*,int(__cdecl*)(lua_State*),int);
    void (__cdecl* setField)(lua_State*,int,const char*);
} lua{};
int beginLua(lua_State* L) {
    try {
        std::size_t size;const auto bytes=lua.checkString(L,1,&size);
        lua.pushBoolean(L,runtime::replica() && startRewind({reinterpret_cast<const std::uint8_t*>(bytes),size}));
    } catch(const std::exception& e) { runtime::abort(e.what());lua.pushBoolean(L,false); }
    return 1;
}
int resetLua(lua_State*) { reset();return 0; }
}
void remember(unsigned slot,int door,const std::vector<rooms::SavedLocation>& locations) {
    if(runtime::replica() || slot>=4 || locations.empty()) return;
    at<int>(game(),0x676ac)=-1;
    originalStore(door);
    at<bool>(game(),bufferOffset+0x20660)=false;
    const auto buffer=game()+bufferOffset;
    if(!at<bool>(buffer,0)) return;
    Checkpoint checkpoint;checkpoint.game=save::encodeAt(image,buffer+4);
    if(checkpoint.game.empty()) throw std::runtime_error("Cannot capture native hourglass state");
    checkpoint.locations=locations;checkpoint.door=at<unsigned>(buffer,0x1fe2c);checkpoint.tick=at<unsigned>(buffer,0x1fe30);
    for(unsigned i=0;i<checkpoint.counters.size();++i) checkpoint.counters[i]=at<unsigned>(buffer,0x1fe34+i*4);
    checkpoints[slot]=std::move(checkpoint);
}
void request(unsigned slot) { if(!pending && slot<4 && checkpoints[slot]) pending=slot; }
bool executePending() {
    if(!pending) return false;
    const auto slot=*pending;pending.reset();
    const auto bytes=encode(*checkpoints[slot],slot);
    runtime::beginRewind(bytes);
    if(!startRewind(bytes)) throw std::runtime_error("Native hourglass rewind failed");
    return true;
}
void reset() { pending.reset();for(auto& checkpoint:checkpoints) checkpoint.reset(); }
bool install(Address base) {
    image=base;
    return MH_CreateHook(reinterpret_cast<void*>(image+0x305ee0),reinterpret_cast<void*>(store),reinterpret_cast<void**>(&originalStore))==MH_OK
        && MH_EnableHook(reinterpret_cast<void*>(image+0x305ee0))==MH_OK;
}
bool bind(lua_State* L,HMODULE module) {
#define IMPORT(field,name) do { auto p=GetProcAddress(module,name);std::memcpy(&lua.field,&p,sizeof(p));if(!lua.field)return false; } while(false)
    IMPORT(checkString,"luaL_checklstring");IMPORT(pushBoolean,"lua_pushboolean");IMPORT(pushClosure,"lua_pushcclosure");IMPORT(setField,"lua_setfield");
#undef IMPORT
    lua.pushClosure(L,beginLua,0);lua.setField(L,-2,"rewind_begin");
    lua.pushClosure(L,resetLua,0);lua.setField(L,-2,"rewind_reset");return true;
}
}
