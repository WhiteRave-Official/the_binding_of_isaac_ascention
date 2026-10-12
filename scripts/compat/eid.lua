local Eid = {}

local COLLECTIBLES = {
    goldenEye = {
        en = "{{Tears}} {{ColorRed}}x0.8 fire rate{{CR}}#{{ColorRed}}Cannot fire directly{{CR}}#Give spectral tears#Give homing tears#Summons a golden eye above the player that automatically attacks enemies for 50% of the player's damage#After 50 / 100 / 200 kills, summons another eye, up to 4",
        ru = "{{Tears}} {{ColorRed}}x0,8 к скорострельности{{CR}}#{{ColorRed}}Игрок теряет возможность стрелять{{CR}}#Даёт спектральные слёзы#Даёт самонаводящиеся слёзы#Призывает над игроком золотой глаз, который автоматически атакует врагов и наносит 50% урона игрока#После 50 / 100 / 200 убийств призывает ещё один глаз, максимум 4",
    },
    arclight = {
        en = "{{Piercing}} Swords pierce enemies#25% chance to summon a sword when firing, rising to 50% at 8 Luck#Swords deal 50% of the player's damage#Sword hits have the same chance to call down a beam of light",
        ru = "{{Piercing}} Мечи пронзают врагов#25% шанс призвать меч при выстреле; при 8 удачи шанс достигает 50%#Мечи наносят 50% урона игрока#Попадание мечом с тем же шансом обрушивает луч света",
    },
    tiara = {
        en = "{{Battery}} 4 charges#Summons 1 Mini Isaac; use again to heal it by 50% of max HP#Only Geburah upgrades the tiara after 2000 / 4000 / 8000 damage points from her and her allies",
        ru = "{{Battery}} 4 заряда#Призывает 1 мини-Айзека; повторное использование лечит его на 50% от максимального здоровья#Только Гебура улучшает тиару после 2000 / 4000 / 8000 очков урона от себя и союзников",
    },
    tiara2 = {
        en = "{{Battery}} 3 charges#Summons up to 2 Mini Isaacs; use again to heal surviving guardians by 75% of max HP",
        ru = "{{Battery}} 3 заряда#Призывает до 2 мини-Айзеков; повторное использование лечит выживших стражников на 75% от максимального здоровья",
    },
    tiara3 = {
        en = "{{Battery}} 3 charges#Summons up to 3 Mini Isaacs; use again to heal surviving guardians by 85% of max HP",
        ru = "{{Battery}} 3 заряда#Призывает до 3 мини-Айзеков; повторное использование лечит выживших стражников на 85% от максимального здоровья",
    },
    tiara4 = {
        en = "{{Battery}} 2 charges#Summons up to 3 Mini Isaacs; use again to heal surviving guardians by 85% of max HP#Geburah's Mini Isaacs gain 10 maximum HP",
        ru = "{{Battery}} 2 заряда#Призывает до 3 мини-Айзеков; повторное использование лечит выживших стражников на 85% от максимального здоровья#Мини-Айзеки Гебуры получают +10 к максимальному здоровью",
    },
    holyChalice = {
          en = "{{Damage}} {{ColorRed}}-1.5 damage{{CR}}#{{Tears}} +0.3 fire rate#{{Shotspeed}} {{ColorRed}}-0.15 shot speed{{CR}}#Holding fire releases a rapid stream of bubbles; its frequency scales with fire rate#Direct hit damage varies from 40% to 140%; bubbles slow down, pause, then burst#Each burst deals 33% of the player's damage to nearby enemies",
          ru = "{{Damage}} {{ColorRed}}-1,5 к урону{{CR}}#{{Tears}} +0,3 к скорострельности#{{Shotspeed}} {{ColorRed}}-0,15 к скорости слёз{{CR}}#При удержании атаки выпускает частый поток пузырей; его частота зависит от скорострельности#Прямой урон варьируется от 40% до 140%; пузыри замедляются, ненадолго замирают и лопаются#Каждый взрыв наносит 33% урона игрока врагам поблизости",
    },
    flamingRose = {
        en = "{{Burn}} Tears set enemies on fire for 3 seconds#Each hit releases a flame in a random dirrection that lasts 7 seconds and deals 2x of isaac's damage",
        ru = "{{Burn}} Слёзы поджигают врагов на 3 секунды#Каждое попадание выпускает огонёк в случайном направлении, который живёт 7 секунд и наносит двойной урон от вызвавшего его попадания",
    },
    eyeOfOldGod = {
        en = "15% chance to fire a golden tear, rising to 50% at 14 Luck#Golden tears mark enemies with the Eye of the Sun for 5 seconds#Only one enemy can be marked at a time: Under Eye of the Sun enemy is slowed by 15% and takes 15% more damage from all sources",
        ru = "15% шанс выстрелить золотой слезой; при 14 удачи шанс достигает 50%#Золотые слёзы накладывают Око Солнца на 5 секунд#Одновременно может быть помечен только один враг: Враг с наличием Ока Солнца замедляется на 15% и получает на 15% больше урона из всех источников",
    },
    heartPendant = {
        en = "{{Damage}} +10% damage for familiars and friendly allies#{{Tears}} +1 firerate to familliars#{{Heart}} +20% maximum health for fammiliars that have health",
        ru = "{{Damage}} +10% к урону фамильяров и дружественных союзников#{{Tears}} +1 к скорострельности фамильяров#{{Heart}} +20% к максимальному здоровью фамильяров, у которых оно есть",
    },
    revelation = {
        en = "{{SoulHeart}} +2 Soul Hearts#{{Tears}} {{ColorRed}}x0.85 fire rate{{CR}}#{{Shotspeed}} {{ColorRed}}-0.15 shot speed{{CR}}#Grants flight#{{Piercing}} Grants piercing tears#{{Spectral}} Grants spectral tears#Tears scatter, curve toward an enemy and leave a holy laser trail dealing 15% of the isaac's damage per hit",
        ru = "{{SoulHeart}} +2 сердца души#{{Tears}} {{ColorRed}}x0,85 к скорострельности{{CR}}#{{Shotspeed}} {{ColorRed}}-0,15 к скорости слёз{{CR}}#Даёт полёт#{{Piercing}} Даёт пронзающие слёзы#{{Spectral}} Даёт спектральные слёзы#Слёзы рассеиваются, разворачиваются к врагу и оставляют след святого лазера с уроном 15% от урона исаака за попадание",
    },
}

local TRINKETS = {
    brokenPendant = {
        en = "Reduces item stat penalties by 20%#Does not affect shot speed or luck",
        ru = "Снижает штрафы характеристик предметов на 20%#Не влияет на скорость слёз и удачу",
    },
}
function Eid.Register(mod, ids)
    mod:AddCallback(ModCallbacks.MC_POST_MODS_LOADED, function()
        local eid = rawget(_G, "EID")
        if not eid or type(eid.addCollectible) ~= "function"
            or type(eid.addTrinket) ~= "function" then return end

        for key, descriptions in pairs(COLLECTIBLES) do
            local id = ids[key]
            if id and id > 0 then
                eid:addCollectible(id, descriptions.en, nil, "en_us")
                eid:addCollectible(id, descriptions.ru, nil, "ru")
            end
        end
        for key, descriptions in pairs(TRINKETS) do
            local id = ids[key]
            if id and id > 0 then
                eid:addTrinket(id, descriptions.en, nil, "en_us")
                eid:addTrinket(id, descriptions.ru, nil, "ru")
            end
        end
    end)
end

return Eid
