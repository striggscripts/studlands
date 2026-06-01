-- Core setup
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local humanoid = char:WaitForChild("Humanoid")
local UIS = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

-- Haal de juiste remotes op die je hebt gevonden
local clientRemotes = RS:WaitForChild("ClientRemotes", 10)
local equipRemote = clientRemotes and clientRemotes:WaitForChild("Inventory"):WaitForChild("EquipItem")
local useRemote = clientRemotes and clientRemotes:WaitForChild("Character"):WaitForChild("UseItem")

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
    LoadingSubtitle = "Geoptimaliseerd met Custom Remotes",
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

-- Verbeterde Auto-Equip via de officiële game remote
local function equipTool(keyword)
    local currentTool = char:FindFirstChildOfClass("Tool")
    if currentTool and currentTool.Name:lower():find(keyword) then
        return currentTool
    end
    
    for _, item in ipairs(player.Backpack:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find(keyword) then
            if equipRemote then
                if equipRemote:IsA("RemoteFunction") then
                    equipRemote:InvokeServer(item.Name)
                elseif equipRemote:IsA("RemoteEvent") then
                    equipRemote:FireServer(item.Name)
                end
            else
                humanoid:EquipTool(item)
            end
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
-- SLIMME MASTER AUTOFARM LOOP
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.1) do
        if autoTeleporting or autoWoodEnabled or autoKilling then
            
            local targetDict = {}
            local toolKeyword = ""
            local offset = CFrame.new(0, 3, 0)
            
            if autoTeleporting then
                targetDict = selectedOres
                toolKeyword = "pickaxe"
            elseif autoWoodEnabled then
                targetDict = selectedWood
                toolKeyword = "axe"
                offset = CFrame.new(0, 4, 0)
            elseif autoKilling then
                targetDict = selectedEnemies
                toolKeyword = "sword" 
                offset = CFrame.new(0, 4, 0)
            end
            
            -- Automatisch tool equippen via Remote
            local myTool = equipTool(toolKeyword)
            if not myTool and toolKeyword == "sword" then
                myTool = equipTool("cleaver")
            end
            if not myTool and toolKeyword == "axe" then
                myTool = equipTool("hatchet") -- Toegevoegd omdat je een Rusty Hatchet hebt
            end
            
            if not myTool then
                showNotification("Geen " .. toolKeyword .. " in inventory gevonden!")
                task.wait(2)
                continue
            end
            
            -- Zoek het DICHTSTBIJZIJNDE doelwit
            local closestTarget = nil
            local shortestDist = math.huge
            
            for _, m in ipairs(workspace:GetDescendants()) do
                if m:IsA("Model") and targetDict[m.Name] and m.PrimaryPart then
                    
                    if autoKilling then
                        local eHum = m:FindFirstChild("Humanoid")
                        if not eHum or eHum.Health <= 0 then continue end
                    end
                    
                    local dist = (hrp.Position - m.PrimaryPart.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        closestTarget = m
                    end
                end
            end
            
            -- Val aan / Hak
            if closestTarget and closestTarget.PrimaryPart then
                local stuckTimer = 0
                
                repeat
                    task.wait(0.15)
                    stuckTimer += 0.15
                    
                    if hrp and closestTarget.PrimaryPart then
                        hrp.CFrame = closestTarget.PrimaryPart.CFrame * offset
                    end
                    
                    if myTool then
                        -- Gebruik de nieuw gevonden UseItem remote
                        if useRemote then
                            if useRemote:IsA("RemoteEvent") then
                                useRemote:FireServer(myTool, false)
                            elseif useRemote:IsA("RemoteFunction") then
                                useRemote:InvokeServer(myTool, false)
                            end
                        else
                            myTool:Activate()
                        end
                    end
                    
                    local isAlive = true
                    if autoKilling then
                        local h = closestTarget:FindFirstChild("Humanoid")
                        if not h or h.Health <= 0 then isAlive = false end
                    else
                        if not closestTarget.Parent or not closestTarget.PrimaryPart then isAlive = false end
                    end
                    
                until not isAlive or stuckTimer > 10 or not (autoTeleporting or autoWoodEnabled or autoKilling)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- LAG VRIJE ESP LOOP
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(1) do
        if mobESPEnabled then
            for _, m in ipairs(workspace:GetDescendants()) do
                if m:IsA("Model") and table.find(mobs, m.Name) then
                    local hum = m:FindFirstChild("Humanoid")
                    if hum and hum.Health > 0 then
                        if not m:FindFirstChild("ESPHighlight") then
                            local hl = Instance.new("Highlight")
                            hl.Name = "ESPHighlight"
                            hl.FillColor = Color3.fromRGB(255, 0, 0)
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.FillTransparency = 0.5
                            hl.Parent = m
                        end
                    elseif hum and hum.Health <= 0 then
                        local hl = m:FindFirstChild("ESPHighlight")
                        if hl then hl:Destroy() end
                    end
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

TabInfo:CreateParagraph({Title = "Status", Content = "Script geoptimaliseerd: Gebruikt nu verborgen ClientRemotes."})

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
