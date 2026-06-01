-- ============================================================
--  Autofarm Script — Gefixte versie
--  Structuur: workspace.Areas.<AreaName>.Enemies.<MobModel>
--  Methode: Blox Fruits-stijl orbit teleport + snelle aanval
-- ============================================================

local player = game.Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hrp    = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")
local UIS    = game:GetService("UserInputService")

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

-- ── ESP tabel (model → Highlight instantie) ─────────────────
local activeHighlights = {}

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
    Name              = "Autofarm — Gefixte versie",
    LoadingTitle      = "Script laden...",
    LoadingSubtitle   = "Areas-structuur targeting + Blox Fruits aanval",
    ConfigurationSaving = { Enabled = false },
    KeySystem         = false
})

--------------------------------------------------------------------------------
-- ── Hulpfuncties ─────────────────────────────────────────────

local function notify(txt)
    Rayfield:Notify({ Title = "Melding", Content = txt, Duration = 3, Image = 4483362458 })
end

-- Tool uitrusten: zoek op trefwoord in karakter + rugzak
local function equipTool(keyword)
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find(keyword) then return item end
    end
    for _, item in ipairs(player.Backpack:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find(keyword) then
            local cur = char:FindFirstChildOfClass("Tool")
            if cur then hum:UnequipTools(); task.wait(0.1) end
            hum:EquipTool(item)
            return item
        end
    end
    return nil
end

-- Cooldown op 0 zetten voor een tool
local function removeCooldown(tool)
    if not noCooldownEnabled then return end
    for _, debName in ipairs({"Cooldown","AttackCooldown","AttackDebounce"}) do
        local deb = tool:FindFirstChild(debName)
        if deb and deb:IsA("NumberValue") then
            deb.Value = 0
            deb.Changed:Connect(function() if noCooldownEnabled then deb.Value = 0 end end)
        end
    end
end

local function hookCharacter(c)
    c.ChildAdded:Connect(function(ch)
        if ch:IsA("Tool") then removeCooldown(ch) end
    end)
    for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") then removeCooldown(t) end
    end
end

player.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    hookCharacter(c)
end)
hookCharacter(char)

--------------------------------------------------------------------------------
-- ── TARGET GATHERING ─────────────────────────────────────────
--
--  ECHTE structuur (zie screenshots):
--  workspace
--  └─ Areas
--     └─ <AreaName>          (StarterArea, BeeHiveArea, CaveArea …)
--        └─ Enemies
--           └─ <MobModel>
--
--  Ores / hout zitten waarschijnlijk in een andere subfolder van Areas.
--  We scannen gewoon Areas:GetDescendants() voor die types.
--
local function getPotentialTargets(targetType)
    local targets = {}
    local areasFolder = workspace:FindFirstChild("Areas")
    if not areasFolder then
        -- Fallback: scan heel workspace als Areas niet gevonden wordt
        areasFolder = workspace
    end

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
        -- Zoek specifiek in <Area>/Enemies/ submappen voor betere performance
        for _, area in ipairs(areasFolder:GetChildren()) do
            local enemiesFolder = area:FindFirstChild("Enemies")
            if enemiesFolder then
                for _, m in ipairs(enemiesFolder:GetChildren()) do
                    if m:IsA("Model") and selectedEnemies[m.Name] and m.PrimaryPart then
                        local eHum = m:FindFirstChildOfClass("Humanoid")
                        if eHum and eHum.Health > 0 then
                            table.insert(targets, m)
                        end
                    end
                end
            end
        end

        -- SpawnRegions submappen ook checken (zie screenshot: SpawnRegions/Area/EnemiestoSpawnHere)
        for _, area in ipairs(areasFolder:GetChildren()) do
            local spawnRegions = area:FindFirstChild("SpawnRegions")
            if spawnRegions then
                for _, region in ipairs(spawnRegions:GetDescendants()) do
                    if region:IsA("Model") and selectedEnemies[region.Name] and region.PrimaryPart then
                        local eHum = region:FindFirstChildOfClass("Humanoid")
                        if eHum and eHum.Health > 0 then
                            table.insert(targets, region)
                        end
                    end
                end
            end
        end
    end

    return targets
end

--------------------------------------------------------------------------------
-- ── BLOX FRUITS STIJL TELEPORT ───────────────────────────────
--
--  Teleporteert naar een positie RONDOM het doel (kleine cirkel),
--  kijkt altijd naar het doel toe zodat aanvallen raakt.
--
local orbitAngle = 0  -- draait elk frame een beetje voor orbit effect

local function getAttackCFrame(targetPart, orbitRadius)
    orbitRadius = orbitRadius or 3.5
    orbitAngle  = (orbitAngle + 15) % 360  -- 15° per aanval → orbit effect
    local rad   = math.rad(orbitAngle)
    local offset = Vector3.new(
        math.cos(rad) * orbitRadius,
        2.5,                           -- iets boven het doel (raakt beter)
        math.sin(rad) * orbitRadius
    )
    local pos = targetPart.Position + offset
    -- CFrame.new(pos, lookAt) → gezicht altijd naar het doel gericht
    return CFrame.new(pos, targetPart.Position)
end

--------------------------------------------------------------------------------
-- ── MASTER AUTOFARM LOOP ─────────────────────────────────────
task.spawn(function()
    while task.wait(0.15) do
        if not (autoTeleporting or autoWoodEnabled or autoKilling) then continue end

        -- Bepaal tool + targettype
        local toolKeyword, targetType, orbitRadius

        if autoTeleporting then
            toolKeyword  = "pickaxe"
            targetType   = "ore"
            orbitRadius  = 3
        elseif autoWoodEnabled then
            toolKeyword  = "axe"
            targetType   = "wood"
            orbitRadius  = 3.5
        elseif autoKilling then
            toolKeyword  = "sword"
            targetType   = "mob"
            orbitRadius  = 3.5
        end

        -- Tool uitrusten met fallbacks
        local myTool = equipTool(toolKeyword)
        if not myTool and toolKeyword == "sword"  then myTool = equipTool("cleaver") end
        if not myTool and toolKeyword == "sword"  then myTool = equipTool("blade")   end
        if not myTool and toolKeyword == "axe"    then myTool = equipTool("hatchet") end
        if not myTool and toolKeyword == "pickaxe" then myTool = equipTool("pick")   end

        if not myTool then
            notify("Geen tool gevonden: " .. toolKeyword)
            task.wait(2)
            continue
        end

        -- Haal geldige doelen op
        local targets = getPotentialTargets(targetType)
        if #targets == 0 then task.wait(0.5) continue end

        -- Dichtstbijzijnde doel
        local closest, minDist = nil, math.huge
        for _, t in ipairs(targets) do
            if t and t.PrimaryPart then
                local d = (hrp.Position - t.PrimaryPart.Position).Magnitude
                if d < minDist then minDist = d; closest = t end
            end
        end

        if not (closest and closest.PrimaryPart) then continue end

        -- ── Aanvalslus op dit doel ───────────────────────────
        local stuckTimer = 0

        repeat
            task.wait(0.07)       -- ~14 aanvallen/sec
            stuckTimer += 0.07

            -- Teleport naar orbit positie rondom het doel
            if hrp and closest.PrimaryPart then
                hrp.CFrame = getAttackCFrame(closest.PrimaryPart, orbitRadius)
            end

            -- Aanvallen (dubbel voor hogere hitrate)
            if myTool then
                myTool:Activate()
                task.wait()
                myTool:Activate()
            end

            -- Doel nog actief?
            local stillAlive = true
            if targetType == "mob" then
                local h = closest:FindFirstChildOfClass("Humanoid")
                if not h or h.Health <= 0 or not closest.Parent then
                    stillAlive = false
                end
            else
                if not closest.Parent or not closest.PrimaryPart then
                    stillAlive = false
                end
            end

        until not stillAlive
            or stuckTimer > 20
            or not (autoTeleporting or autoWoodEnabled or autoKilling)
    end
end)

--------------------------------------------------------------------------------
-- ── ESP LOOP (werkende versie) ────────────────────────────────
--
--  Highlights worden geplaatst in WORKSPACE met Adornee = model.
--  Dit is de meest betrouwbare methode in Roblox.
--
task.spawn(function()
    while task.wait(0.8) do
        if not mobESPEnabled then
            -- Alles opruimen
            for model, hl in pairs(activeHighlights) do
                if hl and hl.Parent then hl:Destroy() end
            end
            activeHighlights = {}
            continue
        end

        -- Huidige levende targets ophalen
        local targets = getPotentialTargets("mob")

        -- Set voor snelle lookup
        local activeSet = {}
        for _, t in ipairs(targets) do activeSet[t] = true end

        -- Verwijder highlights van dode/verdwenen vijanden
        for model, hl in pairs(activeHighlights) do
            if not activeSet[model] or not model.Parent then
                if hl and hl.Parent then hl:Destroy() end
                activeHighlights[model] = nil
            end
        end

        -- Voeg highlights toe aan nieuwe doelen
        for _, m in ipairs(targets) do
            if not activeHighlights[m] then
                local hl = Instance.new("Highlight")
                hl.Adornee          = m                          -- ← CRUCIAAL
                hl.FillColor        = Color3.fromRGB(255, 0, 0)
                hl.OutlineColor     = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.5
                hl.OutlineTransparency = 0
                hl.Parent           = workspace                  -- ← in workspace, niet in model
                activeHighlights[m] = hl
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ── UI OPBOUW ────────────────────────────────────────────────

local TabInfo      = Window:CreateTab("BIGfo")
local TabAutoTP    = Window:CreateTab("Auto TP")
local TabTeleports = Window:CreateTab("Teleports")
local TabCombat    = Window:CreateTab("Combat & Kill")
local TabWood      = Window:CreateTab("Auto Wood")
local TabExtras    = Window:CreateTab("Extras")
local TabESP       = Window:CreateTab("Mob ESP")

TabInfo:CreateParagraph({
    Title   = "Changelog",
    Content = "v2 — Gefixte versie:\n" ..
              "• Juiste Areas-structuur (workspace.Areas.<Area>.Enemies)\n" ..
              "• Blox Fruits orbit teleport aanval\n" ..
              "• ESP met Adornee + workspace parent (werkt nu)\n" ..
              "• Dubbele Activate() per tick voor hogere hitrate\n" ..
              "• SpawnRegions worden ook gescand"
})

-- ── Auto TP (ores) ───────────────────────────────────────────
TabAutoTP:CreateSection("Ore Teleporting")
for _, ore in ipairs(ores) do
    TabAutoTP:CreateToggle({
        Name         = "Farm " .. ore,
        CurrentValue = false,
        Flag         = "AutoTP_" .. ore,
        Callback     = function(val)
            if val then
                selectedOres[ore] = true
                autoTeleporting   = true
                autoWoodEnabled   = false
                autoKilling       = false
            else
                selectedOres[ore] = nil
                autoTeleporting   = next(selectedOres) ~= nil
            end
        end,
    })
end

-- ── Teleports ────────────────────────────────────────────────
TabTeleports:CreateSection("Locations")
for _, v in ipairs(tpList) do
    TabTeleports:CreateButton({
        Name     = v[1],
        Callback = function()
            hrp.Anchored = true
            hrp.CFrame   = CFrame.new(v[2])
            task.wait(0.3)
            hrp.Anchored = false
        end,
    })
end

TabTeleports:CreateSection("Bosses")
for _, v in ipairs(bossesTP) do
    TabTeleports:CreateButton({
        Name     = v[1],
        Callback = function()
            hrp.Anchored = true
            hrp.CFrame   = CFrame.new(v[2])
            task.wait(0.3)
            hrp.Anchored = false
        end,
    })
end

-- ── Combat ───────────────────────────────────────────────────
TabCombat:CreateSection("Modifiers")
TabCombat:CreateToggle({
    Name         = "No Cooldown",
    CurrentValue = false,
    Flag         = "NoCooldown",
    Callback     = function(val)
        noCooldownEnabled = val
        hookCharacter(char)
    end,
})

TabCombat:CreateSection("Auto Kill Targets")
local allEnemies = {}
for _, v in ipairs(mobs)   do table.insert(allEnemies, v) end
for _, v in ipairs(bosses) do table.insert(allEnemies, v) end

for _, name in ipairs(allEnemies) do
    TabCombat:CreateToggle({
        Name         = "Kill " .. name,
        CurrentValue = false,
        Flag         = "AutoKill_" .. name,
        Callback     = function(val)
            if val then
                selectedEnemies[name] = true
                autoKilling           = true
                autoTeleporting       = false
                autoWoodEnabled       = false
            else
                selectedEnemies[name] = nil
                autoKilling           = next(selectedEnemies) ~= nil
            end
        end,
    })
end

-- ── Auto Wood ────────────────────────────────────────────────
TabWood:CreateSection("Wood Farming")
for _, w in ipairs(woodStumps) do
    TabWood:CreateToggle({
        Name         = w,
        CurrentValue = false,
        Flag         = "AutoWood_" .. w,
        Callback     = function(val)
            if val then
                selectedWood[w]   = true
                autoWoodEnabled   = true
                autoTeleporting   = false
                autoKilling       = false
            else
                selectedWood[w]   = nil
                autoWoodEnabled   = next(selectedWood) ~= nil
            end
        end,
    })
end

-- ── Extras ───────────────────────────────────────────────────
TabExtras:CreateSection("Character Mods")
TabExtras:CreateSlider({
    Name         = "WalkSpeed",
    Range        = {16, 200},
    Increment    = 1,
    CurrentValue = 16,
    Flag         = "SliderWS",
    Callback     = function(val) hum.WalkSpeed = val end,
})

TabExtras:CreateSlider({
    Name         = "JumpPower",
    Range        = {50, 300},
    Increment    = 1,
    CurrentValue = 50,
    Flag         = "SliderJP",
    Callback     = function(val) hum.JumpPower = val end,
})

TabExtras:CreateToggle({
    Name         = "Semi-God Mode",
    CurrentValue = false,
    Flag         = "SemiGod",
    Callback     = function(val) semiGodEnabled = val end,
})

-- Semi god: bij laag HP terugtrekken + genezen
hum.HealthChanged:Connect(function(hp)
    if semiGodEnabled and autoKilling and hp > 0 and hp < 30 then
        returnPosition = hrp.CFrame
        notify("HP laag! Vluchten...")
        hrp.CFrame = CFrame.new(-564, -315, -1093)
        repeat task.wait(0.5) until hum.Health >= hum.MaxHealth
        notify("Genezen! Terugkeren...")
        if returnPosition then hrp.CFrame = returnPosition end
    end
end)

TabExtras:CreateToggle({
    Name         = "Infinite Jump",
    CurrentValue = false,
    Flag         = "InfJump",
    Callback     = function(val) infiniteJumpEnabled = val end,
})

UIS.JumpRequest:Connect(function()
    if infiniteJumpEnabled and hum and hum.Health > 0 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- ── ESP ──────────────────────────────────────────────────────
TabESP:CreateSection("Mob ESP")
TabESP:CreateToggle({
    Name         = "Highlight vijanden",
    CurrentValue = false,
    Flag         = "MobESP",
    Callback     = function(val)
        mobESPEnabled = val
        if not val then
            for _, hl in pairs(activeHighlights) do
                if hl and hl.Parent then hl:Destroy() end
            end
            activeHighlights = {}
        end
    end,
})

TabESP:CreateParagraph({
    Title   = "ESP Info",
    Content = "ESP zoekt in workspace.Areas.<Area>.Enemies\n" ..
              "Highlights zijn rood met witte rand.\n" ..
              "Alleen geselecteerde vijanden worden gemarkeerd."
})
