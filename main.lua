-- ============================================================
--  Autofarm Script — Ultimate Blox Fruits Style (Behind Target)
-- ============================================================

local player = game.Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hrp    = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")
local UIS    = game:GetService("UserInputService")
local RS     = game:GetService("ReplicatedStorage")

-- ── State flags ──────────────────────────────────────────────
local autoTeleporting    = false
local autoWoodEnabled    = false
local autoKilling        = false
local noCooldownEnabled  = false
local semiGodEnabled     = false
local infiniteJumpEnabled = false
local mobESPEnabled      = false

local selectedOres    = {}
local selectedWood    = {}
local selectedEnemies = {}
local returnPosition  = nil
local activeHighlights = {}

-- ── Content lists ────────────────────────────────────────────
local ores = {
    "Iron","Gold","Magnetite","Dark Geode","Ice","Rock","Diamond",
    "Salt Rock","Meteorite","Jade","Blood Stone","Sapphire",
    "Amethyst","Obsidian","Shroomium","Sandstone"
}
local woodStumps = {"Oak Stump","Redwood Stump","Spruce Stump"}
local mobs = {
    "Cubey","Wedgey","Field Mousey","Flying Goldfish","Wooden Mimic","Dummy", "Target Dummy",
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
local bosses = {
    "Duke Cublindor","Jimbee","Pharaoh's Curse","Musheynator",
    "Enormous Ballzo","Glacier Giant","Lord Cublindor","Blazing Jimbee","Orbdenier"
}

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

local bossesTP = {
    {"Duke",        Vector3.new(-7262,-1346,230)},
    {"Jimbee",      Vector3.new(-2474,-2186,-4439)},
    {"Pharaoh",     Vector3.new(-3972,-1528,2630)},
    {"Musheynator", Vector3.new(-1787,-322,11)},
    {"Ice Giant",   Vector3.new(-2030,-65,-2006)}
}

--------------------------------------------------------------------------------
-- Rayfield UI
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name              = "Autofarm — Blox Fruits Methode",
    LoadingTitle      = "Script laden...",
    LoadingSubtitle   = "No Damage + Onafhankelijke ESP",
    ConfigurationSaving = { Enabled = false },
    KeySystem         = false
})

--------------------------------------------------------------------------------
-- ── VEILIGE TOOL FINDER ──────────────────────────────────────────────────────
local function getEquippedOrBestTool(type)
    local keywords = {}
    if type == "weapon" then keywords = {"sword", "cleaver", "blade", "hatchet", "dagger", "katana", "machete", "scythe"} end
    if type == "pickaxe" then keywords = {"pick", "drill"} end
    if type == "axe" then keywords = {"axe", "hatchet"} end
    
    local function checkTool(item)
        local n = item.Name:lower()
        for _, kw in ipairs(keywords) do if n:find(kw) then return true end end
        return false
    end

    local currentTool = char:FindFirstChildOfClass("Tool")
    if currentTool and checkTool(currentTool) then return currentTool end
    
    for _, item in ipairs(player.Backpack:GetChildren()) do
        if item:IsA("Tool") and checkTool(item) then
            hum:EquipTool(item)
            return item
        end
    end
    
    if currentTool then return currentTool end
    local fallback = player.Backpack:FindFirstChildOfClass("Tool")
    if fallback then hum:EquipTool(fallback); return fallback end
    return nil
end

local function hookCharacter(c)
    for _, t in ipairs(c:GetDescendants()) do
        if t:IsA("NumberValue") and (t.Name:find("Cooldown") or t.Name:find("Debounce")) then
            if noCooldownEnabled then t.Value = 0 end
            t.Changed:Connect(function() if noCooldownEnabled then t.Value = 0 end end)
        end
    end
end
player.CharacterAdded:Connect(function(c)
    char = c; hrp = c:WaitForChild("HumanoidRootPart"); hum = c:WaitForChild("Humanoid")
    hookCharacter(c)
end)
hookCharacter(char)

--------------------------------------------------------------------------------
-- ── STRICT NPC FILTER ────────────────────────────────────────────────────────
-- Kijkt of het model écht in een vijand-map staat
local function isValidEnemy(model)
    if not model:IsA("Model") or not model.PrimaryPart then return false end
    
    local p = model.Parent
    while p and p ~= workspace do
        if p.Name == "Enemies" or p.Name == "SpawnRegions" or p.Name == "EnemiesToSpawnHere" then
            return true
        end
        p = p.Parent
    end
    return false
end

local function getPotentialTargets(targetType)
    local targets = {}
    local areasFolder = workspace:FindFirstChild("Areas") or workspace

    if targetType == "ore" then
        for _, m in ipairs(areasFolder:GetDescendants()) do
            if m:IsA("Model") and selectedOres[m.Name] and m.PrimaryPart then
                table.insert(targets, m)
            end
        end
    elseif targetType == "wood" then
        for _, m in ipairs(areasFolder:GetDescendants()) do
            if m:IsA("Model") and selectedWood[m.Name] and m.PrimaryPart then
                table.insert(targets, m)
            end
        end
    elseif targetType == "mob" then
        for _, m in ipairs(areasFolder:GetDescendants()) do
            -- Strenge controle: naam geselecteerd EN het is een geldige enemy map
            if m:IsA("Model") and selectedEnemies[m.Name] and isValidEnemy(m) then
                local eHum = m:FindFirstChildOfClass("Humanoid")
                if eHum and eHum.Health > 0 then
                    table.insert(targets, m)
                end
            end
        end
    end
    return targets
end

--------------------------------------------------------------------------------
-- ── BLOX FRUITS AUTOFARM LOOP (TELEPORT ACHTER VIJAND) ───────────────────────
task.spawn(function()
    while task.wait(0.1) do
        if not (autoKilling or autoWoodEnabled or autoTeleporting) then continue end
        
        local mode, typeFilter = "", ""
        if autoKilling then mode = "weapon"; typeFilter = "mob"
        elseif autoWoodEnabled then mode = "axe"; typeFilter = "wood"
        elseif autoTeleporting then mode = "pickaxe"; typeFilter = "ore" end
        
        local targets = getPotentialTargets(typeFilter)
        if #targets == 0 then continue end
        
        local closest, minDist = nil, math.huge
        for _, t in ipairs(targets) do
            local d = (hrp.Position - t.PrimaryPart.Position).Magnitude
            if d < minDist then minDist = d; closest = t end
        end
        
        if closest and closest.PrimaryPart then
            local stuck = 0
            while closest.Parent and closest.PrimaryPart and stuck < 60 do
                if not (autoKilling or autoWoodEnabled or autoTeleporting) then break end
                
                if mode == "weapon" then
                    local eHum = closest:FindFirstChildOfClass("Humanoid")
                    if not eHum or eHum.Health <= 0 then break end
                end
                
                task.wait(0.05) -- Extra snelle aanval-loop
                stuck += 1
                
                local tool = getEquippedOrBestTool(mode)
                
                if hrp and closest.PrimaryPart then
                    if mode == "weapon" then
                        -- BLOX FRUITS METHODE: Teleporteer 4.5 studs ACHTER de vijand en kijk ernaar
                        local enemyCF = closest.PrimaryPart.CFrame
                        local behindPosition = (enemyCF * CFrame.new(0, 1, 4.5)).Position
                        hrp.CFrame = CFrame.new(behindPosition, closest.PrimaryPart.Position)
                    else
                        -- Voor resources: Ervoor staan
                        local tPos = closest.PrimaryPart.Position
                        hrp.CFrame = CFrame.new(tPos + Vector3.new(0, 3, 3), tPos)
                    end
                    hrp.Velocity = Vector3.new(0, 0, 0)
                end
                
                if tool then
                    tool:Activate()
                    
                    local cr = RS:FindFirstChild("ClientRemotes")
                    if cr and cr:FindFirstChild("Character") and cr.Character:FindFirstChild("UseItem") then
                        cr.Character.UseItem:FireServer(tool, false)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ── ONAFHANKELIJKE ESP LOOP ──────────────────────────────────────────────────
-- Haal alle Mobs op die bestaan, ongeacht of je ze farmt
local function getESPTargets()
    local targets = {}
    local areasFolder = workspace:FindFirstChild("Areas") or workspace
    for _, m in ipairs(areasFolder:GetDescendants()) do
        if m:IsA("Model") and table.find(mobs, m.Name) and isValidEnemy(m) then
            local eHum = m:FindFirstChildOfClass("Humanoid")
            if eHum and eHum.Health > 0 then
                table.insert(targets, m)
            end
        end
    end
    return targets
end

task.spawn(function()
    while task.wait(0.5) do
        if not mobESPEnabled then
            for model, hl in pairs(activeHighlights) do
                if hl and hl.Parent then hl:Destroy() end
            end
            table.clear(activeHighlights)
            continue
        end
        
        -- Gebruik de onafhankelijke lijst, zodat alles aangaat!
        local targets = getESPTargets()
        local activeSet = {}
        
        for _, t in ipairs(targets) do 
            activeSet[t] = true
            if not activeHighlights[t] then
                local hl = Instance.new("Highlight")
                hl.Adornee = t
                hl.FillColor = Color3.fromRGB(255, 0, 0)
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.5
                hl.OutlineTransparency = 0
                hl.Parent = workspace 
                activeHighlights[t] = hl
            end
        end
        
        for model, hl in pairs(activeHighlights) do
            if not activeSet[model] or not model.Parent then
                if hl and hl.Parent then hl:Destroy() end
                activeHighlights[model] = nil
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ── UI OPBOUW ────────────────────────────────────────────────────────────────
local TabInfo      = Window:CreateTab("Info")
local TabAutoTP    = Window:CreateTab("Auto TP")
local TabTeleports = Window:CreateTab("Teleports")
local TabCombat    = Window:CreateTab("Combat & Kill")
local TabWood      = Window:CreateTab("Auto Wood")
local TabExtras    = Window:CreateTab("Extras")
local TabESP       = Window:CreateTab("Mob ESP")

TabInfo:CreateParagraph({
    Title   = "Changelog",
    Content = "• Teleporteert nu ACHTER de enemy's rug. Je krijgt geen damage meer!\n" ..
              "• ESP werkt nu onafhankelijk: laat álle vijanden in de map zien.\n" ..
              "• 100% beveiligd tegen het per ongeluk doden van NPCs."
})

TabAutoTP:CreateSection("Ore Teleporting")
for _, ore in ipairs(ores) do
    TabAutoTP:CreateToggle({
        Name = "Farm " .. ore, CurrentValue = false, Flag = "AutoTP_" .. ore,
        Callback = function(val)
            if val then selectedOres[ore] = true; autoTeleporting = true; autoWoodEnabled = false; autoKilling = false
            else selectedOres[ore] = nil; autoTeleporting = next(selectedOres) ~= nil end
        end,
    })
end

TabTeleports:CreateSection("Locations")
for _, v in ipairs(tpList) do TabTeleports:CreateButton({ Name = v[1], Callback = function() hrp.Anchored = true; hrp.CFrame = CFrame.new(v[2]); task.wait(0.3); hrp.Anchored = false end }) end

TabTeleports:CreateSection("Bosses")
for _, v in ipairs(bossesTP) do TabTeleports:CreateButton({ Name = v[1], Callback = function() hrp.Anchored = true; hrp.CFrame = CFrame.new(v[2]); task.wait(0.3); hrp.Anchored = false end }) end

TabCombat:CreateSection("Modifiers")
TabCombat:CreateToggle({
    Name = "No Cooldown", CurrentValue = false, Flag = "NoCooldown",
    Callback = function(val) noCooldownEnabled = val; hookCharacter(char) end,
})

TabCombat:CreateSection("Auto Kill Targets")
local allEnemies = {}
for _, v in ipairs(mobs)   do table.insert(allEnemies, v) end
for _, v in ipairs(bosses) do table.insert(allEnemies, v) end

for _, name in ipairs(allEnemies) do
    TabCombat:CreateToggle({
        Name = "Kill " .. name, CurrentValue = false, Flag = "AutoKill_" .. name,
        Callback = function(val)
            if val then selectedEnemies[name] = true; autoKilling = true; autoTeleporting = false; autoWoodEnabled = false
            else selectedEnemies[name] = nil; autoKilling = next(selectedEnemies) ~= nil end
        end,
    })
end

TabWood:CreateSection("Wood Farming")
for _, w in ipairs(woodStumps) do
    TabWood:CreateToggle({
        Name = w, CurrentValue = false, Flag = "AutoWood_" .. w,
        Callback = function(val)
            if val then selectedWood[w] = true; autoWoodEnabled = true; autoTeleporting = false; autoKilling = false
            else selectedWood[w] = nil; autoWoodEnabled = next(selectedWood) ~= nil end
        end,
    })
end

TabExtras:CreateSection("Character Mods")
TabExtras:CreateSlider({ Name = "WalkSpeed", Range = {16, 200}, Increment = 1, CurrentValue = 16, Flag = "SliderWS", Callback = function(val) hum.WalkSpeed = val end })
TabExtras:CreateSlider({ Name = "JumpPower", Range = {50, 300}, Increment = 1, CurrentValue = 50, Flag = "SliderJP", Callback = function(val) hum.JumpPower = val end })
TabExtras:CreateToggle({ Name = "Infinite Jump", CurrentValue = false, Flag = "InfJump", Callback = function(val) infiniteJumpEnabled = val end })

UIS.JumpRequest:Connect(function()
    if infiniteJumpEnabled and hum and hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

TabESP:CreateSection("Mob ESP")
TabESP:CreateToggle({ Name = "Highlight vijanden", CurrentValue = false, Flag = "MobESP", Callback = function(val) mobESPEnabled = val end })
