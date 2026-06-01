-- Core setup
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local humanoid = char:WaitForChild("Humanoid")
local UIS = game:GetService("UserInputService")
local runService = game:GetService("RunService")

-- State flags
local autoTeleporting = false
local autoWoodEnabled = false
local autoKilling = false
local noCooldownEnabled = false
local semiGodEnabled = false
local infiniteJumpEnabled = false
local mobESPEnabled = false

local selectedOres = {}
local selectedWood = {}
local selectedEnemies = {}
local returnPosition = nil

-- Caching variables for objects (Performance Boost)
local oreCache = {}
local woodCache = {}
local mobCache = {}

-- Content lists
local ores = {
    "Iron","Gold","Magnetite","Dark Geode","Ice","Rock","Diamond",
    "Salt Rock","Meteorite","Jade","Blood Stone","Sapphire",
    "Amethyst","Obsidian","Shroomium","Sandstone"
}
local woodStumps = {"Oak Stump","Redwood Stump","Spruce Stump"}
local mobs = {
    "Cubey","Wedgey","Field Mousey","Flying Goldfish","Wooden Mimic","Dummy",
    "Cavey","Spidey","Bonezo","Cave Spidey","Sentient Assault Rifle","Mini Cubey",
    "Mini Bomb","Cubey Mage","Ghostey","Buney","Cublin","Cublin Warrior",
    "Cublin Brute","Angry Wasp","Redwood Mimic","Flowey","Blooming Flowey",
    "Fire Flowey","Darktainium Miner","Parawalker","Watchstalker",
    "Pestililypadey","Scorpion","Tumblezo","Mousey","Vampiric Outlaw",
    "Rustey","Solar Elemental","Frost Buney","Snowdeerey","Ice Lizardey","Icy Snail","Firefly","Living Berry Bush","Cylindery","Ballzo","Ballzo Warrior","Frogey","Mushey","Browncapey","Swamp Hydrey","Lilypadey","Ghostey","Spikezo","Enormous Ballzo","Coconut Crab","Moai","Crab Champion","El Espinoso","Prickley","Pumpkiney","Viney","Pumpkinpadey"
}
local bosses = {
    "Duke Cublindor","Jimbee","Pharaoh's Curse","Musheynator",
    "Enormous Ballzo","Glacier Giant","Lord Cublindor","Blazing Jimbee","Orbdenier"
}

local tpList = {
    {"Home", Vector3.new(-591,-351,-195)},
    {"Forest", Vector3.new(-819,-175,-1623)},
    {"Plains", Vector3.new(-591,-349,-679)},
    {"Flowey", Vector3.new(-30,-350,-1132)},
    {"Redwood", Vector3.new(-1222,-353,-622)},
    {"Ballzone", Vector3.new(188,-361,83)},
    {"Wretched", Vector3.new(-2731,-269,-522)},
    {"Cherry", Vector3.new(727,-166,-2528)},
    {"Mushey", Vector3.new(-1930,-292,-361)},
    {"Tundra", Vector3.new(-1809,15,-2327)},
    {"Desert", Vector3.new(258,-269,1200)},
    {"Grotto", Vector3.new(708,-343,-2687)},
    {"Silly", Vector3.new(2139,-1481,-367)}
}

local bossesTP = {
    {"Duke", Vector3.new(-7262,-1346,230)},
    {"Jimbee", Vector3.new(-2474,-2186,-4439)},
    {"Pharaoh", Vector3.new(-3972,-1528,2630)},
    {"Musheynator", Vector3.new(-1787,-322,11)},
    {"Ice Giant", Vector3.new(-2030,-65,-2006)}
}

--------------------------------------------------------------------------------
-- Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Ore Teleporter & Autofarm",
    LoadingTitle = "Loading Script...",
    LoadingSubtitle = "Geoptimaliseerd: Area Scanning & Reliable Targeting",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

--------------------------------------------------------------------------------
-- Utility Functions
local function showNotification(txt)
    Rayfield:Notify({
        Title = "Systeem Melding",
        Content = txt,
        Duration = 3,
        Image = 4483362458
    })
end

-- Fallback equip-methode die beter is dan de vorige versie
local function equipToolFallback(keyword)
    -- Eerst kijken we in de character
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find(keyword) then
            return item
        end
    end
    
    -- Daarna in de backpack
    for _, item in ipairs(player.Backpack:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find(keyword) then
            -- Forceer een unequip van de huidige tool (indien van toepassing)
            local currentTool = char:FindFirstChildOfClass("Tool")
            if currentTool then
                 humanoid:UnequipTools()
                 task.wait(0.1)
            end
            
            humanoid:EquipTool(item)
            return item
        end
    end
    return nil
end

local function removeCooldown(tool)
    if not noCooldownEnabled then return end
    local deb = tool:FindFirstChild("Cooldown") or tool:FindFirstChild("AttackCooldown") or tool:FindFirstChild("AttackDebounce")
    if deb and deb:IsA("NumberValue") then
        deb.Value = 0
        deb.Changed:Connect(function() if noCooldownEnabled then deb.Value = 0 end end)
    end
end

local function hookCharacter(c)
    c.ChildAdded:Connect(function(ch)
        if ch:IsA("Tool") then removeCooldown(ch) end
    end)
    for _, t in pairs(c:GetChildren()) do
        if t:IsA("Tool") then removeCooldown(t) end
    end
end

player.CharacterAdded:Connect(function(c)
    char = c
    hrp = c:WaitForChild("HumanoidRootPart")
    humanoid = c:WaitForChild("Humanoid")
    hookCharacter(c)
end)
hookCharacter(char)

--------------------------------------------------------------------------------
-- TARGET GATHERING (The "Fix")
--------------------------------------------------------------------------------
-- We scannen specifiek de mappen waar de game objecten spawnt. Dit lost de "nil" fouten op
-- en vermindert lag aanzienlijk.

local function getPotentialTargets(targetType)
    local targets = {}
    local searchArea = workspace
    
    -- Vaak groepeert Roblox games objecten in specifieke folders. We proberen deze te vinden.
    -- Je kunt deze namen aanpassen op basis van wat je in je console/explorer ziet.
    local mapFolder = workspace:FindFirstChild("MAP")
    if mapFolder then
        searchArea = mapFolder
    end

    if targetType == "ore" then
       for _, m in ipairs(searchArea:GetDescendants()) do
            if m:IsA("Model") and selectedOres[m.Name] and m.PrimaryPart then
               table.insert(targets, m)
            end
       end
    elseif targetType == "wood" then
       for _, m in ipairs(searchArea:GetDescendants()) do
            if m:IsA("Model") and selectedWood[m.Name] and m.PrimaryPart then
                table.insert(targets, m)
            end
       end
    elseif targetType == "mob" then
        -- Mobs staan vaak in een 'Entities' of soortgelijke map
        local entityFolder = searchArea:FindFirstChild("Entities") or searchArea:FindFirstChild("Enemies") or searchArea
        
        for _, m in ipairs(entityFolder:GetDescendants()) do
            if m:IsA("Model") and selectedEnemies[m.Name] and m.PrimaryPart then
                local eHum = m:FindFirstChild("Humanoid")
                -- Alleen levende doelen toevoegen!
                if eHum and eHum.Health > 0 then
                   table.insert(targets, m)
                end
            end
        end
    end
    
    return targets
end


--------------------------------------------------------------------------------
-- SLIMME MASTER AUTOFARM LOOP
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.2) do
        if autoTeleporting or autoWoodEnabled or autoKilling then
            
            local toolKeyword = ""
            local offset = CFrame.new(0, 3, 0)
            local targetType = ""
            
            if autoTeleporting then
                toolKeyword = "pickaxe"
                targetType = "ore"
            elseif autoWoodEnabled then
                toolKeyword = "axe"
                offset = CFrame.new(0, 4, 0)
                targetType = "wood"
            elseif autoKilling then
                toolKeyword = "sword" 
                offset = CFrame.new(0, 4, 0)
                targetType = "mob"
            end
            
            -- Automatisch tool equippen met de fallback methode
            local myTool = equipToolFallback(toolKeyword)
            if not myTool and toolKeyword == "sword" then
                myTool = equipToolFallback("cleaver")
            end
            if not myTool and toolKeyword == "axe" then
                myTool = equipToolFallback("hatchet")
            end
            
            if not myTool then
                showNotification("Geen geldig wapen (" .. toolKeyword .. ") gevonden in inventory!")
                task.wait(2)
                continue
            end
            
            -- Haal een lijst op met *geldige* doelen, direct uit de juiste map
            local possibleTargets = getPotentialTargets(targetType)
            
            if #possibleTargets == 0 then
               -- Wacht even voordat we opnieuw scannen als er niets is
               task.wait(1)
               continue
            end
            
            -- Zoek de dichtstbijzijnde
            local closestTarget = nil
            local shortestDist = math.huge
            
            for _, target in ipairs(possibleTargets) do
                -- Extra check of primarypart nog steeds bestaat
                if target and target.PrimaryPart then
                    local dist = (hrp.Position - target.PrimaryPart.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        closestTarget = target
                    end
                end
            end
            
            -- Val aan / Hak
            if closestTarget and closestTarget.PrimaryPart then
                local stuckTimer = 0
                
                repeat
                    task.wait(0.1) -- Snellere loop voor sneller aanvallen
                    stuckTimer += 0.1
                    
                    if hrp and closestTarget.PrimaryPart then
                        hrp.CFrame = closestTarget.PrimaryPart.CFrame * offset
                    end
                    
                    -- Meest betrouwbare manier om te 'klikken' in Roblox
                    if myTool then
                       myTool:Activate()
                    end
                    
                    -- Check of het doel nog leeft/bestaat
                    local isAlive = true
                    if targetType == "mob" then
                        local h = closestTarget:FindFirstChild("Humanoid")
                        if not h or h.Health <= 0 then isAlive = false end
                    else
                        if not closestTarget.Parent or not closestTarget.PrimaryPart then isAlive = false end
                    end
                    
                until not isAlive or stuckTimer > 15 or not (autoTeleporting or autoWoodEnabled or autoKilling)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- LAG VRIJE ESP LOOP (Nu alleen specifieke mappen scannen)
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(1) do
        if mobESPEnabled then
            -- We scannen alleen naar de vijanden die we relevant vinden (levend)
            local possibleTargets = getPotentialTargets("mob")
            
            -- Eerst ruimen we oude highlights op
            for _, m in ipairs(workspace:GetDescendants()) do
                if m:IsA("Model") and m:FindFirstChild("ESPHighlight") then
                   -- Check of dit model nog in onze "levende" lijst staat
                   local isStillRelevant = false
                   for _, activeTarget in ipairs(possibleTargets) do
                       if activeTarget == m then isStillRelevant = true break end
                   end
                   
                   if not isStillRelevant then
                       m.ESPHighlight:Destroy()
                   end
                end
            end
            
            -- Voeg highlights toe aan levende, geselecteerde vijanden
            for _, m in ipairs(possibleTargets) do
                if not m:FindFirstChild("ESPHighlight") then
                    local hl = Instance.new("Highlight")
                    hl.Name = "ESPHighlight"
                    hl.FillColor = Color3.fromRGB(255, 0, 0)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5
                    hl.Parent = m
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- UI Tabs Setup (Ongewijzigd)
local TabInfo = Window:CreateTab("Info")
local TabAutoTP = Window:CreateTab("Auto TP")
local TabTeleports = Window:CreateTab("Teleports")
local TabCombat = Window:CreateTab("Combat & Kill")
local TabWood = Window:CreateTab("Auto Wood")
local TabExtras = Window:CreateTab("Extras")
local TabESP = Window:CreateTab("Mob ESP")

TabInfo:CreateParagraph({Title = "Status", Content = "Script geoptimaliseerd: Map-specifieke ESP en verbeterde targeting."})

TabAutoTP:CreateSection("Ore Teleporting")
for _, ore in ipairs(ores) do
    TabAutoTP:CreateToggle({
        Name = "Farm " .. ore,
        CurrentValue = false,
        Flag = "AutoTP_" .. ore,
        Callback = function(Value)
            if Value then
                selectedOres[ore] = true
                autoTeleporting = true
                autoWoodEnabled = false
                autoKilling = false
            else
                selectedOres[ore] = nil
                autoTeleporting = next(selectedOres) ~= nil
            end
        end,
    })
end

TabTeleports:CreateSection("Locations")
for _, v in ipairs(tpList) do
    TabTeleports:CreateButton({
        Name = v[1],
        Callback = function()
            hrp.Anchored = true
            hrp.CFrame = CFrame.new(v[2])
            task.wait(0.3)
            hrp.Anchored = false
        end,
    })
end

TabTeleports:CreateSection("Bosses")
for _, v in ipairs(bossesTP) do
    TabTeleports:CreateButton({
        Name = v[1],
        Callback = function()
            hrp.Anchored = true
            hrp.CFrame = CFrame.new(v[2])
            task.wait(0.3)
            hrp.Anchored = false
        end,
    })
end

TabCombat:CreateSection("Modifiers")
TabCombat:CreateToggle({
    Name = "No Cooldown",
    CurrentValue = false,
    Flag = "NoCooldown",
    Callback = function(Value)
        noCooldownEnabled = Value
        hookCharacter(char)
    end,
})

TabCombat:CreateSection("Auto Kill Targets")
local allEnemies = {}
for _, v in ipairs(mobs) do table.insert(allEnemies, v) end
for _, v in ipairs(bosses) do table.insert(allEnemies, v) end

for _, name in ipairs(allEnemies) do
    TabCombat:CreateToggle({
        Name = "Kill " .. name,
        CurrentValue = false,
        Flag = "AutoKill_" .. name,
        Callback = function(Value)
            if Value then
                selectedEnemies[name] = true
                autoTeleporting = false
                autoWoodEnabled = false
                autoKilling = true
            else
                selectedEnemies[name] = nil
                autoKilling = next(selectedEnemies) ~= nil
            end
        end,
    })
end

TabWood:CreateSection("Wood Farming")
for _, w in ipairs(woodStumps) do
    TabWood:CreateToggle({
        Name = w,
        CurrentValue = false,
        Flag = "AutoWood_" .. w,
        Callback = function(Value)
            if Value then
                selectedWood[w] = true
                autoWoodEnabled = true
                autoTeleporting = false
                autoKilling = false
            else
                selectedWood[w] = nil
                autoWoodEnabled = next(selectedWood) ~= nil
            end
        end,
    })
end

TabExtras:CreateSection("Character Mods")
TabExtras:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 100},
    Increment = 1,
    CurrentValue = 16,
    Flag = "SliderWS",
    Callback = function(Value)
        humanoid.WalkSpeed = Value
    end,
})

TabExtras:CreateSlider({
    Name = "JumpPower",
    Range = {50, 200},
    Increment = 1,
    CurrentValue = 50,
    Flag = "SliderJP",
    Callback = function(Value)
        humanoid.JumpPower = Value
    end,
})

TabExtras:CreateToggle({
    Name = "Semi-God Mode",
    CurrentValue = false,
    Flag = "SemiGod",
    Callback = function(Value)
        semiGodEnabled = Value
    end,
})

humanoid.HealthChanged:Connect(function(hp)
    if semiGodEnabled and autoKilling and hp > 0 and hp < 30 then
        returnPosition = hrp.CFrame
        showNotification("Health low! Terugtrekken...")
        hrp.CFrame = CFrame.new(-564, -315, -1093)

        repeat task.wait(1) until humanoid.Health >= humanoid.MaxHealth

        showNotification("Genezingsproces voltooid! Terugkeren...")
        if returnPosition then
            hrp.CFrame = returnPosition
        end
    end
end)

TabExtras:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfJump",
    Callback = function(Value)
        infiniteJumpEnabled = Value
    end,
})

UIS.JumpRequest:Connect(function()
    if infiniteJumpEnabled and humanoid and humanoid.Health > 0 then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

TabESP:CreateSection("Visuals")
TabESP:CreateToggle({
    Name = "Highlight Mobs",
    CurrentValue = false,
    Flag = "MobESP",
    Callback = function(Value)
        mobESPEnabled = Value
        if not Value then
            for _, m in ipairs(workspace:GetDescendants()) do
                if m:IsA("Model") then
                    local hl = m:FindFirstChild("ESPHighlight")
                    if hl then hl:Destroy() end
                end
            end
        end
    end,
})
