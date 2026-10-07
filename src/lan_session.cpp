#include "lan_session.h"
#include "state_compression.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <bcrypt.h>
#include <algorithm>
#include <chrono>
#include <deque>
#include <map>

namespace isaac::lan {
namespace {
using Clock = std::chrono::steady_clock;
struct ConnectionLost:std::runtime_error { using std::runtime_error::runtime_error; };
Writer stageMessage(const Stage& value,std::size_t offset=0) {
    Writer w(Message::stage);w.u32(value.epoch);w.u8(value.level);w.u8(value.type);w.u8(value.animation);w.u8(value.same);
    for(auto seed:value.seeds) w.u32(seed);
    w.u8(value.rKey);
    w.u32(value.rewind.size());w.u32(offset);
    w.blob(std::span(value.rewind).subspan(offset,std::min<std::size_t>(3000,value.rewind.size()-offset)));
    return w;
}
std::string randomIdentity() {
    std::array<unsigned char,16> bytes{};
    if(BCryptGenRandom(nullptr,bytes.data(),bytes.size(),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)
        throw std::runtime_error("Cannot create player identity");
    std::string result;
    for(auto value:bytes) { result.push_back("0123456789abcdef"[value>>4]);result.push_back("0123456789abcdef"[value&15]); }
    return result;
}
bool validIdentity(const std::string& value) {
    return value.size()==32 && std::all_of(value.begin(),value.end(),[](char c){return (c>='0' && c<='9') || (c>='a' && c<='f');});
}
bool wouldBlock() { return WSAGetLastError() == WSAEWOULDBLOCK; }
void configure(SOCKET s) {
    u_long mode = 1;
    if (ioctlsocket(s, FIONBIO, &mode) != 0) throw std::runtime_error("Cannot set nonblocking socket");
    BOOL on = TRUE;
    if (setsockopt(s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&on), sizeof(on)) != 0)
        throw std::runtime_error("Cannot disable TCP buffering");
}
struct Socket {
    SOCKET handle = INVALID_SOCKET;
    std::vector<std::uint8_t> received;
    std::deque<std::vector<std::uint8_t>> outgoing;
    std::size_t sent = 0, queued = 0;
    bool accepted = false, finished = false;
    std::string mods;
    bool loaded = false;
    bool waiting=false, ready=false, rejoining=false, hasInput=false;
    std::shared_ptr<const Start> checkpoint;
    std::optional<Stage> floorAfterLoad;
    std::optional<Stage> sendingStage;
    std::size_t stageSent=0;
    std::optional<WorldState> sending, pending;
    std::size_t worldSent=0;
    std::uint32_t inputSequence=0;
    std::optional<std::uint32_t> acknowledged;
    std::size_t snapshotSent = 0;
    Clock::time_point connectedAt = Clock::now();
    Clock::time_point advancedAt = Clock::now(), inputAt=Clock::now();
    Clock::time_point pingAt=Clock::now()-std::chrono::seconds(1);
    std::uint32_t pingSequence=0;
    bool pingPending=false;
    explicit Socket(SOCKET value = INVALID_SOCKET) : handle(value) {}
    void beginStage(const Stage& value) {
        sending.reset();pending.reset();sendingStage=value;stageSent=0;
    }
    ~Socket() { if (handle != INVALID_SOCKET) closesocket(handle); }
    void sendMessage(const Writer& w) {
        if (w.bytes.empty() || w.bytes.size() > maxMessageSize || queued + w.bytes.size() > 262144)
            throw std::runtime_error("Network queue limit exceeded");
        std::vector<std::uint8_t> data;
        auto size = static_cast<std::uint16_t>(w.bytes.size());
        data.push_back(size >> 8); data.push_back(size & 255);
        data.insert(data.end(), w.bytes.begin(), w.bytes.end());
        queued += data.size();
        outgoing.push_back(std::move(data));
    }
    void flush() {
        while (!outgoing.empty()) {
            auto& data = outgoing.front();
            int n = ::send(handle, reinterpret_cast<const char*>(data.data() + sent), static_cast<int>(data.size() - sent), 0);
            if (n == SOCKET_ERROR) { if (wouldBlock()) return; throw ConnectionLost("Peer send failed"); }
            if (n <= 0) throw ConnectionLost("Peer closed connection");
            sent += n; queued -= n;
            if (sent == data.size()) { outgoing.pop_front(); sent = 0; }
        }
    }
    template<class F> void receive(F callback) {
        std::array<std::uint8_t, 8192> buffer;
        // Bound each poll so one peer cannot monopolize the engine thread.
        for (unsigned chunk = 0; chunk < 8; ++chunk) {
            int n = recv(handle, reinterpret_cast<char*>(buffer.data()), static_cast<int>(buffer.size()), 0);
            if (n == SOCKET_ERROR) { if (wouldBlock()) break; throw ConnectionLost("Peer receive failed"); }
            if (!n) { if(finished) return; throw ConnectionLost("Peer disconnected"); }
            received.insert(received.end(), buffer.begin(), buffer.begin() + n);
            std::size_t consumed = 0;
            while (received.size() - consumed >= 2) {
                auto size = static_cast<unsigned>((received[consumed] << 8) | received[consumed + 1]);
                if (!size || size > maxMessageSize) throw std::runtime_error("Invalid network message size");
                if (received.size() - consumed < size + 2) break;
                Reader reader{std::span<const std::uint8_t>(received).subspan(consumed + 2, size)};
                callback(reader);
                reader.finish();
                consumed += size + 2;
            }
            received.erase(received.begin(), received.begin() + consumed);
            if (received.size() > maxMessageSize + 2) throw std::runtime_error("Receive buffer limit exceeded");
        }
    }
};
}
struct Session::Impl {
    StateCompression compression;
    void (*logger)(const std::string&);
    bool winsock=false,hosting=false,connecting=false,localReady=false,initialStarted=false;
    Phase state=Phase::idle;
    std::string failure,fingerprint,identity,mods,hostIP;
    bool modMismatch=false,lobbyDirty=false,choicesRequired=false;
    std::array<std::string,maxPlayers> identities;
    unsigned localSlot=0,playerCount=1,activeMask=1;
    std::uint16_t boundPort=0;
    SOCKET listener=INVALID_SOCKET;
    std::array<std::unique_ptr<Socket>,maxPlayers> peers;
    std::vector<std::unique_ptr<Socket>> incoming;
    Start startSettings;
    std::array<Choice,maxPlayers> choices{};
    std::array<Command,maxPlayers> commands{};
    std::array<InputFrame,maxPlayers> latest{};
    std::array<std::uint32_t,maxPlayers> sequences{};
    std::array<int,maxPlayers> latency{0,-1,-1,-1};
    Clock::time_point latencyAt=Clock::now()-std::chrono::seconds(1);
    std::uint32_t nextInput=0,nextConsume=0,committed=0;
    std::optional<std::uint32_t> consumedLocal,verified;
    std::optional<WorldState> receivedState,assembling;
    std::optional<Stage> receivedStage;
    std::optional<Stage> assemblingStage;
    std::size_t stageSize=0;
    std::array<std::optional<RoomRequest>,maxPlayers> roomRequests{};
    std::size_t worldSize=0,snapshotSize=0;
    std::uint64_t snapshotChecksum=0;
    Clock::time_point progress=Clock::now();

    explicit Impl(void (*log)(const std::string&)):logger(log) {
        WSADATA data{};winsock=WSAStartup(MAKEWORD(2,2),&data)==0;
    }
    ~Impl() { shutdown();if(winsock) WSACleanup(); }
    void shutdown() {
        if(listener!=INVALID_SOCKET) { closesocket(listener);listener=INVALID_SOCKET; }
        for(auto& peer:peers) peer.reset();
        incoming.clear();
    }
    void fail(const std::string& reason) {
        if(state==Phase::failed) return;
        failure=reason;state=Phase::failed;
        if(logger) logger("network_failure="+reason);
        Writer w(Message::error);w.string(reason.substr(0,240));
        for(auto& p:peers) if(p) { try { p->sendMessage(w);p->flush(); } catch(...) {} }
        shutdown();
    }
    void broadcast(const Writer& w) {
        for(auto& p:peers) if(p && p->accepted) p->sendMessage(w);
    }
    void measureLatency() {
        if(!hosting) return;
        const auto now=Clock::now();
        for(unsigned slot=1;slot<maxPlayers;++slot) if(auto& peer=peers[slot];peer && peer->accepted) {
            if(now-peer->pingAt<std::chrono::seconds(peer->pingPending?5:1) || peer->queued>16384) continue;
            Writer ping(Message::ping);ping.u32(++peer->pingSequence);peer->sendMessage(ping);
            peer->pingAt=now;peer->pingPending=true;
        } else latency[slot]=-1;
        if(now-latencyAt<std::chrono::seconds(1)) return;
        latencyAt=now;Writer info(Message::latency);
        for(auto ms:latency) info.u16(ms<0?65535:std::min(ms,65534));
        broadcast(info);
    }
    void updateMods(bool force=false) {
        const bool different=std::any_of(peers.begin(),peers.end(),[&](const auto& p) {
            return p && p->accepted && (mods.empty() || p->mods.empty() || p->mods!=mods);
        });
        if(!force && different==modMismatch) return;
        modMismatch=different;Writer w(Message::modStatus);w.u8(different);broadcast(w);
    }
    void lobby() {
        unsigned next=1;
        for(unsigned i=1;i<maxPlayers;++i) if(peers[i] && peers[i]->accepted) {
            if(i!=next) { std::swap(peers[i],peers[next]);std::swap(choices[i],choices[next]);std::swap(identities[i],identities[next]); }
            ++next;
        }
        playerCount=next;
        for(unsigned i=1;i<playerCount;++i) {
            Writer w(Message::lobby);w.u8(playerCount);w.u8(i);
            for(auto choice:choices) { w.u16(choice.character);w.u8(choice.ready); }
            peers[i]->sendMessage(w);
        }
        lobbyDirty=false;updateMods(true);
    }
    Writer startMessage(Message type,const Start& value) {
        Writer w(type);w.string(value.seed);w.u8(value.difficulty);
        for(auto c:value.characters) w.u16(c);
        w.progress(value.progress);w.u32(value.firstTick);w.u8(value.connected);
        w.u32(value.snapshot.size());w.u64(snapshotHash(value.snapshot));return w;
    }
    void remove(unsigned slot) {
        activeMask&=~(1u<<slot);latest[slot]={};commands[slot]=Command::none;roomRequests[slot].reset();
        peers[slot].reset();
        if(logger) logger("network_departure slot="+std::to_string(slot));
    }
    void acceptHello(unsigned slot,Reader& r) {
        if(r.u16()!=protocolVersion || r.string()!=fingerprint) throw std::runtime_error("Game, extension or protocol mismatch");
        const auto id=r.string();auto& p=*peers[slot];p.mods=r.string();
        if(!validIdentity(id) || std::find(identities.begin(),identities.end(),id)!=identities.end())
            throw std::runtime_error("Invalid or duplicate player identity");
        identities[slot]=id;p.accepted=true;
        Writer welcome(Message::welcome);welcome.u8(slot);p.sendMessage(welcome);lobbyDirty=true;
    }
    void message(unsigned slot,Reader& r) {
        const auto type=static_cast<Message>(r.u8());auto& p=*peers[slot];
        if(type==Message::ping && !hosting && p.accepted) {
            Writer response(Message::pong);response.u32(r.u32());p.sendMessage(response);return;
        }
        if(type==Message::pong && hosting && p.accepted) {
            const auto sequence=r.u32();
            if(p.pingPending && sequence==p.pingSequence) {
                latency[slot]=static_cast<int>(std::min<std::int64_t>(65534,std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now()-p.pingAt).count()));
                p.pingPending=false;
            }
            return;
        }
        if(type==Message::latency && !hosting && p.accepted) {
            for(auto& ms:latency) { const auto value=r.u16();ms=value==65535?-1:value; }
            return;
        }
        if(type==Message::error) throw std::runtime_error("Peer: "+r.string());
        if(type==Message::goodbye) throw ConnectionLost("Peer left the session");
        if(hosting) {
            if(!p.accepted && type==Message::hello && state==Phase::lobby) { acceptHello(slot,r);return; }
            if(!p.accepted) throw std::runtime_error("Handshake required");
            if(type==Message::choice && state==Phase::lobby) {
                const auto c=r.u16(),ready=static_cast<std::uint16_t>(r.u8());
                if(ready>1) throw std::runtime_error("Invalid ready flag");
                choices[slot]={c,ready!=0};choicesRequired=true;lobbyDirty=true;return;
            }
            if(type==Message::loaded && p.checkpoint) {
                if(p.loaded || p.snapshotSent!=p.checkpoint->snapshot.size() || r.u64()!=snapshotHash(p.checkpoint->snapshot))
                    throw std::runtime_error("Invalid checkpoint receipt");
                p.loaded=true;p.advancedAt=Clock::now();return;
            }
            if(type==Message::ready && state==Phase::running) {
                const auto epoch=r.u32();
                if(epoch!=(p.checkpoint?p.checkpoint->firstTick:startSettings.firstTick) || (p.checkpoint && !p.loaded))
                    throw std::runtime_error("Invalid engine readiness");
                p.ready=true;p.checkpoint.reset();p.inputAt=Clock::now();
                p.hasInput=false;p.inputSequence=0;latest[slot]={};
                // A slow loader may have an older floor checkpoint. Deliver
                // the latest native floor event before its first live view.
                if(p.floorAfterLoad) { p.beginStage(*p.floorAfterLoad);p.floorAfterLoad.reset(); }
                if(p.rejoining) { activeMask|=1u<<slot;p.rejoining=false;p.waiting=false; }
                return;
            }
            if(type==Message::input && (state==Phase::running || state==Phase::finishing)) {
                const auto sequence=r.u32();const auto value=r.input();
                if(!p.ready || p.waiting || state==Phase::finishing) return;
                if(p.hasInput && sequence<=p.inputSequence) throw std::runtime_error("Duplicate input sequence");
                p.hasInput=true;p.inputSequence=sequence;p.inputAt=Clock::now();
                const auto edges=latest[slot].triggered;latest[slot]=value;latest[slot].triggered|=edges;sequences[slot]=sequence;
                return;
            }
            if(type==Message::control && state==Phase::running) {
                const auto c=r.u8();
                if(!c || c>static_cast<unsigned>(Command::leave) || c==static_cast<unsigned>(Command::saveExit))
                    throw std::runtime_error("Unauthorized shared command");
                if(p.ready) commands[slot]=static_cast<Command>(c);
                return;
            }
            if(type==Message::roomRequest && state==Phase::running) {
                RoomRequest value;value.stage=r.u8();value.type=r.u8();value.sourceDimension=r.u8();value.dimension=r.u8();
                value.source=static_cast<std::int16_t>(r.u16());value.destination=static_cast<std::int16_t>(r.u16());const auto teleport=r.u8();
                if(value.stage<1 || value.stage>13 || value.type>5 || value.sourceDimension>2 || value.dimension>2
                    || value.source< -20 || value.source>=169 || value.destination< -20 || value.destination>=169 || teleport>1)
                    throw std::runtime_error("Invalid room command");
                value.teleport=teleport!=0;
                if(p.ready && !p.waiting && !p.rejoining) roomRequests[slot]=value;
                return;
            }
            if(type==Message::applied && (state==Phase::running || state==Phase::finishing)) {
                const auto tick=r.u32();
                if(tick>=nextConsume || (p.acknowledged && tick<=*p.acknowledged)) throw std::runtime_error("Invalid state receipt");
                p.acknowledged=tick;p.advancedAt=Clock::now();return;
            }
            throw std::runtime_error("Unexpected client message");
        }
        if(type==Message::welcome && state==Phase::connecting) {
            localSlot=r.u8();if(!localSlot || localSlot>=maxPlayers) throw std::runtime_error("Invalid assigned slot");
            p.accepted=true;state=Phase::lobby;return;
        }
        if(!p.accepted) throw std::runtime_error("Handshake required");
        if(type==Message::modStatus) { const auto n=r.u8();if(n>1) throw std::runtime_error("Invalid Mod advisory");modMismatch=n!=0;return; }
        if(type==Message::finish) { r.u32();p.finished=true;state=Phase::closed;return; }
        if(type==Message::lobby && state==Phase::lobby) {
            playerCount=r.u8();localSlot=r.u8();
            if(playerCount<2 || playerCount>maxPlayers || !localSlot || localSlot>=playerCount) throw std::runtime_error("Invalid lobby");
            for(auto& c:choices) { c.character=r.u16();const auto n=r.u8();if(n>1) throw std::runtime_error("Invalid ready flag");c.ready=n!=0; }
            return;
        }
        if(type==Message::waitFloor) {
            playerCount=r.u8();failure=r.string();
            if(playerCount<2 || playerCount>4 || localSlot>=playerCount) throw std::runtime_error("Invalid waiting roster");
            state=Phase::waiting;localReady=false;receivedState.reset();return;
        }
        if(type==Message::start && (state==Phase::lobby || state==Phase::waiting)) {
            Start value;value.seed=r.string();value.difficulty=r.u8();
            for(auto& c:value.characters) c=r.u16();
            value.progress=r.progress();value.firstTick=r.u32();value.connected=r.u8();
            snapshotSize=r.u32();snapshotChecksum=r.u64();
            if(value.seed.size()!=8 || value.difficulty>3 || !(value.connected&1) || value.connected>=(1u<<playerCount) || snapshotSize>maxSnapshotSize)
                throw std::runtime_error("Invalid start state");
            localReady=false;receivedState.reset();assembling.reset();
            startSettings=value;activeMask=value.connected;nextConsume=value.firstTick;nextInput=0;state=snapshotSize?Phase::loading:Phase::running;
            progress=Clock::now();return;
        }
        if(type==Message::snapshot && state==Phase::loading) {
            auto& target=startSettings;
            const auto offset=r.u32();const auto bytes=r.blob(3000);
            if(offset!=target.snapshot.size() || bytes.empty() || offset>snapshotSize || bytes.size()>snapshotSize-offset)
                throw std::runtime_error("Invalid checkpoint chunk");
            target.snapshot.insert(target.snapshot.end(),bytes.begin(),bytes.end());progress=Clock::now();
            if(target.snapshot.size()==snapshotSize) {
                if(snapshotHash(target.snapshot)!=snapshotChecksum) throw std::runtime_error("Checkpoint transfer is damaged");
                Writer w(Message::loaded);w.u64(snapshotChecksum);p.sendMessage(w);
                state=Phase::running;
            }
            return;
        }
        if(type==Message::stage && state==Phase::running && localReady) {
            Stage value;value.epoch=r.u32();value.level=r.u8();value.type=r.u8();value.animation=r.u8();const auto same=r.u8();
            for(auto& seed:value.seeds) seed=r.u32();
            const auto rKey=r.u8();value.rKey=rKey!=0;
            const auto total=r.u32(),offset=r.u32();auto bytes=r.blob(3000);
            if(!value.epoch || value.level<1 || value.level>13 || value.type>5 || same>1 || total>maxWorldSize+5
                || rKey>1 || (rKey && (total || value.animation || value.level!=1 || value.type))
                || (total?value.animation!=12:value.animation>6))
                throw std::runtime_error("Invalid floor transition");
            value.same=same!=0;
            if(!offset) { assemblingStage=std::move(value);stageSize=total;receivedState.reset();assembling.reset(); }
            if(!assemblingStage || assemblingStage->epoch!=value.epoch || assemblingStage->seeds!=value.seeds
                || assemblingStage->rKey!=value.rKey || total!=stageSize
                || offset!=assemblingStage->rewind.size() || offset>total || bytes.size()>total-offset || (total && bytes.empty()))
                throw std::runtime_error("Invalid rewind transaction chunk");
            assemblingStage->rewind.insert(assemblingStage->rewind.end(),bytes.begin(),bytes.end());
            if(assemblingStage->rewind.size()==total) {
                if(total) assemblingStage->rewind=compression.expand(assemblingStage->rewind);
                receivedStage=std::move(assemblingStage);assemblingStage.reset();
            }
            progress=Clock::now();return;
        }
        if(type==Message::world && state==Phase::running) {
            const auto tick=r.u32(),offset=r.u32(),total=r.u32();
            if(!offset) {
                if(total==0 || total>maxWorldSize+5 || (receivedState && tick<=receivedState->tick) || (verified && tick<=*verified))
                    throw std::runtime_error("Invalid world state header");
                assembling=WorldState{};assembling->tick=tick;assembling->connected=r.u8();assembling->pauseOwner=r.u8();const auto paused=r.u8();
                if(!(assembling->connected&1) || assembling->connected>=(1u<<playerCount) || assembling->pauseOwner>=playerCount || paused>1)
                    throw std::runtime_error("Invalid world roster");
                assembling->paused=paused!=0;
                for(auto& seq:assembling->inputSequences) seq=r.u32();
                worldSize=total;
            }
            const auto bytes=r.blob(3000);
            if(!assembling || assembling->tick!=tick || total!=worldSize || offset!=assembling->bytes.size() || bytes.empty() || bytes.size()>total-offset)
                throw std::runtime_error("Invalid world state chunk");
            assembling->bytes.insert(assembling->bytes.end(),bytes.begin(),bytes.end());
            if(assembling->bytes.size()==total) {
                assembling->bytes=compression.expand(assembling->bytes);
                receivedState=std::move(assembling);assembling.reset();
            }
            progress=Clock::now();return;
        }
        throw std::runtime_error("Unexpected host message");
    }
    void sendPending() {
        if(!hosting) return;
        for(unsigned slot=1;slot<playerCount;++slot) if(peers[slot]) {
            auto& p=*peers[slot];
            if(p.checkpoint && !p.loaded) {
                const auto& bytes=p.checkpoint->snapshot;
                for(unsigned part=0;part<8 && p.queued<32768 && p.snapshotSent<bytes.size();++part) {
                    const auto n=std::min<std::size_t>(3000,bytes.size()-p.snapshotSent);
                    Writer w(Message::snapshot);w.u32(p.snapshotSent);w.blob(std::span(bytes).subspan(p.snapshotSent,n));p.sendMessage(w);p.snapshotSent+=n;
                }
                continue;
            }
            if(!p.ready) continue;
            if(p.sendingStage) {
                for(unsigned part=0;part<8 && p.queued<32768 && p.sendingStage;++part) {
                    p.sendMessage(stageMessage(*p.sendingStage,p.stageSent));
                    p.stageSent+=std::min<std::size_t>(3000,p.sendingStage->rewind.size()-p.stageSent);
                    if(p.stageSent==p.sendingStage->rewind.size()) p.sendingStage.reset();
                }
                if(p.sendingStage) continue;
            }
            if(!p.sending && p.pending) {
                p.sending=std::move(p.pending);p.pending.reset();p.worldSent=0;
                const auto size=p.sending->bytes.size();
                p.sending->bytes=compression.compress(p.sending->bytes);
                if(logger && p.sending->tick%300==0) logger("state_transfer slot="+std::to_string(slot)
                    +" tick="+std::to_string(p.sending->tick)+" raw="+std::to_string(size)+" wire="+std::to_string(p.sending->bytes.size()));
            }
            if(!p.sending) continue;
            auto& value=*p.sending;
            for(unsigned part=0;part<8 && p.queued<16384 && p.worldSent<value.bytes.size();++part) {
                const auto n=std::min<std::size_t>(3000,value.bytes.size()-p.worldSent);
                Writer w(Message::world);w.u32(value.tick);w.u32(p.worldSent);w.u32(value.bytes.size());
                if(!p.worldSent) { w.u8(value.connected);w.u8(value.pauseOwner);w.u8(value.paused);for(auto seq:value.inputSequences) w.u32(seq); }
                w.blob(std::span(value.bytes).subspan(p.worldSent,n));p.sendMessage(w);p.worldSent+=n;
            }
            if(p.worldSent==value.bytes.size()) p.sending.reset();
        }
    }
    void receiveReturning() {
        for(auto it=incoming.begin();it!=incoming.end();) {
            auto& p=**it;std::optional<unsigned> slot;bool rejected=false;
            try {
                if(Clock::now()-p.connectedAt>std::chrono::seconds(10)) throw std::runtime_error("Handshake timed out");
                p.receive([&](Reader& r) {
                    if(slot || r.u8()!=static_cast<unsigned>(Message::hello) || r.u16()!=protocolVersion || r.string()!=fingerprint)
                        throw std::runtime_error("Game, extension or protocol mismatch");
                    const auto id=r.string();p.mods=r.string();
                    const auto found=std::find(identities.begin()+1,identities.begin()+playerCount,id);
                    if(!validIdentity(id) || found==identities.begin()+playerCount) throw std::runtime_error("Only original players can rejoin");
                    const auto i=static_cast<unsigned>(found-identities.begin());
                    if(peers[i] || (activeMask&(1u<<i))) throw std::runtime_error("Player already connected");
                    slot=i;
                });
            } catch(const std::exception& e) {
                try { Writer w(Message::error);w.string(std::string(e.what()).substr(0,240));p.sendMessage(w);p.flush(); } catch(...) {}
                rejected=true;
            }
            if(slot && !rejected) {
                peers[*slot]=std::move(*it);auto& q=*peers[*slot];q.accepted=true;q.waiting=true;
                Writer w(Message::welcome);w.u8(*slot);q.sendMessage(w);
                Writer wait(Message::waitFloor);wait.u8(playerCount);wait.string("");q.sendMessage(wait);updateMods(true);
            }
            if(slot || rejected) it=incoming.erase(it);else ++it;
        }
    }
};
Session::Session(void (*logger)(const std::string&)):impl(std::make_unique<Impl>(logger)) {}
Session::~Session()=default;
bool Session::host(std::uint16_t port,const std::string& fingerprint,const std::string& mods) {
    if(!impl->winsock || impl->state!=Phase::idle || fingerprint.empty()) return false;
    try {
        impl->listener=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(impl->listener==INVALID_SOCKET) throw std::runtime_error("Cannot create LAN socket");
        configure(impl->listener);BOOL exclusive=TRUE;
        setsockopt(impl->listener,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive));
        sockaddr_in a{};a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=INADDR_ANY;
        if(bind(impl->listener,reinterpret_cast<sockaddr*>(&a),sizeof(a)) || listen(impl->listener,3)) throw std::runtime_error("LAN port is unavailable");
        int size=sizeof(a);if(getsockname(impl->listener,reinterpret_cast<sockaddr*>(&a),&size)) throw std::runtime_error("Cannot inspect LAN port");
        impl->boundPort=ntohs(a.sin_port);impl->hosting=true;impl->fingerprint=fingerprint;impl->mods=mods;impl->state=Phase::lobby;return true;
    } catch(const std::exception& e) { impl->fail(e.what());return false; }
}
bool Session::join(const std::string& ip,std::uint16_t port,const std::string& fingerprint,const std::string& identity,const std::string& mods) {
    if(!impl->winsock || impl->state!=Phase::idle || fingerprint.empty()) return false;
    try {
        impl->identity=identity.empty()?randomIdentity():identity;if(!validIdentity(impl->identity)) throw std::runtime_error("Invalid player identity");
        sockaddr_in a{};a.sin_family=AF_INET;a.sin_port=htons(port);
        if(InetPtonA(AF_INET,ip.c_str(),&a.sin_addr)!=1) throw std::runtime_error("Enter a valid IPv4 address");
        SOCKET s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(s==INVALID_SOCKET) throw std::runtime_error("Cannot create LAN socket");
        impl->peers[0]=std::make_unique<Socket>(s);configure(s);
        if(connect(s,reinterpret_cast<sockaddr*>(&a),sizeof(a)) && !wouldBlock()) throw std::runtime_error("Cannot connect to host");
        impl->connecting=true;impl->fingerprint=fingerprint;impl->mods=mods;impl->hostIP=ip;impl->boundPort=port;impl->state=Phase::connecting;return true;
    } catch(const std::exception& e) { impl->fail(e.what());return false; }
}
bool Session::reconnect() {
    if(impl->hosting || impl->state!=Phase::failed || impl->hostIP.empty()) return false;
    const auto ip=impl->hostIP,identity=impl->identity,fingerprint=impl->fingerprint,mods=impl->mods;
    const auto port=impl->boundPort;const auto logger=impl->logger;
    const auto choices=impl->choices;
    impl=std::make_unique<Impl>(logger);
    impl->choices=choices;
    return join(ip,port,fingerprint,identity,mods);
}
bool Session::beginStage(const Stage& value) {
    if(!impl->hosting || impl->state!=Phase::running) return false;
    auto encoded=value;
    if(!encoded.rewind.empty()) encoded.rewind=impl->compression.compress(encoded.rewind);
    for(unsigned slot=1;slot<impl->playerCount;++slot) if(auto& p=impl->peers[slot];p && p->accepted) {
        if(p->rejoining) { p->floorAfterLoad=encoded;continue; }
        if(!p->ready || p->waiting) continue;
        try {
            // An unfinished view is superseded. Already queued chunks precede
            // this reliable event; no chunk from that view may follow it.
            p->beginStage(encoded);
        } catch(const std::exception&) { impl->remove(slot); }
    }
    impl->sendPending();
    for(unsigned slot=1;slot<impl->playerCount;++slot) if(auto& p=impl->peers[slot];p) {
        try { p->flush(); } catch(const std::exception&) { impl->remove(slot); }
    }
    return true;
}
std::optional<Stage> Session::takeStage() { auto value=impl->receivedStage;impl->receivedStage.reset();return value; }
bool Session::requestRoom(const RoomRequest& value) {
    if(impl->hosting || impl->state!=Phase::running || !impl->localReady) return false;
    Writer w(Message::roomRequest);w.u8(value.stage);w.u8(value.type);w.u8(value.sourceDimension);w.u8(value.dimension);
    w.u16(static_cast<std::uint16_t>(value.source));w.u16(static_cast<std::uint16_t>(value.destination));w.u8(value.teleport);
    impl->peers[0]->sendMessage(w);return true;
}
std::array<std::optional<RoomRequest>,maxPlayers> Session::takeRoomRequests() {
    auto result=std::move(impl->roomRequests);impl->roomRequests={};return result;
}
void Session::poll() {
    if(impl->state==Phase::failed || impl->state==Phase::closed || impl->state==Phase::idle) return;
    try {
        if(impl->listener!=INVALID_SOCKET) {
            SOCKET s=accept(impl->listener,nullptr,nullptr);
            if(s!=INVALID_SOCKET) {
                if(impl->state==Phase::running && impl->incoming.size()<3) { impl->incoming.push_back(std::make_unique<Socket>(s));configure(s); }
                else {
                    unsigned slot=1;while(slot<maxPlayers && impl->peers[slot]) ++slot;
                    if(slot==maxPlayers || impl->state!=Phase::lobby) closesocket(s);
                    else { impl->peers[slot]=std::make_unique<Socket>(s);configure(s); }
                }
            } else if(!wouldBlock()) throw std::runtime_error("LAN accept failed");
        }
        if(impl->connecting) {
            auto& p=*impl->peers[0];fd_set write,error;FD_ZERO(&write);FD_ZERO(&error);FD_SET(p.handle,&write);FD_SET(p.handle,&error);timeval timeout{};
            if(select(0,nullptr,&write,&error,&timeout)==SOCKET_ERROR || FD_ISSET(p.handle,&error)) throw std::runtime_error("Host connection refused");
            if(!FD_ISSET(p.handle,&write)) { if(Clock::now()-p.connectedAt>std::chrono::seconds(10)) throw std::runtime_error("Host connection timed out");return; }
            int status=0,size=sizeof(status);getsockopt(p.handle,SOL_SOCKET,SO_ERROR,reinterpret_cast<char*>(&status),&size);
            if(status) throw std::runtime_error("Host connection failed");
            impl->connecting=false;
            Writer hello(Message::hello);hello.u16(protocolVersion);hello.string(impl->fingerprint);hello.string(impl->identity);hello.string(impl->mods);p.sendMessage(hello);
        }
        for(unsigned i=0;i<maxPlayers;++i) if(impl->peers[i]) {
            auto& p=*impl->peers[i];
            try {
                if(!p.accepted && Clock::now()-p.connectedAt>std::chrono::seconds(10)) throw std::runtime_error("Handshake timed out");
                p.flush();p.receive([&](Reader& r){impl->message(i,r);});
                if(impl->hosting && p.ready && Clock::now()-p.inputAt>std::chrono::seconds(15)) throw ConnectionLost("Player connection timed out");
            } catch(const std::exception& e) {
                if(!impl->hosting) throw;
                try { Writer w(Message::error);w.string(std::string(e.what()).substr(0,240));p.sendMessage(w);p.flush(); } catch(...) {}
                impl->remove(i);if(impl->state==Phase::lobby) { impl->choices[i]={};impl->identities[i].clear();impl->lobbyDirty=true; }
            }
        }
        if(impl->hosting && impl->lobbyDirty) impl->lobby();
        if(impl->hosting) { impl->receiveReturning();impl->updateMods();impl->measureLatency();impl->sendPending(); }
        for(unsigned i=0;i<maxPlayers;++i) if(impl->peers[i]) {
            try { impl->peers[i]->flush(); }
            catch(const std::exception&) { if(!impl->hosting) throw;impl->remove(i); }
        }
        if(impl->state==Phase::finishing) {
            const bool drained=std::all_of(impl->peers.begin(),impl->peers.end(),[](const auto& p){return !p || p->outgoing.empty();});
            if(drained || Clock::now()-impl->progress>std::chrono::seconds(5)) { impl->shutdown();impl->state=Phase::closed; }
        }
        if(!impl->hosting && impl->state==Phase::running && impl->localReady && Clock::now()-impl->progress>std::chrono::seconds(20))
            throw std::runtime_error("Host state transfer timed out");
    } catch(const std::exception& e) { impl->fail(e.what()); }
}
void Session::close() {
    Writer bye(Message::goodbye);for(auto& p:impl->peers) if(p) { try { p->sendMessage(bye);p->flush(); } catch(...) {} }
    impl->shutdown();impl->state=Phase::closed;
}
void Session::finish() {
    if(!impl->hosting || impl->state!=Phase::running) { close();return; }
    try {
        Writer w(Message::finish);w.u32(impl->nextConsume);impl->broadcast(w);
        impl->state=Phase::finishing;impl->progress=Clock::now();
        for(auto& peer:impl->peers) if(peer) peer->flush();
    }
    catch(const std::exception& e) { impl->fail(e.what()); }
}
void Session::abort(const std::string& reason) { impl->fail(reason); }
bool Session::start(const Start& settings) {
    if(!impl->hosting || impl->state!=Phase::lobby || impl->playerCount<2 || settings.seed.size()!=8 || settings.difficulty>3 || settings.snapshot.size()>maxSnapshotSize) return false;
    for(unsigned i=1;i<maxPlayers;++i) if((i<impl->playerCount && (!impl->peers[i] || !impl->peers[i]->accepted)) || (i>=impl->playerCount && impl->peers[i])) return false;
    if(impl->choicesRequired) for(unsigned i=0;i<impl->playerCount;++i) if(!impl->choices[i].ready || (settings.snapshot.empty() && impl->choices[i].character!=settings.characters[i])) return false;
    impl->startSettings=settings;impl->startSettings.firstTick=0;impl->activeMask=(1u<<impl->playerCount)-1;impl->startSettings.connected=impl->activeMask;
    impl->broadcast(impl->startMessage(Message::start,impl->startSettings));
    if(!settings.snapshot.empty()) for(auto& p:impl->peers) if(p) p->checkpoint=std::make_shared<Start>(impl->startSettings);
    impl->state=Phase::running;impl->progress=Clock::now();return true;
}
bool Session::checkpoint(const Start& settings,std::uint32_t tick) {
    if(!impl->hosting || impl->state!=Phase::running || settings.snapshot.empty() || settings.snapshot.size()>maxSnapshotSize || tick!=impl->committed) return false;
    auto saved=std::make_shared<Start>(settings);saved->firstTick=tick;saved->connected=impl->activeMask;
    impl->startSettings=*saved;impl->startSettings.snapshot.clear();
    for(unsigned slot=1;slot<impl->playerCount;++slot) if(auto& p=impl->peers[slot];p && p->accepted && p->waiting) {
        impl->latest[slot]={};impl->commands[slot]=Command::none;
        p->ready=false;p->loaded=false;p->snapshotSent=0;p->checkpoint=saved;p->pending.reset();
        // Finish a partly transmitted view before the checkpoint header.
        // All queued chunks are bounded; the receiver discards the old view.
        p->sending.reset();
        p->rejoining=true;p->sendMessage(impl->startMessage(Message::start,*saved));p->waiting=false;
    }
    return true;
}
bool Session::checkpointNeeded() const {
    if(!impl->hosting || impl->state!=Phase::running) return false;
    return std::any_of(impl->peers.begin(),impl->peers.end(),[](const auto& p){return p && p->accepted && p->waiting;});
}
bool Session::choose(Choice choice) {
    if(impl->state!=Phase::lobby) return false;
    if(impl->hosting) { impl->choices[0]=choice;impl->choicesRequired=true;impl->lobbyDirty=true; }
    else { Writer w(Message::choice);w.u16(choice.character);w.u8(choice.ready);impl->peers[0]->sendMessage(w); }return true;
}
const std::array<Choice,maxPlayers>& Session::choices() const { return impl->choices; }
bool Session::command(Command c) {
    if(impl->state!=Phase::running || c==Command::none || c>Command::leave || (!impl->hosting && c==Command::saveExit) || (impl->hosting && c==Command::leave)) return false;
    if(c==Command::leave) { close();return true; }
    if(impl->hosting) impl->commands[0]=c;
    else { Writer w(Message::control);w.u8(static_cast<unsigned>(c));impl->peers[0]->sendMessage(w); }return true;
}
bool Session::submit(std::uint32_t sequence,const InputFrame& input) {
    if(impl->state!=Phase::running || sequence!=impl->nextInput) return false;
    if(impl->hosting) { const auto edges=impl->latest[0].triggered;impl->latest[0]=input;impl->latest[0].triggered|=edges;impl->sequences[0]=sequence; }
    else { Writer w(Message::input);w.u32(sequence);w.input(input);impl->peers[0]->sendMessage(w); }
    ++impl->nextInput;return true;
}
std::optional<Frame> Session::take() {
    if(!impl->hosting || impl->state!=Phase::running || !impl->localReady || !impl->nextInput) return {};
    if(!impl->initialStarted) {
        for(unsigned i=1;i<impl->playerCount;++i) if(impl->peers[i] && !impl->peers[i]->ready) return {};
        impl->initialStarted=true;
    }
    if(impl->consumedLocal==impl->sequences[0]) return {};
    impl->consumedLocal=impl->sequences[0];
    Frame frame;frame.tick=impl->nextConsume++;frame.players=impl->playerCount;
    for(unsigned i=1;i<impl->playerCount;++i) {
        if(impl->commands[i]==Command::leave) { impl->remove(i);continue; }
        if(impl->peers[i] && Clock::now()-impl->peers[i]->inputAt>std::chrono::milliseconds(500)) impl->latest[i]={};
    }
    frame.connected=impl->activeMask;frame.commands=impl->commands;impl->commands={};
    for(unsigned i=0;i<impl->playerCount;++i) {
        if(impl->activeMask&(1u<<i)) frame.inputs[i]=impl->latest[i];
        impl->latest[i].triggered=0;
    }
    impl->progress=Clock::now();return frame;
}
bool Session::ready() {
    if(impl->state!=Phase::running) return false;
    impl->localReady=true;impl->progress=Clock::now();
    if(!impl->hosting) { Writer w(Message::ready);w.u32(impl->startSettings.firstTick);impl->peers[0]->sendMessage(w); }return true;
}
bool Session::publish(unsigned slot,const WorldState& state) {
    if(!impl->hosting || impl->state!=Phase::running || !slot || slot>=impl->playerCount || state.bytes.empty() || state.bytes.size()>maxWorldSize || state.tick>=impl->nextConsume) return false;
    if(auto& p=impl->peers[slot];p && p->ready) p->pending=state;
    return true;
}
std::optional<WorldState> Session::takeState() {
    if(impl->hosting || !impl->localReady || !impl->receivedState) return {};
    auto value=std::move(impl->receivedState);impl->receivedState.reset();impl->activeMask=value->connected;return value;
}
void Session::applied(std::uint32_t tick) {
    if(impl->hosting || impl->state!=Phase::running || (impl->verified && tick<=*impl->verified)) return;
    impl->verified=tick;impl->nextConsume=tick+1;
    Writer w(Message::applied);w.u32(tick);impl->peers[0]->sendMessage(w);
}
void Session::completed(std::uint32_t tick) { if(impl->hosting) { impl->committed=tick+1;impl->verified=tick; } }
std::array<std::uint32_t,maxPlayers> Session::inputSequences() const { return impl->sequences; }
const std::array<int,maxPlayers>& Session::latency() const { return impl->latency; }
const std::string& Session::identity() const { return impl->identity; }
Phase Session::phase() const { return impl->state; }
unsigned Session::slot() const { return impl->localSlot; }
unsigned Session::players() const { return impl->playerCount; }
unsigned Session::connectedMask() const { return impl->activeMask; }
bool Session::isHost() const { return impl->hosting; }
bool Session::modsDiffer() const { return impl->modMismatch; }
const std::string& Session::error() const { return impl->failure; }
const Start& Session::settings() const { return impl->startSettings; }
std::optional<std::uint32_t> Session::verifiedTick() const { return impl->verified; }
std::uint16_t Session::port() const { return impl->boundPort; }
}
