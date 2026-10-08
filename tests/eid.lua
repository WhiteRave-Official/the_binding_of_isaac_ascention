ModCallbacks = { MC_POST_MODS_LOADED = 1 }
local onModsLoaded
local mod = { AddCallback = function(_, callback, handler)
    assert(callback == ModCallbacks.MC_POST_MODS_LOADED)
    onModsLoaded = handler
end }

local ids = {
    goldenEye = 1, arclight = 2, tiara = 3, flamingRose = 5,
    eyeOfOldGod = 6, heartPendant = 7, holyChalice = 9, revelation = 643,
    brokenPendant = 8,
}
dofile("scripts/compat/eid.lua").Register(mod, ids)
assert(onModsLoaded)
onModsLoaded()

local entries = { collectible = {}, trinket = {} }
EID = {
    addCollectible = function(_, id, description, name, language)
        assert(type(description) == "string" and #description > 0)
        assert(name == nil)
        entries.collectible[tostring(id) .. ":" .. language] = description
    end,
    addTrinket = function(_, id, description, name, language)
        assert(type(description) == "string" and #description > 0)
        assert(name == nil)
        entries.trinket[tostring(id) .. ":" .. language] = description
    end,
}
onModsLoaded()

for _, id in ipairs({ 1, 2, 3, 5, 6, 7, 9, 643 }) do
    assert(entries.collectible[id .. ":en_us"])
    assert(entries.collectible[id .. ":ru"])
end
assert(entries.trinket["8:en_us"])
assert(entries.trinket["8:ru"])
assert(not entries.collectible["8:ru"])
assert(entries.collectible["643:ru"]:find("15%%"))
assert(entries.trinket["8:ru"]:find("20%%"))
for _, language in ipairs({ "en_us", "ru" }) do
    local goldenEye = entries.collectible["1:" .. language]
    local revelation = entries.collectible["643:" .. language]
    assert(select(2, goldenEye:gsub("{{ColorRed}}", "")) == 2)
    assert(select(2, goldenEye:gsub("{{CR}}", "")) == 2)
    assert(select(2, revelation:gsub("{{ColorRed}}", "")) == 2)
    assert(select(2, revelation:gsub("{{CR}}", "")) == 2)
end
print("eid: OK")
