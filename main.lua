-- ============================================================
--  Autofarm Script — Strict Targeting Fix
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
    "Cubey","Wedgey","Field Mousey","Flying Goldfish","Wooden Mimic","Target Dummy", "Dummy",
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
    Name              = "Autofarm — Strict Target Fix",
    LoadingTitle      = "Script laden...",
    LoadingSubtitle   = "Geoptimaliseerd door AI",
    ConfigurationSaving = { Enabled = false },
    KeySystem         = false
})

local function notify(txt)
    Rayfield:Notify({ Title = "Melding", Content = txt, Duration = 3, Image = 4483362458 })
end

--------------------------------------------------------------------------------
-- ── STRICT TARGET FINDER ─────────────────────────────────────────────────────
--------------------------------------------------------------------------------
local function isValidTarget(obj, isMob)
    if not obj:IsA("Model") or not obj.PrimaryPart then return false end
    
    -- STRENGE CONTROLE: Is dit een vijand of een NPC?
    if isMob then
        -- Controleer of het object zich in een map bevindt die "Enemies" heet.
        -- Dit voorkomt dat we vriendschappelijke NPC's aanvallen.
        local isEnemy = false
        local parent = obj.Parent
        while parent do
            if parent.Name == "Enemies" then
                isEnemy = true
                break
            end
            parent = parent.Parent
        end
        
        if not isEnemy then return false end

        -- Check of de vijand leeft
        local eHum = obj:FindFirstChildOfClass("Humanoid")
        if not eHum or eHum.Health <= 0 then return false end
    end
    
    return true
end

local function getActiveTargets(targetDict, isMob)
    local targets = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if targetDict[obj.Name] and isValidTarget(obj, isMob) then
            table.insert(targets, obj)
        end
    end
    return targets
end

--------------------------------------------------------------------------------
-- ── TOOL FINDER ──────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
local function getEquippedOrBestTool(type)
    local keywords = {}
    if type == "weapon" then keywords = {"sword", "cleaver", "blade", "hatchet", "dagger", "katana", "machete", "scythe"} end
    if type == "pickaxe" then keywords = {"pick", "drill"} end
    if type == "axe" then keywords = {"axe", "hatchet"} end
    
    local function checkTool(item)
        local n = item.Name:lower()
        for _, kw in ipairs(keywords) do
            if n:find(kw) then return true end
        end
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
-- ── AUTOFARM LOOP ────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.1) do
        if not (autoKilling or autoWoodEnabled or autoTeleporting) then continue end
        
        local mode, dict = "", {}
        if autoKilling then mode = "weapon"; dict = selectedEnemies
        elseif autoWoodEnabled then mode = "axe"; dict = selectedWood
        elseif autoTeleporting then mode = "pickaxe"; dict = selectedOres end
        
        local targets = getActiveTargets(dict, autoKilling)
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
                
                task.wait(0.1)
                stuck += 1
                
                local tool = getEquippedOrBestTool(mode)
                
                if hrp and closest.PrimaryPart then
                    local targetPos = closest.PrimaryPart.Position
                    if mode == "weapon" then
                        -- VERLAAGD NAAR 4 STUDS: Zorgt ervoor dat je hitboxes de enemy raken.
                        hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 4, 0), targetPos)
                    else
                        hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 3), targetPos)
                    end
                    hrp.Velocity = Vector3.new(0, 0, 0)
                end
                
                if tool then
                    tool:Activate()
                    
                    -- Gebruik de remotes die je in SimpleSpy zag, als ze bestaan
                    local remoteEvent = RS:FindFirstChild("ClientRemotes") and RS.ClientRemotes:FindFirstChild("Character") and RS.ClientRemotes.Character:FindFirstChild("UseItem")
                    if remoteEvent and remoteEvent:IsA("RemoteEvent") then
                        remoteEvent:FireServer(tool, false)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ── VLOEIENDE ESP LOOP ───────────────────────────────────────────────────────
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.5) do
        if not mobESPEnabled then
            for obj, hl in pairs(activeHighlights) do
                if hl and hl.Parent then hl:Destroy() end
            end
            table.clear(activeHighlights)
            continue
        end
        
        local targets = getActiveTargets(selectedEnemies, true)
        local currentTargets = {}
        
        for _, t in ipairs(targets) do
            currentTargets[t] = true
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
        
        for obj, hl in pairs(activeHighlights) do
            if not currentTargets[obj] or not obj.Parent then
                if hl and hl.Parent then hl:Destroy() end
                activeHighlights[obj] = nil
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
    Title   = "Changelog (Strict Targeting Fix)",
    Content = "• Script valt geen NPCs meer aan! (Controleert nu strict of de vijand in een 'Enemies' folder zit).\n" ..
              "• Aanvalshoogte is verlaagd naar 4 studs zodat je slagen daadwerkelijk raken.\n" ..
              "• Target Dummy is toegevoegd aan de lijst."
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

TabWood:CreateSection("Wood Farming")
for _, w in ipairs(woodStumps) do
    TabWood:CreateToggle({
        Name = w, CurrentValue = false, Flag = "AutoWood_" .. w,
        Callback = function(val)
            if val then
                selectedWood[w] = true; autoWoodEnabled = true; autoTeleporting = false; autoKilling = false
            else
                selectedWood[w] = nil; autoWoodEnabled = next(selectedWood) ~= nil
            end
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
TabESP:CreateToggle({
    Name = "Highlight vijanden", CurrentValue = false, Flag = "MobESP",
    Callback = function(val) mobESPEnabled = val end,
})
