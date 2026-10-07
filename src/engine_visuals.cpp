#include "engine_visuals.h"
#include "net_protocol.h"
#include "runtime_net.h"
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <vector>

namespace isaac::visuals {
namespace {
using Address=std::uintptr_t;
template<class T> T& at(Address p,unsigned offset) { return *reinterpret_cast<T*>(p+offset); }
struct API {
    int (__cdecl* getTop)(lua_State*);
    void* (__cdecl* toUserdata)(lua_State*,int);
    void* (__cdecl* newUserdata)(lua_State*,std::size_t);
    int (__cdecl* getMetatable)(lua_State*,int);
    int (__cdecl* setMetatable)(lua_State*,int);
    std::size_t (__cdecl* rawLength)(lua_State*,int);
    const char* (__cdecl* checkString)(lua_State*,int,std::size_t*);
    const char* (__cdecl* pushString)(lua_State*,const char*,std::size_t);
    void (__cdecl* pushInteger)(lua_State*,long long);
    long long (__cdecl* checkInteger)(lua_State*,int);
    void (__cdecl* pushBoolean)(lua_State*,int);
    void (__cdecl* createTable)(lua_State*,int,int);
    void (__cdecl* rawSetI)(lua_State*,int,long long);
    void (__cdecl* pushClosure)(lua_State*,int(__cdecl*)(lua_State*),int);
    void (__cdecl* setField)(lua_State*,int,const char*);
} lua{};
Address sprite(lua_State* L) {
    auto wrapper=static_cast<Address*>(lua.toUserdata(L,1));
    const auto size=lua.rawLength(L,1);
    if(!wrapper || (size!=8 && size!=0x11c)) throw std::runtime_error("Invalid native Sprite wrapper");
    return wrapper[1];
}
int doorSprite(lua_State* L) {
    // ExtraSprite's Lua property returns an owning copy in J460. Expose the
    // door-owned ANM2 through the same non-owning wrapper as GetSprite().
    auto sample=static_cast<Address*>(lua.toUserdata(L,1));
    if(!sample || lua.rawLength(L,1)!=8) { lua.pushBoolean(L,false);return 1; }
    auto wrapper=static_cast<Address*>(lua.newUserdata(L,8));
    wrapper[0]=sample[0];wrapper[1]=sample[1]-0x40+0x27c;
    lua.getMetatable(L,1);lua.setMetatable(L,-2);return 1;
}
int gridVariant(lua_State* L) {
    auto sample=static_cast<Address*>(lua.toUserdata(L,1));
    if(!runtime::replica() || !sample || lua.rawLength(L,1)!=8) { lua.pushBoolean(L,false);return 1; }
    at<int>(sample[1]-0x40,8)=static_cast<int>(lua.checkInteger(L,2));
    lua.pushBoolean(L,true);return 1;
}
int doorSlot(lua_State* L) {
    if(!runtime::replica()) { lua.pushBoolean(L,false);return 1; }
    const auto image=reinterpret_cast<Address>(GetModuleHandleW(nullptr));
    const auto room=at<Address>(at<Address>(image,0x871678),0x18300);
    const auto slot=lua.checkInteger(L,1);
    if(slot==-1) {
        for(unsigned i=0;i<8;++i) at<Address>(room,0x724+i*4)=0;
    } else {
        const auto index=lua.checkInteger(L,2);
        if(slot<0 || slot>7 || index<0 || index>=448) {
            lua.pushBoolean(L,false);return 1;
        }
        at<unsigned>(room,0x744+slot*4)=static_cast<unsigned>(index);
        if(lua.getTop(L)<3) {
            using MakeDoor=bool(__attribute__((thiscall))*)(void*,int);
            lua.pushBoolean(L,reinterpret_cast<MakeDoor>(image+0x3eea90)(reinterpret_cast<void*>(room),static_cast<int>(slot)));return 1;
        }
        auto sample=static_cast<Address*>(lua.toUserdata(L,3));
        if(!sample || lua.rawLength(L,3)!=8) { lua.pushBoolean(L,false);return 1; }
        // The room grid vector owns the door; Room::GetDoor/Render use a
        // separate borrowed slot table. Late Devil/Angel doors need both.
        at<Address>(room,0x724+slot*4)=sample[1]-0x40;
    }
    lua.pushBoolean(L,true);return 1;
}
std::string string(Address p) {
    const auto length=at<unsigned>(p,0x10),capacity=at<unsigned>(p,0x14);
    if(length>capacity || length>1024) throw std::runtime_error("Invalid sprite path");
    return {reinterpret_cast<const char*>(capacity<16?p:at<Address>(p,0)),length};
}
unsigned count(Address p,unsigned offset,unsigned limit=64) {
    const auto n=at<unsigned>(p,offset);
    if(n>limit) throw std::runtime_error("Invalid native visual array");
    return n;
}
unsigned number(lan::Reader& r) {
    const auto bits=r.u32();
    if(!std::isfinite(std::bit_cast<float>(bits))) throw std::runtime_error("Invalid visual number");
    return bits;
}
unsigned boolean(lan::Reader& r) {
    const auto v=r.u8();if(v>1) throw std::runtime_error("Invalid visual flag");return v;
}
Address layer(Address s,unsigned id) {
    const auto begin=at<Address>(s,0x7c);
    for(unsigned i=0;i<count(s,0x80);++i) {
        const auto p=begin+i*0xa0;
        if(at<unsigned>(at<Address>(p,0),0)==id) return p;
    }
    return 0;
}
void captureAnimation(lan::Writer& w,Address state) {
    const auto data=at<Address>(state,4);w.u8(data!=0);
    if(!data) return;
    w.u32(at<unsigned>(state,0x10));w.u8(at<bool>(state,0x14));
    const auto n=count(data,0x1c);w.u16(n);
    for(unsigned i=0;i<n;++i) {
        w.u16(at<unsigned>(at<Address>(data,0x18)+i*0x10,0));
        w.u32(at<unsigned>(at<Address>(state,8),i*4));
    }
}
void applyAnimation(lan::Reader& r,Address state) {
    if(!boolean(r)) {
        if(at<Address>(state,4)) {
            using Reset=void(__attribute__((thiscall))*)(void*,void*);
            reinterpret_cast<Reset>(reinterpret_cast<Address>(GetModuleHandleW(nullptr))+0x8830)(reinterpret_cast<void*>(state),nullptr);
        }
        return;
    }
    const auto frame=number(r),playing=boolean(r);const auto n=r.u16();
    if(n>64) throw std::runtime_error("Too many animation layers");
    const auto data=at<Address>(state,4);
    if(data) { at<unsigned>(state,0x10)=frame;at<bool>(state,0x14)=playing; }
    for(unsigned i=0;i<n;++i) {
        const auto id=r.u16();const int frameIndex=static_cast<int>(r.u32());
        if(!data || id>=64) continue;
        const int order=at<int>(data,0x38+id*4);
        if(order<0 || static_cast<unsigned>(order)>=count(data,0x1c)) continue;
        const auto frames=count(at<Address>(data,0x18)+order*0x10,8,65535);
        if(frameIndex>=-1 && frameIndex<static_cast<int>(frames))
            at<int>(at<Address>(state,8),order*4)=frameIndex;
    }
}
constexpr std::array<unsigned,18> layerNumbers={0x34,0x38,0x3c,0x40,0x44,
    0x48,0x4c,0x50,0x54,0x58,0x5c,0x60,0x64,0x68,0x6c,0x70,0x90,0x94};
int spriteState(lua_State* L) {
    try {
        const auto s=sprite(L);
        if(lua.getTop(L)==1) {
            lan::Writer w(lan::Message::world);
            captureAnimation(w,s+0x30);captureAnimation(w,s+0x50);
            w.u32(at<unsigned>(s,0x10c));
            // Colorize/champion colors and rendering flags are not exposed by
            // the seven Lua Color channels. They affect blood/floor decals.
            for(unsigned offset=0xa8;offset<0x100;offset+=4) w.u32(at<unsigned>(s,offset));
            w.u32(at<unsigned>(s,0x104));w.u32(at<unsigned>(s,0x110));w.u8(at<bool>(s,0x70));
            const auto n=count(s,0x80);w.u16(n);
            for(unsigned i=0;i<n;++i) {
                const auto p=at<Address>(s,0x7c)+i*0xa0;
                w.u16(at<unsigned>(at<Address>(p,0),0));w.string(string(p+8));
                for(auto offset:{0x32u,0x33u,0x74u}) w.u8(at<bool>(p,offset));
                for(auto offset:layerNumbers) w.u32(at<unsigned>(p,offset));
                for(unsigned offset=0x78;offset<0x8c;offset+=4) w.u32(at<unsigned>(p,offset));
                w.u32(at<unsigned>(p,0x8c));
            }
            lua.pushString(L,reinterpret_cast<const char*>(w.bytes.data()+1),w.bytes.size()-1);return 1;
        }
        if(!runtime::replica()) throw std::runtime_error("Only replicas apply visual state");
        std::size_t size=0;const auto bytes=lua.checkString(L,2,&size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes),size});
        applyAnimation(r,s+0x30);applyAnimation(r,s+0x50);
        const int shadowLayer=static_cast<int>(r.u32());
        if(shadowLayer<-1 || shadowLayer>=64) throw std::runtime_error("Invalid shadow layer");
        at<int>(s,0x10c)=shadowLayer>=0 && !layer(s,shadowLayer)?-1:shadowLayer;
        for(unsigned offset=0xa8;offset<0x100;offset+=4) at<unsigned>(s,offset)=number(r);
        at<unsigned>(s,0x104)=number(r);at<unsigned>(s,0x110)=r.u32();at<bool>(s,0x70)=boolean(r);
        const auto n=r.u16();if(n>64) throw std::runtime_error("Too many sprite layers");
        lua.createTable(L,0,0);unsigned changed=0;
        for(unsigned i=0;i<n;++i) {
            const auto id=r.u16();const auto path=r.string();const auto p=layer(s,id);
            if(p && path!=string(p+8)) {
                lua.createTable(L,2,0);lua.pushInteger(L,id);lua.rawSetI(L,-2,1);
                lua.pushString(L,path.data(),path.size());lua.rawSetI(L,-2,2);lua.rawSetI(L,-2,++changed);
            }
            for(auto offset:{0x32u,0x33u,0x74u}) { const auto v=boolean(r);if(p) at<bool>(p,offset)=v; }
            for(auto offset:layerNumbers) { const auto v=number(r);if(p) at<unsigned>(p,offset)=v; }
            for(unsigned offset=0x78;offset<0x8c;offset+=4) {
                const auto v=r.u32();if(v>32) throw std::runtime_error("Invalid sprite blend mode");
                if(p) at<unsigned>(p,offset)=v;
            }
            const auto flags=r.u32();if(p) at<unsigned>(p,0x8c)=flags;
        }
        r.finish();return 1;
    } catch(const std::exception& e) { runtime::abort(e.what());lua.pushBoolean(L,false);return 1; }
}
std::vector<Address> costumes(Address player) {
    const auto first=at<Address>(player,0x1220),last=at<Address>(player,0x1224);
    if(last<first || (last-first)%0x130 || last-first>4096*0x130) throw std::runtime_error("Invalid costume array");
    std::vector<Address> result;
    for(auto p=first;p<last;p+=0x130) result.push_back(p);
    return result;
}
int entityShadow(lua_State* L) {
    try {
        // EntityList::RenderShadows and Entity::RenderShadowLayer read these
        // three floats in J460. Effect Update normally initializes them;
        // replicas must receive them instead of drawing constructor shadows.
        const auto entity=sprite(L)-0x48;
        if(lua.getTop(L)==1) {
            lan::Writer w(lan::Message::world);
            for(auto offset:{0x15cu,0x160u,0x164u}) w.u32(at<unsigned>(entity,offset));
            lua.pushString(L,reinterpret_cast<const char*>(w.bytes.data()+1),w.bytes.size()-1);return 1;
        }
        if(!runtime::replica()) throw std::runtime_error("Only replicas apply entity shadows");
        std::size_t size=0;const auto bytes=lua.checkString(L,2,&size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes),size});
        for(auto offset:{0x15cu,0x160u,0x164u}) at<unsigned>(entity,offset)=number(r);
        r.finish();lua.pushBoolean(L,true);return 1;
    } catch(const std::exception& e) { runtime::abort(e.what());lua.pushBoolean(L,false);return 1; }
}
int actorPose(lua_State* L) {
    try {
        const auto player=sprite(L)-0x48;
        if(at<unsigned>(player,0x28)!=1) throw std::runtime_error("Actor visual state requires a player");
        const auto current=costumes(player);
        if(lua.getTop(L)==1) {
            lan::Writer w(lan::Message::world);
            w.u8(at<bool>(player,0x1398));w.u8(at<bool>(player,0x139a));
            w.u32(at<unsigned>(player,0x1338));
            // J460 Render reads damageCooldown modulo six to hide the body.
            // Replica Update is suppressed, so an arrival cooldown otherwise
            // stays on the same invisible frame until the next floor reload.
            w.u32(at<unsigned>(player,0x13bc));
            for(unsigned slot=0;slot<5;++slot) {
                const auto weapon=at<Address>(player,0x13dc+slot*4);
                w.u8(weapon!=0);
                if(weapon) {
                    w.u32(at<unsigned>(weapon,0x30));
                    for(auto offset:{0xcu,0x10u,0x14u}) w.u32(at<unsigned>(weapon,offset));
                }
            }
            w.u16(current.size());
            for(auto p:current) w.string(string(p));
            for(unsigned i=0;i<15;++i) {
                const auto p=player+0x122c+i*0x10;
                for(auto offset:{0u,4u,8u}) w.u32(at<unsigned>(p,offset));
                w.u8(at<bool>(p,0xc));
            }
            lua.pushString(L,reinterpret_cast<const char*>(w.bytes.data()+1),w.bytes.size()-1);return 1;
        }
        if(!runtime::replica()) throw std::runtime_error("Only replicas apply actor pose");
        std::size_t size=0;const auto bytes=lua.checkString(L,2,&size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes),size});
        at<bool>(player,0x1398)=boolean(r);at<bool>(player,0x139a)=boolean(r);
        at<unsigned>(player,0x1338)=r.u32();
        at<unsigned>(player,0x13bc)=r.u32();
        for(unsigned slot=0;slot<5;++slot) if(boolean(r)) {
            const auto type=r.u32();
            std::array<unsigned,3> values{};
            for(auto& value:values) value=number(r);
            const auto weapon=at<Address>(player,0x13dc+slot*4);
            if(weapon && at<unsigned>(weapon,0x30)==type) {
                at<unsigned>(weapon,0xc)=values[0];
                at<unsigned>(weapon,0x10)=values[1];
                at<unsigned>(weapon,0x14)=values[2];
            }
        }
        const auto n=r.u16();if(n>4096) throw std::runtime_error("Too many costumes");
        std::vector<int> mapping(n,-1);std::vector<bool> used(current.size(),false);
        for(unsigned i=0;i<n;++i) {
            const auto path=r.string();
            for(unsigned j=0;j<current.size();++j) if(!used[j] && string(current[j])==path) {
                mapping[i]=j;used[j]=true;break;
            }
        }
        for(unsigned i=0;i<15;++i) {
            const int remote=static_cast<int>(r.u32()),layerID=static_cast<int>(r.u32());
            const auto priority=r.u32(),body=boolean(r);const auto p=player+0x122c+i*0x10;
            const int local=remote>=0 && static_cast<unsigned>(remote)<n?mapping[remote]:-1;
            // A cosmetic Mod absent on this peer must not leave a dangling
            // costume index. The native base layer remains a valid fallback.
            at<int>(p,0)=local;at<int>(p,4)=local>=0?layerID:static_cast<int>(i);
            at<unsigned>(p,8)=priority;at<bool>(p,0xc)=body;
        }
        r.finish();lua.pushBoolean(L,true);return 1;
    } catch(const std::exception& e) { runtime::abort(e.what());lua.pushBoolean(L,false);return 1; }
}

}
bool bind(lua_State* L,HMODULE module) {
#define IMPORT(field,name) do { auto p=GetProcAddress(module,name);std::memcpy(&lua.field,&p,sizeof(p));if(!lua.field)return false; } while(false)
    IMPORT(getTop,"lua_gettop");IMPORT(toUserdata,"lua_touserdata");IMPORT(rawLength,"lua_rawlen");
    IMPORT(newUserdata,"lua_newuserdata");IMPORT(getMetatable,"lua_getmetatable");IMPORT(setMetatable,"lua_setmetatable");
    IMPORT(checkString,"luaL_checklstring");IMPORT(pushString,"lua_pushlstring");IMPORT(pushInteger,"lua_pushinteger");
    IMPORT(checkInteger,"luaL_checkinteger");
    IMPORT(pushBoolean,"lua_pushboolean");IMPORT(createTable,"lua_createtable");IMPORT(rawSetI,"lua_rawseti");
    IMPORT(pushClosure,"lua_pushcclosure");IMPORT(setField,"lua_setfield");
#undef IMPORT
    lua.pushClosure(L,spriteState,0);lua.setField(L,-2,"sprite_state");
    lua.pushClosure(L,actorPose,0);lua.setField(L,-2,"actor_pose");
    lua.pushClosure(L,entityShadow,0);lua.setField(L,-2,"entity_shadow");
    lua.pushClosure(L,gridVariant,0);lua.setField(L,-2,"grid_variant");
    lua.pushClosure(L,doorSprite,0);lua.setField(L,-2,"door_sprite");
    lua.pushClosure(L,doorSlot,0);lua.setField(L,-2,"door_slot");return true;
}
}
