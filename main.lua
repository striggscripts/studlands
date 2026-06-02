-- ============================================================
--  Autofarm Script v3 — Direct Remote Edition
-- ============================================================
-- WHAT CHANGED FROM v2:
--  • Combat now fires ClientRemotes.Enemies.DamageDone directly
--    → no swing delay, no teleport twitch, enemies die instantly
--  • Resources fire ClientRemotes.Resources.ResourceDamageDone directly
--    → instant mining/chopping, no animation wait
--  • Resources are read from workspace.ResourceSpawns (their real home)
--  • Real no-damage: enemies are killed before they can hit you.
--    (The old hum.Health reset was client-only = "just visual".)
--  • "Teleport to target" is now an OPTIONAL toggle (default OFF)
--    so there is no twitching unless the remote needs proximity.
-- ============================================================

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hrp    = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")

-- ── Remotes (from your rSpy capture) ───────────────────────
local CR        = RS:WaitForChild("ClientRemotes")
local rDamage   = CR:WaitForChild("Enemies"):WaitForChild("DamageDone")
local rResDmg   = CR:WaitForChild("Resources"):WaitForChild("ResourceDamageDone")
local rUseItem  = CR:WaitForChild("Character"):WaitForChild("UseItem")
local rEquip    = CR:WaitForChild("Inventory"):WaitForChild("EquipItem")

-- ── State flags ────────────────────────────────────────────
local autoOre      = false
local autoWood     = false
local autoKill     = false
local noCooldown   = false
local healthLoop   = false   -- optional client-side HP reset (may be visual only)
local infiniteJump = false
local espEnabled   = false
local tpToTarget   = false   -- only TP if the game validates proximity
local instantKill  = true    -- send lethal damage (faster, but more detectable)

local selOres    = {}
local selWood    = {}
local selEnemies = {}
local espCache   = {}

-- ── Content lists ──────────────────────────────────────────
local oreNames = {
    "Iron","Gold","Magnetite","Dark Geode","Ice","Rock","Diamond",
    "Salt Rock","Meteorite","Jade","Blood Stone","Sapphire",
    "Amethyst","Obsidian","Shroomium","Sandstone"
}
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

-- ── Character respawn ──────────────────────────────────────
local function hookCooldowns(c)
    c.DescendantAdded:Connect(function(d)
        if d:IsA("NumberValue") and (d.Name:find("Cooldown") or d.Name:find("Debounce")) then
            d.Changed:Connect(function() if noCooldown then d.Value = 0 end end)
        end
    end)
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("NumberValue") and (d.Name:find("Cooldown") or d.Name:find("Debounce")) then
            if noCooldown then d.Value = 0 end
            d.Changed:Connect(function() if noCooldown then d.Value = 0 end end)
        end
    end
end
player.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    hookCooldowns(c)
end)
hookCooldowns(char)

-- ── Optional client HP reset (kept as a minor safety net) ──
task.spawn(function()
    while task.wait(0.1) do
        if healthLoop and hum and hum.Parent and hum.Health > 0 then
            hum.Health = hum.MaxHealth
        end
    end
end)

-- ── Root part helper (handles nil PrimaryPart) ─────────────
local function getRootPart(obj)
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart")
    elseif obj:IsA("BasePart") then
        return obj
    end
    return nil
end

-- ── Tool matcher + equipper ────────────────────────────────
local function toolMatches(item, toolType)
    local n = item.Name:lower()
    local kw
    if toolType == "weapon" then
        kw = {"sword","cleaver","blade","dagger","katana","machete","scythe","knife","rapier"}
    elseif toolType == "pickaxe" then
        kw = {"pick","pickaxe","drill","mattock","mine"}
    elseif toolType == "axe" then
        kw = {"axe","hatchet","chop","lumber"}
    else
        return false
    end
    for _, k in ipairs(kw) do if n:find(k) then return true end end
    return false
end

-- Equips the right tool ONLY when needed (avoids spamming EquipItem)
local function ensureTool(toolType)
    local cur = char:FindFirstChildOfClass("Tool")
    if cur and toolMatches(cur, toolType) then return cur end

    local pick
    for _, t in ipairs(player.Backpack:GetChildren()) do
        if t:IsA("Tool") and toolMatches(t, toolType) then pick = t break end
    end
    pick = pick or cur or player.Backpack:FindFirstChildOfClass("Tool")

    if pick then
        pcall(function() rEquip:InvokeServer(pick.Name) end)  -- tell server
        pcall(function() hum:EquipTool(pick) end)             -- local equip
        return char:FindFirstChildOfClass("Tool") or pick
    end
    return cur
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

-- ── Target scanners ────────────────────────────────────────
local function getEnemyTargets()
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

-- Resources live at workspace.ResourceSpawns[area][node].CurrentResources[...]
local function getResourceTargets(selSet)
    local list = {}
    local spawns = workspace:FindFirstChild("ResourceSpawns")
    if spawns then
        for _, area in ipairs(spawns:GetChildren()) do
            for _, node in ipairs(area:GetChildren()) do
                local cur = node:FindFirstChild("CurrentResources")
                if cur then
                    for _, res in ipairs(cur:GetChildren()) do
                        if selSet[res.Name] then
                            local part = getRootPart(res)
                            if part then table.insert(list, {obj=res, part=part}) end
                        end
                    end
                end
            end
        end
    end
    -- Fallback: full workspace scan if structure differs / empty
    if #list == 0 then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if selSet[obj.Name] then
                local part = getRootPart(obj)
                if part then table.insert(list, {obj=obj, part=part}) end
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

-- ── Positioning (only when tpToTarget is on; ONE jump per target) ──
local function tpBehind(part)
    if not (hrp and part and part.Parent) then return end
    local behind = (part.CFrame * CFrame.new(0, 1, 5)).Position
    hrp.CFrame = CFrame.new(behind, part.Position)
    hrp.Velocity = Vector3.new(0,0,0)
end
local function tpNear(part)
    if not (hrp and part and part.Parent) then return end
    local pos = part.Position
    hrp.CFrame = CFrame.new(pos + Vector3.new(3.5, 2, 0), pos)
    hrp.Velocity = Vector3.new(0,0,0)
end

-- ── Combat: fire DamageDone directly ───────────────────────
local function dealEnemyDamage(enemy, weapon, dmg)
    -- Args mirror your capture: (enemy, weapon, damage, false, 0, 0)
    pcall(function() rDamage:FireServer(enemy, weapon, dmg, false, 0, 0) end)
    -- Backup: legit swing in case the server requires UseItem
    pcall(function() rUseItem:FireServer(weapon, false, nil, nil, 0.6) end)
end

-- ── Resources: fire ResourceDamageDone directly ────────────
local function dealResourceDamage(res, tool, dmg)
    pcall(function() rResDmg:FireServer(res, tool, dmg, false, 0, 0) end)
    pcall(function() rUseItem:FireServer(tool, false, nil, nil, 0.6) end)
end

-- ══════════════════════════════════════════════════════════
-- MAIN FARM LOOP
-- ══════════════════════════════════════════════════════════
task.spawn(function()
    while task.wait(0.03) do
        if not (autoKill or autoOre or autoWood) then continue end

        if autoKill then
            -- COMBAT
            local target = getClosest(getEnemyTargets())
            if not target then continue end

            local obj, part = target.obj, target.part
            local eHum = target.hum
            local weapon = ensureTool("weapon")
            if not weapon then continue end

            if tpToTarget then tpBehind(part) end   -- single jump, only if enabled

            local tries = 0
            while obj.Parent and eHum and eHum.Health > 0 and tries < 60 do
                if not autoKill then break end
                local dmg = instantKill and (eHum.MaxHealth + 100) or math.max(eHum.MaxHealth * 0.25, 25)
                dealEnemyDamage(obj, weapon, dmg)
                tries += 1
                task.wait(0.03)
            end

        else
            -- RESOURCES
            local mode    = autoWood and "wood" or "ore"
            local selSet  = autoWood and selWood or selOres
            local toolType = autoWood and "axe" or "pickaxe"

            local target = getClosest(getResourceTargets(selSet))
            if not target then continue end

            local obj, part = target.obj, target.part
            local tool = ensureTool(toolType)
            if not tool then continue end

            if tpToTarget then tpNear(part) end

            local tries = 0
            while obj.Parent and part.Parent and tries < 100 do
                if not (autoOre or autoWood) then break end
                dealResourceDamage(obj, tool, 9999)
                tries += 1
                task.wait(0.03)
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════
-- ESP (unchanged from v2 — staggered cleanup, HP bar, distance)
-- ══════════════════════════════════════════════════════════
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
    bb.Size        = UDim2.new(0,160,0,72)
    bb.StudsOffset = Vector3.new(0,4.5,0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 250
    bb.Adornee     = rootP
    bb.Parent      = workspace

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1,0,1,0); bg.BackgroundColor3 = Color3.fromRGB(10,10,10)
    bg.BackgroundTransparency = 0.4; bg.BorderSizePixel = 0; bg.Parent = bb
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0,5)

    local stripe = Instance.new("Frame")
    stripe.Size = UDim2.new(1,0,0,3); stripe.BorderSizePixel = 0
    stripe.BackgroundColor3 = isBoss and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,50,50)
    stripe.Parent = bg

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1,-4,0.38,0); nameL.Position = UDim2.new(0,2,0,5)
    nameL.BackgroundTransparency = 1
    nameL.Text = (isBoss and "[BOSS] " or "") .. model.Name
    nameL.TextColor3 = isBoss and Color3.fromRGB(255,215,0) or Color3.fromRGB(255,120,120)
    nameL.TextStrokeTransparency = 0.3; nameL.TextScaled = true
    nameL.Font = Enum.Font.GothamBold; nameL.Parent = bg

    local infoL = Instance.new("TextLabel")
    infoL.Size = UDim2.new(1,-4,0.30,0); infoL.Position = UDim2.new(0,2,0.42,0)
    infoL.BackgroundTransparency = 1; infoL.TextColor3 = Color3.fromRGB(220,220,220)
    infoL.TextStrokeTransparency = 0.35; infoL.TextScaled = true
    infoL.Font = Enum.Font.Gotham; infoL.Parent = bg

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
                if eHum and eHum.Health > 0 then
                    seen[m] = true
                    buildESP(m)
                end
            end
        end
        for m in pairs(espCache) do
            if not seen[m] then destroyESP(m) end
        end
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
    Name              = "Autofarm v3",
    LoadingTitle      = "Loading...",
    LoadingSubtitle   = "Direct Remote — Instant, No Twitch",
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

TabInfo:CreateParagraph({ Title = "v3 — What Changed", Content =
    "Combat fires DamageDone remote directly = instant, no twitch\n" ..
    "Resources fire ResourceDamageDone directly = no delay\n" ..
    "Resources read from workspace.ResourceSpawns (their real path)\n" ..
    "Real no-damage: enemies die before they can hit you\n" ..
    "'Teleport to target' is now OPTIONAL (default OFF = no twitch)\n" ..
    "Turn it ON only if enemies/resources don't take damage from range"
})
TabInfo:CreateParagraph({ Title = "If something doesn't work", Content =
    "Enemies not dying from range → enable 'Teleport to target' in Combat\n" ..
    "Resources not breaking → enable 'Teleport to target'\n" ..
    "Getting kicked/banned → turn OFF 'Instant Kill' (uses lethal damage)\n" ..
    "Still taking damage during a boss → that boss may need its own remote;\n" ..
    "capture it with rSpy and I'll add it"
})

-- Combat
TabCombat:CreateSection("Combat Settings")
TabCombat:CreateToggle({
    Name = "Instant Kill (lethal damage)", CurrentValue = true, Flag = "InstaKill",
    Callback = function(v) instantKill = v end
})
TabCombat:CreateToggle({
    Name = "Teleport to target (only if needed)", CurrentValue = false, Flag = "TPTarget",
    Callback = function(v) tpToTarget = v end
})
TabCombat:CreateToggle({
    Name = "No Cooldown", CurrentValue = false, Flag = "NoCooldown",
    Callback = function(v) noCooldown = v; hookCooldowns(char) end
})
TabCombat:CreateToggle({
    Name = "Client HP Reset (backup, may be visual)", CurrentValue = false, Flag = "HPLoop",
    Callback = function(v) healthLoop = v end
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

-- Auto Ore
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

-- Auto Wood
TabWood:CreateSection("Select Wood to Chop")
local woodDisplay = {"Oak Stump", "Redwood Stump", "Spruce Stump"}
for _, w in ipairs(woodDisplay) do
    TabWood:CreateToggle({
        Name = w, CurrentValue = false, Flag = "Wood_" .. w,
        Callback = function(val)
            local base = w:gsub(" Stump", "")
            selWood[w]               = val or nil
            selWood[base]            = val or nil
            selWood[base .. " Tree"] = val or nil
            autoWood = next(selWood) ~= nil
            if val then autoOre = false; autoKill = false end
        end
    })
end

-- Teleports
TabTPs:CreateSection("Locations")
for _, v in ipairs(tpList) do
    TabTPs:CreateButton({ Name = v[1], Callback = function()
        hrp.Anchored = true; hrp.CFrame = CFrame.new(v[2]); task.wait(0.3); hrp.Anchored = false
    end})
end
TabTPs:CreateSection("Boss Locations")
for _, v in ipairs(bossTPList) do
    TabTPs:CreateButton({ Name = v[1], Callback = function()
        hrp.Anchored = true; hrp.CFrame = CFrame.new(v[2]); task.wait(0.3); hrp.Anchored = false
    end})
end

-- Extras
TabExtras:CreateSection("Character")
TabExtras:CreateSlider({ Name = "WalkSpeed", Range = {16,250}, Increment = 1, CurrentValue = 16, Flag = "WS",
    Callback = function(v) hum.WalkSpeed = v end })
TabExtras:CreateSlider({ Name = "JumpPower", Range = {50,350}, Increment = 1, CurrentValue = 50, Flag = "JP",
    Callback = function(v) hum.JumpPower = v end })
TabExtras:CreateToggle({ Name = "Infinite Jump", CurrentValue = false, Flag = "InfJump",
    Callback = function(v) infiniteJump = v end })
UIS.JumpRequest:Connect(function()
    if infiniteJump and hum and hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- ESP
TabESP:CreateSection("Mob Highlight ESP")
TabESP:CreateToggle({ Name = "Enable ESP", CurrentValue = false, Flag = "ESP",
    Callback = function(v) espEnabled = v end })
TabESP:CreateParagraph({ Title = "ESP Details", Content =
    "HP bar (green/orange/red) + HP numbers + distance\n" ..
    "Bosses: orange highlight + [BOSS] tag\n" ..
    "Shows through walls; toggle cleanup is staggered (no lag)"
})
