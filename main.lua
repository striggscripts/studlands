-- Core setup
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local humanoid = char:WaitForChild("Humanoid")
local UIS = game:GetService("UserInputService")
local runService = game:GetService("RunService")

-- State flags
local toolEquipped = false
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

local originalColors = {}

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
    LoadingSubtitle = "by You",
    ConfigurationSaving = {
        Enabled = false
    },
    KeySystem = false
})

--------------------------------------------------------------------------------
-- Utility Functions
local function showNotification(txt)
    Rayfield:Notify({
        Title = "System Notification",
        Content = txt,
        Duration = 3,
        Image = 4483362458
    })
end

local function updateToolStatus()
    toolEquipped = false
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        local nm = tool.Name:lower()
        if autoTeleporting and nm:find("pickaxe") then toolEquipped = true end
        if autoWoodEnabled and nm:find("axe") then toolEquipped = true end
        if autoKilling and (nm:find("sword") or nm:find("cleaver")) then toolEquipped = true end
    end
end

local function teleportAndSwing(model, offset, keyword)
    if not model.PrimaryPart then
        model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
        if not model.PrimaryPart then return end
    end
    local targetPos = (model.PrimaryPart.CFrame * offset).p
    if (hrp.Position - targetPos).Magnitude > 0.5 then
        hrp.CFrame = CFrame.new(targetPos)
    end
    task.wait(0.15)
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name:lower():find(keyword) then
        workspace.Remotes.UseItem:FireServer(tool, false)
    end
end

local function removeCooldown(tool)
    if not noCooldownEnabled then return end
    local deb = tool:FindFirstChild("Cooldown")
             or tool:FindFirstChild("AttackCooldown")
             or tool:FindFirstChild("AttackDebounce")
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
-- UI Tabs Setup
local TabInfo = Window:CreateTab("Info")
local TabAutoTP = Window:CreateTab("Auto TP")
local TabTeleports = Window:CreateTab("Teleports")
local TabCombat = Window:CreateTab("Combat & Kill")
local TabWood = Window:CreateTab("Auto Wood")
local TabExtras = Window:CreateTab("Extras")
local TabESP = Window:CreateTab("Mob ESP")

-- Tab 1: Info
TabInfo:CreateParagraph({Title = "Information", Content = "Script successfully ported to Rayfield UI."})

-- Tab 2: Auto TP
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

spawn(function()
    while true do
        if autoTeleporting and next(selectedOres) then
            updateToolStatus()
            if not toolEquipped then
                showNotification("Equip a pickaxe!")
            else
                for _, m in ipairs(workspace:GetDescendants()) do
                    if m:IsA("Model") and selectedOres[m.Name] and m.PrimaryPart then
                        repeat
                            teleportAndSwing(m, CFrame.new(0,3,0), "pickaxe")
                            task.wait(0.5)
                        until not m.Parent or not autoTeleporting
                    end
                end
            end
        end
        task.wait(5)
    end
end)

-- Tab 3: Teleports
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

-- Tab 4: Combat (No Cooldown & Auto Kill)
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

spawn(function()
    while true do
        if autoKilling and next(selectedEnemies) then
            updateToolStatus()
            if not toolEquipped then
                showNotification("Equip a sword!")
            else
                local found = false
                for _, m in ipairs(workspace:GetDescendants()) do
                    if m:IsA("Model") and selectedEnemies[m.Name] and m.PrimaryPart then
                        found = true
                        teleportAndSwing(m, CFrame.new(0,4,0), "sword")
                        task.wait(0.2)
                    end
                end
                if not found then task.wait(1) end
            end
        end
        task.wait(5)
    end
end)

-- Tab 5: Auto Wood
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

spawn(function()
    while true do
        if autoWoodEnabled and next(selectedWood) then
            updateToolStatus()
            if not toolEquipped then
                showNotification("Equip an axe!")
            else
                for _, m in ipairs(workspace:GetDescendants()) do
                    if m:IsA("Model") and selectedWood[m.Name] and m.PrimaryPart then
                        repeat
                            teleportAndSwing(m, CFrame.new(0,4,0), "axe")
                            task.wait(0.5)
                        until not m.Parent or not autoWoodEnabled
                    end
                end
            end
        end
        task.wait(5)
    end
end)

-- Tab 6: Extras
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
        if Value then
            showNotification("Semi-God enabled")
        else
            showNotification("Semi-God disabled")
        end
    end,
})

humanoid.HealthChanged:Connect(function(hp)
    if semiGodEnabled and autoKilling and hp > 0 and hp < 30 then
        returnPosition = hrp.CFrame
        showNotification("Health low! Retreating home")
        hrp.CFrame = CFrame.new(-564, -315, -1093)

        repeat task.wait(1) until humanoid.Health >= humanoid.MaxHealth

        showNotification("Healed! Returning...")
        if returnPosition then
            hrp.CFrame = returnPosition
        end
        showNotification("Resuming Auto-Kill")
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

-- Tab 7: Mob ESP
TabESP:CreateSection("Visuals")
TabESP:CreateToggle({
    Name = "Highlight Mobs",
    CurrentValue = false,
    Flag = "MobESP",
    Callback = function(Value)
        mobESPEnabled = Value
        if not Value then
            for part, color in pairs(originalColors) do
                if part and part.Parent then part.Color = color end
            end
            originalColors = {}
        end
    end,
})

runService.Heartbeat:Connect(function()
    if mobESPEnabled then
        for _, m in ipairs(workspace:GetDescendants()) do
            if m:IsA("Model") and table.find(mobs, m.Name) then
                for _, part in ipairs(m:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if not originalColors[part] then
                            originalColors[part] = part.Color
                        end
                        part.Color = Color3.fromRGB(0, 255, 0)
                    end
                end
            end
        end
    end
end)
