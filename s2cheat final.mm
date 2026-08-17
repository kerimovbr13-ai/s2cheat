#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <vector>

typedef void Il2CppObject;
typedef void Il2CppClass;
typedef void Il2CppDomain;
typedef void Il2CppImage;
typedef void Il2CppAssembly;
typedef void Il2CppMethodInfo;
typedef void Il2CppFieldInfo;

typedef Il2CppDomain*     (*t_dget)(void);
typedef Il2CppAssembly**  (*t_dasms)(Il2CppDomain*, size_t*);
typedef Il2CppImage*      (*t_aimg)(Il2CppAssembly*);
typedef Il2CppClass*      (*t_cname)(Il2CppImage*, const char*, const char*);
typedef Il2CppMethodInfo* (*t_cmeth)(Il2CppClass*, const char*, int);
typedef Il2CppFieldInfo*  (*t_cfield)(Il2CppClass*, const char*);
typedef Il2CppObject*     (*t_inv)(Il2CppMethodInfo*, Il2CppObject*, void**, Il2CppObject**);
typedef void              (*t_fset)(Il2CppObject*, Il2CppFieldInfo*, void*);
typedef void*             (*t_ctype)(Il2CppClass*);
typedef Il2CppObject*     (*t_tobj)(void*);

static t_dget   p_dget;
static t_dasms  p_dasms;
static t_aimg   p_aimg;
static t_cname  p_cname;
static t_cmeth  p_cmeth;
static t_cfield p_cfield;
static t_inv    p_inv;
static t_fset   p_fset;
static t_ctype  p_ctype;
static t_tobj   p_tobj;
static void*    fw;

static bool g_wh  = true;
static bool g_aim = true;
static bool g_menu_visible = false;
static int   g_taps = 0;
static NSTimeInterval g_last = 0;

static UIWindow* g_win = nil;
static UIView*   g_mv  = nil;

static Il2CppClass*      g_cls    = nil;
static Il2CppMethodInfo* g_alive  = nil;
static Il2CppMethodInfo* g_enemy  = nil;
static Il2CppMethodInfo* g_findall = nil;
static std::vector<Il2CppObject*> g_enemies;
static pthread_mutex_t g_mtx = PTHREAD_MUTEX_INITIALIZER;

static bool il2_init(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) {
            fw = dlopen(n, RTLD_NOW|RTLD_NOLOAD);
            break;
        }
    }
    if (!fw) fw = RTLD_DEFAULT;
    p_dget  = (t_dget) dlsym(fw,"il2cpp_domain_get");
    p_dasms = (t_dasms)dlsym(fw,"il2cpp_domain_get_assemblies");
    p_aimg  = (t_aimg) dlsym(fw,"il2cpp_assembly_get_image");
    p_cname = (t_cname)dlsym(fw,"il2cpp_class_from_name");
    p_cmeth = (t_cmeth)dlsym(fw,"il2cpp_class_get_method_from_name");
    p_cfield= (t_cfield)dlsym(fw,"il2cpp_class_get_field_from_name");
    p_inv   = (t_inv)  dlsym(fw,"il2cpp_runtime_invoke");
    p_fset  = (t_fset) dlsym(fw,"il2cpp_field_set_value");
    p_ctype = (t_ctype)dlsym(fw,"il2cpp_class_get_type");
    p_tobj  = (t_tobj) dlsym(fw,"il2cpp_type_get_object");
    return p_dget && p_dasms && p_cname && p_inv;
}

static Il2CppClass* find_class(const char* ns, const char* name) {
    Il2CppDomain* dom = p_dget();
    size_t cnt = 0;
    Il2CppAssembly** asms = p_dasms(dom, &cnt);
    for (size_t i = 0; i < cnt; i++) {
        Il2CppImage* img = p_aimg(asms[i]);
        if (!img) continue;
        Il2CppClass* c = p_cname(img, ns, name);
        if (c) return c;
    }
    return nullptr;
}

static Il2CppObject* call(Il2CppMethodInfo* m, Il2CppObject* o) {
    Il2CppObject* exc = nullptr;
    Il2CppObject* r = p_inv(m, o, nullptr, &exc);
    return exc ? nullptr : r;
}

static void tick(void) {
    if (!g_cls || !g_findall || !p_ctype || !p_tobj) return;
    void* pt = p_ctype(g_cls);
    if (!pt) return;
    Il2CppObject* to = p_tobj(pt);
    if (!to) return;
    void* args[1] = {to};
    Il2CppObject* exc = nullptr;
    Il2CppObject* arr = p_inv(g_findall, nullptr, args, &exc);
    if (!arr || exc) return;
    int32_t cnt = *(int32_t*)((uintptr_t)arr + 0x18);
    Il2CppObject** el = (Il2CppObject**)((uintptr_t)arr + 0x20);
    pthread_mutex_lock(&g_mtx);
    g_enemies.clear();
    for (int32_t i = 0; i < cnt && i < 32; i++) {
        Il2CppObject* p = el[i];
        if (!p) continue;
        if (g_alive) {
            Il2CppObject* r = call(g_alive, p);
            if (r && !*(bool*)((uintptr_t)r + 16)) continue;
        }
        if (g_enemy) {
            Il2CppObject* r = call(g_enemy, p);
            if (r && !*(bool*)((uintptr_t)r + 16)) continue;
        }
        g_enemies.push_back(p);
        if (g_wh && p_cfield) {
            Il2CppClass* kl = *(Il2CppClass**)p;
            if (kl) {
                Il2CppFieldInfo* f = p_cfield(kl, "m_Enabled");
                if (f) { bool on = true; p_fset(p, f, &on); }
            }
        }
    }
    pthread_mutex_unlock(&g_mtx);
}

static void show_menu(BOOL show) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (show) {
            if (!g_win) {
                g_win = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
                g_win.windowLevel = UIWindowLevelAlert + 100;
                g_win.backgroundColor = UIColor.clearColor;
                [g_win makeKeyAndVisible];
            }
            if (!g_mv) {
                g_mv = [[UIView alloc] initWithFrame:CGRectMake(30,100,240,170)];
                g_mv.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
                g_mv.layer.cornerRadius = 12;
                g_mv.layer.borderWidth = 1;
                g_mv.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1].CGColor;

                UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0,8,240,28)];
                title.text = @"S2 Cheat";
                title.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1];
                title.textAlignment = NSTextAlignmentCenter;
                title.font = [UIFont boldSystemFontOfSize:15];
                [g_mv addSubview:title];

                UILabel* l1 = [[UILabel alloc] initWithFrame:CGRectMake(14,46,130,36)];
                l1.text = @"WallHack";
                l1.textColor = UIColor.whiteColor;
                l1.font = [UIFont systemFontOfSize:14];
                [g_mv addSubview:l1];

                UISwitch* s1 = [[UISwitch alloc] initWithFrame:CGRectMake(166,50,0,0)];
                s1.on = g_wh;
                s1.tag = 1;
                s1.onTintColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1];
                [s1 addTarget:g_mv action:@selector(tog:) forControlEvents:UIControlEventValueChanged];
                [g_mv addSubview:s1];

                UILabel* l2 = [[UILabel alloc] initWithFrame:CGRectMake(14,100,130,36)];
                l2.text = @"Silent Aim";
                l2.textColor = UIColor.whiteColor;
                l2.font = [UIFont systemFontOfSize:14];
                [g_mv addSubview:l2];

                UISwitch* s2 = [[UISwitch alloc] initWithFrame:CGRectMake(166,104,0,0)];
                s2.on = g_aim;
                s2.tag = 2;
                s2.onTintColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1];
                [s2 addTarget:g_mv action:@selector(tog:) forControlEvents:UIControlEventValueChanged];
                [g_mv addSubview:s2];

                UILabel* hint = [[UILabel alloc] initWithFrame:CGRectMake(0,146,240,20)];
                hint.text = @"3 тапа — закрыть";
                hint.textColor = UIColor.grayColor;
                hint.textAlignment = NSTextAlignmentCenter;
                hint.font = [UIFont systemFontOfSize:11];
                [g_mv addSubview:hint];

                UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:g_mv action:@selector(pan:)];
                [g_mv addGestureRecognizer:pan];
                [g_win addSubview:g_mv];
            }
        } else {
            [g_mv removeFromSuperview];
            g_mv = nil;
        }
    });
}

static IMP orig_send;
static void hook_send(UIApplication* self, SEL sel, UIEvent* ev) {
    for (UITouch* t in [ev allTouches]) {
        if (t.phase == UITouchPhaseBegan) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (now - g_last < 0.5) g_taps++;
            else g_taps = 1;
            g_last = now;
            if (g_taps >= 3) {
                g_taps = 0;
                g_menu_visible = !g_menu_visible;
                show_menu(g_menu_visible);
            }
        }
    }
    ((void(*)(id,SEL,UIEvent*))orig_send)(self, sel, ev);
}

static void* thread_fn(void*) {
    sleep(4);
    if (!il2_init()) return nullptr;
    sleep(2);
    const char* nss[] = {"","Game","Battle","Gameplay",nullptr};
    const char* cls[] = {"PlayerController","BattlePlayer","NetworkPlayer",nullptr};
    for (int n = 0; nss[n] && !g_cls; n++) {
        for (int c = 0; cls[c] && !g_cls; c++) {
            Il2CppClass* k = find_class(nss[n], cls[c]);
            if (!k) continue;
            Il2CppMethodInfo* a = p_cmeth(k,"get_isAlive",0);
            if (!a) a = p_cmeth(k,"get_IsAlive",0);
            if (!a) continue;
            g_cls   = k;
            g_alive = a;
            g_enemy = p_cmeth(k,"IsEnemy",0);
        }
    }
    Il2CppClass* oc = find_class("UnityEngine","Object");
    if (oc) g_findall = p_cmeth(oc,"FindObjectsOfTypeAll",1);
    while (true) { tick(); usleep(50000); }
    return nullptr;
}

__attribute__((constructor))
static void s2_init(void) {
    Method m = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
    orig_send = method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_send);
    pthread_t tid;
    pthread_create(&tid, nullptr, thread_fn, nullptr);
    pthread_detach(tid);
}

