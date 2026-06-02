-- ============================================================
--  Autofarm Script v2 — Full Fix Edition
-- ============================================================
-- FIXES:
--  1. No damage during auto kill → health reset loop tied to autoKill flag
--  2. Auto Ore fixed → searches full workspace + handles nil PrimaryPart
--  3. Auto Wood fixed → same fix + registers alternate stump names
--  4. ESP no longer lags on toggle → staggered cleanup + separate update loop
--  5. ESP now shows: HP bar, HP/MaxHP, distance, boss tag, colored stripe
-- ============================================================

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hrp    = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")

-- ── State flags ────────────────────────────────────────────
local autoOre      = false
local autoWood     = false
local autoKill     = false
local noCooldown   = false
local noDamage     = false
local infiniteJump = false
local espEnabled   = false

local selOres    = {}
local selWood    = {}
local selEnemies = {}
local espCache   = {}   -- [model] = {hl, bb, infoL, hpFill, eHum, rootPart}

-- ── Content lists ──────────────────────────────────────────
local oreNames = {
    "Iron","Gold","Magnetite","Dark Geode","Ice","Rock","Diamond",
    "Salt Rock","Meteorite","Jade","Blood Stone","Sapphire",
    "Amethyst","Obsidian","Shroomium","Sandstone"
}

-- FIX: include alternate names the game might use (no "Stump" suffix)
local woodNames = {
    "Oak Stump","Redwood Stump","Spruce Stump",
    "Oak","Redwood","Spruce"
}

local mobNames = {
    "Cubey","Wedgey","Field Mousey","Flying Goldfish","Wooden Mimic","Dummy","Target Dummy",
    "Cavey","Spidey","Bonezo","Cave Spidey","Sentient Assault Rifle","Mini Cubey",
    "Mini Bomb","Cubey Mage","Ghostey","Buney","Cublin","Cublin Warrior",
    "Cublin Brute","Angry Wasp","Redwood Mimic","Flowey","Blooming Flowey",
    "Fire Flowey","Darktainium Miner","Parawalker","Watchstalker",
    "Pestililypadey","Scorpion","Tumblezo","Mousey","Vampiric Outlaw",
    "Rustey","Solar Elemental","Frost Buney","Snowdeerey","Ice Lizardey",
    "Icy Snail","Firefly","Living Berry Bush","Cylindery","Ballzo","Ballzo Warrior",
    "Frogey","Mushey","Browncapey","Swamp Hydrey","Lilypadey","Spikezo",
    "Enormous Ballzo","Coconut Crab","Moai","Crab Champion","El Espinoso",
    "Prickley","Pumpkiney","Viney","Pumpkinpadey"
}
local bossNames = {
    "Duke Cublindor","Jimbee","Pharaoh's Curse","Musheynator",
    "Enormous Ballzo","Glacier Giant","Lord Cublindor","Blazing Jimbee","Orbdenier"
}

-- Quick lookup sets (O(1) instead of table.find loops)
local bossSet   = {}; for _, b in ipairs(bossNames) do bossSet[b]   = true end
local allMobSet = {}
for _, m in ipairs(mobNames)  do allMobSet[m] = true end
for _, b in ipairs(bossNames) do allMobSet[b] = true end

local tpList = {
    {"Home",     Vector3.new(-591,-351,-195)},
    {"Forest",   Vector3.new(-819,-175,-1623)},
    {"Plains",   Vector3.new(-591,-349,-679)},
    {"Flowey",   Vector3.new(-30,-350,-1132)},
    {"Redwood",  Vector3.new(-1222,-353,-622)},
    {"Ballzone", Vector3.new(188,-361,83)},
    {"Wretched", Vector3.new(-2731,-269,-522)},
    {"Cherry",   Vector3.new(727,-166,-2528)},
    {"Mushey",   Vector3.new(-1930,-292,-361)},
    {"Tundra",   Vector3.new(-1809,15,-2327)},
    {"Desert",   Vector3.new(258,-269,1200)},
    {"Grotto",   Vector3.new(708,-343,-2687)},
    {"Silly",    Vector3.new(2139,-1481,-367)}
}
local bossTPList = {
    {"Duke",        Vector3.new(-7262,-1346,230)},
    {"Jimbee",      Vector3.new(-2474,-2186,-4439)},
    {"Pharaoh",     Vector3.new(-3972,-1528,2630)},
    {"Musheynator", Vector3.new(-1787,-322,11)},
    {"Ice Giant",   Vector3.new(-2030,-65,-2006)}
}

-- ── No-cooldown hook ───────────────────────────────────────
local function hookCooldowns(c)
    -- Hook any future descendants added at runtime
    c.DescendantAdded:Connect(function(d)
        if d:IsA("NumberValue") and (d.Name:find("Cooldown") or d.Name:find("Debounce")) then
            d.Changed:Connect(function() if noCooldown then d.Value = 0 end end)
        end
    end)
    -- Hook existing descendants
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("NumberValue") and (d.Name:find("Cooldown") or d.Name:find("Debounce")) then
            if noCooldown then d.Value = 0 end
            d.Changed:Connect(function() if noCooldown then d.Value = 0 end end)
        end
    end
end

-- Character respawn handler
player.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    hookCooldowns(c)
end)
hookCooldowns(char)

-- ── FIX 1: No Damage ──────────────────────────────────────
-- Runs at ~20 Hz; resets health when auto killing or standalone toggle is on.
-- Works on games that don't fully server-validate health.
task.spawn(function()
    while task.wait(0.05) do
        if (autoKill or noDamage) and hum and hum.Parent then
            if hum.Health > 0 then
                hum.Health = hum.MaxHealth
            end
        end
    end
end)

-- ── Tool finder ────────────────────────────────────────────
local function getTool(toolType)
    local kw = {}
    if toolType == "weapon" then
        kw = {"sword","cleaver","blade","dagger","katana","machete","scythe","knife","rapier"}
    elseif toolType == "pickaxe" then
        kw = {"pick","pickaxe","drill","mattock","mine"}
    elseif toolType == "axe" then
        kw = {"axe","hatchet","chop","lumber"}
    end

    local function matches(item)
        local n = item.Name:lower()
        for _, k in ipairs(kw) do if n:find(k) then return true end end
        return false
    end

    local cur = char:FindFirstChildOfClass("Tool")
    if cur and matches(cur) then return cur end

    for _, t in ipairs(player.Backpack:GetChildren()) do
        if t:IsA("Tool") and matches(t) then
            hum:EquipTool(t)
            return t
        end
    end

    -- Fallback: whatever is equipped or first in backpack
    if cur then return cur end
    local fb = player.Backpack:FindFirstChildOfClass("Tool")
    if fb then hum:EquipTool(fb); return fb end
    return nil
end

-- ── Enemy validator ────────────────────────────────────────
local function isEnemy(model)
    if not model:IsA("Model") then return false end
    local p = model.Parent
    while p and p ~= workspace do
        if p.Name == "Enemies" or p.Name == "SpawnRegions" or p.Name == "EnemiesToSpawnHere" then
            return true
        end
        p = p.Parent
    end
    return false
end

-- ── FIX 2: Safe root part (handles nil PrimaryPart) ───────
-- This was the core bug: m.PrimaryPart returned nil → whole model skipped silently
local function getRootPart(obj)
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart")
    elseif obj:IsA("BasePart") then
        return obj
    end
    return nil
end

-- ── FIX 2: Target scanner ─────────────────────────────────
-- Ore/Wood now search ENTIRE workspace, not just Areas.
-- Also supports bare BaseParts (some ores are just parts, not full Models).
local function getTargets(mode)
    local list = {}

    if mode == "mob" then
        local root = workspace:FindFirstChild("Areas") or workspace
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("Model") and selEnemies[obj.Name] and isEnemy(obj) then
                local eHum = obj:FindFirstChildOfClass("Humanoid")
                local part = getRootPart(obj)
                if eHum and eHum.Health > 0 and part then
                    table.insert(list, {obj=obj, part=part, hum=eHum})
                end
            end
        end

    elseif mode == "ore" then
        -- Search ALL of workspace — ores may not live inside Areas
        for _, obj in ipairs(workspace:GetDescendants()) do
            if selOres[obj.Name] then
                local part = getRootPart(obj)
                if part then
                    table.insert(list, {obj=obj, part=part})
                end
            end
        end

    elseif mode == "wood" then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if selWood[obj.Name] then
                local part = getRootPart(obj)
                if part then
                    table.insert(list, {obj=obj, part=part})
                end
            end
        end
    end

    return list
end

-- Find closest target in list
local function getClosest(list)
    local best, bestD = nil, math.huge
    for _, t in ipairs(list) do
        if t.part and t.part.Parent then
            local d = (hrp.Position - t.part.Position).Magnitude
            if d < bestD then bestD = d; best = t end
        end
    end
    return best
end

-- ── Main farm loop ─────────────────────────────────────────
task.spawn(function()
    while task.wait(0.1) do
        if not (autoKill or autoWood or autoOre) then continue end

        local mode     = autoKill and "mob"  or (autoWood and "wood"    or "ore")
        local toolType = autoKill and "weapon" or (autoWood and "axe" or "pickaxe")

        local targets = getTargets(mode)
        local target  = getClosest(targets)
        if not target then continue end

        local obj  = target.obj
        local part = target.part
        -- Resources need more attempts (120 × 0.05s = 6s); mobs less
        local maxTries = (mode == "mob") and 80 or 150
        local stuck = 0

        while obj.Parent and part.Parent and stuck < maxTries do
            if not (autoKill or autoWood or autoOre) then break end

            -- Kill dead mob early
            if mode == "mob" then
                local eHum = target.hum or obj:FindFirstChildOfClass("Humanoid")
                if not eHum or eHum.Health <= 0 then break end
            end

            -- Teleport to target
            if hrp and part.Parent then
                if mode == "mob" then
                    -- In Roblox CFrame local space +Z is backward (behind the model).
                    -- We stand 5 studs behind the enemy looking toward it.
                    local behind = (part.CFrame * CFrame.new(0, 1, 5)).Position
                    hrp.CFrame = CFrame.new(behind, part.Position)
                else
                    -- Stand beside the resource at swing range
                    local pos = part.Position
                    hrp.CFrame = CFrame.new(pos + Vector3.new(3.5, 2, 0), pos)
                end
                hrp.Velocity = Vector3.new(0, 0, 0)
            end

            -- Equip and activate tool
            local tool = getTool(toolType)
            if tool then
                pcall(function() tool:Activate() end)

                -- Fire game-specific UseItem remote if it exists
                local cr = RS:FindFirstChild("ClientRemotes")
                if cr then
                    local charR = cr:FindFirstChild("Character")
                    if charR then
                        local useItem = charR:FindFirstChild("UseItem")
                        if useItem then
                            pcall(function() useItem:FireServer(tool, false) end)
                        end
                    end
                end

                -- Try ProximityPrompt interaction (used by many resource games)
                if mode ~= "mob" then
                    local pp = obj:FindFirstChild("ProximityPrompt", true)
                           or part:FindFirstChildOfClass("ProximityPrompt")
                    if pp then
                        pcall(function()
                            pp:InputHoldBegin()
                            task.wait(0.1)
                            pp:InputHoldEnd()
                        end)
                    end
                    -- Try ClickDetector (older resource style)
                    local cd = obj:FindFirstChild("ClickDetector", true)
                           or part:FindFirstChildOfClass("ClickDetector")
                    if cd then
                        pcall(function() fireClickDetector(cd) end)
                    end
                end
            end

            task.wait(0.05)
            stuck += 1
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- FIX 3 + 4: IMPROVED ESP
-- - Scan loop  (0.5s): finds new targets, removes dead ones
-- - Update loop (0.1s): refreshes labels (HP, distance)
-- - Toggle OFF: staggered destruction → no frame spike
-- ═══════════════════════════════════════════════════════════

local function destroyESP(model)
    local d = espCache[model]
    if not d then return end
    if d.hl and d.hl.Parent then d.hl:Destroy() end
    if d.bb and d.bb.Parent then d.bb:Destroy() end
    espCache[model] = nil
end

local function buildESP(model)
    if espCache[model] then return end

    local eHum  = model:FindFirstChildOfClass("Humanoid")
    local rootP = getRootPart(model)
    if not eHum or not rootP then return end

    local isBoss = bossSet[model.Name] ~= nil

    -- ── Highlight ──────────────────────────────────────────
    local hl = Instance.new("Highlight")
    hl.Adornee             = model
    hl.FillColor           = isBoss and Color3.fromRGB(255, 130,  0) or Color3.fromRGB(200, 30, 30)
    hl.OutlineColor        = isBoss and Color3.fromRGB(255, 210,  0) or Color3.fromRGB(255,255,255)
    hl.FillTransparency    = 0.45
    hl.OutlineTransparency = 0
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop   -- shows through walls
    hl.Parent              = workspace

    -- ── BillboardGui ───────────────────────────────────────
    local bb = Instance.new("BillboardGui")
    bb.Size        = UDim2.new(0, 160, 0, 72)
    bb.StudsOffset = Vector3.new(0, 4.5, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 250
    bb.Adornee     = rootP
    bb.Parent      = workspace

    -- Background
    local bg = Instance.new("Frame")
    bg.Size                  = UDim2.new(1,0,1,0)
    bg.BackgroundColor3      = Color3.fromRGB(10,10,10)
    bg.BackgroundTransparency = 0.4
    bg.BorderSizePixel       = 0
    bg.Parent                = bb
    local bgC = Instance.new("UICorner"); bgC.CornerRadius = UDim.new(0,5); bgC.Parent = bg

    -- Colored top stripe (red for mob, orange for boss)
    local stripe = Instance.new("Frame")
    stripe.Size             = UDim2.new(1,0,0,3)
    stripe.BackgroundColor3 = isBoss and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,50,50)
    stripe.BorderSizePixel  = 0
    stripe.Parent           = bg

    -- Name label
    local nameL = Instance.new("TextLabel")
    nameL.Size                   = UDim2.new(1,-4,0.38,0)
    nameL.Position               = UDim2.new(0,2,0,5)
    nameL.BackgroundTransparency = 1
    nameL.Text                   = (isBoss and "[BOSS] " or "") .. model.Name
    nameL.TextColor3             = isBoss and Color3.fromRGB(255,215,0) or Color3.fromRGB(255,120,120)
    nameL.TextStrokeTransparency = 0.3
    nameL.TextStrokeColor3       = Color3.fromRGB(0,0,0)
    nameL.TextScaled             = true
    nameL.Font                   = Enum.Font.GothamBold
    nameL.Parent                 = bg

    -- Info label: HP numbers + distance (updated by the update loop below)
    local infoL = Instance.new("TextLabel")
    infoL.Size                   = UDim2.new(1,-4,0.30,0)
    infoL.Position               = UDim2.new(0,2,0.42,0)
    infoL.BackgroundTransparency = 1
    infoL.TextColor3             = Color3.fromRGB(220,220,220)
    infoL.TextStrokeTransparency = 0.35
    infoL.TextStrokeColor3       = Color3.fromRGB(0,0,0)
    infoL.TextScaled             = true
    infoL.Font                   = Enum.Font.Gotham
    infoL.Parent                 = bg

    -- HP bar background
    local hpBg = Instance.new("Frame")
    hpBg.Size             = UDim2.new(1,-6,0,8)
    hpBg.Position         = UDim2.new(0,3,1,-13)
    hpBg.BackgroundColor3 = Color3.fromRGB(30,30,30)
    hpBg.BorderSizePixel  = 0
    hpBg.Parent           = bg
    local hpBgC = Instance.new("UICorner"); hpBgC.CornerRadius = UDim.new(1,0); hpBgC.Parent = hpBg

    -- HP bar fill (width updated by loop)
    local hpFill = Instance.new("Frame")
    hpFill.Size             = UDim2.new(1,0,1,0)
    hpFill.BackgroundColor3 = Color3.fromRGB(0,200,80)
    hpFill.BorderSizePixel  = 0
    hpFill.Parent           = hpBg
    local hpFillC = Instance.new("UICorner"); hpFillC.CornerRadius = UDim.new(1,0); hpFillC.Parent = hpFill

    espCache[model] = {
        hl       = hl,
        bb       = bb,
        infoL    = infoL,
        hpFill   = hpFill,
        eHum     = eHum,
        rootPart = rootP,
    }
end

-- ESP scan: discovers new mobs, culls dead ones (every 0.5s is fine for this)
task.spawn(function()
    while task.wait(0.5) do
        if not espEnabled then
            -- STAGGERED cleanup → no single-frame lag spike on toggle off
            local toKill = {}
            for m in pairs(espCache) do table.insert(toKill, m) end
            for i, m in ipairs(toKill) do
                destroyESP(m)
                if i % 5 == 0 then task.wait() end  -- yield every 5 deletions
            end
            continue
        end

        local root = workspace:FindFirstChild("Areas") or workspace
        local seen = {}

        for _, m in ipairs(root:GetDescendants()) do
            if m:IsA("Model") and allMobSet[m.Name] and isEnemy(m) then
                local eHum = m:FindFirstChildOfClass("Humanoid")
                if eHum and eHum.Health > 0 then
                    seen[m] = true
                    buildESP(m)
                end
            end
        end

        -- Cull models that died or left
        for m in pairs(espCache) do
            if not seen[m] then destroyESP(m) end
        end
    end
end)

-- ESP label update: refreshes HP bar + text every 0.1s
-- Separated from scan so toggling off the scan doesn't stutter the updates
task.spawn(function()
    while task.wait(0.1) do
        if not espEnabled then continue end
        for model, d in pairs(espCache) do
            if not model.Parent or not d.eHum.Parent then
                destroyESP(model)
                continue
            end

            local hp    = math.floor(d.eHum.Health)
            local maxHp = math.floor(d.eHum.MaxHealth)
            local dist  = math.floor((hrp.Position - d.rootPart.Position).Magnitude)
            local pct   = math.clamp(hp / math.max(maxHp, 1), 0, 1)

            -- Update text: HP numbers + distance
            d.infoL.Text = string.format("HP: %d / %d  |  %d studs", hp, maxHp, dist)

            -- Update HP bar width + colour (green → orange → red)
            d.hpFill.Size = UDim2.new(pct, 0, 1, 0)
            if pct > 0.6 then
                d.hpFill.BackgroundColor3 = Color3.fromRGB(0,200,80)
            elseif pct > 0.3 then
                d.hpFill.BackgroundColor3 = Color3.fromRGB(255,165,0)
            else
                d.hpFill.BackgroundColor3 = Color3.fromRGB(210,40,40)
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════
-- UI
-- ══════════════════════════════════════════════════════════
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name              = "Autofarm v2",
    LoadingTitle      = "Loading...",
    LoadingSubtitle   = "No Damage | Fixed Ore/Wood | Better ESP",
    ConfigurationSaving = { Enabled = false },
    KeySystem         = false
})

local TabInfo   = Window:CreateTab("Info")
local TabOre    = Window:CreateTab("Auto Ore")
local TabTPs    = Window:CreateTab("Teleports")
local TabCombat = Window:CreateTab("Combat")
local TabWood   = Window:CreateTab("Auto Wood")
local TabExtras = Window:CreateTab("Extras")
local TabESP    = Window:CreateTab("Mob ESP")

-- ── Info Tab ───────────────────────────────────────────────
TabInfo:CreateParagraph({ Title = "v2 — What Changed", Content =
    "FIX: No Damage — HP reset loop active during auto kill\n" ..
    "FIX: Auto Ore — nil PrimaryPart no longer skips the target\n" ..
    "FIX: Auto Ore — now searches full workspace, not just Areas\n" ..
    "FIX: Auto Wood — same fixes + Oak/Redwood/Spruce alt names added\n" ..
    "FIX: ESP toggle lag — staggered cleanup, no frame spike\n" ..
    "NEW: ESP shows HP bar (color coded), HP/MaxHP, distance\n" ..
    "NEW: ESP boss indicator — orange highlight + [BOSS] tag\n" ..
    "NEW: No Damage standalone toggle in Combat tab"
})

-- ── Auto Ore Tab ───────────────────────────────────────────
TabOre:CreateSection("Select Ore to Mine")
for _, ore in ipairs(oreNames) do
    TabOre:CreateToggle({
        Name = "Mine " .. ore, CurrentValue = false, Flag = "Ore_" .. ore,
        Callback = function(val)
            selOres[ore] = val or nil
            autoOre = next(selOres) ~= nil
            if val then autoWood = false; autoKill = false end
        end
    })
end

-- ── Teleports Tab ──────────────────────────────────────────
TabTPs:CreateSection("Locations")
for _, v in ipairs(tpList) do
    TabTPs:CreateButton({ Name = v[1], Callback = function()
        hrp.Anchored = true
        hrp.CFrame   = CFrame.new(v[2])
        task.wait(0.3)
        hrp.Anchored = false
    end})
end
TabTPs:CreateSection("Boss Locations")
for _, v in ipairs(bossTPList) do
    TabTPs:CreateButton({ Name = v[1], Callback = function()
        hrp.Anchored = true
        hrp.CFrame   = CFrame.new(v[2])
        task.wait(0.3)
        hrp.Anchored = false
    end})
end

-- ── Combat Tab ─────────────────────────────────────────────
TabCombat:CreateSection("Modifiers")
TabCombat:CreateToggle({
    Name = "No Cooldown", CurrentValue = false, Flag = "NoCooldown",
    Callback = function(val)
        noCooldown = val
        hookCooldowns(char)
    end
})
TabCombat:CreateToggle({
    -- Standalone toggle: no-damage outside of auto kill (e.g. boss fights)
    Name = "No Damage (standalone)", CurrentValue = false, Flag = "NoDamage",
    Callback = function(val) noDamage = val end
})

TabCombat:CreateSection("Auto Kill Targets")
local allEnemyList = {}
for _, v in ipairs(mobNames)  do table.insert(allEnemyList, v) end
for _, v in ipairs(bossNames) do table.insert(allEnemyList, v) end

for _, name in ipairs(allEnemyList) do
    TabCombat:CreateToggle({
        Name = "Kill " .. name, CurrentValue = false, Flag = "Kill_" .. name,
        Callback = function(val)
            selEnemies[name] = val or nil
            autoKill = next(selEnemies) ~= nil
            if val then autoOre = false; autoWood = false end
        end
    })
end

-- ── Auto Wood Tab ──────────────────────────────────────────
TabWood:CreateSection("Select Wood to Chop")
local woodDisplay = {"Oak Stump", "Redwood Stump", "Spruce Stump"}
for _, w in ipairs(woodDisplay) do
    TabWood:CreateToggle({
        Name = w, CurrentValue = false, Flag = "Wood_" .. w,
        Callback = function(val)
            -- Register canonical stump name + bare name + tree name variant
            local base = w:gsub(" Stump", "")
            selWood[w]                 = val or nil
            selWood[base]              = val or nil
            selWood[base .. " Tree"]   = val or nil
            autoWood = next(selWood) ~= nil
            if val then autoOre = false; autoKill = false end
        end
    })
end

-- ── Extras Tab ─────────────────────────────────────────────
TabExtras:CreateSection("Character")
TabExtras:CreateSlider({
    Name = "WalkSpeed", Range = {16, 250}, Increment = 1,
    CurrentValue = 16, Flag = "WS",
    Callback = function(v) hum.WalkSpeed = v end
})
TabExtras:CreateSlider({
    Name = "JumpPower", Range = {50, 350}, Increment = 1,
    CurrentValue = 50, Flag = "JP",
    Callback = function(v) hum.JumpPower = v end
})
TabExtras:CreateToggle({
    Name = "Infinite Jump", CurrentValue = false, Flag = "InfJump",
    Callback = function(v) infiniteJump = v end
})

UIS.JumpRequest:Connect(function()
    if infiniteJump and hum and hum.Health > 0 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- ── ESP Tab ────────────────────────────────────────────────
TabESP:CreateSection("Mob Highlight ESP")
TabESP:CreateToggle({
    Name = "Enable ESP", CurrentValue = false, Flag = "ESP",
    Callback = function(v) espEnabled = v end
})
TabESP:CreateParagraph({ Title = "ESP Details", Content =
    "Shows all live enemies inside the Areas folder\n" ..
    "• HP bar: green (>60%) / orange (30-60%) / red (<30%)\n" ..
    "• HP/MaxHP numbers + distance in studs\n" ..
    "• Bosses: orange highlight + [BOSS] label\n" ..
    "• Highlight shows through walls (AlwaysOnTop)\n" ..
    "• Toggle lag fixed: cleanup staggered over multiple frames"
})
