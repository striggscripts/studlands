-- ============================================================
--  Autofarm Script — Stutter-Free Platform & Perfect ESP
-- ============================================================

local player = game.Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hrp    = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")
local UIS    = game:GetService("UserInputService")
local RS     = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

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
local activeESP       = {}

-- ── Content lists ────────────────────────────────────────────
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
-- Rayfield UI laden
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name              = "Autofarm — Platform Edit",
    LoadingTitle      = "Script laden...",
    LoadingSubtitle   = "Gefixt en Geoptimaliseerd",
    ConfigurationSaving = { Enabled = false },
    KeySystem         = false
})

local function notify(txt)
    Rayfield:Notify({ Title = "Melding", Content = txt, Duration = 3, Image = 4483362458 })
end

--------------------------------------------------------------------------------
-- ── DE "VIND ALLES" FUNCTIE & MODEL TRACKER ──────────────────────────────────
--------------------------------------------------------------------------------
-- Forceert het vinden van een ankerpunt, zelfs als de makers dit vergeten zijn.
local function getRoot(model)
    if not model then return nil end
    return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChildWhichIsA("BasePart")
end

local allModels = {}
local function addModel(obj)
    if obj:IsA("Model") then allModels[obj] = true end
end
for _, obj in ipairs(workspace:GetDescendants()) do addModel(obj) end
workspace.DescendantAdded:Connect(addModel)
workspace.DescendantRemoving:Connect(function(obj)
    if allModels[obj] then allModels[obj] = nil end
end)

local function getActiveTargets(targetDict, isMob)
    local targets = {}
    for obj, _ in pairs(allModels) do
        if obj.Parent and targetDict[obj.Name] then
            if isMob then
                local eHum = obj:FindFirstChildOfClass("Humanoid")
                if eHum and eHum.Health > 0 then table.insert(targets, obj) end
            else
                table.insert(targets, obj)
            end
        end
    end
    return targets
end

--------------------------------------------------------------------------------
-- ── SLIMME TOOL FINDER ───────────────────────────────────────────────────────
--------------------------------------------------------------------------------
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
-- ── DE ANTI-STUITER PLATFORM AUTOFARM ────────────────────────────────────────
--------------------------------------------------------------------------------
local farmPlatform = Instance.new("Part")
farmPlatform.Name = "AntiJitterPlatform"
farmPlatform.Size = Vector3.new(10, 1, 10)
farmPlatform.Anchored = true
farmPlatform.Transparency = 1 -- Onzichtbaar, maar je kan er wel op staan!
farmPlatform.CanCollide = true
farmPlatform.Parent = workspace

task.spawn(function()
    while task.wait(0.05) do -- Ultrasnelle loop
        if not (autoKilling or autoWoodEnabled or autoTeleporting) then 
            farmPlatform.CFrame = CFrame.new(0, -10000, 0) -- Verstop platform als we niks doen
            continue 
        end
        
        local mode, dict = "", {}
        if autoKilling then mode = "weapon"; dict = selectedEnemies
        elseif autoWoodEnabled then mode = "axe"; dict = selectedWood
        elseif autoTeleporting then mode = "pickaxe"; dict = selectedOres end
        
        local targets = getActiveTargets(dict, autoKilling)
        if #targets == 0 then continue end
        
        local closest, minDist = nil, math.huge
        for _, t in ipairs(targets) do
            local root = getRoot(t)
            if root then
                local d = (hrp.Position - root.Position).Magnitude
                if d < minDist then minDist = d; closest = t end
            end
        end
        
        local targetRoot = getRoot(closest)
        if closest and targetRoot then
            local stuck = 0
            while closest.Parent and targetRoot and stuck < 100 do
                if not (autoKilling or autoWoodEnabled or autoTeleporting) then break end
                
                if mode == "weapon" then
                    local eHum = closest:FindFirstChildOfClass("Humanoid")
                    if not eHum or eHum.Health <= 0 then break end
                end
                
                task.wait(0.05)
                stuck += 1
                
                local tool = getEquippedOrBestTool(mode)
                
                -- HET GEHEIM: We verplaatsen het vloertje onder je, zodat de game denkt dat je stilstaat op de grond
                if hrp and targetRoot then
                    local targetPos = targetRoot.Position
                    if mode == "weapon" then
                        local goalCFrame = CFrame.new(targetPos + Vector3.new(0, 6.5, 0), targetPos)
                        hrp.CFrame = goalCFrame
                        farmPlatform.CFrame = goalCFrame * CFrame.new(0, -3.5, 0)
                    else
                        local goalCFrame = CFrame.new(targetPos + Vector3.new(0, 4, 3), targetPos)
                        hrp.CFrame = goalCFrame
                        farmPlatform.CFrame = goalCFrame * CFrame.new(0, -3.5, 0)
                    end
                    hrp.Velocity = Vector3.new(0, 0, 0) 
                end
                
                if tool then
                    tool:Activate() 
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ── CRASH-FREE ESP LOOP (Werkt met tekst, faalt nooit) ───────────────────────
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.5) do
        if not mobESPEnabled then
            for obj, esp in pairs(activeESP) do
                if esp and esp.Parent then esp:Destroy() end
            end
            table.clear(activeESP)
            continue
        end
        
        local targets = getActiveTargets(selectedEnemies, true)
        local currentTargets = {}
        
        for _, t in ipairs(targets) do
            currentTargets[t] = true
            if not activeESP[t] then
                local root = getRoot(t)
                if root then
                    -- Strakke tekst die dwars door alles heen schijnt
                    local bg = Instance.new("BillboardGui")
                    bg.Name = "MobESP"
                    bg.Adornee = root
                    bg.Size = UDim2.new(0, 200, 0, 50)
                    bg.StudsOffset = Vector3.new(0, 3.5, 0)
                    bg.AlwaysOnTop = true
                    
                    local text = Instance.new("TextLabel")
                    text.Size = UDim2.new(1, 0, 1, 0)
                    text.BackgroundTransparency = 1
                    text.Text = "🎯 " .. t.Name
                    text.TextColor3 = Color3.fromRGB(255, 50, 50)
                    text.TextStrokeTransparency = 0 -- Zorgt voor een leesbare zwarte rand
                    text.TextStrokeColor3 = Color3.fromRGB(0,0,0)
                    text.TextScaled = true
                    text.Font = Enum.Font.GothamBold
                    text.Parent = bg
                    
                    -- Plaatsen in CoreGui (beste manier tegen anti-cheat) of Workspace
                    local targetFolder = CoreGui:FindFirstChild("RobloxGui") or CoreGui
                    bg.Parent = targetFolder
                    activeESP[t] = bg
                end
            end
        end
        
        for obj, esp in pairs(activeESP) do
            if not currentTargets[obj] or not obj.Parent then
                if esp and esp.Parent then esp:Destroy() end
                activeESP[obj] = nil
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ── UI OPBOUW ────────────────────────────────────────────────────────────────
local TabInfo      = Window:CreateTab("Info & Fixes")
local TabAutoTP    = Window:CreateTab("Auto TP")
local TabTeleports = Window:CreateTab("Teleports")
local TabCombat    = Window:CreateTab("Combat & Kill")
local TabWood      = Window:CreateTab("Auto Wood")
local TabExtras    = Window:CreateTab("Extras")
local TabESP       = Window:CreateTab("Mob ESP")

TabInfo:CreateParagraph({
    Title   = "Changelog (Zero-Lag Edit)",
    Content = "• Anti-Jitter Vloertje toegevoegd. Geen vallende/stotterende camera meer!\n" ..
              "• PrimaryPart Bypass toegevoegd. Nu pakt hij ELK model, ook kapotte.\n" ..
              "• ESP geüpdatet naar 'Billboard Text'. Crasht niet meer door Roblox limieten."
})

TabAutoTP:CreateSection("Ore Teleporting")
for _, ore in ipairs(ores) do
    TabAutoTP:CreateToggle({
        Name = "Farm " .. ore, CurrentValue = false, Flag = "AutoTP_" .. ore,
        Callback = function(val)
            if val then
                selectedOres[ore] = true; autoTeleporting = true; autoWoodEnabled = false; autoKilling = false
            else
                selectedOres[ore] = nil; autoTeleporting = next(selectedOres) ~= nil
            end
        end,
    })
end

TabTeleports:CreateSection("Locations")
for _, v in ipairs(tpList) do
    TabTeleports:CreateButton({
        Name = v[1], Callback = function()
            hrp.Anchored = true; hrp.CFrame = CFrame.new(v[2]); task.wait(0.3); hrp.Anchored = false
        end,
    })
end

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
            if val then
                selectedEnemies[name] = true; autoKilling = true; autoTeleporting = false; autoWoodEnabled = false
            else
                selectedEnemies[name] = nil; autoKilling = next(selectedEnemies) ~= nil
            end
        end,
    })
end

TabWood:Create
