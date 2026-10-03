#include "HookSystem.h"
#include "IsaacRepentance.h"
#include "LuaCore.h"
#include "libzhl.h"
#include "lua.hpp"

#include <algorithm>
#include <cmath>
#include <unordered_map>

namespace {
struct ProxyState {
    unsigned int seed;
    int lastTick = -1;
    int releaseFrames = 0;
    bool wasShooting = false;
    unsigned int inputReads = 0;
    unsigned int blockedFireCalls = 0;
    Vector blockedFireArg{ 0.0f, 0.0f };
    Vector afterFireDirection{ 0.0f, 0.0f };
    unsigned int releases = 0;
    unsigned int projectileCalls = 0;
    unsigned int brimstoneCalls = 0;
    unsigned int techLaserCalls = 0;
    unsigned int techXCalls = 0;
    unsigned int knifeCalls = 0;
};

std::unordered_map<Entity_Familiar*, ProxyState> proxies;
bool firingProxy = false;
ProxyState* inputProxy = nullptr;
Vector inputDirection{ 0.0f, 0.0f };
bool inputShooting = false;
bool inputTriggered = false;

float shootActionValue(int action) {
    if (!inputProxy || action < 4 || action > 7) return -1.0f;
    ++inputProxy->inputReads;
    if (!inputShooting) return 0.0f;
    switch (action) {
    case 4: return std::max(0.0f, -inputDirection.x);
    case 5: return std::max(0.0f, inputDirection.x);
    case 6: return std::max(0.0f, -inputDirection.y);
    case 7: return std::max(0.0f, inputDirection.y);
    default: return 0.0f;
    }
}

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

bool blockPlayerFire(Weapon* weapon, const Vector& argument) {
    if (!suppressPlayerFire(weapon)) return false;
    auto& proxy = proxies.at(weapon->GetOwner()->ToFamiliar());
    ++proxy.blockedFireCalls;
    proxy.blockedFireArg = argument;
    return true;
}

int registerProxy(lua_State* state) {
    auto* familiar = familiarArg(state);
    if (familiar && familiar->_type == 3 && familiar->_variant == 80) {
        proxies[familiar] = { familiar->_initSeed };
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

int getInputReads(lua_State* state) {
    auto* familiar = familiarArg(state);
    lua_pushinteger(state, familiar && registered(familiar)
        ? proxies.at(familiar).inputReads : 0);
    return 1;
}

int isRegistered(lua_State* state) {
    auto* familiar = familiarArg(state);
    lua_pushboolean(state, familiar && registered(familiar));
    return 1;
}

int diagnostics(lua_State* state) {
    auto* familiar = familiarArg(state);
    lua_newtable(state);
    if (!familiar || !registered(familiar)) return 1;
    const auto& proxy = proxies.at(familiar);
    lua_pushinteger(state, proxy.inputReads); lua_setfield(state, -2, "input_reads");
    lua_pushinteger(state, proxy.blockedFireCalls); lua_setfield(state, -2, "blocked_fire");
    lua_pushnumber(state, proxy.blockedFireArg.x); lua_setfield(state, -2, "blocked_x");
    lua_pushnumber(state, proxy.blockedFireArg.y); lua_setfield(state, -2, "blocked_y");
    lua_pushnumber(state, proxy.afterFireDirection.x); lua_setfield(state, -2, "after_x");
    lua_pushnumber(state, proxy.afterFireDirection.y); lua_setfield(state, -2, "after_y");
    lua_pushinteger(state, proxy.releases); lua_setfield(state, -2, "releases");
    lua_pushinteger(state, proxy.projectileCalls); lua_setfield(state, -2, "projectiles");
    lua_pushinteger(state, proxy.brimstoneCalls); lua_setfield(state, -2, "brimstones");
    lua_pushinteger(state, proxy.techLaserCalls); lua_setfield(state, -2, "tech_lasers");
    lua_pushinteger(state, proxy.techXCalls); lua_setfield(state, -2, "tech_x");
    lua_pushinteger(state, proxy.knifeCalls); lua_setfield(state, -2, "knives");
    return 1;
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
    bool releaseCharge = false;
    if (!hasTarget) {
        proxy.releaseFrames = 0;
    } else if (maxCharge > 0.0f) {
        if (proxy.releaseFrames == 0 && *weapon->GetCharge() >= maxCharge) {
            proxy.releaseFrames = weapon->GetWeaponType() == WEAPON_BRIMSTONE ? 25 : 2;
            releaseCharge = true;
        }
        if (proxy.releaseFrames > 0) {
            --proxy.releaseFrames;
            shooting = false;
        }
    }
    const float length = std::sqrt(x * x + y * y);
    const Vector direction = hasTarget ? Vector{ x / length, y / length } : Vector{ 0.0f, 0.0f };
    *weapon->GetDirection() = direction;
    const int previousShots = weapon->GetNumFired();
    inputProxy = &proxy;
    inputDirection = direction;
    inputShooting = shooting;
    inputTriggered = shooting && !proxy.wasShooting;
    firingProxy = true;
    weapon->Fire(direction, shooting, false);
    proxy.afterFireDirection = *weapon->GetDirection();
    if (releaseCharge) {
        ++proxy.releases;
        inputShooting = true;
        inputTriggered = true;
        familiar->Shoot();
    }
    firingProxy = false;
    inputProxy = nullptr;
    proxy.wasShooting = shooting;
    lua_pushboolean(state, weapon->GetNumFired() != previousShots);
    return 1;
}

void registerApi(lua_State* state) {
    lua_newtable(state);
    lua_pushinteger(state, 1); lua_setfield(state, -2, "abi");
    lua_pushcfunction(state, registerProxy); lua_setfield(state, -2, "RegisterProxy");
    lua_pushcfunction(state, unregisterProxy); lua_setfield(state, -2, "UnregisterProxy");
    lua_pushcfunction(state, resetProxies); lua_setfield(state, -2, "ResetProxies");
    lua_pushcfunction(state, getInputReads); lua_setfield(state, -2, "GetInputReads");
    lua_pushcfunction(state, isRegistered); lua_setfield(state, -2, "IsRegistered");
    lua_pushcfunction(state, diagnostics); lua_setfield(state, -2, "Diagnostics");
    lua_pushcfunction(state, tickProxy); lua_setfield(state, -2, "TickProxy");
    lua_setglobal(state, "AscentionNative");
}
}

HOOK_METHOD(Entity_Familiar, Shoot, () -> void) {
    if (registered(this) && !firingProxy) return;
    super();
}

HOOK_METHOD(Entity_Familiar, FireProjectile, (const Vector& aimDirection, bool unknown) -> Entity_Tear*) {
    if (registered(this) && firingProxy && inputDirection.x * inputDirection.x
            + inputDirection.y * inputDirection.y > 0.001f) {
        ++proxies.at(this).projectileCalls;
        return super(inputDirection, unknown);
    }
    return super(aimDirection, unknown);
}

HOOK_METHOD(Entity_Familiar, FireBrimstone, (const Vector& aimDirection, bool unknown) -> Entity_Laser*) {
    if (registered(this) && firingProxy && inputDirection.x * inputDirection.x
            + inputDirection.y * inputDirection.y > 0.001f) {
        ++proxies.at(this).brimstoneCalls;
        return super(inputDirection, unknown);
    }
    return super(aimDirection, unknown);
}

HOOK_METHOD(Entity_Familiar, FireTechLaser, (const Vector& aimDirection) -> Entity_Laser*) {
    if (registered(this) && firingProxy && inputDirection.x * inputDirection.x
            + inputDirection.y * inputDirection.y > 0.001f) {
        ++proxies.at(this).techLaserCalls;
        return super(inputDirection);
    }
    return super(aimDirection);
}

HOOK_METHOD(Entity_Player, FireTechXLaser, (const Vector& position, const Vector& direction,
        float radius, Entity* source, float damageMultiplier) -> Entity_Laser*) {
    if (firingProxy && inputProxy && inputDirection.x * inputDirection.x
            + inputDirection.y * inputDirection.y > 0.001f) {
        ++inputProxy->techXCalls;
        const float speed = std::sqrt(direction.x * direction.x + direction.y * direction.y);
        const Vector aimedVelocity{ inputDirection.x * speed, inputDirection.y * speed };
        return super(position, aimedVelocity, radius, source, damageMultiplier);
    }
    return super(position, direction, radius, source, damageMultiplier);
}

HOOK_METHOD(Entity_Player, FireKnife, (Entity* parent, unsigned int variant, float rotationOffset,
        bool cantOverwrite, unsigned int subType) -> Entity_Knife*) {
    if (firingProxy && inputProxy) ++inputProxy->knifeCalls;
    return super(parent, variant, rotationOffset, cantOverwrite, subType);
}

HOOK_METHOD(InputManager, GetActionValue, (int action, int controller, int unknown) -> float) {
    const float value = shootActionValue(action);
    return value >= 0.0f ? value : super(action, controller, unknown);
}

HOOK_METHOD(InputManager, IsActionPressed, (int action, int controller, int unknown) -> bool) {
    const float value = shootActionValue(action);
    return value >= 0.0f ? value > 0.01f : super(action, controller, unknown);
}

HOOK_METHOD(InputManager, IsActionTriggered, (int action, int controller, int unknown) -> bool) {
    const float value = shootActionValue(action);
    return value >= 0.0f ? inputTriggered && value > 0.01f
        : super(action, controller, unknown);
}

HOOK_METHOD(Weapon, Fire, (const Vector& direction, bool shooting, bool interpolated) -> void) {
    if (blockPlayerFire(this, direction)) return;
    super(direction, shooting, interpolated);
}

HOOK_METHOD(Weapon_Brimstone, Fire, (const Vector& direction, bool shooting, bool interpolated) -> void) {
    if (blockPlayerFire(this, direction)) return;
    super(direction, shooting, interpolated);
}

HOOK_METHOD(Weapon_MonstrosLung, Fire, (const Vector& direction, bool shooting, bool interpolated) -> void) {
    if (blockPlayerFire(this, direction)) return;
    super(direction, shooting, interpolated);
}

HOOK_METHOD_PRIORITY(LuaEngine, RegisterClasses, 500, () -> void) {
    super();
    registerApi(_state);
}

MOD_EXPORT int ModInit() { return 0; }
