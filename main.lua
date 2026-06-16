-- ============================================================
--  Autofarm Script v15 — Auto Harvest + Quest/Dungeon polish
-- ============================================================
-- NEW IN v10:
--  • FULL enemy list pulled from ReplicatedStorage.Enemies (exact in-game
--    names), alphabetical, bosses split into their own section.
--  • Boss Timers tab: auto-detects when a boss is alive / gone and counts
--    down a 15-min respawn (confirmed for Duke & Blazing Jimbee). Includes
--    "Mark killed" buttons for when you're out of the boss's area, plus an
--    adjustable respawn interval.
--  Carried over: master Kill/Mine/Chop ALL toggles, cheap enemy-folder scan,
--  held-item equip + per-mode re-equip, world teleport, death recovery,
--  No Cooldown.
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
-- NPC dialog remote (captured): DialogEvent:FireServer(npc, "StartQuest", {QuestName=...})
local DialogEvent = ClientRemotes:WaitForChild("Character"):WaitForChild("DialogEvent", 10)

-- Find any remote by name anywhere under ClientRemotes (e.g. "StartDungeon")
local function findRemote(name)
    for _, d in ipairs(ClientRemotes:GetDescendants()) do
        if d.Name == name and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) then
            return d
        end
    end
    return nil
end

local function callRemote(r, ...)
    if not r then return false, "remote not found" end
    if r:IsA("RemoteFunction") then
        return pcall(function(...) return r:InvokeServer(...) end, ...)
    end
    return pcall(function(...) r:FireServer(...) end, ...)
end

-- ── State ──────────────────────────────────────────────────
local autoOre, autoWood, autoKill = false, false, false
local autoHarvest = false              -- shears/scissors harvesting
local harvestAll = false               -- harvest every bush/plant found
local autoDungeon = false        -- Auto Dungeon mode (overrides other farming)
local autoQuest   = false        -- Auto-farm active quest kill targets
local questActionMsg = ""        -- last accept result for the UI
local dungeonChoice = "CublinDungeon"  -- which dungeon to run
local mineAll, chopAll, killAll   = false, false, false
local noCooldown, infiniteJump, espEnabled = false, false, false
local deathRecover = true

local SWING_DELAY = 0.05
local MOB_OFFSET = Vector3.new(0, 1.5, 2)
local RES_OFFSET = Vector3.new(0, 2, 2.5)
local TARGET_MOVE_RETP = 3
local FELL_AWAY_RETP   = 7
local STALL_SECONDS    = 4

local lastFarmPos = nil
local needRecover = false
local lastEquipped = {}

local selOres, selWood, selEnemies = {}, {}, {}
local selHarvest = {}
local espCache = {}

-- ── Content lists (exact names from ReplicatedStorage.Enemies) ──
local oreNames = {
    "Amethyst","Blood Stone","Copper","Dark Geode","Darktainium","Diamond",
    "Emerald","Gold","Ice","Iron","Jade","Magnetite","Meteorite","Obsidian",
    "Platinum","Rock","Salt Rock","Sandstone","Sapphire","Shroomium","Tin","Valerion"
}
local woodNames = { "Oak Stump","Redwood Stump","Spruce Stump" }

local regularEnemies = {
    "Angry Wasp","Bad Lad","Ballzo","Ballzo Warrior","Bananey","Bell Flowey","Big Mushman",
    "Bloom Mimic","Blooming Flowey","Blossom Keeper","Blueberrey","Bluecapey","Bombee","Bombey",
    "Bonezo","Browncapey","Bumblecubee","Buney","Candy Corn Leafy","Cave Spidey","Cavey",
    "Coconut Crab","Coghead","Corney","Cubee","Cubeek","Cubemaster","Cubey",
    "Cubey Bandit","Cubey Bodyguard","Cubey Mage","Cublin","Cublin Brute","Cublin Warrior",
    "Cylindery","Easter Buney","Eclipsed Ghostey","El Espinoso","Field Mousey","Fire Flowey",
    "Firefly","Floral Turtley","Flowey","Flying Archerfish","Flying Goldfish","Fremlin","Frogey",
    "Frost Buney","Ghostey","Gnome","Hallow Cubey Mage","Honey Mimic","Ice Lizardey","Icy Snail",
    "Jack O'Cubee","Leafy","Lepus","Lilypadey","Living Berry Bush","Midnight Samurai","Mini Cubey",
    "Mini Leafy","Mini Tankzo","Moai","Monster Mousey","Mousey","Mr. CRT","Mushey","Mushmasher",
    "Mystic Mimic","Parawalker","Pestililypadey","Petalith","Prickley","Pumpkiney","Pumpkinpadey",
    "Quadropod","Redwood Mimic","Roadkillzo","Rogue Cubey","Rustey","Scorpion","Sea Serpent",
    "Sentient Assault Rifle","Shockbox","Snowdeerey","Solar Elemental","Spidey","Spikezo","Stoney",
    "Strawberry","Swamp Hydrey","Target Dummy","Testing Cubey","Tumblezo","Vampiric Druid",
    "Vampiric Outlaw","Voidey","Watchstalker","Wedgey","Wedgey1","Wooden Mimic","Wraithhorn"
}

local bossEnemies = {
    "Awakened Swamp Hydrey","BLAZING JIMBEE","C U B E Y","CURSE INCARNATE","Crab Champion",
    "Duke Cublindor","Enormous Ballzo","Eruption Furnace","Glacier Giant","Jimbee",
    "LORD CUBLINDOR","Lord Ganongar The 12th","Musheynator","Orbdenier","Pharaoh's Curse","Wedgey God"
}

local bossSet = {}; for _, b in ipairs(bossEnemies) do bossSet[b] = true end

-- Boss trackers, split by ACTUAL mechanic (researched on the Studlands wiki):
--  • RESPAWN_MINIBOSSES auto-respawn at a shrine on a timer. Cylindery spawns
--    at the cylinder shrine every 64s (wiki-sourced), one at a time.
--  • SUMMON_BOSSES only appear when summoned (item / dungeon / enrage), gated by
--    a cooldown. 15 min is the wiki-sourced cooldown (Duke, Enormous Ballzo,
--    Lord Cublindor, Blazing Jimbee, Crab Champion).
-- Both share the same detect-and-count mechanic; only defaults/labels differ.
local RESPAWN_MINIBOSSES = { "Cylindery" }
local SUMMON_BOSSES = {
    "Crab Champion","Duke Cublindor","Enormous Ballzo","Glacier Giant",
    "Jimbee","Musheynator","Orbdenier","Pharaoh's Curse"
}

local DEFAULT_CD_SUMMON  = 900  -- 15 min, wiki-sourced summon cooldown
local DEFAULT_CD_RESPAWN = 64   -- 64s, wiki-sourced Cylindery shrine respawn

local TRACKED = {}        -- ordered: { {name=, kind=}, ... }
local TRACKED_NAMES = {}  -- ordered plain names for loops
for _, n in ipairs(RESPAWN_MINIBOSSES) do
    TRACKED[#TRACKED+1] = { name=n, kind="respawn" }; TRACKED_NAMES[#TRACKED_NAMES+1] = n
end
for _, n in ipairs(SUMMON_BOSSES) do
    TRACKED[#TRACKED+1] = { name=n, kind="summon" }; TRACKED_NAMES[#TRACKED_NAMES+1] = n
end

local bossState = {}
-- seen     = currently present & alive in a loaded area
-- lastDeath= os.time() when it last went from present -> absent
-- nextReady= os.time() the timer/cooldown finishes
-- interval = length (starts at the kind's sourced default, updated by measurement)
-- measured = true once we've timed a real gone->reappear cycle
-- kind     = "respawn" | "summon"
for _, t in ipairs(TRACKED) do
    local cd = (t.kind == "respawn") and DEFAULT_CD_RESPAWN or DEFAULT_CD_SUMMON
    bossState[t.name] = { seen=false, lastDeath=nil, nextReady=nil,
                          interval=cd, measured=false, kind=t.kind }
end

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

local function isWoodName(nm)
    return nm:find("Stump") ~= nil or nm:find("Tree") ~= nil or nm:find("Log") ~= nil
end

-- Harvestables (shears/scissors/sickles) — live in CurrentResources like ores.
-- Names below are the in-game resource Model names (PrimaryPart "Center").
local harvestNames = {
    "Bitterberry Bush","Blackberry Bush","Blueberry Bush","Cola Berry Bush",
    "Coconut","Elderberry Bush","Frostberry Bush","Golden Coconut",
    "Gummyberry Bush","Strawberry Bush","Wheat"
}
local function isHarvestName(nm)
    local low = nm:lower()
    return low:find("bush") ~= nil or low:find("berry") ~= nil
        or low:find("coconut") ~= nil or low:find("strawberry") ~= nil
        or low:find("wheat") ~= nil
end

local CHAR_PART = {
    Humanoid=true, HumanoidRootPart=true, Head=true, Torso=true, UpperTorso=true, LowerTorso=true,
    ["Left Arm"]=true, ["Right Arm"]=true, ["Left Leg"]=true, ["Right Leg"]=true,
    LeftUpperArm=true, LeftLowerArm=true, LeftHand=true, RightUpperArm=true, RightLowerArm=true, RightHand=true,
    LeftUpperLeg=true, LeftLowerLeg=true, LeftFoot=true, RightUpperLeg=true, RightLowerLeg=true, RightFoot=true,
    Animate=true, ["Body Colors"]=true, Health=true,
}

local function isHeldItem(c)
    if CHAR_PART[c.Name] then return false end
    if c:IsA("Humanoid") or c:IsA("LuaSourceContainer") or c:IsA("Shirt") or c:IsA("Pants")
       or c:IsA("BodyColors") or c:IsA("Accessory") or c:IsA("Folder") or c:IsA("ValueBase")
       or c:IsA("Sound") or c:IsA("CharacterMesh") or c:IsA("Decal") then
        return false
    end
    if c:IsA("Tool") then return true end
    if c:IsA("Model") and (c:FindFirstChild("Handle") or c.PrimaryPart) then return true end
    if c:IsA("BasePart") and c:FindFirstChild("Handle") then return true end
    return false
end

local function getEquipped()
    local fallback
    for _, c in ipairs(char:GetChildren()) do
        if isHeldItem(c) then
            if c:FindFirstChild("Handle") then return c end
            fallback = fallback or c
        end
    end
    return fallback
end

local function currentMode()
    if autoDungeon then return "kill"     -- dungeon uses the weapon memory
    elseif autoQuest then return "kill"   -- quest farm picks tool per target
    elseif autoKill then return "kill"
    elseif autoWood then return "wood"
    elseif autoHarvest then return "harvest"
    elseif autoOre then return "ore" end
    return nil
end

local function ensureEquipped(mode)
    local eq = getEquipped()
    if eq then
        if mode then lastEquipped[mode] = eq.Name end
        return eq
    end
    local name = mode and lastEquipped[mode]
    if name then
        for _ = 1, 3 do
            pcall(function() EquipItem:InvokeServer(name) end)
            task.wait(0.15)
            eq = getEquipped()
            if eq then
                if mode then lastEquipped[mode] = eq.Name end
                return eq
            end
        end
    end
    return getEquipped()
end

-- ── No Cooldown ────────────────────────────────────────────
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

-- ── Enemy folders ──────────────────────────────────────────
local function collectEnemyFolders()
    local folders = {}
    local areas = workspace:FindFirstChild("Areas")
    if not areas then return folders end
    for _, area in ipairs(areas:GetChildren()) do
        local en = area:FindFirstChild("Enemies")
        if en then folders[#folders+1] = en end
        local sr = area:FindFirstChild("SpawnRegions")
        if sr then
            local sub = sr:FindFirstChild("Area")
            local eth = sub and sub:FindFirstChild("EnemiesToSpawnHere")
            if eth then folders[#folders+1] = eth end
        end
    end
    return folders
end

local function getMobTargets()
    local list = {}
    for _, folder in ipairs(collectEnemyFolders()) do
        for _, obj in ipairs(folder:GetChildren()) do
            if obj:IsA("Model") then
                local include = killAll or selEnemies[obj.Name]
                if include then
                    local eHum = obj:FindFirstChildOfClass("Humanoid")
                    local part = getRootPart(obj)
                    if eHum and eHum.Health > 0 and part then
                        list[#list+1] = {obj=obj, part=part, hum=eHum}
                    end
                end
            end
        end
    end
    return list
end

local function getResourceTargets(kind)
    local list = {}
    local spawns = workspace:FindFirstChild("ResourceSpawns")
    if not spawns then return list end
    for _, region in ipairs(spawns:GetChildren()) do
        for _, node in ipairs(region:GetChildren()) do
            local cr = node:FindFirstChild("CurrentResources")
            if cr then
                for _, res in ipairs(cr:GetChildren()) do
                    local nm = res.Name
                    local include = false
                    if kind == "ore" then
                        -- mineAll = everything that isn't wood and isn't a harvestable
                        if mineAll then include = (not isWoodName(nm)) and (not isHarvestName(nm))
                        else include = selOres[nm] == true end
                    elseif kind == "wood" then
                        if chopAll then include = isWoodName(nm) else include = selWood[nm] == true end
                    else -- harvest
                        if harvestAll then include = isHarvestName(nm) else include = selHarvest[nm] == true end
                    end
                    if include then
                        local part = getRootPart(res)
                        if part then list[#list+1] = {obj=res, part=part} end
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

local function recompute()
    autoKill    = killAll or (next(selEnemies) ~= nil)
    autoOre     = mineAll or (next(selOres) ~= nil)
    autoWood    = chopAll or (next(selWood) ~= nil)
    autoHarvest = harvestAll or (next(selHarvest) ~= nil)
    -- enabling any normal farm mode takes over from Auto Dungeon / Auto Quest
    if autoKill or autoOre or autoWood or autoHarvest then autoDungeon = false; autoQuest = false end
end

-- ── Boss timer monitor ─────────────────────────────────────
local function bossPresent(name)
    for _, folder in ipairs(collectEnemyFolders()) do
        local m = folder:FindFirstChild(name)
        if m then
            local h = m:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then return true end
        end
    end
    return false
end

task.spawn(function()
    while task.wait(2) do
        for _, name in ipairs(TRACKED_NAMES) do
            local st = bossState[name]
            local present = bossPresent(name)
            if present then
                if not st.seen then
                    -- boss just (re)appeared — if we timed its absence, learn the interval
                    if st.lastDeath then
                        local measured = os.time() - st.lastDeath
                        -- accept only sane values (30s .. 2h) to ignore glitches
                        if measured >= 30 and measured <= 7200 then
                            st.interval = measured
                            st.measured = true
                        end
                    end
                    st.nextReady = nil
                end
                st.seen = true
            elseif st.seen then
                -- boss just died / despawned — start the cooldown
                st.seen = false
                st.lastDeath = os.time()
                st.nextReady = os.time() + st.interval
            end
        end
    end
end)

-- ── Auto Dungeon ───────────────────────────────────────────
-- Built from Dex captures of the live dungeon structure:
--   Areas.<Dungeon>.DungeonKills.StageN (IntValue kills) + .Required (IntValue)
--   Areas.<Dungeon>.Enemies            (live mobs spawn here, incl. the boss)
--   Areas.<Dungeon>.SpawnRegions.Boss.EnemiesToSpawnHere -> boss name
--   Areas.<Dungeon>.Spawn              (entry point model)
--   BeeHive only: Map.Switches.Switch1-4 with a "Pulled" attribute
local DUNGEONS = {
    CublinDungeon = {
        label = "Duke Cublindor's Domain",
        boss  = "Duke Cublindor",       -- becomes LORD CUBLINDOR when enraged
        altBoss = "LORD CUBLINDOR",
        hasSwitches = false,
    },
    BeeHiveArea = {
        label = "The Grand Beehive",
        boss  = "Jimbee",               -- becomes BLAZING JIMBEE when enraged
        altBoss = "BLAZING JIMBEE",
        hasSwitches = true,
    },
}

local dungeonStatus = "idle"
local dungeonBossWasSeen = false

local function getDungeonArea()
    local areas = workspace:FindFirstChild("Areas")
    return areas and areas:FindFirstChild(dungeonChoice) or nil
end

-- Live, alive models in the dungeon's Enemies folder (boss included)
local function getDungeonTargets()
    local list = {}
    local area = getDungeonArea()
    if not area then return list end
    local en = area:FindFirstChild("Enemies")
    if not en then return list end
    for _, obj in ipairs(en:GetChildren()) do
        if obj:IsA("Model") then
            local eHum = obj:FindFirstChildOfClass("Humanoid")
            local part = getRootPart(obj)
            if eHum and eHum.Health > 0 and part then
                list[#list+1] = {obj=obj, part=part, hum=eHum}
            end
        end
    end
    return list
end

-- "S1 12/20  S2 0/20  S3 0/25" from DungeonKills
local function dungeonKillText()
    local area = getDungeonArea()
    if not area then return "?" end
    local dk = area:FindFirstChild("DungeonKills")
    if not dk then return "?" end
    local parts = {}
    for _, st in ipairs(dk:GetChildren()) do
        if st:IsA("IntValue") then
            local req = st:FindFirstChild("Required")
            local r = (req and req:IsA("IntValue")) and req.Value or "?"
            parts[#parts+1] = string.format("%s %d/%s", st.Name:gsub("Stage","S"), st.Value, tostring(r))
        end
    end
    table.sort(parts)
    return table.concat(parts, "  ")
end

local function dungeonStagesDone()
    local area = getDungeonArea()
    if not area then return false end
    local dk = area:FindFirstChild("DungeonKills")
    if not dk then return false end
    local any = false
    for _, st in ipairs(dk:GetChildren()) do
        if st:IsA("IntValue") then
            any = true
            local req = st:FindFirstChild("Required")
            if req and req:IsA("IntValue") and st.Value < req.Value then return false end
        end
    end
    return any
end

local function dungeonBossAlive()
    local def = DUNGEONS[dungeonChoice]
    if not def then return nil end
    local area = getDungeonArea()
    local en = area and area:FindFirstChild("Enemies")
    if not en then return nil end
    for _, nm in ipairs({def.boss, def.altBoss}) do
        local m = nm and en:FindFirstChild(nm)
        if m then
            local h = m:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then return m end
        end
    end
    return nil
end

-- Beehive switch phase: TP to each unpulled switch and fire its prompt
local function pullSwitches()
    local area = getDungeonArea()
    local map = area and area:FindFirstChild("Map")
    local sw  = map and map:FindFirstChild("Switches")
    if not sw then return true end   -- nothing to pull
    local allPulled = true
    for _, s in ipairs(sw:GetChildren()) do
        if s:IsA("Model") and s.Name:find("Switch") then
            if s:GetAttribute("Pulled") ~= true then
                allPulled = false
                dungeonStatus = "pulling " .. s.Name
                local pivot = s:GetPivot().Position
                pcall(function()
                    hrp.CFrame = CFrame.new(pivot + Vector3.new(0, 3, 0))
                    hrp.AssemblyLinearVelocity = Vector3.zero
                end)
                task.wait(0.4)
                -- fire any ProximityPrompt inside the switch (exploit global)
                for _, d in ipairs(s:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        if typeof(fireproximityprompt) == "function" then
                            pcall(function() fireproximityprompt(d) end)
                        else
                            pcall(function()
                                d.HoldDuration = 0
                                d:InputHoldBegin(); task.wait(0.1); d:InputHoldEnd()
                            end)
                        end
                        task.wait(0.3)
                    end
                end
                -- give the server a moment; standing on it covers touch-based switches
                local t0 = os.clock()
                while os.clock() - t0 < 3 do
                    if s:GetAttribute("Pulled") == true then break end
                    task.wait(0.25)
                end
            end
        end
    end
    return allPulled
end

-- TP into the dungeon's spawn point
local function gotoDungeonSpawn()
    local area = getDungeonArea()
    local sp = area and area:FindFirstChild("Spawn")
    if not sp then return false end
    local pos
    if sp:IsA("Model") then pos = sp:GetPivot().Position
    elseif sp:IsA("BasePart") then pos = sp.Position end
    if not pos then return false end
    pcall(function()
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    return true
end

-- A dungeon run is active when the area's "Running" attribute is true
local function dungeonRunning(area)
    area = area or getDungeonArea()
    if not area then return false end
    return area:GetAttribute("Running") == true
end

-- Find the red "start" zone you stand in to begin the run. Tries common names,
-- then a reddish part, then falls back to the Spawn point.
local function getStartZonePos()
    local area = getDungeonArea()
    if not area then return nil end
    local keys = { "start", "begin", "trigger", "enter", "pad", "portal", "red", "activate" }
    local reddish
    for _, d in ipairs(area:GetDescendants()) do
        if d:IsA("BasePart") then
            local low = d.Name:lower()
            for _, k in ipairs(keys) do
                if low:find(k) then return d.Position end
            end
            local c = d.Color
            if not reddish and c.R > 0.55 and c.G < 0.35 and c.B < 0.35 then
                reddish = d.Position
            end
        end
    end
    if reddish then return reddish end
    local sp = area:FindFirstChild("Spawn")
    if sp then
        if sp:IsA("Model") then return sp:GetPivot().Position
        elseif sp:IsA("BasePart") then return sp.Position end
    end
    return nil
end

-- Stand in the start zone until the run begins (Running flips true / enemies appear)
local function holdInStartZone(area)
    local pos = getStartZonePos()
    if not pos then dungeonStatus = "can't find start zone — stand in the red pad"; task.wait(0.5); return end
    local t0 = os.clock()
    while autoDungeon and not needRecover do
        if dungeonRunning(area) or dungeonBossAlive() or #getDungeonTargets() > 0 then
            dungeonStatus = "run started!"
            return
        end
        local waited = math.floor(os.clock() - t0)
        dungeonStatus = string.format("standing in start zone... %ds (wait ~30s)", waited)
        pcall(function()
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        task.wait(0.5)
        if os.clock() - t0 > 60 then
            dungeonStatus = "no run after 60s — is this the right dungeon / spot?"
            return
        end
    end
end

-- ── Auto Quest (progress farming) ──────────────────────────
-- From Dex captures:
--   Definitions: ReplicatedStorage.Quests.{Normal|Daily|Angler}.<Quest>
--     .Requirements.<TargetName> (IntValue = how many needed)
--     .QuestType (e.g. "DefeatEnemies"), .Rewards, .Repeatable
--   Your progress: Players.<you>.Quests.<Quest>.Requirements.<TargetName>
-- Accepting/turning in goes through the NPC dialogue (remote not yet
-- captured), so v1 farms the KILLS for whatever quests you've accepted;
-- you talk to the NPC to accept and to turn in.
local function findQuestDef(questName)
    local defs = RS:FindFirstChild("Quests")
    if not defs then return nil end
    for _, cat in ipairs(defs:GetChildren()) do
        local q = cat:FindFirstChild(questName)
        if q then return q end
    end
    return nil
end

-- Array of {quest, target, cur, req, done, farmable}
local function getQuestRequirements()
    local out = {}
    local pq = player:FindFirstChild("Quests")
    if not pq then return out end
    for _, q in ipairs(pq:GetChildren()) do
        local reqs = q:FindFirstChild("Requirements")
        if reqs then
            local def = findQuestDef(q.Name)
            local defReqs = def and def:FindFirstChild("Requirements")
            for _, r in ipairs(reqs:GetChildren()) do
                if r:IsA("IntValue") or r:IsA("NumberValue") then
                    local dr = defReqs and defReqs:FindFirstChild(r.Name)
                    local req = (dr and (dr:IsA("IntValue") or dr:IsA("NumberValue"))) and dr.Value or nil
                    -- complete if counted up to req, or counted down to 0
                    local done = (req and r.Value >= req) or r.Value <= 0
                    local isKill    = allMobSet[r.Name] == true
                    local isHarvest = (not isKill) and isHarvestName(r.Name)
                    out[#out+1] = {
                        quest = q.Name, target = r.Name,
                        cur = r.Value, req = req,
                        done = done,
                        farmable = isKill or isHarvest,
                        harvest = isHarvest,
                    }
                end
            end
        end
    end
    return out
end

-- Sets of still-needed quest targets, split by how they're farmed
local function questNeeds()
    local kills, harvests = {}, {}
    for _, r in ipairs(getQuestRequirements()) do
        if r.farmable and not r.done then
            if r.harvest then harvests[r.target] = true else kills[r.target] = true end
        end
    end
    return kills, harvests
end

local function getQuestTargets()
    local list = {}
    local kills, harvests = questNeeds()
    if next(kills) ~= nil then
        for _, folder in ipairs(collectEnemyFolders()) do
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and kills[obj.Name] then
                    local eHum = obj:FindFirstChildOfClass("Humanoid")
                    local part = getRootPart(obj)
                    if eHum and eHum.Health > 0 and part then
                        list[#list+1] = {obj=obj, part=part, hum=eHum, harvest=false}
                    end
                end
            end
        end
    end
    if next(harvests) ~= nil then
        local spawns = workspace:FindFirstChild("ResourceSpawns")
        if spawns then
            for _, region in ipairs(spawns:GetChildren()) do
                for _, node in ipairs(region:GetChildren()) do
                    local cr = node:FindFirstChild("CurrentResources")
                    if cr then
                        for _, res in ipairs(cr:GetChildren()) do
                            if harvests[res.Name] then
                                local part = getRootPart(res)
                                if part then list[#list+1] = {obj=res, part=part, harvest=true} end
                            end
                        end
                    end
                end
            end
        end
    end
    return list
end

-- ── Quest accept / turn-in (via captured DialogEvent) ──────
local questNPCCache = {}   -- [questName] = npc instance that accepted it

local function questActive(qname)
    local pq = player:FindFirstChild("Quests")
    return pq and pq:FindFirstChild(qname) ~= nil
end

-- Some quest defs may name their giver; use it when present
local function questGiverFromDef(qname)
    local def = findQuestDef(qname)
    if not def then return nil end
    for _, v in ipairs(def:GetChildren()) do
        if v:IsA("StringValue") and (v.Name == "NPC" or v.Name == "Giver"
            or v.Name == "QuestGiver" or v.Name == "From") then
            local npcs = workspace:FindFirstChild("NPCs")
            local m = npcs and npcs:FindFirstChild(v.Value)
            if m then return m end
        end
    end
    return nil
end

local function npcPos(n)
    if n:IsA("Model") then return n:GetPivot().Position
    elseif n:IsA("BasePart") then return n.Position end
    return nil
end

local function fireDialog(npc, action, qname)
    if not DialogEvent then return end
    pcall(function() DialogEvent:FireServer(npc, action, { QuestName = qname }) end)
end

-- Accept: TP to giver (or crawl all NPCs), fire StartQuest, verify it appears
local function acceptQuest(qname)
    if questActive(qname) then return true, "already active" end
    if not DialogEvent then return false, "DialogEvent remote not found" end
    local npcs = workspace:FindFirstChild("NPCs")
    if not npcs then return false, "workspace.NPCs not found" end
    local origin = hrp.CFrame

    local function tryNPC(npc)
        local p = npcPos(npc)
        if not p then return false end
        pcall(function()
            hrp.CFrame = CFrame.new(p + Vector3.new(0, 3, 3))
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        task.wait(0.25)
        fireDialog(npc, "StartQuest", qname)
        task.wait(0.45)
        if questActive(qname) then questNPCCache[qname] = npc; return true end
        return false
    end

    local known = questNPCCache[qname] or questGiverFromDef(qname)
    if known and tryNPC(known) then
        pcall(function() hrp.CFrame = origin end)
        return true, "accepted at " .. known.Name
    end
    for _, npc in ipairs(npcs:GetChildren()) do
        if tryNPC(npc) then
            pcall(function() hrp.CFrame = origin end)
            return true, "accepted at " .. npc.Name
        end
    end
    pcall(function() hrp.CFrame = origin end)
    return false, "no NPC accepted it (server may require quest prerequisites)"
end

-- NOTE: quests in Studlands auto-complete and auto-reward the moment their
-- requirements are met (confirmed in-game) — there is NO turn-in step, so we
-- don't fire any completion remote. Accept + farm is all that's needed.

-- ── Death recovery ─────────────────────────────────────────
local function farmingActive() return autoKill or autoOre or autoWood or autoHarvest or autoDungeon or autoQuest end

local function anyTargetLoaded()
    if autoDungeon then return #getDungeonTargets() > 0
    elseif autoQuest then return #getQuestTargets() > 0
    elseif autoKill then return #getMobTargets() > 0
    elseif autoWood then return #getResourceTargets("wood") > 0
    elseif autoHarvest then return #getResourceTargets("harvest") > 0
    elseif autoOre then return #getResourceTargets("ore") > 0 end
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
            local mode = currentMode()
            local back = lastFarmPos
            task.wait(1)
            local te = os.clock()
            repeat
                ensureEquipped(mode)
                task.wait(0.2)
            until getEquipped() or os.clock() - te > 5
            pcall(function()
                hrp.CFrame = CFrame.new(back)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end)
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

            local mode  = currentMode()
            local isMob = autoKill or autoDungeon or autoQuest

            -- Auto Dungeon pre-phases
            if autoDungeon then
                local def = DUNGEONS[dungeonChoice]
                local area = getDungeonArea()
                if not area then
                    dungeonStatus = "area not loaded — walk/TP near the dungeon"
                    task.wait(0.5); return
                end
                -- completion check: boss was seen and is now gone
                if dungeonBossWasSeen and not dungeonBossAlive() and #getDungeonTargets() == 0 then
                    dungeonStatus = "COMPLETE — boss down!"
                    task.wait(1); return
                end
                -- if no run is active yet, stand in the start zone to begin it
                if not dungeonRunning(area) and not dungeonBossAlive() and #getDungeonTargets() == 0 then
                    holdInStartZone(area)
                    return
                end
                if def and def.hasSwitches then
                    if not pullSwitches() then
                        task.wait(0.3); return   -- still pulling; loop re-enters
                    end
                end
                if dungeonBossAlive() then
                    dungeonBossWasSeen = true
                    dungeonStatus = "fighting boss — " .. dungeonKillText()
                else
                    dungeonStatus = "clearing — " .. dungeonKillText()
                end
            end

            local targets
            if autoDungeon then targets = getDungeonTargets()
            elseif autoQuest then targets = getQuestTargets()
            elseif autoKill then targets = getMobTargets()
            elseif autoWood then targets = getResourceTargets("wood")
            elseif autoHarvest then targets = getResourceTargets("harvest")
            else targets = getResourceTargets("ore") end

            local target = getClosest(targets)
            if not target then task.wait(0.25); return end

            -- Auto Quest picks the right tool per target (enemy vs bush)
            if autoQuest then
                if target.harvest then mode = "harvest"; isMob = false
                else mode = "kill"; isMob = true end
            end

            local obj, part = target.obj, target.part
            local offset = isMob and MOB_OFFSET or RES_OFFSET
            local anchorPos = nil
            local guard, maxGuard = 0, (isMob and 220 or 420)
            local lastHP, stallT = nil, os.clock()

            ensureEquipped(mode)

            while obj.Parent and part.Parent and guard < maxGuard do
                if not farmingActive() then break end
                if needRecover then break end

                if isMob then
                    local eHum = target.hum or obj:FindFirstChildOfClass("Humanoid")
                    if not eHum or eHum.Health <= 0 then break end
                    local h = eHum.Health
                    if lastHP == nil then lastHP = h end
                    if h < lastHP then lastHP = h; stallT = os.clock() end
                    if os.clock() - stallT > STALL_SECONDS then break end
                end

                local desired = part.Position + offset
                if (not anchorPos)
                   or (anchorPos - desired).Magnitude > TARGET_MOVE_RETP
                   or (hrp.Position - desired).Magnitude > FELL_AWAY_RETP then
                    hrp.CFrame = CFrame.new(desired, part.Position)
                    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
                    anchorPos = desired
                end
                lastFarmPos = hrp.Position

                local eq = getEquipped() or ensureEquipped(mode)
                if eq then
                    if mode then lastEquipped[mode] = eq.Name end
                    pcall(function() UseItem:FireServer(eq, false, nil, nil, 0.6) end)
                end

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
        local seen = {}
        for _, folder in ipairs(collectEnemyFolders()) do
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") then
                    local eHum = m:FindFirstChildOfClass("Humanoid")
                    if eHum and eHum.Health > 0 then seen[m] = true; buildESP(m) end
                end
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
    Name = "Autofarm v15",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "Respawn vs summon tracking",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local TabInfo    = Window:CreateTab("Info")
local TabOre     = Window:CreateTab("Auto Ore")
local TabTPs     = Window:CreateTab("Teleports")
local TabCombat  = Window:CreateTab("Combat")
local TabWood    = Window:CreateTab("Auto Wood")
local TabHarvest = Window:CreateTab("Auto Harvest")
local TabDungeon = Window:CreateTab("Auto Dungeon")
local TabQuest   = Window:CreateTab("Auto Quest")
local TabTimers  = Window:CreateTab("Boss Timers")
local TabExtras  = Window:CreateTab("Extras")
local TabESP     = Window:CreateTab("Mob ESP")

TabInfo:CreateParagraph({ Title = "v15 — Auto Harvest", Content =
    "NEW: Auto Dungeon tab clears Duke Cublindor's Domain / The Grand Beehive\n" ..
    "(switches, kill stages, boss) hands-free once you're inside. Auto Quest\n" ..
    "tab reads your accepted quests and farms exactly the kills they need.\n" ..
    "Boss Timers split into respawn minibosses (Cylindery ~64s) and summon\n" ..
    "cooldowns (~15m), both self-calibrating from observation." })

-- ── Auto Ore ───────────────────────────────────────────────
TabOre:CreateSection("Master")
TabOre:CreateToggle({ Name="Mine ALL Ores", CurrentValue=false, Flag="MineAll",
    Callback=function(v) mineAll=v; if v then chopAll=false; killAll=false; harvestAll=false end; recompute() end })
TabOre:CreateSection("Select Ore")
for _, ore in ipairs(oreNames) do
    TabOre:CreateToggle({ Name = "Mine "..ore, CurrentValue = false, Flag = "Ore_"..ore,
        Callback = function(v)
            for _, n in ipairs({ ore, ore.." Ore", ore.." Vein" }) do selOres[n] = v or nil end
            recompute()
        end })
end

-- ── Teleports ──────────────────────────────────────────────
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

-- ── Combat ─────────────────────────────────────────────────
TabCombat:CreateSection("Survival")
TabCombat:CreateToggle({ Name="Death Recovery (re-equip + TP back)", CurrentValue=deathRecover, Flag="Recover",
    Callback=function(v) deathRecover=v end })
TabCombat:CreateToggle({ Name="No Cooldown", CurrentValue=false, Flag="NoCooldown",
    Callback=function(v) noCooldown=v end })

TabCombat:CreateSection("Master")
TabCombat:CreateToggle({ Name="Kill ALL Enemies", CurrentValue=false, Flag="KillAll",
    Callback=function(v) killAll=v; if v then mineAll=false; chopAll=false; harvestAll=false end; recompute() end })

TabCombat:CreateSection("Bosses")
for _, name in ipairs(bossEnemies) do
    TabCombat:CreateToggle({ Name="Kill "..name, CurrentValue=false, Flag="Kill_"..name,
        Callback=function(v) selEnemies[name] = v or nil; recompute() end })
end

TabCombat:CreateSection("Regular Enemies")
for _, name in ipairs(regularEnemies) do
    TabCombat:CreateToggle({ Name="Kill "..name, CurrentValue=false, Flag="Kill_"..name,
        Callback=function(v) selEnemies[name] = v or nil; recompute() end })
end

-- ── Auto Wood ──────────────────────────────────────────────
TabWood:CreateSection("Master")
TabWood:CreateToggle({ Name="Chop ALL Wood", CurrentValue=false, Flag="ChopAll",
    Callback=function(v) chopAll=v; if v then mineAll=false; killAll=false; harvestAll=false end; recompute() end })
TabWood:CreateSection("Select Wood")
for _, w in ipairs(woodNames) do
    TabWood:CreateToggle({ Name=w, CurrentValue=false, Flag="Wood_"..w,
        Callback=function(v)
            local base = w:gsub(" Stump","")
            for _, n in ipairs({ w, base, base.." Tree", base.." Tree Stump" }) do selWood[n] = v or nil end
            recompute()
        end })
end

-- ── Auto Harvest ───────────────────────────────────────────
TabHarvest:CreateParagraph({ Title="How it works", Content=
    "Equip your shears / scissors / sickle once (the harvesting tool), then\n" ..
    "flip a toggle. Works exactly like Auto Ore but for bushes, berries,\n" ..
    "coconuts and wheat in CurrentResources. Harvest ALL grabs every bush/\n" ..
    "plant in range; or pick specific ones below." })
TabHarvest:CreateSection("Master")
TabHarvest:CreateToggle({ Name="Harvest ALL Plants", CurrentValue=false, Flag="HarvestAll",
    Callback=function(v) harvestAll=v; if v then mineAll=false; chopAll=false; killAll=false end; recompute() end })
TabHarvest:CreateSection("Select Harvestable")
for _, h in ipairs(harvestNames) do
    TabHarvest:CreateToggle({ Name="Harvest "..h, CurrentValue=false, Flag="Harv_"..h,
        Callback=function(v)
            -- register the bush name plus a couple of likely variants
            local variants = { h }
            if h:find(" Bush") then variants[#variants+1] = h:gsub(" Bush","") end
            variants[#variants+1] = h .. " Bush"
            for _, n in ipairs(variants) do selHarvest[n] = v or nil end
            recompute()
        end })
end

-- ── Auto Dungeon ───────────────────────────────────────────
TabDungeon:CreateParagraph({ Title="How it works", Content=
    "1) Pick the dungeon below and flip Auto Dungeon ON near the dungeon.\n" ..
    "2) If no run is active, the script stands in the start zone (~30s) to\n" ..
    "begin it, then pulls the Beehive's 4 switches if needed, clears the kill\n" ..
    "stages (Duke's: 20/20/25, doubled when enraged) and kills the boss when\n" ..
    "he spawns. Handles Lord Cublindor / Blazing Jimbee. Status shows progress." })

TabDungeon:CreateSection("Dungeon")
TabDungeon:CreateDropdown({
    Name = "Select Dungeon",
    Options = { "Duke Cublindor's Domain", "The Grand Beehive" },
    CurrentOption = { "Duke Cublindor's Domain" },
    Flag = "DungeonPick",
    Callback = function(opt)
        local pick = typeof(opt) == "table" and opt[1] or opt
        if pick == "The Grand Beehive" then dungeonChoice = "BeeHiveArea"
        else dungeonChoice = "CublinDungeon" end
    end
})

TabDungeon:CreateToggle({ Name="Auto Dungeon", CurrentValue=false, Flag="AutoDungeon",
    Callback=function(v)
        autoDungeon = v
        if v then
            -- dungeon overrides other farm modes
            autoQuest = false; autoHarvest = false
            killAll=false; mineAll=false; chopAll=false; harvestAll=false
            selEnemies = {}; selOres = {}; selWood = {}; selHarvest = {}
            recompute()
            dungeonBossWasSeen = false
            dungeonStatus = "starting — heading to start zone..."
            task.spawn(gotoDungeonSpawn)
        else
            dungeonStatus = "idle"
        end
    end })

TabDungeon:CreateSection("Status")
local dungeonLabel = TabDungeon:CreateLabel("Status: idle")
TabDungeon:CreateButton({ Name="Re-TP to Start Zone", Callback=function()
    task.spawn(function()
        local pos = getStartZonePos()
        if pos then
            pcall(function()
                hrp.CFrame = CFrame.new(pos + Vector3.new(0,3,0))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end)
            dungeonStatus = "moved to start zone"
        else
            dungeonStatus = "start zone not found"
        end
    end)
end })
task.spawn(function()
    while task.wait(1) do
        local def = DUNGEONS[dungeonChoice]
        local nm = def and def.label or dungeonChoice
        pcall(function()
            dungeonLabel:Set(string.format("[%s] %s", nm, dungeonStatus))
        end)
    end
end)


-- ── Auto Quest ─────────────────────────────────────────────
TabQuest:CreateParagraph({ Title="How it works", Content=
    "Pick a quest and hit Accept — the script fires the game's DialogEvent\n" ..
    "(StartQuest) at the right NPC, crawling workspace.NPCs and verifying the\n" ..
    "quest lands in Player.Quests. Auto-Farm then does exactly what the quest\n" ..
    "needs: kills enemies AND harvests bushes (auto-swaps weapon/shears per\n" ..
    "target). Quests auto-complete and reward themselves once requirements are\n" ..
    "met — no turn-in needed. Fishing/collect objectives are skipped." })

TabQuest:CreateSection("Control")
TabQuest:CreateToggle({ Name="Auto-Farm Active Quest Targets", CurrentValue=false, Flag="AutoQuest",
    Callback=function(v)
        autoQuest = v
        if v then
            autoDungeon = false; autoHarvest = false
            killAll=false; mineAll=false; chopAll=false; harvestAll=false
            selEnemies = {}; selOres = {}; selWood = {}; selHarvest = {}
            autoKill=false; autoOre=false; autoWood=false
        end
    end })

TabQuest:CreateSection("Accept Quest")
local questOptions = {}
do
    local defs = RS:FindFirstChild("Quests")
    local normal = defs and defs:FindFirstChild("Normal")
    if normal then
        for _, q in ipairs(normal:GetChildren()) do questOptions[#questOptions+1] = q.Name end
        table.sort(questOptions)
    end
    if #questOptions == 0 then questOptions = { "(no quests found)" } end
end
local selectedQuest = questOptions[1]
TabQuest:CreateDropdown({ Name="Quest", Options=questOptions, CurrentOption={questOptions[1]}, Flag="QuestPick",
    Callback=function(opt) selectedQuest = typeof(opt)=="table" and opt[1] or opt end })
TabQuest:CreateButton({ Name="Accept Selected Quest", Callback=function()
    task.spawn(function()
        questActionMsg = "Accepting '" .. tostring(selectedQuest) .. "'..."
        local ok, msg = acceptQuest(selectedQuest)
        questActionMsg = (ok and "Accepted: " or "Accept failed: ") .. tostring(msg)
    end)
end })
local questActionLabel = TabQuest:CreateLabel("Last action: —")
task.spawn(function()
    while task.wait(1) do
        if questActionMsg ~= "" then
            pcall(function() questActionLabel:Set("Last action: " .. questActionMsg) end)
        end
    end
end)

TabQuest:CreateSection("Active Quests")
local questLabel = TabQuest:CreateLabel("No active quests found.")
task.spawn(function()
    while task.wait(1.5) do
        local reqs = getQuestRequirements()
        local txt
        if #reqs == 0 then
            txt = "No active quests found."
        else
            local lines = {}
            for _, r in ipairs(reqs) do
                local reqTxt = r.req and tostring(r.req) or "?"
                local mark = r.done and "DONE" or (r.farmable and "farming" or "not auto-farmable")
                lines[#lines+1] = string.format("%s: %s %d/%s [%s]", r.quest, r.target, r.cur, reqTxt, mark)
            end
            txt = table.concat(lines, "  |  ")
        end
        pcall(function() questLabel:Set(txt) end)
    end
end)

-- ── Boss Timers ────────────────────────────────────────────
TabTimers:CreateParagraph({ Title="How it works", Content=
    "Two kinds of tracked bosses:\n" ..
    "• RESPAWN minibosses: Cylindery auto-respawns at his shrine every ~64s\n" ..
    "  (wiki-sourced) — the timer shows when he should be up again.\n" ..
    "• SUMMON bosses (Crab Champion, Duke, Enormous Ballzo, Glacier Giant,\n" ..
    "  Jimbee, Musheynator, Orbdenier, Pharaoh's Curse) only appear when\n" ..
    "  summoned — the timer shows the ~15 min summon cooldown (wiki-sourced).\n" ..
    "In-area, the script measures the real gone->reappear time and calibrates\n" ..
    "itself ('measured'). Out of area, use 'Mark killed' to start it manually." })
TabTimers:CreateSlider({ Name="Summon cooldown default (min)", Range={1,60}, Increment=1, CurrentValue=15, Flag="BossInt",
    Callback=function(v)
        -- adjusts only summon bosses that haven't been calibrated from observation
        -- (Cylindery's 64s respawn default is sourced and stays untouched)
        for _, name in ipairs(SUMMON_BOSSES) do
            local st = bossState[name]
            if not st.measured then st.interval = v*60 end
        end
    end })

local bossLabels = {}
TabTimers:CreateSection("Respawn Minibosses")
for _, name in ipairs(RESPAWN_MINIBOSSES) do
    bossLabels[name] = TabTimers:CreateLabel(name .. ": --")
end

TabTimers:CreateSection("Summon Boss Cooldowns")
for _, name in ipairs(SUMMON_BOSSES) do
    bossLabels[name] = TabTimers:CreateLabel(name .. ": --")
end

TabTimers:CreateSection("Mark Killed (manual)")
for _, name in ipairs(TRACKED_NAMES) do
    TabTimers:CreateButton({ Name="Mark "..name.." killed", Callback=function()
        local st = bossState[name]
        st.seen = false
        st.lastDeath = os.time()
        st.nextReady = os.time() + st.interval
    end})
end

-- live updater for boss timer labels
local function fmtCD(sec)
    if sec < 120 then return string.format("%ds", sec) end
    return string.format("%dm", math.floor(sec/60))
end
task.spawn(function()
    while task.wait(1) do
        for _, name in ipairs(TRACKED_NAMES) do
            local st = bossState[name]
            local tag = st.measured and "measured" or "default"
            local cds = fmtCD(st.interval)
            local txt
            if st.kind == "respawn" then
                if st.seen then
                    txt = string.format("%s: UP NOW  (~%s respawn, %s)", name, cds, tag)
                elseif st.nextReady then
                    local rem = st.nextReady - os.time()
                    if rem <= 0 then
                        txt = string.format("%s: SHOULD BE UP  (~%s, %s)", name, cds, tag)
                    else
                        txt = string.format("%s: respawns in %d:%02d  (~%s, %s)", name, math.floor(rem/60), rem%60, cds, tag)
                    end
                else
                    txt = string.format("%s: -- no data yet  (~%s respawn, %s)", name, cds, tag)
                end
            else -- summon
                if st.seen then
                    txt = string.format("%s: ALIVE NOW  (summon cd ~%s, %s)", name, cds, tag)
                elseif st.nextReady then
                    local rem = st.nextReady - os.time()
                    if rem <= 0 then
                        txt = string.format("%s: SUMMON READY  (cd ~%s, %s)", name, cds, tag)
                    else
                        txt = string.format("%s: summonable in %d:%02d  (cd ~%s, %s)", name, math.floor(rem/60), rem%60, cds, tag)
                    end
                else
                    txt = string.format("%s: -- no data yet  (summon cd ~%s, %s)", name, cds, tag)
                end
            end
            pcall(function() bossLabels[name]:Set(txt) end)
        end
    end
end)

-- ── Extras ─────────────────────────────────────────────────
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

-- ── ESP ────────────────────────────────────────────────────
TabESP:CreateSection("Mob Highlight ESP")
TabESP:CreateToggle({ Name="Enable ESP", CurrentValue=false, Flag="ESP",
    Callback=function(v) espEnabled=v end })
TabESP:CreateParagraph({ Title="ESP Details", Content=
    "Highlights every enemy in the area. HP bar, HP/MaxHP, distance.\nBosses = orange + [BOSS] tag. Shows through walls." })
