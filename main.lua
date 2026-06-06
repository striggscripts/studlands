-- ============================================================
--  Autofarm Script v6 — Stripped Combat Edition
-- ============================================================
-- Combat is now minimal:
--   • Death Recovery (re-equip + TP back to where you died)
--   • No Cooldown (active loop zeroes Cooldown/Debounce values)
--   • Auto Kill target list
-- Removed: smart-avoid, stable mode, anti-aggro, all positioning sliders.
-- Equip is detected by tool type (weapon/pickaxe/axe) and fired through
-- your EquipItem remote with whatever the tool is named — nothing hardcoded.
-- ============================================================

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hrp    = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")

-- ── Remotes ────────────────────────────────────────────────
local ClientRemotes = RS:WaitForChild("ClientRemotes")
local UseItem   = ClientRemotes:WaitForChild("Character"):WaitForChild("UseItem")
local EquipItem = ClientRemotes:WaitForChild("Inventory"):WaitForChild("EquipItem")

-- ── State ──────────────────────────────────────────────────
local autoOre      = false
local autoWood     = false
local autoKill     = false
local noCooldown   = false
local infiniteJump = false
local espEnabled   = false
local deathRecover = true

local SWING_DELAY = 0.03        -- fixed attack rate
local REPOS_THRESH = 4          -- only re-teleport if drifted this far

local lastFarmPos = nil
local needRecover = false

local selOres, selWood, selEnemies = {}, {}, {}
local espCache = {}

-- ── Content lists ──────────────────────────────────────────
local oreNames = {
    "Iron","Gold","Magnetite","Dark Geode","Ice","Rock","Diamond",
    "Salt Rock","Meteorite","Jade","Blood Stone","Sapphire",
    "Amethyst","Obsidian","Shroomium","Sandstone"
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

-- ── Helpers ────────────────────────────────────────────────
local function getRootPart(obj)
    if obj:IsA("Model")    then return obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart")
    elseif obj:IsA("BasePart") then return obj end
    return nil
end

local function isEnemy(model)
    local p = model.Parent
    while p and p ~= workspace do
        if p.Name == "Enemies" or p.Name == "SpawnRegions" or p.Name == "EnemiesToSpawnHere" then
            return true
        end
        p = p.Parent
    end
    return false
end

-- Tool detection by type (NOT by hardcoded name)
local TOOL_KW = {
    weapon  = {"sword","cleaver","blade","dagger","katana","machete","scythe","knife","rapier"},
    pickaxe = {"pick","pickaxe","drill","mattock","mine"},
    axe     = {"axe","hatchet","chop","lumber"},
}
local function toolMatches(name, toolType)
    name = name:lower()
    for _, k in ipairs(TOOL_KW[toolType] or {}) do
        if name:find(k) then return true end
    end
    return false
end

local function findTool(toolType)
    local cur = char:FindFirstChildOfClass("Tool")
    if cur and toolMatches(cur.Name, toolType) then return cur end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and toolMatches(t.Name, toolType) then return t end
    end
    for _, t in ipairs(player.Backpack:GetChildren()) do
        if t:IsA("Tool") and toolMatches(t.Name, toolType) then return t end
    end
    if cur then return cur end
    return player.Backpack:FindFirstChildOfClass("Tool")
end

-- Equip via your EquipItem remote (by detected name) + EquipTool fallback
local function ensureEquipped(toolType)
    local cur = char:FindFirstChildOfClass("Tool")
    local desired = findTool(toolType)
    if not desired then return cur end
    if cur and cur.Name == desired.Name and cur.Parent == char then return cur end

    for _ = 1, 3 do
        pcall(function() EquipItem:InvokeServer(desired.Name) end)
        local inHand = char:FindFirstChild(desired.Name)
        if not (inHand and inHand:IsA("Tool")) then
            local bp = player.Backpack:FindFirstChild(desired.Name)
            if bp then pcall(function() hum:EquipTool(bp) end) end
            inHand = char:FindFirstChild(desired.Name)
        end
        if inHand and inHand:IsA("Tool") then return inHand end
        task.wait(0.1)
    end
    return char:FindFirstChildOfClass("Tool")
end

local function swing(tool)
    if not tool then return end
    pcall(function() UseItem:FireServer(tool, false, nil, nil, 0.6) end)
end

-- ── No Cooldown (active zeroing loop) ──────────────────────
task.spawn(function()
    while task.wait(0.1) do
        if noCooldown and char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("NumberValue") and (d.Name:find("Cooldown") or d.Name:find("Debounce")) then
                    pcall(function() d.Value = 0 end)
                end
            end
        end
    end
end)

-- ── Target scanners ────────────────────────────────────────
local function getMobTargets()
    local list = {}
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
    return list
end

local function getResourceTargets(selTable)
    local list = {}
    local spawns = workspace:FindFirstChild("ResourceSpawns")
    if not spawns then return list end
    for _, region in ipairs(spawns:GetChildren()) do
        for _, node in ipairs(region:GetChildren()) do
            local cr = node:FindFirstChild("CurrentResources")
            if cr then
                for _, res in ipairs(cr:GetChildren()) do
                    if selTable[res.Name] then
                        local part = getRootPart(res)
                        if part then table.insert(list, {obj=res, part=part}) end
                    end
                end
            end
        end
    end
    return list
end

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

-- Simple positioning: next to the target, only re-TP if drifted
local function desiredCFrame(part, isMob)
    if isMob then
        return CFrame.new((part.CFrame * CFrame.new(0, 2, 4)).Position, part.Position)
    else
        return CFrame.new(part.Position + Vector3.new(3, 2.5, 0), part.Position)
    end
end

local function holdPosition(cf)
    if (hrp.Position - cf.Position).Magnitude > REPOS_THRESH then
        hrp.CFrame = cf
        pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
    end
end

-- ── Death recovery ─────────────────────────────────────────
local function farmingActive()
    return autoKill or autoOre or autoWood
end

local function anyTargetLoaded()
    if autoKill then return #getMobTargets() > 0
    elseif autoWood then return #getResourceTargets(selWood) > 0
    elseif autoOre then return #getResourceTargets(selOres) > 0 end
    return false
end

local function setupDeathWatch(humanoid)
    humanoid.Died:Connect(function()
        if deathRecover and farmingActive() and lastFarmPos then
            needRecover = true
        end
    end)
end

player.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    setupDeathWatch(hum)

    if needRecover and lastFarmPos and farmingActive() then
        needRecover = false
        task.spawn(function()
            local toolType = autoKill and "weapon" or (autoWood and "axe" or "pickaxe")

            -- wait for tools to load
            local t0 = os.clock()
            while os.clock() - t0 < 5 do
                if char:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool") then break end
                task.wait(0.2)
            end

            -- re-equip (polls until in hand)
            local te = os.clock()
            repeat
                ensureEquipped(toolType)
                task.wait(0.15)
            until char:FindFirstChildOfClass("Tool") or os.clock() - te > 4

            -- TP back to where we died
            local back = lastFarmPos
            pcall(function()
                hrp.CFrame = CFrame.new(back)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end)

            -- wait for the area to stream in (until a target loads, 12s cap)
            local ts = os.clock()
            while os.clock() - ts < 12 do
                if anyTargetLoaded() then break end
                pcall(function() hrp.CFrame = CFrame.new(back) end)
                task.wait(0.5)
            end
        end)
    end
end)
setupDeathWatch(hum)

-- ── Main farm loop ─────────────────────────────────────────
task.spawn(function()
    while true do
        local ok = pcall(function()
            if not farmingActive() then task.wait(0.2); return end
            if needRecover then task.wait(0.2); return end

            local isMob = autoKill
            local toolType = autoKill and "weapon" or (autoWood and "axe" or "pickaxe")

            local targets
            if autoKill then targets = getMobTargets()
            elseif autoWood then targets = getResourceTargets(selWood)
            else targets = getResourceTargets(selOres) end

            local target = getClosest(targets)
            if not target then task.wait(0.25); return end

            local obj, part = target.obj, target.part
            local tool = ensureEquipped(toolType)

            local guard, maxGuard = 0, (isMob and 220 or 420)
            while obj.Parent and part.Parent and guard < maxGuard do
                if not farmingActive() then break end
                if needRecover then break end

                if isMob then
                    local eHum = target.hum or obj:FindFirstChildOfClass("Humanoid")
                    if not eHum or eHum.Health <= 0 then break end
                end

                holdPosition(desiredCFrame(part, isMob))
                lastFarmPos = hrp.Position

                if not (tool and tool.Parent == char) then
                    tool = ensureEquipped(toolType)
                end
                swing(tool)

                task.wait(SWING_DELAY)
                guard += 1
            end
        end)
        if not ok then task.wait(0.15) end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  ESP
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

    local hl = Instance.new("Highlight")
    hl.Adornee             = model
    hl.FillColor           = isBoss and Color3.fromRGB(255,130,0) or Color3.fromRGB(200,30,30)
    hl.OutlineColor        = isBoss and Color3.fromRGB(255,210,0) or Color3.fromRGB(255,255,255)
    hl.FillTransparency    = 0.45
    hl.OutlineTransparency = 0
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent              = workspace

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0,160,0,72); bb.StudsOffset = Vector3.new(0,4.5,0)
    bb.AlwaysOnTop = true; bb.MaxDistance = 250; bb.Adornee = rootP; bb.Parent = workspace

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1,0,1,0); bg.BackgroundColor3 = Color3.fromRGB(10,10,10)
    bg.BackgroundTransparency = 0.4; bg.BorderSizePixel = 0; bg.Parent = bb
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0,5)

    local stripe = Instance.new("Frame")
    stripe.Size = UDim2.new(1,0,0,3)
    stripe.BackgroundColor3 = isBoss and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,50,50)
    stripe.BorderSizePixel = 0; stripe.Parent = bg

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1,-4,0.38,0); nameL.Position = UDim2.new(0,2,0,5)
    nameL.BackgroundTransparency = 1
    nameL.Text = (isBoss and "[BOSS] " or "") .. model.Name
    nameL.TextColor3 = isBoss and Color3.fromRGB(255,215,0) or Color3.fromRGB(255,120,120)
    nameL.TextStrokeTransparency = 0.3; nameL.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    nameL.TextScaled = true; nameL.Font = Enum.Font.GothamBold; nameL.Parent = bg

    local infoL = Instance.new("TextLabel")
    infoL.Size = UDim2.new(1,-4,0.30,0); infoL.Position = UDim2.new(0,2,0.42,0)
    infoL.BackgroundTransparency = 1; infoL.TextColor3 = Color3.fromRGB(220,220,220)
    infoL.TextStrokeTransparency = 0.35; infoL.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    infoL.TextScaled = true; infoL.Font = Enum.Font.Gotham; infoL.Parent = bg

    local hpBg = Instance.new("Frame")
    hpBg.Size = UDim2.new(1,-6,0,8); hpBg.Position = UDim2.new(0,3,1,-13)
    hpBg.BackgroundColor3 = Color3.fromRGB(30,30,30); hpBg.BorderSizePixel = 0; hpBg.Parent = bg
    Instance.new("UICorner", hpBg).CornerRadius = UDim.new(1,0)

    local hpFill = Instance.new("Frame")
    hpFill.Size = UDim2.new(1,0,1,0); hpFill.BackgroundColor3 = Color3.fromRGB(0,200,80)
    hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
    Instance.new("UICorner", hpFill).CornerRadius = UDim.new(1,0)

    espCache[model] = { hl=hl, bb=bb, infoL=infoL, hpFill=hpFill, eHum=eHum, rootPart=rootP }
end

task.spawn(function()
    while task.wait(0.5) do
        if not espEnabled then
            local toKill = {}
            for m in pairs(espCache) do table.insert(toKill, m) end
            for i, m in ipairs(toKill) do
                destroyESP(m)
                if i % 5 == 0 then task.wait() end
            end
            continue
        end
        local root = workspace:FindFirstChild("Areas") or workspace
        local seen = {}
        for _, m in ipairs(root:GetDescendants()) do
            if m:IsA("Model") and allMobSet[m.Name] and isEnemy(m) then
                local eHum = m:FindFirstChildOfClass("Humanoid")
                if eHum and eHum.Health > 0 then seen[m] = true; buildESP(m) end
            end
        end
        for m in pairs(espCache) do if not seen[m] then destroyESP(m) end end
    end
end)

task.spawn(function()
    while task.wait(0.1) do
        if not espEnabled then continue end
        for model, d in pairs(espCache) do
            if not model.Parent or not d.eHum.Parent then destroyESP(model); continue end
            local hp    = math.floor(d.eHum.Health)
            local maxHp = math.floor(d.eHum.MaxHealth)
            local dist  = math.floor((hrp.Position - d.rootPart.Position).Magnitude)
            local pct   = math.clamp(hp / math.max(maxHp,1), 0, 1)
            d.infoL.Text = string.format("HP: %d / %d  |  %d studs", hp, maxHp, dist)
            d.hpFill.Size = UDim2.new(pct,0,1,0)
            d.hpFill.BackgroundColor3 = (pct>0.6 and Color3.fromRGB(0,200,80))
                or (pct>0.3 and Color3.fromRGB(255,165,0)) or Color3.fromRGB(210,40,40)
        end
    end
end)

-- ══════════════════════════════════════════════════════════
--  UI
-- ══════════════════════════════════════════════════════════
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Autofarm v6",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "Lean combat",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local TabInfo   = Window:CreateTab("Info")
local TabOre    = Window:CreateTab("Auto Ore")
local TabTPs    = Window:CreateTab("Teleports")
local TabCombat = Window:CreateTab("Combat")
local TabWood   = Window:CreateTab("Auto Wood")
local TabExtras = Window:CreateTab("Extras")
local TabESP    = Window:CreateTab("Mob ESP")

TabInfo:CreateParagraph({ Title = "v6 — Lean", Content =
    "Combat trimmed to: Death Recovery, No Cooldown, and Auto Kill targets.\n" ..
    "Equip is auto-detected by tool type and fired through your EquipItem remote.\n" ..
    "No Cooldown now actively zeroes Cooldown/Debounce values while it's on."
})

-- Auto Ore
TabOre:CreateSection("Select Ore")
for _, ore in ipairs(oreNames) do
    TabOre:CreateToggle({ Name = "Mine "..ore, CurrentValue = false, Flag = "Ore_"..ore,
        Callback = function(v)
            selOres[ore] = v or nil
            autoOre = next(selOres) ~= nil
            if v then autoWood=false; autoKill=false end
        end })
end

-- Teleports
TabTPs:CreateSection("Locations")
for _, v in ipairs(tpList) do
    TabTPs:CreateButton({ Name=v[1], Callback=function()
        hrp.Anchored=true; hrp.CFrame=CFrame.new(v[2]); task.wait(0.3); hrp.Anchored=false
    end})
end
TabTPs:CreateSection("Boss Locations")
for _, v in ipairs(bossTPList) do
    TabTPs:CreateButton({ Name=v[1], Callback=function()
        hrp.Anchored=true; hrp.CFrame=CFrame.new(v[2]); task.wait(0.3); hrp.Anchored=false
    end})
end

-- Combat (lean)
TabCombat:CreateSection("Survival")
TabCombat:CreateToggle({ Name="Death Recovery (re-equip + TP back)", CurrentValue=deathRecover, Flag="Recover",
    Callback=function(v) deathRecover=v end })

TabCombat:CreateSection("Modifiers")
TabCombat:CreateToggle({ Name="No Cooldown", CurrentValue=false, Flag="NoCooldown",
    Callback=function(v) noCooldown=v end })

TabCombat:CreateSection("Auto Kill Targets")
local allEnemyList = {}
for _, v in ipairs(mobNames)  do table.insert(allEnemyList, v) end
for _, v in ipairs(bossNames) do table.insert(allEnemyList, v) end
for _, name in ipairs(allEnemyList) do
    TabCombat:CreateToggle({ Name="Kill "..name, CurrentValue=false, Flag="Kill_"..name,
        Callback=function(v)
            selEnemies[name] = v or nil
            autoKill = next(selEnemies) ~= nil
            if v then autoOre=false; autoWood=false end
        end })
end

-- Auto Wood
TabWood:CreateSection("Select Wood")
for _, w in ipairs({"Oak Stump","Redwood Stump","Spruce Stump"}) do
    TabWood:CreateToggle({ Name=w, CurrentValue=false, Flag="Wood_"..w,
        Callback=function(v)
            local base = w:gsub(" Stump","")
            selWood[w]=v or nil; selWood[base]=v or nil; selWood[base.." Tree"]=v or nil
            autoWood = next(selWood) ~= nil
            if v then autoOre=false; autoKill=false end
        end })
end

-- Extras
TabExtras:CreateSection("Character")
TabExtras:CreateSlider({ Name="WalkSpeed", Range={16,250}, Increment=1, CurrentValue=16, Flag="WS",
    Callback=function(v) hum.WalkSpeed=v end })
TabExtras:CreateSlider({ Name="JumpPower", Range={50,350}, Increment=1, CurrentValue=50, Flag="JP",
    Callback=function(v) hum.JumpPower=v end })
TabExtras:CreateToggle({ Name="Infinite Jump", CurrentValue=false, Flag="InfJump",
    Callback=function(v) infiniteJump=v end })
UIS.JumpRequest:Connect(function()
    if infiniteJump and hum and hum.Health>0 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- ESP
TabESP:CreateSection("Mob Highlight ESP")
TabESP:CreateToggle({ Name="Enable ESP", CurrentValue=false, Flag="ESP",
    Callback=function(v) espEnabled=v end })
TabESP:CreateParagraph({ Title="ESP Details", Content=
    "HP bar (green/orange/red), HP/MaxHP, distance.\nBosses = orange + [BOSS] tag. Shows through walls." })
