// IOSDisplayShim.m — iOS stand-in for Wine's mac driver, used by DXMT.
//
// DXMT (src/winemetal/unix/winemetal_unix.c) looks up this API via
// dlsym(RTLD_DEFAULT, "macdrv_functions") to obtain a CAMetalLayer for a
// given HWND. We export those symbols from the main binary so DXMT finds
// them in the same process.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <pthread.h>

#include "IOSDisplayShim.h"

// --- Types mirroring DXMT's expectations (see winemetal_unix.c lines ~1524) ---

typedef struct macdrv_opaque_metal_device *macdrv_metal_device;
typedef struct macdrv_opaque_metal_view   *macdrv_metal_view;
typedef struct macdrv_opaque_metal_layer  *macdrv_metal_layer;
typedef struct macdrv_opaque_view         *macdrv_view;
typedef struct macdrv_opaque_window       *macdrv_window;
typedef struct opaque_HWND                *HWND;

struct macdrv_win_data {
    HWND         hwnd;
    macdrv_window cocoa_window;
    macdrv_view   cocoa_view;
    macdrv_view   client_cocoa_view;
};

struct macdrv_functions_t {
    void (*macdrv_init_display_devices)(BOOL);
    struct macdrv_win_data *(*get_win_data)(HWND hwnd);
    void (*release_win_data)(struct macdrv_win_data *data);
    macdrv_window (*macdrv_get_cocoa_window)(HWND hwnd, BOOL require_on_screen);
    macdrv_metal_device (*macdrv_create_metal_device)(void);
    void (*macdrv_release_metal_device)(macdrv_metal_device d);
    macdrv_metal_view (*macdrv_view_create_metal_view)(macdrv_view v, macdrv_metal_device d);
    macdrv_metal_layer (*macdrv_view_get_metal_layer)(macdrv_metal_view v);
    void (*macdrv_view_release_metal_view)(macdrv_metal_view v);
    void (*on_main_thread)(dispatch_block_t b);
};

// --- iOS-side state: one layer shared by the whole process ---

static CAMetalLayer *g_layer = nil;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

void mythic_display_set_layer(CAMetalLayer *layer) {
    pthread_mutex_lock(&g_lock);
    g_layer = layer;
    pthread_mutex_unlock(&g_lock);
}

// --- macdrv_* implementations ---

// DXMT only dereferences client_cocoa_view (passing it straight back to
// macdrv_view_create_metal_view), so we use that field to carry the HWND
// through: desktop mode needs it to pick the right window's layer. One
// static struct suffices — DXMT's get/create/release sequence is not
// concurrent per-process, and the value is consumed before release.
static struct macdrv_win_data g_fake_win_data = {
    .hwnd              = NULL,
    .cocoa_window      = NULL,
    .cocoa_view        = (macdrv_view)(uintptr_t)0x1,
    .client_cocoa_view = (macdrv_view)(uintptr_t)0x1,
};

static struct macdrv_win_data *my_get_win_data(HWND hwnd) {
    g_fake_win_data.hwnd = hwnd;
    g_fake_win_data.client_cocoa_view = (macdrv_view)hwnd;
    return &g_fake_win_data;
}

static void my_release_win_data(struct macdrv_win_data *data) {
    (void)data;
}

static int mythic_desktop_mode(void) {
    const char *d = getenv("MYTHIC_DESKTOP");
    return (d && *d == '1');
}

// Winios.m compositor: per-window CAMetalLayer inside the window's
// compositor layer (desktop mode only).
extern CAMetalLayer *winios_metal_layer_for_hwnd(void *hwnd);

static macdrv_metal_device my_create_metal_device(void) {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    fprintf(stderr, "[mythic-display] create_metal_device -> %p (name: %s)\n",
            (__bridge void *)dev, dev ? [[dev name] UTF8String] : "NULL");
    fflush(stderr);
    return (macdrv_metal_device)CFBridgingRetain(dev);
}

static void my_release_metal_device(macdrv_metal_device d) {
    if (d && (uintptr_t)d != 0x1) {
        CFBridgingRelease((CFTypeRef)d);
    }
}

// The critical two: return a "view" handle that maps to the CAMetalLayer.
// We pack the layer pointer directly. `v` carries the swapchain's HWND
// (see my_get_win_data). Desktop mode: per-window layer in the desktop
// compositor. Game mode: the fullscreen singleton, exactly as before.
static macdrv_metal_view my_view_create_metal_view(macdrv_view v, macdrv_metal_device d) {
    fprintf(stderr, "[mythic-display] view_create_metal_view requested for hwnd=%p device=%p (desktop=%d)\n",
            (void *)v, (void *)d, mythic_desktop_mode());
    fflush(stderr);
    if (mythic_desktop_mode()) {
        CAMetalLayer *layer = winios_metal_layer_for_hwnd((void *)v);
        if (layer) {
            fprintf(stderr, "[mythic-display] desktop metal view for hwnd=%p layer=%p frame={%.0f,%.0f,%.0f,%.0f} drawableSize={%.0f,%.0f}\n",
                    (void *)v, layer, layer.frame.origin.x, layer.frame.origin.y, layer.frame.size.width, layer.frame.size.height,
                    layer.drawableSize.width, layer.drawableSize.height);
            fflush(stderr);
            return (macdrv_metal_view)CFBridgingRetain(layer);
        }
        fprintf(stderr, "[mythic-display] desktop metal layer not found for hwnd=%p, falling back to main layer\n", (void *)v);
        fflush(stderr);
    }
    pthread_mutex_lock(&g_lock);
    CAMetalLayer *layer = g_layer;
    pthread_mutex_unlock(&g_lock);
    if (!layer) {
        fprintf(stderr, "[mythic-display] ERROR: view_create_metal_view called but g_layer is NULL!\n");
        fflush(stderr);
        return NULL;
    }
    fprintf(stderr, "[mythic-display] standalone fullscreen metal view returned layer=%p frame={%.0f,%.0f,%.0f,%.0f} drawableSize={%.0f,%.0f}\n",
            layer, layer.frame.origin.x, layer.frame.origin.y, layer.frame.size.width, layer.frame.size.height,
            layer.drawableSize.width, layer.drawableSize.height);
    fflush(stderr);
    return (macdrv_metal_view)CFBridgingRetain(layer);
}

static macdrv_metal_layer my_view_get_metal_layer(macdrv_metal_view v) {
    return (macdrv_metal_layer)v;
}

static void my_view_release_metal_view(macdrv_metal_view v) {
    if (v) CFBridgingRelease((CFTypeRef)v);
}

static void my_on_main_thread(dispatch_block_t b) {
    if ([NSThread isMainThread]) b();
    else dispatch_async(dispatch_get_main_queue(), b);
}

// --- Exported symbols (dlsym RTLD_DEFAULT finds these in the main binary) ---
//
// `used` is LOAD-BEARING, not decoration. Nothing in this program references
// these by name: DXMT's winemetal_unix.c reaches them only through
// dlsym(RTLD_DEFAULT, "macdrv_functions"), which the linker cannot see. Under a
// Release link (-dead_strip) they are therefore unreferenced and get removed,
// visibility("default") notwithstanding -- visibility governs whether a symbol
// that SURVIVES is exported, not whether it survives. `used` emits .no_dead_strip
// so the linker keeps them.
//
// That is exactly how Thumper broke on 2026-08-08: the host app was rebuilt
// Release instead of Debug, these six symbols vanished from the binary, DXMT's
// lookup returned NULL and d3d11_swapchain aborted with "your Wine has no
// exported symbols needed by DXMT" -> exit code 3 -> white screen.
//
// `used` alone proved sufficient: after adding it, all six land in the export
// trie of a Release build, so no -u roots or -export_dynamic are needed. Do not
// assume that stays true -- VERIFY BY CONTENT after any build or link change:
//   xcrun dyld_info -exports Mythic.app/Mythic | grep macdrv_functions
// If that prints nothing, Thumper will exit 3 with a white screen.

__attribute__((used, visibility("default")))
struct macdrv_functions_t macdrv_functions = {
    .macdrv_init_display_devices    = NULL,
    .get_win_data                   = my_get_win_data,
    .release_win_data               = my_release_win_data,
    .macdrv_get_cocoa_window        = NULL,
    .macdrv_create_metal_device     = my_create_metal_device,
    .macdrv_release_metal_device    = my_release_metal_device,
    .macdrv_view_create_metal_view  = my_view_create_metal_view,
    .macdrv_view_get_metal_layer    = my_view_get_metal_layer,
    .macdrv_view_release_metal_view = my_view_release_metal_view,
    .on_main_thread                 = my_on_main_thread,
};

// Also export individual symbols as a fallback (DXMT checks both paths).
__attribute__((used, visibility("default")))
struct macdrv_win_data *get_win_data(HWND hwnd) { return my_get_win_data(hwnd); }

__attribute__((used, visibility("default")))
void release_win_data(struct macdrv_win_data *data) { my_release_win_data(data); }

__attribute__((used, visibility("default")))
macdrv_metal_view macdrv_view_create_metal_view(macdrv_view v, macdrv_metal_device d) {
    return my_view_create_metal_view(v, d);
}

__attribute__((used, visibility("default")))
macdrv_metal_layer macdrv_view_get_metal_layer(macdrv_metal_view v) {
    return my_view_get_metal_layer(v);
}

__attribute__((used, visibility("default")))
void macdrv_view_release_metal_view(macdrv_metal_view v) {
    my_view_release_metal_view(v);
}
