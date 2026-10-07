#include "engine_presentation.h"
#include "engine_rooms.h"
#include "runtime_net.h"
#include "net_protocol.h"
#include <MinHook.h>
#include <deque>
#include <cstring>

namespace isaac::presentation {
namespace {
std::uintptr_t image=0;
template<class T> T& at(std::uintptr_t p,unsigned offset) { return *reinterpret_cast<T*>(p+offset); }
struct Intro { unsigned serial,tick,audience;int stage,type,dimension,room;unsigned first,second; };
std::deque<Intro> intros;
unsigned serial=0,seen=0;
using StartIntro=void(__attribute__((thiscall))*)(void*,unsigned,unsigned);
StartIntro originalIntro;
void playIntro(void* transition,unsigned first,unsigned second) {
    const auto game=at<std::uintptr_t>(image,0x871678);
    const auto target=reinterpret_cast<std::uintptr_t>(transition);
    // StartBossIntro consults the transition's destination descriptor while
    // loading native versus graphics. LAN already entered this room without
    // the global door transition, so supply its current native destination.
    at<int>(target,0x14)=at<int>(game,0x18304);
    at<int>(target,0x18)=at<int>(game,0x1830c);
    const auto roster=at<std::uintptr_t>(game,0x1baa8);
    if(roster!=at<std::uintptr_t>(game,0x1baac)) at<std::uintptr_t>(game,0x1bb74)=at<std::uintptr_t>(roster,0);
    originalIntro(transition,first,second);
}
void __attribute__((fastcall)) startIntro(void* transition,void*,unsigned first,unsigned second) {
    const auto audience=rooms::soundAudience();
    if(!audience) { originalIntro(transition,first,second);return; }
    // Replica room initialization can request a provisional intro. Its native
    // UI is started once from the authoritative event after that room arrives.
    if(runtime::replica()) return;
    const auto game=at<std::uintptr_t>(image,0x871678);
    intros.push_back({++serial,runtime::tick(),audience,at<int>(game,0),at<int>(game,4),
        at<int>(game,0x1830c),at<int>(game,0x18304),first,second});
    while(intros.size()>32) intros.pop_front();
    // A native intro owns the process-wide transition screen. Background room
    // entry must notify its occupants without taking over the host's viewport.
    if(audience&1u) playIntro(transition,first,second);
}
struct API {
    int (__cdecl* getTop)(lua_State*);
    long long (__cdecl* checkInteger)(lua_State*,int);
    const char* (__cdecl* checkString)(lua_State*,int,std::size_t*);
    const char* (__cdecl* pushString)(lua_State*,const char*,std::size_t);
    void (__cdecl* pushBoolean)(lua_State*,int);
    void (__cdecl* pushClosure)(lua_State*,int(__cdecl*)(lua_State*),int);
    void (__cdecl* setField)(lua_State*,int,const char*);
} lua{};
int events(lua_State* L) {
    try {
        if(lua.getTop(L)==1 && !runtime::replica()) {
            const auto slot=lua.checkInteger(L,1);lan::Writer w(lan::Message::world);
            if(slot>=0 && slot<4) for(const auto& e:intros) {
                if(!(e.audience&(1u<<slot)) || runtime::tick()-e.tick>90) continue;
                for(auto v:{e.serial,e.tick,static_cast<unsigned>(e.stage),static_cast<unsigned>(e.type),
                    static_cast<unsigned>(e.dimension),static_cast<unsigned>(e.room),e.first,e.second}) w.u32(v);
            }
            lua.pushString(L,reinterpret_cast<const char*>(w.bytes.data()+1),w.bytes.size()-1);return 1;
        }
        if(!runtime::replica()) throw std::runtime_error("Only replicas apply presentation events");
        std::size_t size=0;const auto bytes=lua.checkString(L,1,&size);
        if(size%32 || size>32*32) throw std::runtime_error("Invalid intro events");
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes),size});
        const auto game=at<std::uintptr_t>(image,0x871678);
        for(std::size_t i=0;i<size/32;++i) {
            const auto id=r.u32(),tick=r.u32();
            const int stage=r.u32(),type=r.u32(),dimension=r.u32(),room=r.u32();
            const auto first=r.u32(),second=r.u32();
            if(id<=seen) continue;
            seen=id;
            if((runtime::tick()>tick && runtime::tick()-tick>90) || stage!=at<int>(game,0) || type!=at<int>(game,4)
                || dimension!=at<int>(game,0x1830c) || room!=at<int>(game,0x18304)) continue;
            rooms::withView([&]{playIntro(reinterpret_cast<void*>(game+0x1b83c),first,second);},true);
        }
        r.finish();lua.pushBoolean(L,true);return 1;
    } catch(const std::exception& e) { runtime::abort(e.what());lua.pushBoolean(L,false);return 1; }
}
int resetLua(lua_State*) { reset();return 0; }
int active(lua_State* L) {
    const auto transition=at<std::uintptr_t>(image,0x871678)+0x1b83c;
    lua.pushBoolean(L,at<int>(transition,0)==2 && at<int>(transition,0x238)!=0);return 1;
}
}
bool install(std::uintptr_t base) {
    image=base;
    return MH_CreateHook(reinterpret_cast<void*>(image+0x42f1c0),reinterpret_cast<void*>(startIntro),reinterpret_cast<void**>(&originalIntro))==MH_OK
        && MH_EnableHook(reinterpret_cast<void*>(image+0x42f1c0))==MH_OK;
}
bool bind(lua_State* L,HMODULE module) {
#define IMPORT(field,name) do { const auto p=GetProcAddress(module,name);std::memcpy(&lua.field,&p,sizeof(p));if(!lua.field)return false; } while(false)
    IMPORT(getTop,"lua_gettop");IMPORT(checkInteger,"luaL_checkinteger");IMPORT(checkString,"luaL_checklstring");
    IMPORT(pushString,"lua_pushlstring");IMPORT(pushBoolean,"lua_pushboolean");IMPORT(pushClosure,"lua_pushcclosure");IMPORT(setField,"lua_setfield");
#undef IMPORT
    lua.pushClosure(L,events,0);lua.setField(L,-2,"presentation_events");
    lua.pushClosure(L,resetLua,0);lua.setField(L,-2,"presentation_reset");
    lua.pushClosure(L,active,0);lua.setField(L,-2,"presentation_active");return true;
}
void reset() { intros.clear();serial=seen=0; }
void roomEntered(std::uintptr_t room) {
    if(runtime::replica()) return;
    // These are the same native boss IDs and living-enemy checks used by
    // RoomTransition::ChangeRoom. Per-player room entry skips that global
    // transition, but must retain its original versus presentation.
    const auto first=at<unsigned>(room,0x1bb0),second=at<unsigned>(room,0x1bb4);
    if(first && at<int>(room,0x12c8)+at<int>(room,0x12cc)>0) {
        const auto game=at<std::uintptr_t>(image,0x871678);
        startIntro(reinterpret_cast<void*>(game+0x1b83c),nullptr,first,second);
    } else {
        const auto descriptor=at<std::uintptr_t>(room,4);
        const auto data=descriptor?at<std::uintptr_t>(descriptor,0x10):0;
        // Vanilla also treats the unopened special Greed shop as a versus
        // entry, even before the native boss-ID cache has been populated.
        if(data && at<int>(data,0)==35 && at<int>(data,8)==1 && at<int>(data,12)==1000
            && !(at<unsigned>(descriptor,0x44)&1u)) {
            const auto game=at<std::uintptr_t>(image,0x871678);
            startIntro(reinterpret_cast<void*>(game+0x1b83c),nullptr,99,0);
        }
    }
}
}
