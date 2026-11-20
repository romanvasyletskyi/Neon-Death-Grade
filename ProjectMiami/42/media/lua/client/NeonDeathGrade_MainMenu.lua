require "OptionScreens/MainScreen"

local ART = "media/textures/NeonDeathGrade/HotlineMiami2/"
local MENU_SOUND = "NeonDeathGradeHotlineMenu"
local FRAME_WIDTH, FRAME_HEIGHT = 640, 332
local FRAME_COLUMNS, FRAMES_PER_SHEET = 3, 15
local FRAME_COUNT, FRAME_RATE, LOOP_BLEND = 60, 8, 5
local OPTIONS = {
    "latestSaveOption", "loadOption", "tutorialOption", "survivalOption",
    "onlineOption", "onlineCoopOption", "optionsOption", "modsOption",
    "workshopOption", "creditOption", "exitOption",
}

-- Glyph metrics from the installed Hotline Miami 2 bitmap fonts.
local FONT_DATA = {
    fntTitle = {
        [65] = { 242, 126, 66, 57, -10, 13, 33 }, -- A
        [67] = { 240, 295, 48, 51, 1, 13, 45 }, -- C
        [69] = { 446, 289, 50, 47, -5, 16, 34 }, -- E
        [73] = { 478, 121, 22, 52, 0, 11, 13 }, -- I
        [74] = { 166, 0, 51, 66, -14, 3, 30 }, -- J
        [77] = { 391, 63, 63, 58, -6, 4, 51 }, -- M
        [79] = { 165, 354, 36, 41, -1, 18, 37 }, -- O
        [80] = { 297, 66, 46, 59, -10, 9, 35 }, -- P
        [82] = { 110, 131, 45, 58, -3, 14, 37 }, -- R
        [84] = { 183, 67, 56, 59, -8, 4, 37 }, -- T
    },
    fntMenu = {
        [32] = { 250, 29, 3, 1, -1, 25, 7 }, --  
        [33] = { 242, 178, 13, 16, -1, 6, 8 }, -- !
        [39] = { 229, 214, 10, 8, 1, 6, 7 }, -- '
        [40] = { 0, 217, 18, 16, 1, 6, 16 }, -- (
        [41] = { 152, 198, 19, 16, -1, 6, 17 }, -- )
        [45] = { 80, 233, 14, 5, 1, 12, 13 }, -- -
        [46] = { 246, 23, 9, 5, -1, 17, 8 }, -- .
        [47] = { 131, 198, 20, 16, -1, 6, 14 }, -- /
        [48] = { 44, 200, 21, 16, 0, 6, 18 }, -- 0
        [49] = { 241, 127, 14, 16, 2, 6, 13 }, -- 1
        [50] = { 132, 181, 21, 16, 0, 6, 18 }, -- 2
        [51] = { 22, 200, 21, 16, 0, 6, 18 }, -- 3
        [52] = { 184, 163, 22, 16, 1, 6, 20 }, -- 4
        [53] = { 110, 198, 20, 16, 0, 6, 18 }, -- 5
        [54] = { 161, 163, 22, 16, 0, 6, 18 }, -- 6
        [55] = { 172, 197, 19, 16, 3, 6, 18 }, -- 7
        [56] = { 198, 180, 21, 16, 0, 6, 18 }, -- 8
        [57] = { 138, 163, 22, 16, 0, 6, 18 }, -- 9
        [58] = { 171, 215, 11, 12, -1, 10, 8 }, -- :
        [63] = { 110, 181, 21, 16, 0, 6, 18 }, -- ?
        [65] = { 0, 89, 26, 19, -1, 3, 24 }, -- A
        [66] = { 27, 89, 26, 19, -1, 3, 21 }, -- B
        [67] = { 135, 89, 25, 19, 1, 3, 22 }, -- C
        [68] = { 225, 67, 26, 19, -1, 3, 21 }, -- D
        [69] = { 161, 88, 25, 19, 0, 3, 21 }, -- E
        [70] = { 187, 87, 25, 19, 0, 3, 21 }, -- F
        [71] = { 117, 46, 24, 21, 1, 3, 21 }, -- G
        [72] = { 142, 68, 27, 19, 0, 3, 23 }, -- H
        [73] = { 239, 87, 16, 19, 0, 3, 12 }, -- I
        [74] = { 54, 89, 26, 19, 1, 3, 23 }, -- J
        [75] = { 111, 69, 30, 19, 0, 3, 26 }, -- K
        [76] = { 156, 109, 24, 19, 0, 3, 23 }, -- L
        [77] = { 160, 46, 33, 20, -1, 3, 28 }, -- M
        [78] = { 170, 67, 27, 19, -1, 3, 22 }, -- N
        [79] = { 0, 109, 25, 19, 0, 3, 22 }, -- O
        [80] = { 181, 108, 24, 19, 0, 3, 21 }, -- P
        [81] = { 81, 89, 26, 19, 0, 3, 25 }, -- Q
        [82] = { 26, 109, 25, 19, 0, 3, 22 }, -- R
        [83] = { 52, 109, 25, 19, 1, 3, 23 }, -- S
        [84] = { 206, 107, 23, 19, 3, 3, 22 }, -- T
        [85] = { 78, 109, 25, 19, 1, 3, 22 }, -- U
        [86] = { 104, 109, 25, 19, 3, 3, 24 }, -- V
        [87] = { 194, 46, 32, 20, 0, 2, 28 }, -- W
        [88] = { 78, 69, 32, 19, -1, 3, 27 }, -- X
        [89] = { 130, 109, 25, 19, 5, 3, 26 }, -- Y
        [90] = { 108, 89, 26, 19, 0, 3, 23 }, -- Z
    },
}

local originalPrerender = MainScreen.prerender
local originalKeyRelease = MainScreen.onKeyRelease
local menuMusic, musicRetry, leavingMenu = nil, 0, false

local function stopMenuMusic()
    if not menuMusic then return end
    local manager = getSoundManager()
    manager:stopUISound(menuMusic)
    manager:setMusicVolume(getCore():getOptionMusicVolume() / 10)
    menuMusic = nil
end

local function updateMenuMusic(now)
    if leavingMenu then return end
    local manager = getSoundManager()
    local level = getCore():getOptionMusicVolume() / 10
    if level == 0 then
        stopMenuMusic()
        return
    end
    if not menuMusic and now >= musicRetry then
        musicRetry = now + 1000
        local handle = manager:playUISound(MENU_SOUND)
        if handle and handle ~= 0 then menuMusic = handle end
    end
    if menuMusic then
        manager:getUIEmitter():setVolume(menuMusic, level * 0.72)
        if manager:getMusicVolume() ~= 0 then manager:setMusicVolume(0) end
    end
end

local function loadFont(name)
    return { texture = getTexture(ART .. name .. "_0.png"), glyphs = FONT_DATA[name] }
end

local function measure(font, label)
    local width = 0
    for i = 1, #label do
        local glyph = font.glyphs[string.byte(label, i)]
        if not glyph then return nil end
        width = width + glyph[7]
    end
    return width
end

local function drawGlyphs(ui, font, label, x, y, scale, r, g, b)
    for i = 1, #label do
        local glyph = font.glyphs[string.byte(label, i)]
        if glyph[4] > 1 then
            ui:drawSubTexture(font.texture, glyph[1], glyph[2], glyph[3], glyph[4],
                x + glyph[5] * scale, y + glyph[6] * scale, glyph[3] * scale, glyph[4] * scale,
                1, r, g, b)
        end
        x = x + glyph[7] * scale
    end
end

local function drawMenuFrame(ui, theme, frame, x, y, width, height, alpha)
    local sheet = theme.frames[math.floor(frame / FRAMES_PER_SHEET) + 1]
    local cell = frame % FRAMES_PER_SHEET
    local srcX = (cell % FRAME_COLUMNS) * (FRAME_WIDTH + 2) + 1
    local srcY = math.floor(cell / FRAME_COLUMNS) * (FRAME_HEIGHT + 2) + 1
    ui:drawSubTexture(sheet, srcX, srcY, FRAME_WIDTH, FRAME_HEIGHT,
        x, y, width, height, alpha, 1, 1, 1)
end

local function drawMenuBackground(ui, theme, elapsed, x, y, width, height)
    local period = FRAME_COUNT - LOOP_BLEND
    local position = (elapsed * FRAME_RATE / 1000) % period + LOOP_BLEND
    drawMenuFrame(ui, theme, math.floor(position), x, y, width, height, 1)
    local blend = (position - period) / LOOP_BLEND
    if blend > 0 then
        drawMenuFrame(ui, theme, math.floor(position - period), x, y, width, height,
            blend * blend * (3 - 2 * blend))
    end
end

local function drawTitleWord(ui, font, word, x, y, scale, r, g, b)
    drawGlyphs(ui, font, word, x + 4 * scale, y + 4 * scale, scale, 0.10, 0.01, 0.08)
    drawGlyphs(ui, font, word, x + 2 * scale, y + 2 * scale, scale, 0.80, 0.21, 0.47)
    drawGlyphs(ui, font, word, x, y, scale, r, g, b)
end

local function drawProjectMiami(ui, theme, x, y, width, height)
    local font = theme.titleFont
    local scale = math.min(width * 0.85 / theme.titleWidth, height * 0.29 / 66)
    local left = x + (width - theme.titleWidth * scale) / 2
    local top = y + height * 0.14
    drawTitleWord(ui, font, "PROJECT", left, top, scale, 1, 0.90, 0.61)
    drawTitleWord(ui, font, "MIAMI", left + (theme.projectWidth + 25) * scale, top,
        scale, 0.44, 0.96, 0.82)
end

local function drawOption(self)
    local label = self.translation or self.name
    local center = self.width / 2
    local tm = getTextManager()
    local y = math.floor((self.height - tm:MeasureStringY(self.font, label)) / 2)
    local theme = self.hotlineMenuTheme
    local selected = self.joypadFocused or self:isMouseOver()
        or (not theme.screen.joyfocus and not theme.screen.overBottomPanelButton and theme.keyboardOption == self)
    self.fade:update()
    local text = string.upper(label)
    local font = theme.menuFont
    local pixels = measure(font, text)
    if pixels and pixels > 0 then
        local scale = math.min(self.height / 27, (self.width - 16) / pixels)
        local x = center - pixels * scale / 2
        local top = (self.height - 26 * scale) / 2
        drawGlyphs(self, font, text, x + 2, top + 3, scale, 0.05, 0.01, 0.07)
        if selected then
            drawGlyphs(self, font, text, x + 2, top + 1, scale, 0.03, 0.69, 0.66)
            drawGlyphs(self, font, text, x, top, scale, 1, 0.89, 0.60)
        else
            drawGlyphs(self, font, text, x, top, scale, 0.94, 0.69, 0.73)
        end
        self:updateTooltip()
        return
    end

    self:drawTextCentre(label, center + 2, y + 2, 0.13, 0.01, 0.16, 1, self.font)
    self:drawTextCentre(label, center, y, 1, selected and 0.89 or 0.69, selected and 0.60 or 0.73, 1, self.font)
    self:updateTooltip()
end

local function layoutMenu(screen, theme, width, height)
    local panel = screen.bottomPanel
    local visible, count = 0, 0
    for index, name in ipairs(OPTIONS) do
        local option = screen[name]
        if option and option:isVisible() then
            visible = visible + 2 ^ index
            count = count + 1
        end
    end
    if theme.width == width and theme.height == height and theme.visible == visible then return end
    theme.width, theme.height, theme.visible = width, height, visible

    local tm = getTextManager()
    local top = math.floor(height * 0.51)
    local row = math.max(1, math.min(48, math.floor(height * 0.40 / math.max(count, 1))))
    local font = UIFont.Large
    if tm:getFontHeight(font) > row - 5 then font = UIFont.Medium end
    if tm:getFontHeight(font) > row - 3 then font = UIFont.Small end
    local panelWidth = math.min(width - 16, math.max(width * 0.32, screen.maxMenuItemWidth + 64))
    local panelHeight = row * count
    panel:setX(math.floor((width - panelWidth) / 2))
    panel:setY(top)
    panel:setWidth(panelWidth)
    panel:setHeight(panelHeight)

    local y = 0
    theme.visibleOptions = {}
    for _, name in ipairs(OPTIONS) do
        local option = screen[name]
        if option and option:isVisible() then
            option.font = font
            option:setX(0)
            option:setY(y)
            option:setWidth(panelWidth)
            option:setHeight(row)
            option.hotlineMenuTheme = theme
            option.prerender = drawOption
            table.insert(theme.visibleOptions, option)
            y = y + row
        end
    end
    if not theme.keyboardOption or not theme.keyboardOption:isVisible() then
        local latest = screen.latestSaveOption
        theme.keyboardOption = latest and latest:isVisible() and latest or screen.survivalOption
    end
end

function MainScreen:prerender()
    if self.inGame or isDemo() or ISDemoPopup.instance or not self.bottomPanel then
        return originalPrerender(self)
    end

    local theme = self.neonDeathGradeMenu
    if theme == nil then
        theme = {
            screen = self,
            menuFont = loadFont("fntMenu"),
            titleFont = loadFont("fntTitle"),
            frames = {},
        }
        for i = 1, math.ceil(FRAME_COUNT / FRAMES_PER_SHEET) do
            local sheet = getTexture(ART .. string.format("MenuAnimation%02d.png", i))
            if not sheet then
                theme.frames = nil
                break
            end
            theme.frames[i] = sheet
        end
        theme.projectWidth = measure(theme.titleFont, "PROJECT")
        theme.titleWidth = theme.projectWidth + 25 + measure(theme.titleFont, "MIAMI")
        theme.started = getTimestampMs()
        self.neonDeathGradeMenu = theme
    end
    if not theme.frames or not theme.titleFont.texture or not theme.menuFont.texture then
        return originalPrerender(self)
    end

    if self.delay > 0 then
        if self.firstFrame then
            self.delay = self.delay - UIManager.getMillisSinceLastRender()
        else
            self.firstFrame = true
        end
    end

    local width, height = self:getWidth(), self:getHeight()
    local now = getTimestampMs()
    updateMenuMusic(now)
    local scale = math.min(width / 1920, height / 1080)
    local frameWidth, frameHeight = FRAME_WIDTH * 3 * scale, FRAME_HEIGHT * 3 * scale
    local frameX, frameY = (width - frameWidth) / 2, (height - frameHeight) / 2
    self:drawRect(0, 0, width, height, 1, 0, 0, 0)
    drawMenuBackground(self, theme, now - theme.started, frameX, frameY, frameWidth, frameHeight)

    if not self.bottomPanel:getIsVisible() then
        self:drawRect(0, 0, width, height, 0.74, 0.03, 0.01, 0.05)
        return
    end

    drawProjectMiami(self, theme, frameX, frameY, frameWidth, frameHeight)
    layoutMenu(self, theme, width, height)
end

function MainScreen:onKeyRelease(key)
    local theme = self.neonDeathGradeMenu
    if theme and theme.visibleOptions and self:isVisible() and self.bottomPanel:isVisible()
        and not UIManager.isModalVisible()
        and not self.animPopup and not self.termsOfServiceDialog and not self.checkSavefileModal
        and not self.tutorialButton then
        local items = theme.visibleOptions
        if key == Keyboard.KEY_UP or key == Keyboard.KEY_DOWN then
            for i, item in ipairs(items) do
                if item == theme.keyboardOption then
                    local move = key == Keyboard.KEY_UP and -1 or 1
                    theme.keyboardOption = items[(i + move - 1) % #items + 1]
                    getSoundManager():playUISound("UIHighlightMainMenuItem")
                    return
                end
            end
        elseif (key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER) and theme.keyboardOption then
            theme.keyboardOption:onMouseDown(0, 0)
            return
        end
    end
    return originalKeyRelease(self, key)
end

local function leaveMenu()
    leavingMenu = true
    stopMenuMusic()
end

Events.OnPreMapLoad.Add(function()
    leaveMenu()
    NeonDeathGradeSoundtrack.startLoading()
end)
Events.OnGameStart.Add(leaveMenu)
Events.OnMainMenuEnter.Add(function()
    leavingMenu = false
    musicRetry = 0
end)
