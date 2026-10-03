#include "HookSystem.h"
#include "IsaacRepentance.h"
#include "LuaCore.h"
#include "libzhl.h"
#include "lua.hpp"

#include <cmath>
#include <unordered_map>

namespace {
struct ProxyState {
    unsigned int seed;
    int lastTick = -1;
    bool releaseNextTick = false;
};

std::unordered_map<Entity_Familiar*, ProxyState> proxies;
bool firingProxy = false;

Entity_Familiar* familiarArg(lua_State* state) {
    return lua::GetLuabridgeUserdata<Entity_Familiar*>(
        state, 1, lua::Metatables::ENTITY_FAMILIAR, "EntityFamiliar");
}

bool registered(Entity_Familiar* familiar) {
    const auto found = proxies.find(familiar);
    if (found == proxies.end()) return false;
    if (found->second.seed != familiar->_initSeed) {
        proxies.erase(found);
        return false;
    }
    return true;
}

bool suppressPlayerFire(Weapon* weapon) {
    Entity* owner = weapon->GetOwner();
    Entity_Familiar* familiar = owner ? owner->ToFamiliar() : nullptr;
    return familiar && registered(familiar) && !firingProxy;
}

int registerProxy(lua_State* state) {
    auto* familiar = familiarArg(state);
    if (familiar && familiar->_type == 3 && familiar->_variant == 80) {
        proxies[familiar] = { familiar->_initSeed, -1, false };
        lua_pushboolean(state, 1);
    } else {
        lua_pushboolean(state, 0);
    }
    return 1;
}

int unregisterProxy(lua_State* state) {
    proxies.erase(familiarArg(state));
    return 0;
}

int resetProxies(lua_State*) {
    proxies.clear();
    return 0;
}

int tickProxy(lua_State* state) {
    auto* familiar = familiarArg(state);
    const float x = static_cast<float>(luaL_checknumber(state, 2));
    const float y = static_cast<float>(luaL_checknumber(state, 3));
    const bool hasTarget = lua_toboolean(state, 4) && (x * x + y * y > 0.001f);
    if (!familiar || !registered(familiar) || !g_Game || !familiar->_weapon) {
        lua_pushboolean(state, 0);
        return 1;
    }

    auto& proxy = proxies.at(familiar);
    if (proxy.lastTick == g_Game->_frameCount) {
        lua_pushboolean(state, 0);
        return 1;
    }
    proxy.lastTick = g_Game->_frameCount;

    auto* weapon = familiar->_weapon;
    const float maxCharge = weapon->GetMaxCharge();
    bool shooting = hasTarget;
    if (!hasTarget) {
        proxy.releaseNextTick = false;
    } else if (maxCharge > 0.0f) {
        if (proxy.releaseNextTick) {
            proxy.releaseNextTick = false;
        } else if (*weapon->GetCharge() >= maxCharge) {
            shooting = false;
            proxy.releaseNextTick = true;
        }
    }
    const float length = std::sqrt(x * x + y * y);
    const Vector direction = hasTarget ? Vector{ x / length, y / length } : Vector{ 0.0f, 0.0f };
    *weapon->GetDirection() = direction;
    const int previousShots = weapon->GetNumFired();
    firingProxy = true;
    weapon->Fire(direction, shooting, false);
    firingProxy = false;
    lua_pushboolean(state, weapon->GetNumFired() != previousShots);
    return 1;
}

void registerApi(lua_State* state) {
    lua_newtable(state);
    lua_pushinteger(state, 1); lua_setfield(state, -2, "abi");
    lua_pushcfunction(state, registerProxy); lua_setfield(state, -2, "RegisterProxy");
    lua_pushcfunction(state, unregisterProxy); lua_setfield(state, -2, "UnregisterProxy");
    lua_pushcfunction(state, resetProxies); lua_setfield(state, -2, "ResetProxies");
    lua_pushcfunction(state, tickProxy); lua_setfield(state, -2, "TickProxy");
    lua_setglobal(state, "AscentionNative");
}
}

HOOK_METHOD(Weapon, Fire, (const Vector& direction, bool shooting, bool interpolated) -> void) {
    if (suppressPlayerFire(this)) return;
    super(direction, shooting, interpolated);
}

HOOK_METHOD(Weapon_Brimstone, Fire, (const Vector& direction, bool shooting, bool interpolated) -> void) {
    if (suppressPlayerFire(this)) return;
    super(direction, shooting, interpolated);
}

HOOK_METHOD(Weapon_MonstrosLung, Fire, (const Vector& direction, bool shooting, bool interpolated) -> void) {
    if (suppressPlayerFire(this)) return;
    super(direction, shooting, interpolated);
}

HOOK_METHOD_PRIORITY(LuaEngine, RegisterClasses, 500, () -> void) {
    super();
    registerApi(_state);
}

MOD_EXPORT int ModInit() { return 0; }
