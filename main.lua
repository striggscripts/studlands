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
    LoadingSubtitle = "Geoptimaliseerd",
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
        -- Controleer of de remote event daadwerkelijk bestaat voor veiligheid
        local remote = workspace:FindFirstChild("Remotes") and workspace.Remotes:FindFirstChild("UseItem")
        if remote then
            remote:FireServer(tool, false)
        end
    end
end

local function removeCooldown(tool)
    if not noCooldownEnabled then return end
    local deb = tool:FindFirstChild("Cooldown")
             or tool:FindFirstChild("AttackCooldown")
             or tool:FindFirstChild("AttackDebounce")
    if deb and deb:IsA("NumberValue") then
        deb.Value = 0
        -- Voorkom geheugenlekken met een simpele update
        deb.Changed:Connect(function() 
            if noCooldownEnabled then deb.Value = 0 end 
        end)
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
-- Unified Autofarm Loop (Performance boost)
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.5) do
        if autoTeleporting or autoWoodEnabled or autoKilling then
            updateToolStatus()
