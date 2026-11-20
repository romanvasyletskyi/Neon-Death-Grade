require "ISUI/ISUIElement"

local WeaponHUD = ISUIElement:derive("NeonDeathGradeWeaponHUD")
local huds = {}
local RESERVE_REFRESH_MS = 200
local ART = "media/textures/NeonDeathGrade/HotlineMiami2/"

-- The original atlas has handgun, rifle, and shotgun frames.
local PISTOL_ICON = { frame = 0, height = 24, g = 1, b = 1 }
local HEAVY_RIFLE_ICON = { frame = 1, height = 26, g = 0.70, b = 0.43 }
local AMMO_ICONS = {
    ["Base.556Bullets"] = { frame = 1, height = 24, g = 1, b = 1 },
    ["Base.ShotgunShells"] = { frame = 2, height = 24, g = 1, b = 1 },
    ["Base.308Bullets"] = HEAVY_RIFLE_ICON,
    ["Base.3030Bullets"] = HEAVY_RIFLE_ICON,
}

-- Vanilla Build 42 unpacking recipes. Each carton contains 12 boxes.
local BOXED_AMMO = {
    ["Base.Bullets9mm"] = { "Base.Bullets9mm", 50 },
    ["Base.Bullets38"] = { "Base.Bullets38", 50 },
    ["Base.Bullets357"] = { "Base.Bullets357", 50 },
    ["Base.Bullets45"] = { "Base.Bullets45", 50 },
    ["Base.Bullets44"] = { "Base.Bullets44", 20 },
    ["Base.308Bullets"] = { "Base.308", 20 },
    ["Base.556Bullets"] = { "Base.556", 20 },
    ["Base.3030Bullets"] = { "Base.3030", 20 },
    ["Base.ShotgunShells"] = { "Base.ShotgunShells", 25 },
}

-- Rectangles, offsets, and advances from Hotline Miami 2's fntAmmo.fnt.
local GLYPHS = {
    ["0"] = { 477, 47, 16, 12, 0, 6, 14 },
    ["1"] = { 462, 34, 10, 13, 2, 5, 9 },
    ["2"] = { 443, 48, 16, 12, 0, 6, 14 },
    ["3"] = { 0, 64, 16, 12, 0, 6, 14 },
    ["4"] = { 236, 48, 17, 12, 1, 6, 15 },
    ["5"] = { 446, 34, 15, 13, 0, 5, 14 },
    ["6"] = { 275, 34, 17, 13, 0, 5, 14 },
    ["7"] = { 430, 34, 15, 13, 2, 5, 14 },
    ["8"] = { 409, 48, 16, 12, 0, 6, 14 },
    ["9"] = { 218, 48, 17, 12, 0, 6, 14 },
    ["/"] = { 34, 64, 15, 12, -1, 6, 11 },
    ["+"] = { 224, 61, 15, 10, 0, 7, 13 },
}

local function countReserve(inventory, ammoKey, magazineType)
    local rounds = inventory:getItemCountRecurse(ammoKey)
    if magazineType then
        local magazines = inventory:getAllTypeRecurse(magazineType)
        for i = 0, magazines:size() - 1 do
            rounds = rounds + magazines:get(i):getCurrentAmmoCount()
        end
    end
    local package = BOXED_AMMO[ammoKey]
    if package then
        local boxes = inventory:getItemCountRecurse(package[1] .. "Box")
        local cartons = inventory:getItemCountRecurse(package[1] .. "Carton")
        rounds = rounds + (boxes + cartons * 12) * package[2]
    end
    return rounds
end

function WeaponHUD:getWeaponValues(weapon)
    if not weapon:isRanged() then return nil end

    local ammo = weapon:getAmmoType()
    if not ammo then return nil end

    local ammoKey = ammo:getItemKey()
    local magazineType = weapon:getMagazineType()
    local now = getTimestampMs()
    if ammoKey ~= self.ammoKey or magazineType ~= self.magazineType or now >= self.nextReserveUpdate then
        self.reserve = countReserve(self.player:getInventory(), ammoKey, magazineType)
        self.ammoKey, self.magazineType = ammoKey, magazineType
        self.nextReserveUpdate = now + RESERVE_REFRESH_MS
    end

    local loaded = weapon:getCurrentAmmoCount()
    if magazineType and not weapon:isContainsClip() then loaded = 0 end
    local chamber = weapon:haveChamber() and weapon:isRoundChambered()
    return loaded, self.reserve, chamber, AMMO_ICONS[ammoKey] or PISTOL_ICON
end

function WeaponHUD:drawGlyphs(texture, text, x, baseline, scale, r, g, b)
    for i = 1, #text do
        local glyph = GLYPHS[string.sub(text, i, i)]
        self:drawSubTexture(texture, glyph[1], glyph[2], glyph[3], glyph[4],
            x + glyph[5] * scale, baseline + (glyph[6] - 18) * scale, glyph[3] * scale, glyph[4] * scale,
            1, r, g, b)
        x = x + glyph[7] * scale
    end
    return x
end

function WeaponHUD:drawCounter(text, x, baseline, scale)
    if not self.fontMask then
        local font = scale >= 3 and UIFont.Large or UIFont.Medium
        local tm = getTextManager()
        self:drawText(text, x, baseline - tm:getFontHeight(font), 0.42, 0.95, 1, 1, font)
        return x + tm:MeasureStringX(font, text)
    end

    self:drawGlyphs(self.fontMask, text, x + scale * 2, baseline + scale * 2, scale, 0.10, 0.01, 0.08)
    self:drawGlyphs(self.fontMask, text, x + scale, baseline + scale, scale, 1, 0.08, 0.40)
    if self.fontFace then
        return self:drawGlyphs(self.fontFace, text, x, baseline, scale, 1, 1, 1)
    end
    return self:drawGlyphs(self.fontMask, text, x, baseline, scale, 0.40, 0.95, 1)
end

function WeaponHUD:prerender()
    local player = self.player
    if not isIngameState() or player:isDead() then return end
    -- Hide together with the rest of the interface (the vanilla "hide UI" key).
    if ISUIHandler and not ISUIHandler.allUIVisible then return end
    local weapon = player:getPrimaryHandItem()
    if not weapon or not instanceof(weapon, "HandWeapon") then
        self.nextReserveUpdate = 0
        return
    end

    if weapon ~= self.weapon then
        self.weapon = weapon
        self.nextReserveUpdate = 0
    end
    local current, reserve, chamber, icon = self:getWeaponValues(weapon)
    if current == nil then return end

    local index = self.playerIndex
    local width, height = getPlayerScreenWidth(index), getPlayerScreenHeight(index)
    local scale = math.max(1, math.min(6, math.floor(height / 270 + 0.5)))
    local small = math.max(1, math.floor(scale / 2))
    local x = getPlayerScreenLeft(index) + math.max(12, math.floor(width * 0.028))
    local baseline = getPlayerScreenTop(index) + height - math.max(24, math.floor(height * 0.085))
    if self.symbols then
        self:drawSubTexture(self.symbols, icon.frame * 17, 0, 16, 24,
            x, baseline - (icon.height - 2) * scale, 16 * scale, icon.height * scale, 1, 1, icon.g, icon.b)
        x = x + 18 * scale
    end

    local afterMain = self:drawCounter(string.format("%02d", current), x, baseline, scale)
    local afterDivider = self:drawCounter("/", afterMain + 3 * scale, baseline, small)
    self:drawCounter(string.format("%d", reserve), afterDivider + 2 * small, baseline, small)
    if chamber then
        self:drawCounter("+1", afterMain + 3 * scale, baseline - 14 * small - scale, small)
    end
end

local function createHUD(index, player)
    if huds[index] then huds[index]:removeFromUIManager() end
    local hud = ISUIElement.new(WeaponHUD, 0, 0, 1, 1)
    hud.player, hud.playerIndex = player, index
    hud.nextReserveUpdate = 0
    hud.fontMask = getTexture(ART .. "fntAmmo_0.png")
    hud.fontFace = getTexture(ART .. "fntAmmoCyan_0.png")
    hud.symbols = getTexture(ART .. "sprAmmoSymbols.png")
    hud:setWantMouseEvents(false)
    hud:initialise()
    hud:addToUIManager()
    huds[index] = hud
end

Events.OnCreatePlayer.Add(createHUD)
Events.OnMainMenuEnter.Add(function()
    for _, hud in pairs(huds) do hud:removeFromUIManager() end
    huds = {}
end)
