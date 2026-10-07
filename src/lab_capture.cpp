#include "lab_capture.h"
#include "engine_rooms.h"
#include "runtime_net.h"
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <GL/gl.h>
#include <condition_variable>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <thread>
#include <vector>
#include <algorithm>

namespace isaac::lab_capture {
namespace {
struct Image { int width=0,height=0,readFramebuffer=0,room=-999;unsigned sequence=0,tick=0;bool playing=false;ULONGLONG time=0;std::vector<BYTE> pixels; };
std::mutex mutex;
std::condition_variable available;
std::thread worker;
Image pending;
bool enabled=false,checked=false,closing=false;
unsigned sequence=0,dropped=0;
ULONGLONG previous=0;
unsigned interval=100;
void save(std::filesystem::path directory) {
    ULONG_PTR token=0;Gdiplus::GdiplusStartupInput startup;
    if(Gdiplus::GdiplusStartup(&token,&startup,nullptr)!=Gdiplus::Ok) return;
    const CLSID png={0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
    std::ofstream log(directory/"frames.csv");log<<"sequence,time_ms,width,height,dropped,file,read_framebuffer,tick,room,playing\n";
    for(;;) {
        Image value;unsigned losses;
        {
            std::unique_lock lock(mutex);available.wait(lock,[]{return closing || !pending.pixels.empty();});
            if(pending.pixels.empty()) break;
            value=std::move(pending);pending=Image{};losses=dropped;
        }
        const int stride=(value.width*3+3)&~3;
        std::vector<BYTE> bgr(stride*value.height);
        for(int y=0;y<value.height;++y) for(int x=0;x<value.width;++x) {
            const auto from=((value.height-y-1)*value.width+x)*3,to=y*stride+x*3;
            bgr[to]=value.pixels[from+2];bgr[to+1]=value.pixels[from+1];bgr[to+2]=value.pixels[from];
        }
        const auto name=std::to_string(value.sequence)+".png";
        Gdiplus::Bitmap bitmap(value.width,value.height,stride,PixelFormat24bppRGB,bgr.data());
        const auto staged=directory/(name+".tmp");
        if(bitmap.Save(staged.c_str(),&png,nullptr)==Gdiplus::Ok
            && MoveFileExW(staged.c_str(),(directory/name).c_str(),MOVEFILE_REPLACE_EXISTING))
            log<<value.sequence<<','<<value.time<<','<<value.width<<','<<value.height<<','<<losses<<','<<name<<','<<value.readFramebuffer<<','<<value.tick<<','<<value.room<<','<<value.playing<<'\n'<<std::flush;
    }
    Gdiplus::GdiplusShutdown(token);
}
}
void frame(const std::wstring& labRoot) {
    if(!checked) {
        checked=true;
        // Only marked isolated processes with an explicit recording request.
        // This path is never active in the user's installed game.
        if(labRoot.empty() || !std::filesystem::exists(std::filesystem::path(labRoot)/".isaac-lan-lab")
            || !std::filesystem::exists(std::filesystem::path(labRoot)/"visual-capture.test")) return;
        std::ifstream request(std::filesystem::path(labRoot)/"visual-capture.test");
        unsigned requested=100;
        if(request>>requested) interval=std::clamp(requested,16u,1000u);
        const auto directory=std::filesystem::path(labRoot)/"visual-frames";
        std::filesystem::create_directories(directory);enabled=true;
        worker=std::thread(save,directory);
    }
    if(!enabled || closing) return;
    const auto now=GetTickCount64();if(now-previous<interval) return;previous=now;
    GLint viewport[4],alignment,buffer;
    glGetIntegerv(GL_VIEWPORT,viewport);
    if(viewport[2]<=0 || viewport[3]<=0 || viewport[2]>2048 || viewport[3]>2048) return;
    Image value;value.width=viewport[2];value.height=viewport[3];value.time=now;value.sequence=++sequence;
    value.tick=runtime::tick();value.playing=rooms::stateReady();
    if(value.playing) {
        const auto image=reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
        const auto game=*reinterpret_cast<std::uintptr_t*>(image+0x871678);
        value.room=*reinterpret_cast<int*>(game+0x18304);
    }
    using BindFramebuffer=void(APIENTRY*)(GLenum,GLuint);
    BindFramebuffer bind=nullptr;
    const auto proc=wglGetProcAddress("glBindFramebuffer");
    if(reinterpret_cast<std::uintptr_t>(proc)>4 && reinterpret_cast<std::uintptr_t>(proc)!=static_cast<std::uintptr_t>(-1))
        std::memcpy(&bind,&proc,sizeof(bind));
    // SwapBuffers presents the window's back buffer. Room/minimap work may
    // leave an offscreen read target bound; GL_BACK is invalid on that target
    // and used to produce a spurious all-black recording frame.
    if(bind) glGetIntegerv(0x8caa,&value.readFramebuffer); // GL_READ_FRAMEBUFFER_BINDING
    if(value.readFramebuffer) {
        bind(0x8ca8,0); // GL_READ_FRAMEBUFFER, preserve the draw target
        RECT client{};
        if(GetClientRect(WindowFromDC(wglGetCurrentDC()),&client)) {
            viewport[0]=viewport[1]=0;value.width=client.right;value.height=client.bottom;
        }
    }
    value.pixels.resize(value.width*value.height*3);
    glGetIntegerv(GL_PACK_ALIGNMENT,&alignment);glGetIntegerv(GL_READ_BUFFER,&buffer);
    glPixelStorei(GL_PACK_ALIGNMENT,1);glReadBuffer(GL_BACK);
    glReadPixels(viewport[0],viewport[1],value.width,value.height,GL_RGB,GL_UNSIGNED_BYTE,value.pixels.data());
    glReadBuffer(buffer);glPixelStorei(GL_PACK_ALIGNMENT,alignment);
    if(value.readFramebuffer) bind(0x8ca8,value.readFramebuffer);
    { std::lock_guard lock(mutex);if(!pending.pixels.empty()) ++dropped;pending=std::move(value); }
    available.notify_one();
}
void stop() {
    { std::lock_guard lock(mutex);closing=true; }
    available.notify_one();if(worker.joinable()) worker.join();
}
}
