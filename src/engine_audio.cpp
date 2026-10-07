#include "engine_audio.h"
#include "engine_rooms.h"
#include "runtime_net.h"
#include "net_protocol.h"
#include <MinHook.h>
#include <bit>
#include <deque>
#include <cstring>
#include <map>
#include <optional>
#include <cmath>

namespace isaac::audio {
namespace {
struct Event { std::uint32_t serial,tick;unsigned audience;int id;float volume;int delay;bool loop;float pitch,pan; };
std::deque<Event> events;
std::uint32_t serial=0;
std::uintptr_t image=0;
template<class T> T& at(std::uintptr_t p,unsigned offset) { return *reinterpret_cast<T*>(p+offset); }
using Key=std::pair<int,int>;
Key roomKey() { const auto g=at<std::uintptr_t>(image,0x871678);return {at<int>(g,0x1830c),at<int>(g,0x18304)}; }
struct MusicState { unsigned mode=0;int id=0;float parameter=0;bool operator==(const MusicState&) const=default; };
std::map<Key,MusicState> music;
std::optional<std::pair<Key,MusicState>> played;
using MusicCall=void(__attribute__((thiscall))*)(void*,int,float);
MusicCall originalMusicPlay=nullptr,originalMusicFade=nullptr;
unsigned scopeDepth=0;
std::array<unsigned,2> audibleIDs{};
void musicCall(void* manager,int id,float parameter,unsigned mode,MusicCall original) {
    const auto audience=rooms::soundAudience();
    if(audience) {
        if(runtime::replica()) return;
        music[roomKey()]={mode,id,parameter};
        if(scopeDepth) {
            // Native room music selection reads these IDs directly. Give it
            // its own request, without making a background room audible.
            at<unsigned>(reinterpret_cast<std::uintptr_t>(manager),0x30c)=id;
            at<unsigned>(reinterpret_cast<std::uintptr_t>(manager),0x310)=0;
            return;
        }
        if(!(audience&1)) return;
        played=std::pair{roomKey(),music[roomKey()]};
    }
    original(manager,id,parameter);
}
void __attribute__((fastcall)) musicPlay(void* manager,void*,int id,float volume) { musicCall(manager,id,volume,1,originalMusicPlay); }
void __attribute__((fastcall)) musicFade(void* manager,void*,int id,float rate) { musicCall(manager,id,rate,2,originalMusicFade); }
using Play=void(__attribute__((thiscall))*)(void*,int,float,int,bool,float,float);
Play originalPlay=nullptr;
void __attribute__((fastcall)) play(void* manager,void*,int id,float volume,int delay,bool loop,float pitch,float pan) {
    const auto audience=rooms::soundAudience();
    if(audience && !runtime::replica()) {
        events.push_back({++serial,runtime::tick(),audience,id,volume,delay,loop,pitch,pan});
        while(events.size()>512) events.pop_front();
        // Background rooms retain gameplay and send their sounds to occupants.
        if(!(audience&1)) volume=0;
    }
    originalPlay(manager,id,volume,delay,loop,pitch,pan);
}
struct API {
    void (__cdecl* pushClosure)(lua_State*,int(__cdecl*)(lua_State*),int);
    void (__cdecl* setField)(lua_State*,int,const char*);
    long long (__cdecl* checkInteger)(lua_State*,int);
    const char* (__cdecl* pushString)(lua_State*,const char*,std::size_t);
    const char* (__cdecl* checkString)(lua_State*,int,std::size_t*);
    int (__cdecl* getTop)(lua_State*);
    void (__cdecl* pushBoolean)(lua_State*,int);
} lua{};
int musicState(lua_State* L) {
    try {
        const auto key=roomKey();
        if(lua.getTop(L)==0) {
            const auto found=music.find(key);const auto value=found==music.end()?MusicState{}:found->second;
            lan::Writer w(lan::Message::world);w.u8(value.mode);w.u32(value.id);w.u32(std::bit_cast<unsigned>(value.parameter));
            lua.pushString(L,reinterpret_cast<const char*>(w.bytes.data()+1),w.bytes.size()-1);return 1;
        }
        if(!runtime::replica()) throw std::runtime_error("Only replicas apply room music");
        std::size_t size=0;const auto data=lua.checkString(L,1,&size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(data),size});
        MusicState value;value.mode=r.u8();value.id=r.u32();value.parameter=std::bit_cast<float>(r.u32());r.finish();
        if(value.mode>2 || value.id<0 || !std::isfinite(value.parameter)) throw std::runtime_error("Invalid room music");
        music[key]=value;lua.pushBoolean(L,true);return 1;
    } catch(const std::exception& e) { runtime::abort(e.what());lua.pushBoolean(L,false);return 1; }
}
int capture(lua_State* L) {
    const auto slot=lua.checkInteger(L,1);const auto tick=runtime::tick();
    lan::Writer bytes(lan::Message::world);
    if(slot>=0 && slot<4) for(const auto& event:events) {
        if(!(event.audience&(1u<<slot)) || tick-event.tick>30) continue;
        bytes.u32(event.serial);bytes.u32(event.tick);bytes.u32(event.id);
        bytes.u32(std::bit_cast<std::uint32_t>(event.volume));bytes.u32(event.delay);bytes.u8(event.loop);
        bytes.u32(std::bit_cast<std::uint32_t>(event.pitch));bytes.u32(std::bit_cast<std::uint32_t>(event.pan));
    }
    lua.pushString(L,reinterpret_cast<const char*>(bytes.bytes.data()+1),bytes.bytes.size()-1);return 1;
}
int resetLua(lua_State*) { reset();return 0; }
}
bool install(std::uintptr_t base) {
    image=base;
    return MH_CreateHook(reinterpret_cast<void*>(image+0x52dc30),reinterpret_cast<void*>(play),reinterpret_cast<void**>(&originalPlay))==MH_OK
        && MH_EnableHook(reinterpret_cast<void*>(image+0x52dc30))==MH_OK
        && MH_CreateHook(reinterpret_cast<void*>(image+0x3e1d50),reinterpret_cast<void*>(musicPlay),reinterpret_cast<void**>(&originalMusicPlay))==MH_OK
        && MH_EnableHook(reinterpret_cast<void*>(image+0x3e1d50))==MH_OK
        && MH_CreateHook(reinterpret_cast<void*>(image+0x3e1e70),reinterpret_cast<void*>(musicFade),reinterpret_cast<void**>(&originalMusicFade))==MH_OK
        && MH_EnableHook(reinterpret_cast<void*>(image+0x3e1e70))==MH_OK;
}
bool bind(lua_State* L,HMODULE module) {
#define IMPORT(field,name) do { const auto p=GetProcAddress(module,name);std::memcpy(&lua.field,&p,sizeof(p));if(!lua.field) return false; } while(false)
    IMPORT(pushClosure,"lua_pushcclosure");IMPORT(setField,"lua_setfield");IMPORT(checkInteger,"luaL_checkinteger");IMPORT(pushString,"lua_pushlstring");
    IMPORT(checkString,"luaL_checklstring");IMPORT(getTop,"lua_gettop");IMPORT(pushBoolean,"lua_pushboolean");
#undef IMPORT
    lua.pushClosure(L,capture,0);lua.setField(L,-2,"sound_events");
    lua.pushClosure(L,musicState,0);lua.setField(L,-2,"music_state");
    lua.pushClosure(L,resetLua,0);lua.setField(L,-2,"sound_reset");return true;
}
void reset() { events.clear();serial=0;music.clear();played.reset(); }
RoomScope::RoomScope() {
    if(!image) return;
    manager=at<std::uintptr_t>(image,0x87169c)+0x29fbc;
    previous={at<unsigned>(manager,0x30c),at<unsigned>(manager,0x310)};
    if(!scopeDepth) audibleIDs=previous;
    if(const auto found=music.find(roomKey());found!=music.end() && found->second.mode) {
        at<unsigned>(manager,0x30c)=found->second.id;at<unsigned>(manager,0x310)=0;
    }
    ++scopeDepth;
}
RoomScope::~RoomScope() {
    if(!manager) return;
    const auto ids=scopeDepth==1?audibleIDs:previous;
    at<unsigned>(manager,0x30c)=ids[0];at<unsigned>(manager,0x310)=ids[1];--scopeDepth;
}
void present() {
    const auto key=roomKey();const auto found=music.find(key);
    if(found==music.end() || !found->second.mode) return;
    const auto next=std::pair{key,found->second};if(played==next) return;
    const auto manager=at<std::uintptr_t>(image,0x87169c)+0x29fbc;
    const auto& m=found->second;
    const std::array virtualIDs={at<unsigned>(manager,0x30c),at<unsigned>(manager,0x310)};
    if(scopeDepth) { at<unsigned>(manager,0x30c)=audibleIDs[0];at<unsigned>(manager,0x310)=audibleIDs[1]; }
    // Entering another room must not wait for the preceding room's queued
    // jingle/crossfade. Changes within one room retain native fading.
    if(!played || played->first!=key) originalMusicPlay(reinterpret_cast<void*>(manager),m.id,at<float>(manager,0x398));
    else (m.mode==1?originalMusicPlay:originalMusicFade)(reinterpret_cast<void*>(manager),m.id,m.parameter);
    if(scopeDepth) {
        audibleIDs={at<unsigned>(manager,0x30c),at<unsigned>(manager,0x310)};
        at<unsigned>(manager,0x30c)=virtualIDs[0];at<unsigned>(manager,0x310)=virtualIDs[1];
    }
    played=next;
}
}
