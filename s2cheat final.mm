#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <cmath>
#include <vector>

typedef void Il2CppObject;
typedef void Il2CppClass;
typedef void Il2CppDomain;
typedef void Il2CppImage;
typedef void Il2CppAssembly;
typedef void Il2CppMethodInfo;
typedef void Il2CppFieldInfo;
typedef struct { float x, y, z; } Vector3;

typedef Il2CppDomain*     (*t_domain_get)();
typedef Il2CppAssembly**  (*t_domain_asms)(Il2CppDomain*, size_t*);
typedef Il2CppImage*      (*t_asm_image)(Il2CppAssembly*);
typedef Il2CppClass*      (*t_class_name)(Il2CppImage*, const char*, const char*);
typedef Il2CppMethodInfo* (*t_class_method)(Il2CppClass*, const char*, int);
typedef Il2CppFieldInfo*  (*t_class_field)(Il2CppClass*, const char*);
typedef Il2CppObject*     (*t_invoke)(Il2CppMethodInfo*, Il2CppObject*, void**, Il2CppObject**);
typedef void              (*t_field_get)(Il2CppObject*, Il2CppFieldInfo*, void*);
typedef void              (*t_field_set)(Il2CppObject*, Il2CppFieldInfo*, void*);
typedef void*             (*t_cls_type)(Il2CppClass*);
typedef Il2CppObject*     (*t_type_obj)(void*);

static t_domain_get    p_domain_get;
static t_domain_asms   p_domain_asms;
static t_asm_image     p_asm_image;
static t_class_name    p_class_name;
static t_class_method  p_class_method;
static t_class_field   p_class_field;
static t_invoke        p_invoke;
static t_field_get     p_field_get;
static t_field_set     p_field_set;
static t_cls_type      p_cls_type;
static t_type_obj      p_type_obj;
static void* fw = nullptr;

static bool il2_init() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) {
            fw = dlopen(n, RTLD_NOW|RTLD_NOLOAD);
            break;
        }
    }
    if (!fw) fw = RTLD_DEFAULT;
    p_domain_get   = (t_domain_get)  dlsym(fw, "il2cpp_domain_get");
    p_domain_asms  = (t_domain_asms) dlsym(fw, "il2cpp_domain_get_assemblies");
    p_asm_image    = (t_asm_image)   dlsym(fw, "il2cpp_assembly_get_image");
    p_class_name   = (t_class_name)  dlsym(fw, "il2cpp_class_from_name");
    p_class_method = (t_class_method)dlsym(fw, "il2cpp_class_get_method_from_name");
    p_class_field  = (t_class_field) dlsym(fw, "il2cpp_class_get_field_from_name");
    p_invoke       = (t_invoke)      dlsym(fw, "il2cpp_runtime_invoke");
    p_field_get    = (t_field_get)   dlsym(fw, "il2cpp_field_get_value");
    p_field_set    = (t_field_set)   dlsym(fw, "il2cpp_field_set_value");
    p_cls_type     = (t_cls_type)    dlsym(fw, "il2cpp_class_get_type");
    p_type_obj     = (t_type_obj)    dlsym(fw, "il2cpp_type_get_object");
    return p_domain_get && p_domain_asms && p_class_name;
}

static Il2CppClass* find_class(const char* ns, const char* name) {
    Il2CppDomain* dom = p_domain_get();
    size_t cnt = 0;
    Il2CppAssembly** asms = p_domain_asms(dom, &cnt);
    for (size_t i = 0; i < cnt; i++) {
        Il2CppImage* img = p_asm_image(asms[i]);
        if (!img) continue;
        Il2CppClass* c = p_class_name(img, ns, name);
        if (c) return c;
    }
    return nullptr;
}

static Il2CppObject* do_invoke(Il2CppMethodInfo* m, Il2CppObject* obj, void** p = nullptr) {
    Il2CppObject* exc = nullptr;
    Il2CppObject* r = p_invoke(m, obj, p, &exc);
    return exc ? nullptr : r;
}

static bool g_wh   = true;
static bool g_aim  = true;
static bool g_menu = false;

static Il2CppClass*      cls_player  = nullptr;
static Il2CppMethodInfo* m_isAlive   = nullptr;
static Il2CppMethodInfo* m_getHead   = nullptr;
static Il2CppMethodInfo* m_isEnemy   = nullptr;
static Il2CppMethodInfo* m_findAll   = nullptr;

static pthread_mutex_t g_mtx = PTHREAD_MUTEX_INITIALIZER;
static std::vector<Il2CppObject*> g_enemies;

static void cheat_tick() {
    if (!cls_player || !m_findAll || !p_cls_type || !p_type_obj) return;
    void* ptype = p_cls_type(cls_player);
    if (!ptype) return;
    Il2CppObject* type_obj = p_type_obj(ptype);
    if (!type_obj) return;
    void* params[1] = { type_obj };
    Il2CppObject* arr = do_invoke(m_findAll, nullptr, params);
    if (!arr) return;
    int32_t count = *reinterpret_cast<int32_t*>((uintptr_t)arr + 0x18);
    Il2CppObject** elems = reinterpret_cast<Il2CppObject**>((uintptr_t)arr + 0x20);
    pthread_mutex_lock(&g_mtx);
    g_enemies.clear();
    for (int32_t i = 0; i < count && i < 32; i++) {
        Il2CppObject* p = elems[i];
        if (!p) continue;
        if (m_isAlive) {
            Il2CppObject* r = do_invoke(m_isAlive, p);
            if (r) {
                bool alive = *(bool*)((uintptr_t)r + sizeof(void*)*2);
                if (!alive) continue;
            }
        }
        if (m_isEnemy) {

