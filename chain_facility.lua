--[[
	chain.lol | gamesense-mps
	Complete UI refactor: Obsidian UI library  ->  Facility UI library.

	How the old API was mapped (see the chat summary for the full list):
	- Old state reads:
	    Toggles.X.Value            -> Flags.X            (Flags = Library.Flags)
	    Options.X.Value            -> Flags.X
	    Options["Name"..v].Value   -> Flags["Name"..v]
	    Toggles.X and Toggles.X.Value -> Flags.X
	  Facility keeps every control value inside Library.Flags (booleans, numbers,
	  strings, #RRGGBBAA hex colors, keybind names). Color pickers additionally
	  keep a live handle in the UI table (UI.X.Color / UI.X.Alpha) because the
	  hex string alone is not a Color3.
	- Old :OnChanged() handlers are attached as deferred Callbacks on the element
	  option tables (Cb.X.Callback = ...) at the exact point in the script where
	  the old code registered them. Facility reads opts.Callback at fire time, so
	  callbacks still never fire at element creation and fire exactly once per
	  change (user interaction or programmatic :Set()).
	- Old :SetValue() / :SetValueRGB() -> element api :Set() through the UI table.
- Facility has no tabbox subtabs: the six Reach subtabs (Shoot/Pass/Long/
  Tackle/Dribble/Save) are replicated with a nested tree sidebar - a vertical
  filtering navigation where parent categories (Attacking / Playmaking /
  Defending) expand and collapse, each child connects to its parent through
  tree-view branch lines, and clicking a child pages that move's section
  card (section.Frame - hiding the card itself, never just its inner
  content). All theme-tracked via Library:Tag, like the library's own tab
  buttons; mobile keeps the single "Main" reach section, like before.
- Ball selection is a single dropdown in the Reach "Main" band now (it used
  to repeat inside every subtab); the reach logic reads it for every move.
- Full-width sections ("multisections") with Split sub-columns are used for
  the Reach main controls, per-move reach pages, advanced boosts and the
  Visuals tab; secondary sliders live in Toggle:Gear() popups (Facility's
  built-in per-toggle settings panels).
- The character/tool preview is now a Library:Panel() - a themed, draggable,
  collapsible floating panel docked to the right of the main window, built
  from the same palette/font as the rest of the UI (it used to be a fully
  custom ScreenGui with its own hardcoded colors).
- Facility has no SetNotifySide(): the notification side is replicated by
  repositioning the library's notification holder (Left/Bottom-Left).
- Facility has no SetDPIScale(): "DPI Scale" now maps onto the library's
  Window:SetUserScale (supported range 60% - 140%); the preview panel's own
  UIScale is kept in sync so both windows scale together.
- New, UI-only niceties that did not exist in the old script: "UI Opacity"
  (Window:SetOpacity), a server browser toggle, a live status card in Miscs,
  sidebar tab dividers, and value suffixes on millisecond sliders.
- One font everywhere: the preview, FPS counter and booster HUD labels all
  follow the Facility theme font and refresh on every theme repaint.
- "Instant Shoot Swap" (toggle + hotkey + hook) was removed on request; the
  general PowerShot tool-swap timing (Tool Swap Delay) is untouched.
- The preview character now rebuilds automatically on respawn (the old
  script needed a manual "Rebuild Character" press).
- The B3rnyGuard namecall bypass (B3rnyGuardian report swallow +
  GetClosestPointOnSurface passthrough) is now a toggle, "B3rnyGuard Bypass"
  in Miscs -> Utility, saved with configs like everything else.
  All other game logic is untouched.
	- The old "Risky" toggle styling maps onto Facility's "danger" label style.
	- Old toggle tooltips map onto Facility's Hint ("?" hover).
	- SaveManager:LoadAutoloadConfig() was moved to the very END of the script so
	  autoloaded settings apply after every listener has been registered (the old
	  script loaded the config before most :OnChanged() handlers even existed).
]]

if getgenv().gamesense and getgenv().gamesense.loaded then
	warn("chain STOP SPAMMING!!!!!!!!!!!!!!")
	return
end
getgenv().gamesense = {loaded = true}

local Activated = false

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TextChatService = game:GetService("TextChatService")
local HTTPService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")

local isWindowFocused = true

UserInputService.WindowFocused:Connect(function()
	isWindowFocused = true
end)

UserInputService.WindowFocusReleased:Connect(function()
	isWindowFocused = false
end)

-- Facility UI library (replaces the Obsidian library and its addons;
-- Facility ships its own SaveManager/ThemeManager/InterfaceManager addons)
local repo = "https://raw.githubusercontent.com/FacilityHUB/UI-Facility-Test/refs/heads/main/"
local Library = loadstring(game:HttpGet(repo .. "main.luau"))()
local AnimSocket = loadstring(game:HttpGet("https://raw.github.com/0zbug/AnimSocket/main/main.lua"))()

local SaveManager = Library.SaveManager
local ThemeManager = Library.ThemeManager

-- Facility keeps every control value in Library.Flags:
--   old Toggles.X.Value / Options.X.Value  ->  Flags.X
--   old Options["Name"..value].Value        ->  Flags["Name"..value]
local Flags = Library.Flags
local UI = {} -- element api handles: programmatic :Set(...) calls + live .Color/.Alpha for pickers
local Cb = {} -- element option tables; .Callback is attached later, exactly where the old
               -- script registered :OnChanged(), so callbacks never fire on creation
local PreviewPanel -- Facility floating panel that hosts the character/tool preview
               -- (forward-declared here because the DPI-scale callback and the preview
               --  builder both touch it; the panel itself is created in the preview part)

-- Facility has no SetNotifySide(): replicate the old Left/Right notification side by
-- repositioning the library's notification holder whenever a notification is shown.
local NotifySide = "Right"
local function ApplyNotifySide()
	local holder = Library.NotifyHolder
	if not holder then return end
	local layout = holder:FindFirstChildOfClass("UIListLayout")
	if NotifySide == "Left" then
		holder.AnchorPoint = Vector2.new(0, 1)
		holder.Position = UDim2.new(0, 18, 1, -18)
		if layout then layout.HorizontalAlignment = Enum.HorizontalAlignment.Left end
	else
		holder.AnchorPoint = Vector2.new(1, 1)
		holder.Position = UDim2.new(1, -18, 1, -18)
		if layout then layout.HorizontalAlignment = Enum.HorizontalAlignment.Right end
	end
end

do
	local rawNotify = Library.Notify
	function Library:Notify(opts, text, duration)
		rawNotify(self, opts, text, duration)
		ApplyNotifySide()
	end
end

local function Notify(info)
	Library:Notify(info)
end

-- Default theme: the original "chain" palette (dark gray + pink accent, brighter
-- text) is registered as a Facility theme preset named "chain" and applied when the
-- user has not saved a theme of their own yet. It stays editable from the theme
-- editor modal (paintbrush icon in the window footer).
local THEME_FOLDER = "gamesense-mps"
local chainThemeReady = false
if ThemeManager then
	chainThemeReady = pcall(function()
		ThemeManager:SetLibrary(Library)
		ThemeManager:SetFolder(THEME_FOLDER)
		ThemeManager.Presets.chain = { Bg = Color3.fromRGB(28, 28, 28), Accent = Color3.fromRGB(219, 68, 103) }
		if not table.find(ThemeManager.Order, "chain") then
			table.insert(ThemeManager.Order, 1, "chain")
		end
		if not ThemeManager:Load() then
			ThemeManager:Apply("chain")
			-- nudge the text colors toward the original white-on-dark look
			local Theme = Library.Theme
			Theme.Text = Color3.fromRGB(222, 222, 226)
			Theme.TextDim = Color3.fromRGB(138, 138, 144)
			Theme.TextBright = Color3.fromRGB(244, 244, 248)
			ThemeManager:Save()
		end
	end)
end
if not chainThemeReady then
	-- fallback palette in case the ThemeManager addon could not be loaded
	local Theme = Library.Theme
	Theme.Window = Color3.fromRGB(28, 28, 28)
	Theme.TopBar = Color3.fromRGB(33, 33, 33)
	Theme.Section = Color3.fromRGB(31, 31, 31)
	Theme.Group = Color3.fromRGB(36, 36, 36)
	Theme.Field = Color3.fromRGB(42, 42, 42)
	Theme.FieldHover = Color3.fromRGB(50, 50, 50)
	Theme.PopupBg = Color3.fromRGB(40, 40, 40)
	Theme.Track = Color3.fromRGB(60, 60, 60)
	Theme.WindowBorder = Color3.fromRGB(54, 54, 54)
	Theme.SectionBorder = Color3.fromRGB(48, 48, 48)
	Theme.GroupBorder = Color3.fromRGB(56, 56, 56)
	Theme.Border = Color3.fromRGB(62, 62, 62)
	Theme.BorderSoft = Color3.fromRGB(47, 47, 47)
	Theme.PopupBorder = Color3.fromRGB(64, 64, 64)
	Theme.Accent = Color3.fromRGB(219, 68, 103)
	Theme.AccentSoft = Color3.fromRGB(238, 132, 152)
	Theme.AccentDim = Color3.fromRGB(146, 45, 68)
	Theme.Text = Color3.fromRGB(222, 222, 226)
	Theme.TextDim = Color3.fromRGB(138, 138, 144)
	Theme.TextBright = Color3.fromRGB(244, 244, 248)
end

local Window = Library:Window({
	Title = "chain",
	Suffix = ".lol",         -- renders as "chain.lol" in the top bar
	Folder = THEME_FOLDER,   -- theme.json location (matches the ThemeManager folder)
	Width = 700,
	Height = 600,
	MinWidth = 560,
	MinHeight = 380,
	TabStyle = "side",       -- side tab list, like the old window
	TabWidth = 132,
	Cursor = false,          -- custom crosshair cursor disabled by default
	                         -- (the "Custom Cursor" toggle in UI Settings can re-enable it)
	-- "Right" notifications are Facility's default side; a mobile toggle button is
	-- created automatically on touch devices.
})

-- footer credit (the old window footer text)
Window:Action("all rights reserved to chain")

local Tabs = {}
local Dump = { BallPrediction = {} }

local PLACE_MMP = 9847297509
local PLACE_VEF = 128369064996026
local PLACE_RMF = 72601060985318
local CURRENT_PLACE = game.PlaceId

local IS_MMP = false
local IS_VEF = false
local IS_RMF = false
local IS_4ASIDE = false
local IS_LEGACY = false
local NO_FOLDER = false

if CURRENT_PLACE == PLACE_MMP then
	IS_MMP = true
elseif CURRENT_PLACE == PLACE_VEF then
	IS_VEF = true
elseif CURRENT_PLACE == PLACE_RMF then
	IS_RMF = true
end

local IS_VEF_LIKE = IS_VEF or IS_RMF

local BALL_NAMES = {
	ballPart = true, ROFI = true, fakeBall = true, MPS = true, TPS = true,
	CSF = true, ["l̸̼̔il̷͎̅ḭ̴͘iḮ̷̙il̶̼̈́il̴̘̕Ĩ̵̹į̴̌"] = true,
	SAML = true, VEF = true, VFA = true, VRF = true, CMP = true
}

local SHOOT_MOVES = {
	{name = "Shoot", label = "Shoot", default = true},
	{name = "Bicycle_Kick", label = "Bicycle Kick", default = false},
	{name = "Scorpion_Kick", label = "Scorpion Kick", default = false},
	{name = "Scissor_Kick", label = "Scissor Kick", default = false},
	{name = "Volley", label = "Volley", default = false},
	{name = "Header", label = "Header", default = false},
	{name = "Diving_Header", label = "Diving Header", default = false},
}

local SHOOT_TOOL_NAMES = {
	Shoot = true, Kick = true, Volley = true, Header = true,
	Diving_Header = true, Bicycle_Kick = true,
	Scorpion_Kick = true, Scissor_Kick = true,
}

local CURVE_ENABLED_MOVES = { Shoot = true, Volley = true }
local MULTIHIT_MOVES = { Dribble_C = true, Pass_F = true }

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")

local BallsFolder = nil
local MainModule = nil
local MainModuleTable = nil
local EventsFolder = nil
local PingRemote = nil
local PingHandler = nil
local _BALLS = {}

local LastToolEquipTime = 0
local function TrackToolEquips(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			LastToolEquipTime = tick()
		end
	end)
end

local function RebuildBallList()
	table.clear(_BALLS)
	for _, Ball in ipairs(workspace:GetChildren()) do
		if BALL_NAMES[Ball.Name] then
			table.insert(_BALLS, Ball)
		end
	end
end

local function IsBallOwnedByLocalPlayer(ball)
	if not ball then return false end

	-- ATPS / MMP Values folder ownership check
	local values = ball:FindFirstChild("Values")
	if values then
		local ownerTag = values:FindFirstChild("Owner")
		if ownerTag and ownerTag.Value == LocalPlayer then
			return true
		end
	end

	-- Fallback direct Owner tag check
	local ownerTag = ball:FindFirstChild("Owner") or ball:FindFirstChild("owner")
	if ownerTag then
		if ownerTag.Value == LocalPlayer or ownerTag.Value == LocalPlayer.Name or ownerTag.Value == LocalPlayer.UserId then
			return true
		end
	end

	return false
end

local function GetClosestGuardBall(pos, maxRange, compMode)
	local closest, closestDist = nil, maxRange or math.huge

	local function processBall(v)
		if not (v and v:IsA("BasePart")) then return end
		if compMode and IsBallOwnedByLocalPlayer(v) then return end

		local dist = (pos - v.Position).Magnitude
		if dist < closestDist then
			closestDist = dist
			closest = v
		end
	end

	if NO_FOLDER then
		for _, ball in ipairs(_BALLS) do
			processBall(ball)
		end
	elseif BallsFolder then
		for _, ball in ipairs(BallsFolder:GetChildren()) do
			processBall(ball)
		end
	end

	return closest
end

if LocalPlayer.Backpack:FindFirstChild("ToolManagement") then
	MainModule = LocalPlayer.Backpack:WaitForChild("ToolManagement")
	if not IS_VEF and not IS_RMF then IS_MMP = true end
elseif LocalPlayer.Backpack:FindFirstChild("ToolManagment") then
	MainModule = LocalPlayer.Backpack:WaitForChild("ToolManagment")
	IS_LEGACY = true
	if not IS_MMP and not IS_RMF then IS_VEF = true end
	IS_VEF_LIKE = IS_VEF or IS_RMF
elseif LocalPlayer.Backpack:FindFirstChild("module") then
	MainModule = LocalPlayer.Backpack:WaitForChild("module")
	IS_4ASIDE = true
	if not IS_MMP and not IS_RMF then IS_VEF = true end
	IS_VEF_LIKE = IS_VEF or IS_RMF
end

if MainModule then
	pcall(function() MainModuleTable = require(MainModule) end)
end

if IS_MMP then
	local ok, folder = pcall(function()
		return workspace:WaitForChild("Game", 5):WaitForChild("Interactive", 5):WaitForChild("Balls", 5)
	end)
	if ok and folder then
		BallsFolder = folder
	else
		NO_FOLDER = true
		RebuildBallList()
	end
else
	if workspace:FindFirstChild("Balls", true) then
		BallsFolder = workspace:FindFirstChild("Balls", true)
	else
		NO_FOLDER = true
		RebuildBallList()
	end
end

if ReplicatedStorage:FindFirstChild("Events") or ReplicatedStorage:FindFirstChild("Event") then
	EventsFolder = ReplicatedStorage:FindFirstChild("Events") or ReplicatedStorage:FindFirstChild("Event")
end
if ReplicatedStorage:FindFirstChild("UpdatePing") or (EventsFolder and EventsFolder:FindFirstChild("UpdatePing")) then
	PingRemote = ReplicatedStorage:FindFirstChild("UpdatePing") or EventsFolder:FindFirstChild("UpdatePing")
end
if LocalPlayer.PlayerScripts:FindFirstChild("PingHandler") or LocalPlayer.PlayerScripts:FindFirstChild("ClientPing") then
	PingHandler = LocalPlayer.PlayerScripts:FindFirstChild("PingHandler") or LocalPlayer.PlayerScripts:FindFirstChild("ClientPing")
end

TrackToolEquips(Character)

local function HotkeyMasterOn()
	return Flags.EnableHotkeyBoosters == true
end

-- "Instant Shoot Swap" was removed on request; the general PowerShot swap
-- timing (InsanePowerSwapDelay) is untouched.

local function NukeBallManager()
	if not IS_MMP then return end
	pcall(function()
		local char = LocalPlayer.Character
		if not char then return end
		for _, obj in ipairs(char:GetDescendants()) do
			if obj.Name == "BallManager" and (obj:IsA("LocalScript") or obj:IsA("Script")) then
				obj:Destroy()
			end
		end
	end)
end
local function NukeAntiCheatRemote()
	if not IS_MMP then return end
	pcall(function()
		local events = ReplicatedStorage:FindFirstChild("Events")
		if events then
			local ac = events:FindFirstChild("AntiCheat")
			if ac then ac:Destroy() end
		end
	end)
end
local function ApplyAntiRigBreak()
	NukeBallManager()
	NukeAntiCheatRemote()
end
local function WatchCharacterForBallManager(char)
	if not IS_MMP then return end
	if not char then return end
	char.DescendantAdded:Connect(function(desc)
		if desc.Name == "BallManager" and (desc:IsA("LocalScript") or desc:IsA("Script")) then
			task.wait()
			pcall(function() desc:Destroy() end)
		end
	end)
end
if IS_MMP then
	local events = ReplicatedStorage:FindFirstChild("Events")
	if events then
		events.ChildAdded:Connect(function(child)
			if child.Name == "AntiCheat" then
				task.wait()
				pcall(function() child:Destroy() end)
			end
		end)
	end
end
task.spawn(function()
	task.wait(0.5)
	ApplyAntiRigBreak()
	WatchCharacterForBallManager(Character)
end)

local ReachBox = Instance.new("Part")
ReachBox.Name = tostring(math.random(100000, 999999))
ReachBox.Size = Vector3.new(0, 0, 0)
ReachBox.CFrame = CFrame.new(math.huge, math.huge, math.huge)
ReachBox.Anchored = true
ReachBox.CanCollide = false
ReachBox.CanTouch = true
ReachBox.CanQuery = false
ReachBox.Massless = true
ReachBox.Transparency = 0.9
ReachBox.Material = Enum.Material.SmoothPlastic
ReachBox.CastShadow = false
ReachBox.Parent = workspace

local GS_OVERLAY = Instance.new("ScreenGui")
GS_OVERLAY.Name = tostring(math.random(100000, 999999))
GS_OVERLAY.IgnoreGuiInset = true
GS_OVERLAY.DisplayOrder = 999998
GS_OVERLAY.ResetOnSpawn = false
GS_OVERLAY.Parent = game:GetService("CoreGui")

local Dumbass = Instance.new("ImageLabel")
Dumbass.Name = "Dumbass"
Dumbass.AnchorPoint = Vector2.new(1, 1)
Dumbass.BackgroundColor3 = Color3.new(0, 0, 0)
Dumbass.BackgroundTransparency = 1
Dumbass.Position = UDim2.new(1, 25, 1, 15)
Dumbass.Size = UDim2.new(0, 150, 0, 300)
Dumbass.Image = "rbxassetid://95334651149795"
Dumbass.Visible = false
Dumbass.Parent = GS_OVERLAY

local BallESPFolder = Instance.new("Folder")
BallESPFolder.Name = "GS_ESP_"..tostring(math.random(100000,999999))
BallESPFolder.Parent = game:GetService("CoreGui")

local function IsInsideLinesModel(obj)
	local p = obj
	while p and p ~= workspace do
		if p.Name == "Lines" then return true end
		p = p.Parent
	end
	return false
end
local function SetPitchColor(color)
	pcall(function()
		local pitch = workspace:FindFirstChild("Pitch")
		if pitch then
			local grass = pitch:FindFirstChild("Grass")
			if grass and grass:IsA("BasePart") then grass.Color = color end
		end
		local gameFolder = workspace:FindFirstChild("Game")
		if gameFolder then
			local pitchM = gameFolder:FindFirstChild("Pitch")
			if pitchM then
				local field = pitchM:FindFirstChild("Field")
				if field then
					local grassContainer = field:FindFirstChild("Grass")
					if grassContainer then
						if grassContainer:IsA("BasePart") then
							grassContainer.Color = color
						else
							for _, obj in ipairs(grassContainer:GetDescendants()) do
								if obj:IsA("BasePart") and (obj.Name == "Grass" or obj.Name == "MainGrass") and not IsInsideLinesModel(obj) then
									obj.Color = color
								end
							end
						end
					end
					local mainGrass = field:FindFirstChild("MainGrass")
					if mainGrass and mainGrass:IsA("BasePart") then mainGrass.Color = color end
				end
			end
		end
	end)
end
local function EnforceWhiteLines()
	pcall(function()
		local gameFolder = workspace:FindFirstChild("Game")
		if not gameFolder then return end
		local pitch = gameFolder:FindFirstChild("Pitch")
		if not pitch then return end
		local field = pitch:FindFirstChild("Field")
		if not field then return end
		for _, obj in ipairs(field:GetDescendants()) do
			if obj:IsA("BasePart") and IsInsideLinesModel(obj) then
				obj.Color = Color3.fromRGB(255, 255, 255)
			end
		end
	end)
end

local function quadraticSolver(a, b, c)
	local disc = math.sqrt((b*b) - 4 * a * c)
	local x1 = (-b + disc) / (2 * a)
	local x2 = (-b - disc) / (2 * a)
	return x2 > x1 and x2 or x1
end
local function findTimeAtHeight(a, vel, h, startingH)
	local x = h - startingH
	local disc = math.sqrt((vel * vel) + 2 * a * x)
	local x1 = (disc - vel) / a
	local x2 = -(disc + vel) / a
	return x2 > x1 and x2 or x1
end
local function findHeightAtTime(vel, t, acc)
	return vel.Y * t + 0.5 * -acc * (t*t)
end
local function findPositionAtTime(vel, t, startingPos, acc)
	local height = findHeightAtTime(vel, t, acc)
	return startingPos + Vector3.new(vel.X * t, height, vel.Z * t)
end
local function findLandingPosition(Vo, startingPosition, acc, max)
	local seconds = quadraticSolver((0.5 * -acc), Vo.Y, startingPosition.Y)
	local lastPosition = startingPosition
	for i = 1, max do
		local t = seconds * (1/max * i)
		local nextPosition = findPositionAtTime(Vo, t, startingPosition, acc)
		local result = workspace:Raycast(lastPosition, (nextPosition - lastPosition))
		if result then
			local baseHeight = result.Position.Y
			local timeAtHeight = findTimeAtHeight(-acc, Vo.Y, baseHeight, startingPosition.Y)
			return findPositionAtTime(Vo, timeAtHeight, startingPosition, acc)
		end
		lastPosition = nextPosition
	end
	local horizontalVel = Vector3.new(Vo.X, 0, Vo.Z)
	return startingPosition + (horizontalVel * seconds) + Vector3.new(0, findHeightAtTime(Vo, seconds, acc), 0)
end

local function ClearDump(DumpType)
	for _, DumpInstance in ipairs(Dump[DumpType]) do
		if DumpInstance:IsA("Instance") then DumpInstance:Destroy() end
	end
	table.clear(Dump[DumpType])
end

local function PredictBall(Ball)
	local LandingPosition = findLandingPosition(Ball.AssemblyLinearVelocity, Ball.Position, workspace.Gravity, Flags.BallPredAccuracy)
	local BallPredAtt0 = Instance.new("Attachment")
	BallPredAtt0.WorldPosition = Ball.Position
	BallPredAtt0.Parent = workspace.Terrain
	table.insert(Dump.BallPrediction, BallPredAtt0)
	local BallPredAtt1 = Instance.new("Attachment")
	BallPredAtt1.WorldPosition = LandingPosition
	BallPredAtt1.Parent = workspace.Terrain
	table.insert(Dump.BallPrediction, BallPredAtt1)
	local BallPredBeam = Instance.new("Beam")
	BallPredBeam.Color = ColorSequence.new(UI.BallPredTrailColor.Color)
	BallPredBeam.LightEmission = 0
	BallPredBeam.LightInfluence = 0
	BallPredBeam.Brightness = 1
	BallPredBeam.Transparency = NumberSequence.new(1 - UI.BallPredTrailColor.Alpha)
	BallPredBeam.Attachment0 = BallPredAtt0
	BallPredBeam.Attachment1 = BallPredAtt1
	BallPredBeam.FaceCamera = true
	BallPredBeam.Width0 = Flags.BallPredTrailSize
	BallPredBeam.Width1 = Flags.BallPredTrailSize
	BallPredBeam.Parent = Ball
	table.insert(Dump.BallPrediction, BallPredBeam)
end

Tabs.Reach = Window:Tab("Reach", "footprints")
Tabs.Ball = Window:Tab("Ball", "volleyball")
Tabs.Character = Window:Tab("Character", "volleyball")
Tabs.Visuals = Window:Tab("Visuals", "eye")
Tabs.Preview = Window:Tab("Preview", "user")
Window:TabDivider()
Tabs.Miscs = Window:Tab("Miscs", "ellipsis")
Window:TabDivider()
Tabs.Config = Window:Tab("UI Settings", "settings")

-- ===========================================================================
-- Reach
-- ===========================================================================
-- Facility has no tabbox subtabs, so the old six-subtab Reach tabbox is
-- replicated with a segmented strip (built below) that pages full-width
-- sections: only the selected move's section is visible at a time, exactly
-- like the old tabbox. Mobile keeps the single flat "Main" section, as before.

local ReachMainGroupbox = Tabs.Reach:Section("Main", "full")
local ReachMainSection, ReachShootSection, ReachPassSection, ReachLongSection,
	ReachTackleSection, ReachDribbleSection, ReachSaveSection

ReachMainGroupbox:Split({
	function(left)
		left:Toggle({ Flag = "ReachMasterToggle", Text = "Enabled" })
		UI.ReachVisualizerToggle = left:Toggle({ Flag = "ReachVisualizerToggle", Text = "Visualizer" })
		UI.ReachVisualizerToggle:ColorPicker({ Flag = "ReachVisualizerColor", Default = Color3.new(1, 1, 1) })
		UI.ReachVisualizerColor = UI.ReachVisualizerToggle.Pickers[1]
	end,
	function(right)
		right:Slider({ Flag = "ReachVisualizerTransparency", Text = "Visualizer Transparency", Default = 0.7, Min = 0, Max = 1, Decimals = 2, Step = 0.01 })
		right:Slider({ Flag = "ReachDebounceMs", Text = "DC (ms)", Default = 150, Min = 0, Max = 500, Decimals = 0, Suffix = " ms" })
		right:Label("MMP only. Cooldown for Dribble_C and Pass_F.", { Style = "dim", TextSize = 11 })
		-- ball selection applies to every move now (it used to be per-subtab)
		right:Dropdown({ Flag = "ReachMainBallSelector", Text = "Ball Selection",
			Options = {"Closest to character", "Furthest to character"}, Default = "Closest to character" })
	end,
})

-- one flat reach page (used directly on mobile, and as the subtab builder
-- target shape on desktop)
local function CreateReachTab(TabsElement, ReachType)
	TabsElement:Toggle({ Flag = "Reach"..ReachType.."Toggle", Text = "Enabled" })
	TabsElement:Toggle({ Flag = "InfiniteReach"..ReachType.."Toggle", Text = "Infinite Reach", Style = "danger" })
	TabsElement:Toggle({ Flag = "Reach"..ReachType.."CompToggle", Text = "Comp Reach" })
	TabsElement:Slider({ Flag = "Reach"..ReachType.."SizeX", Text = "Size X", Default = 0, Min = 0, Max = 200, Decimals = 1, Step = 0.1 })
	TabsElement:Slider({ Flag = "Reach"..ReachType.."SizeY", Text = "Size Y", Default = 0, Min = 0, Max = 200, Decimals = 1, Step = 0.1 })
	TabsElement:Slider({ Flag = "Reach"..ReachType.."SizeZ", Text = "Size Z", Default = 0, Min = 0, Max = 200, Decimals = 1, Step = 0.1 })
	TabsElement:Slider({ Flag = "Reach"..ReachType.."OffsetX", Text = "Offset X", Default = 0, Min = -10, Max = 10, Decimals = 1, Step = 0.1 })
	TabsElement:Slider({ Flag = "Reach"..ReachType.."OffsetY", Text = "Offset Y", Default = 0, Min = -10, Max = 10, Decimals = 1, Step = 0.1 })
	TabsElement:Slider({ Flag = "Reach"..ReachType.."OffsetZ", Text = "Offset Z", Default = 0, Min = -10, Max = 10, Decimals = 1, Step = 0.1 })
end

-- desktop: one full-width page per move, split into toggles / sizes / offsets
local function CreateReachPage(TabsElement, ReachType)
	local page = TabsElement:Full(ReachType)
	page:Split({
		function(toggles)
			toggles:Toggle({ Flag = "Reach"..ReachType.."Toggle", Text = "Enabled" })
			toggles:Toggle({ Flag = "InfiniteReach"..ReachType.."Toggle", Text = "Infinite Reach", Style = "danger" })
			toggles:Toggle({ Flag = "Reach"..ReachType.."CompToggle", Text = "Comp Reach" })
		end,
		function(sizes)
			sizes:Slider({ Flag = "Reach"..ReachType.."SizeX", Text = "Size X", Default = 0, Min = 0, Max = 200, Decimals = 1, Step = 0.1 })
			sizes:Slider({ Flag = "Reach"..ReachType.."SizeY", Text = "Size Y", Default = 0, Min = 0, Max = 200, Decimals = 1, Step = 0.1 })
			sizes:Slider({ Flag = "Reach"..ReachType.."SizeZ", Text = "Size Z", Default = 0, Min = 0, Max = 200, Decimals = 1, Step = 0.1 })
		end,
		function(offsets)
			offsets:Slider({ Flag = "Reach"..ReachType.."OffsetX", Text = "Offset X", Default = 0, Min = -10, Max = 10, Decimals = 1, Step = 0.1 })
			offsets:Slider({ Flag = "Reach"..ReachType.."OffsetY", Text = "Offset Y", Default = 0, Min = -10, Max = 10, Decimals = 1, Step = 0.1 })
			offsets:Slider({ Flag = "Reach"..ReachType.."OffsetZ", Text = "Offset Z", Default = 0, Min = -10, Max = 10, Decimals = 1, Step = 0.1 })
		end,
	})
	return page
end

local ReachPages = {}
local ReachTreeParents = {}
local ActiveReachPage = nil

local function SelectReachPage(name)
	ActiveReachPage = name
	for _, page in ipairs(ReachPages) do
		local active = page.name == name
		-- page the section CARD itself (.Frame, the visible box). Hiding the
		-- card removes it from the column completely - true paging, no gaps,
		-- and no leftover title bars (hiding only the inner .Container would
		-- leave every move's empty card visible)
		page.section.Frame.Visible = active
		-- retag so the active child keeps its colour across theme changes,
		-- the same trick the library uses for its own tab buttons
		Library:Tag(page.button, { TextColor3 = active and "Accent" or "TextDim" })
		page.button.TextColor3 = active and Library.Theme.Accent or Library.Theme.TextDim
		Library:Tag(page.bar, { BackgroundColor3 = "Accent" })
		page.bar.BackgroundTransparency = active and 0 or 1
		if active then
			-- soft fade-in so page switches feel smooth instead of snapping
			local card = page.section.Frame
			card.BackgroundTransparency = 0.3
			TweenService:Create(card, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 0 }):Play()
		end
	end
end

-- Nested Tree Sidebar Subtabs: a vertical sub-category navigation inside the
-- tab. Parent groups expand and collapse via a chevron, every child (the old
-- subtabs) is connected to its parent by tree-view branch lines, and clicking
-- a child filters the page area to that move's section. Styled entirely from
-- the live theme so it repaints together with the rest of the UI.
local function MakeTreeSidebar(tab, groups)
	-- row that holds the sidebar card and the page area side by side
	local row = Instance.new("Frame")
	row.Name = "ReachTreeRow"
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.LayoutOrder = tab.Order + 1
	tab.Order = tab.Order + 1
	row.Parent = tab.Page

	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 12)
	rowList.Parent = row

	-- the sidebar card itself
	local sidebar = Instance.new("Frame")
	sidebar.Name = "ReachTree"
	sidebar.Size = UDim2.new(0, 158, 0, 0)
	sidebar.AutomaticSize = Enum.AutomaticSize.Y
	sidebar.BackgroundColor3 = Library.Theme.Section
	sidebar.BorderSizePixel = 0
	sidebar.LayoutOrder = 1
	sidebar.Parent = row
	Library:Tag(sidebar, { BackgroundColor3 = "Section" })

	local sidebarCorner = Instance.new("UICorner")
	sidebarCorner.CornerRadius = UDim.new(0, 6)
	sidebarCorner.Parent = sidebar
	local sidebarStroke = Instance.new("UIStroke")
	sidebarStroke.Thickness = 1
	sidebarStroke.Parent = sidebar
	Library:Tag(sidebarStroke, { Color = "Border" })

	local sidebarPad = Instance.new("UIPadding")
	sidebarPad.PaddingTop = UDim.new(0, 8)
	sidebarPad.PaddingBottom = UDim.new(0, 6)
	sidebarPad.PaddingLeft = UDim.new(0, 8)
	sidebarPad.PaddingRight = UDim.new(0, 8)
	sidebarPad.Parent = sidebar

	local sideList = Instance.new("UIListLayout")
	sideList.SortOrder = Enum.SortOrder.LayoutOrder
	sideList.Padding = UDim.new(0, 1)
	sideList.Parent = sidebar

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 20)
	caption.BackgroundTransparency = 1
	caption.Text = "moves"
	caption.TextColor3 = Library.Theme.TextDim
	-- NOTE: Theme.Font/FontMedium are Enum.Font values, so they go into the legacy
	-- Font property exactly like the library's own labels (never FontFace)
	caption.Font = Library.Theme.FontMedium or Library.Theme.Font
	caption.TextSize = (Library.Theme.TextSize or 15) - 2
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.LayoutOrder = 0
	caption.Parent = sidebar
	Library:Tag(caption, { TextColor3 = "TextDim" })

	-- the page area the move sections get moved into
	local contentCol = Instance.new("Frame")
	contentCol.Name = "ReachPages"
	contentCol.Size = UDim2.new(1, -170, 0, 0)
	contentCol.AutomaticSize = Enum.AutomaticSize.Y
	contentCol.BackgroundTransparency = 1
	contentCol.LayoutOrder = 2
	contentCol.Parent = row

	local colList = Instance.new("UIListLayout")
	colList.SortOrder = Enum.SortOrder.LayoutOrder
	colList.Padding = UDim.new(0, 14)
	colList.Parent = contentCol

	local order = 1
	for _, group in ipairs(groups) do
		local parent = { name = group.name, expanded = true, rows = {} }

		-- parent row: chevron + category label
		local prow = Instance.new("Frame")
		prow.Size = UDim2.new(1, 0, 0, 26)
		prow.BackgroundTransparency = 1
		prow.LayoutOrder = order; order += 1
		prow.Parent = sidebar

		local chevron = Instance.new("TextLabel")
		chevron.Size = UDim2.new(0, 14, 1, 0)
		chevron.BackgroundTransparency = 1
		chevron.Text = "►"
		chevron.TextColor3 = Library.Theme.TextDim
		chevron.Font = Library.Theme.Font
		chevron.TextSize = (Library.Theme.TextSize or 15) - 3
		chevron.Rotation = 90
		chevron.Parent = prow
		Library:Tag(chevron, { TextColor3 = "TextDim" })

		local pbtn = Instance.new("TextButton")
		pbtn.Size = UDim2.new(1, -16, 1, 0)
		pbtn.Position = UDim2.new(0, 16, 0, 0)
		pbtn.BackgroundTransparency = 1
		pbtn.AutoButtonColor = false
		pbtn.Text = group.name
		pbtn.TextColor3 = Library.Theme.TextBright
		pbtn.Font = Library.Theme.FontMedium or Library.Theme.Font
		pbtn.TextSize = (Library.Theme.TextSize or 15) - 1
		pbtn.TextXAlignment = Enum.TextXAlignment.Left
		pbtn.Parent = prow
		Library:Tag(pbtn, { TextColor3 = "TextBright" })

		parent.button = pbtn
		parent.chevron = chevron
		pbtn.MouseEnter:Connect(function() pbtn.TextColor3 = Library.Theme.Text end)
		pbtn.MouseLeave:Connect(function() pbtn.TextColor3 = Library.Theme.TextBright end)

		-- children: subtab rows connected to the parent by branch lines
		for index, childName in ipairs(group.children) do
			local crow = Instance.new("Frame")
			crow.Size = UDim2.new(1, 0, 0, 24)
			crow.BackgroundTransparency = 1
			crow.LayoutOrder = order; order += 1
			crow.Parent = sidebar
			parent.rows[#parent.rows + 1] = crow

			-- tree-view branch indicator: vertical spine + horizontal twig
			local isLast = index == #group.children
			local vLine = Instance.new("Frame")
			vLine.Position = UDim2.new(0, 7, 0, 0)
			vLine.Size = isLast and UDim2.new(0, 1, 0, 12) or UDim2.new(0, 1, 1, 0)
			vLine.BackgroundColor3 = Library.Theme.BorderSoft
			vLine.BorderSizePixel = 0
			vLine.Parent = crow
			Library:Tag(vLine, { BackgroundColor3 = "BorderSoft" })
			local hLine = Instance.new("Frame")
			hLine.Position = UDim2.new(0, 7, 0, 11)
			hLine.Size = UDim2.new(0, 10, 0, 1)
			hLine.BackgroundColor3 = Library.Theme.BorderSoft
			hLine.BorderSizePixel = 0
			hLine.Parent = crow
			Library:Tag(hLine, { BackgroundColor3 = "BorderSoft" })

			local cbtn = Instance.new("TextButton")
			cbtn.Size = UDim2.new(1, -20, 1, 0)
			cbtn.Position = UDim2.new(0, 20, 0, 0)
			cbtn.BackgroundColor3 = Library.Theme.Field
			cbtn.BackgroundTransparency = 1
			cbtn.AutoButtonColor = false
			cbtn.Text = childName
			cbtn.TextColor3 = Library.Theme.TextDim
			cbtn.Font = Library.Theme.Font
			cbtn.TextSize = (Library.Theme.TextSize or 15) - 1
			cbtn.TextXAlignment = Enum.TextXAlignment.Left
			cbtn.Parent = crow

			-- active marker: accent bar on the left edge, like the library's
			-- own side tab buttons
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 3, 1, -6)
			bar.Position = UDim2.new(0, -6, 0, 3)
			bar.BackgroundColor3 = Library.Theme.Accent
			bar.BackgroundTransparency = 1
			bar.BorderSizePixel = 0
			bar.Parent = cbtn
			local barCorner = Instance.new("UICorner")
			barCorner.CornerRadius = UDim.new(1, 0)
			barCorner.Parent = bar
			Library:Tag(bar, { BackgroundColor3 = "Accent" })

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 4)
			btnCorner.Parent = cbtn
			Library:Tag(cbtn, { BackgroundColor3 = "Field", TextColor3 = "TextDim" })

			cbtn.Activated:Connect(function()
				SelectReachPage(childName)
			end)
			cbtn.MouseEnter:Connect(function()
				TweenService:Create(cbtn,
					TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 0.82 }):Play()
				if ActiveReachPage ~= childName then cbtn.TextColor3 = Library.Theme.Text end
			end)
			cbtn.MouseLeave:Connect(function()
				TweenService:Create(cbtn,
					TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1 }):Play()
				if ActiveReachPage ~= childName then cbtn.TextColor3 = Library.Theme.TextDim end
			end)

			ReachPages[#ReachPages + 1] = { name = childName, button = cbtn, bar = bar, row = crow }
		end

		-- breathing room after each group
		local gap = Instance.new("Frame")
		gap.Size = UDim2.new(1, 0, 0, 7)
		gap.BackgroundTransparency = 1
		gap.LayoutOrder = order; order += 1
		gap.Parent = sidebar

		pbtn.Activated:Connect(function()
			parent.expanded = not parent.expanded
			TweenService:Create(chevron,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Rotation = parent.expanded and 90 or 0 }):Play()
			for _, r in ipairs(parent.rows) do
				r.Visible = parent.expanded
			end
		end)

		ReachTreeParents[#ReachTreeParents + 1] = parent
	end

	return contentCol
end

if UserInputService.TouchEnabled then
	ReachMainSection = Tabs.Reach:Section("Main", 2)
	CreateReachTab(ReachMainSection, "Main")
else
	local ReachPageColumn = MakeTreeSidebar(Tabs.Reach, {
		{ name = "Attacking",  children = { "Shoot", "Long" } },
		{ name = "Playmaking", children = { "Pass", "Dribble" } },
		{ name = "Defending",  children = { "Tackle", "Save" } },
	})
	ReachShootSection = CreateReachPage(Tabs.Reach, "Shoot")
	ReachPassSection = CreateReachPage(Tabs.Reach, "Pass")
	ReachLongSection = CreateReachPage(Tabs.Reach, "Long")
	ReachTackleSection = CreateReachPage(Tabs.Reach, "Tackle")
	ReachDribbleSection = CreateReachPage(Tabs.Reach, "Dribble")
	ReachSaveSection = CreateReachPage(Tabs.Reach, "Save")
	local ReachSections = {
		Shoot = ReachShootSection, Pass = ReachPassSection, Long = ReachLongSection,
		Tackle = ReachTackleSection, Dribble = ReachDribbleSection, Save = ReachSaveSection,
	}
	for _, entry in ipairs(ReachPages) do
		entry.section = ReachSections[entry.name]
		-- reparent the move section CARDS into the sidebar's page area
		entry.section.Frame.Parent = ReachPageColumn
	end
	SelectReachPage("Shoot")
end

-- ===========================================================================
-- Character
-- ===========================================================================

local GuardGroupbox = Tabs.Character:Section("Auto Guard", 1)

local GuardEnabledApi = GuardGroupbox:Toggle({ Flag = "GuardEnabled", Text = "Enabled", Default = false })
-- toggle-synced keybind (the old SyncToggleState picker): pressing the key
-- flips the toggle state, and the keybind is saved with configs
GuardEnabledApi:Keybind({ Flag = "GuardKeybind", Default = "LeftAlt", Mode = "toggle" })

GuardGroupbox:Toggle({ Flag = "GuardCompEnabled", Text = "Comp Guard (Ignore Owned)", Default = false })
GuardGroupbox:Toggle({ Flag = "AntiHizake", Text = "Anti Hizake (Disable if tabbed out)", Default = true })
GuardGroupbox:Slider({ Flag = "GuardRange", Text = "Max Guard Range", Default = 50, Min = 5, Max = 200, Decimals = 0 })
GuardGroupbox:Slider({ Flag = "GuardDistance", Text = "Follow Distance", Default = 0, Min = 0, Max = 20, Decimals = 1, Step = 0.1 })
GuardGroupbox:Slider({ Flag = "GuardPrediction", Text = "Prediction Multiplier", Default = 0.3, Min = 0, Max = 1.5, Decimals = 2, Step = 0.01 })

local CharHumGroupbox = Tabs.Character:Section("Humanoid", 1)
CharHumGroupbox:Toggle({ Flag = "CharSpeedToggle", Text = "Speed", Default = false })
CharHumGroupbox:Slider({ Flag = "CharSpeed", Text = "Speed Value", Default = 0, Min = 0, Max = 10, Decimals = 1, Step = 0.1 })
CharHumGroupbox:Toggle({ Flag = "InfJumpToggle", Text = "Infinite Jump", Default = false })

if not UserInputService.TouchEnabled then
	local PowerShotBox = Tabs.Character:Section("PowerShot", 2)
	-- the three tuning sliders moved into the gear popup next to the master
	-- toggle (Facility's per-toggle settings panel); flags and defaults are
	-- exactly what they were when the sliders sat inline
	local InsanePowerApi = PowerShotBox:Toggle({ Flag = "InsanePowerShoot", Text = "PowerShot Master", Default = false })
	InsanePowerApi:Gear(function(panel)
		panel:Slider({ Flag = "InsanePowerValue", Text = "Multiplier", Default = 1.5, Min = -5, Max = 5, Decimals = 2, Step = 0.01 })
		panel:Slider({ Flag = "InsanePowerMaxVel", Text = "Max Velocity Cap", Default = 300, Min = 100, Max = 1000, Decimals = 0 })
		panel:Slider({ Flag = "InsanePowerSwapDelay", Text = "Tool Swap Delay (ms)", Default = 500, Min = 0, Max = 2000, Decimals = 0 })
	end)

	if not IS_MMP then
		local KnuckleApi = PowerShotBox:Toggle({ Flag = "ForceKnuckleToggle", Text = "Force Knuckleball", Default = false })
		KnuckleApi:Gear(function(panel)
			panel:Slider({ Flag = "KnuckleWobbleIntensity", Text = "Wobble Intensity", Default = 1.0, Min = -5.0, Max = 5.0, Decimals = 2, Step = 0.01 })
			panel:Slider({ Flag = "KnuckleWobbleSpeed", Text = "Wobble Speed", Default = 0.2, Min = 0.05, Max = 0.6, Decimals = 2, Step = 0.01 })
		end)
	end

	-- per-move overrides: two half-width columns instead of one long list
	local PerMoveGroupbox = Tabs.Character:Section("PowerShot Per-Move", 2)
	local moveCount = #SHOOT_MOVES
	PerMoveGroupbox:Split({
		function(left)
			for i = 1, math.ceil(moveCount / 2) do
				local move = SHOOT_MOVES[i]
				left:Toggle({ Flag = "PowerShot_"..move.name, Text = move.label, Default = move.default })
			end
		end,
		function(right)
			for i = math.ceil(moveCount / 2) + 1, moveCount do
				local move = SHOOT_MOVES[i]
				right:Toggle({ Flag = "PowerShot_"..move.name, Text = move.label, Default = move.default })
			end
		end,
	})

	-- advanced boosts: one full-width band, multiplier/cap sliders tucked
	-- into each boost's gear popup
	local AdvancedGroupbox = Tabs.Character:Section("Advanced Boosts", "full")
	AdvancedGroupbox:Toggle({ Flag = "AdvancedBoostEnabled", Text = "Enable Advanced Boosts", Default = false })
	AdvancedGroupbox:Split({
		function(left)
			local AngleApi = left:Toggle({ Flag = "AngleBoostEnabled", Text = "Angle Boost", Default = false })
			AngleApi:Gear(function(panel)
				panel:Slider({ Flag = "AngleBoostMult", Text = "Angle Multiplier", Default = 1.5, Min = -3, Max = 3, Decimals = 2, Step = 0.01 })
				panel:Slider({ Flag = "AngleBoostCap", Text = "Angle Y Cap", Default = 100, Min = 30, Max = 300, Decimals = 0 })
			end)
			local CurveApi = left:Toggle({ Flag = "CurveBoostEnabled", Text = "Curve Boost", Default = false })
			CurveApi:Gear(function(panel)
				panel:Slider({ Flag = "CurveBoostMult", Text = "Curve Multiplier", Default = 2, Min = -5, Max = 5, Decimals = 2, Step = 0.01 })
				panel:Slider({ Flag = "CurveBoostCap", Text = "Curve Force Cap", Default = 800, Min = 200, Max = 3000, Decimals = 0 })
			end)
		end,
		function(right)
			local TopspinApi = right:Toggle({ Flag = "TopspinBoostEnabled", Text = "Topspin Boost", Default = false })
			TopspinApi:Gear(function(panel)
				panel:Slider({ Flag = "TopspinBoostMult", Text = "Topspin Multiplier", Default = 1.5, Min = -3, Max = 3, Decimals = 2, Step = 0.01 })
			end)
			local BackspinApi = right:Toggle({ Flag = "BackspinBoostEnabled", Text = "Backspin Boost", Default = false })
			BackspinApi:Gear(function(panel)
				panel:Slider({ Flag = "BackspinBoostMult", Text = "Backspin Multiplier", Default = 1.5, Min = -3, Max = 3, Decimals = 2, Step = 0.01 })
			end)
			local SpinRotApi = right:Toggle({ Flag = "SpinRotBoostEnabled", Text = "Spin Rotation Boost", Default = false })
			SpinRotApi:Gear(function(panel)
				panel:Slider({ Flag = "SpinRotBoostMult", Text = "Spin Rotation Multiplier", Default = 2, Min = -3, Max = 3, Decimals = 2, Step = 0.01 })
			end)
		end,
	})

	if not IS_MMP then
		local HotkeyBox = Tabs.Character:Section("Hotkey Boosters", "full")
		HotkeyBox:Toggle({
			Flag = "EnableHotkeyBoosters",
			Text = "Enable Hotkey Boosters",
			Hint = "When ON, boosters only fire if you press their hotkey while charging a shot. When OFF, boosters use their normal toggles above.",
			Default = false,
		})
		HotkeyBox:Split({
			function(keys)
				keys:Divider()
				keys:Keybind({ Flag = "PowerShotHotkey", Text = "PowerShot", Default = "V" })
				keys:Keybind({ Flag = "CurveHotkey", Text = "Curve Boost", Default = "X" })
				keys:Keybind({ Flag = "KnuckleHotkey", Text = "Force Knuckleball", Default = "G" })
				keys:Keybind({ Flag = "SpinRotHotkey", Text = "Spin Rotation", Default = "B" })
			end,
			function(auto)
				auto:Toggle({
					Flag = "KnuckleAutoPowerShot",
					Text = "Knuckleball → auto-arm PowerShot",
					Hint = "When ON, pressing the knuckleball hotkey also arms PowerShot for that shot.",
					Default = true,
				})
				auto:Toggle({
					Flag = "PowerShotAutoCurve",
					Text = "PowerShot → auto-arm Curve",
					Hint = "When ON, pressing the PowerShot hotkey also arms Curve Boost for that shot.",
					Default = false,
				})
				auto:Divider()
				auto:Toggle({
					Flag = "HotkeyClearEnabled",
					Text = "Panic Clear Hotkey",
					Hint = "Disarms all boosters instantly.",
					Default = true,
				})
				-- standalone keybind row: pressing the key must NOT flip the toggle itself
				-- (the old picker used Mode = "Always" and is handled manually further below)
				auto:Keybind({ Flag = "HotkeyClearKey", Text = "Clear All", Default = "Backspace" })
			end,
		})
	end
end

-- ===========================================================================
-- Ball
-- ===========================================================================

local BallPredictionGroupbox = Tabs.Ball:Section("Main", "full")
BallPredictionGroupbox:Split({
	function(left)
		local BallPredToggleApi = left:Toggle({ Flag = "BallPredToggle", Text = "Ball Prediction", Default = false })
		BallPredToggleApi:ColorPicker({ Flag = "BallPredTrailColor", Default = Color3.new(1, 1, 1), DefaultAlpha = 1 })
		UI.BallPredTrailColor = BallPredToggleApi.Pickers[1]
		left:Slider({ Flag = "BallPredTrailSize", Text = "Trail Size", Default = 0.1, Min = 0.01, Max = 0.5, Decimals = 2, Step = 0.01 })
	end,
	function(right)
		right:Slider({ Flag = "BallPredHZ", Text = "Refresh Rate", Default = 0.1, Min = 0.05, Max = 1, Decimals = 2, Step = 0.01 })
		right:Slider({ Flag = "BallPredThreshold", Text = "Prediction Threshold", Default = 25, Min = 0, Max = 100, Decimals = 0 })
		right:Slider({ Flag = "BallPredAccuracy", Text = "Prediction Accuracy", Default = 5, Min = 1, Max = 10, Decimals = 0 })
	end,
})

-- ===========================================================================
-- Visuals
-- ===========================================================================

local VisualsLightingTab = Tabs.Visuals:Section("Lighting", "full")

Cb.SkyboxColorToggle = { Flag = "SkyboxColorToggle", Text = "Skybox Color", Default = false }
Cb.SkyboxColor = { Flag = "SkyboxColor", Default = Color3.new(1, 1, 1) }
Cb.SkyboxDecay = { Flag = "SkyboxDecay", Default = Color3.new(1, 1, 1) }
Cb.SkyboxGlare = { Flag = "SkyboxGlare", Text = "Skybox Glare", Default = 1, Min = 0, Max = 10, Decimals = 2, Step = 0.01 }
Cb.SkyboxHaze = { Flag = "SkyboxHaze", Text = "Skybox Haze", Default = 1, Min = 0, Max = 10, Decimals = 2, Step = 0.01 }
Cb.CorrectionToggle = { Flag = "CorrectionToggle", Text = "Correction", Default = false }
Cb.CorrectionColor = { Flag = "CorrectionColor", Default = Color3.new(1, 1, 1) }
Cb.CorrectionBrightness = { Flag = "CorrectionBrightness", Text = "Brightness", Default = 0, Min = -1, Max = 1, Decimals = 2, Step = 0.01 }
Cb.CorrectionContrast = { Flag = "CorrectionContrast", Text = "Contrast", Default = 0, Min = -1, Max = 1, Decimals = 2, Step = 0.01 }
Cb.CorrectionSaturation = { Flag = "CorrectionSaturation", Text = "Saturation", Default = 0, Min = -1, Max = 1, Decimals = 2, Step = 0.01 }

VisualsLightingTab:Split({
	function(skybox)
		UI.SkyboxColorToggle = skybox:Toggle(Cb.SkyboxColorToggle)
		UI.SkyboxColorToggle:ColorPicker(Cb.SkyboxColor)
		UI.SkyboxColorToggle:ColorPicker(Cb.SkyboxDecay)
		UI.SkyboxColor = UI.SkyboxColorToggle.Pickers[1]
		UI.SkyboxDecay = UI.SkyboxColorToggle.Pickers[2]
		UI.SkyboxGlare = skybox:Slider(Cb.SkyboxGlare)
		UI.SkyboxHaze = skybox:Slider(Cb.SkyboxHaze)
	end,
	function(correction)
		UI.CorrectionToggle = correction:Toggle(Cb.CorrectionToggle)
		UI.CorrectionToggle:ColorPicker(Cb.CorrectionColor)
		UI.CorrectionColor = UI.CorrectionToggle.Pickers[1]
		UI.CorrectionBrightness = correction:Slider(Cb.CorrectionBrightness)
		UI.CorrectionContrast = correction:Slider(Cb.CorrectionContrast)
		UI.CorrectionSaturation = correction:Slider(Cb.CorrectionSaturation)
	end,
})

local LIGHTING_PRESETS = {
	["Pink Chain"] = { SkyColor = Color3.fromRGB(219,68,103), SkyDecay = Color3.fromRGB(80,20,40), Glare=2.5, Haze=1.5, CorrColor=Color3.fromRGB(255,180,200), Brightness=0.05, Contrast=0.1, Saturation=0.2, ESPColor=Color3.fromRGB(219,68,103), PitchColor=Color3.fromRGB(120,40,70) },
	["Night Void"] = { SkyColor = Color3.fromRGB(10,10,30), SkyDecay = Color3.fromRGB(5,5,15), Glare=0.2, Haze=0.5, CorrColor=Color3.fromRGB(100,100,255), Brightness=-0.1, Contrast=0.2, Saturation=-0.3, ESPColor=Color3.fromRGB(100,100,255), PitchColor=Color3.fromRGB(20,20,50) },
	["Golden Hour"] = { SkyColor = Color3.fromRGB(255,160,60), SkyDecay = Color3.fromRGB(180,80,20), Glare=4.0, Haze=3.0, CorrColor=Color3.fromRGB(255,210,150), Brightness=0.1, Contrast=0.05, Saturation=0.3, ESPColor=Color3.fromRGB(255,160,60), PitchColor=Color3.fromRGB(150,110,50) },
	["Toxic Green"] = { SkyColor = Color3.fromRGB(30,180,50), SkyDecay = Color3.fromRGB(10,60,15), Glare=1.5, Haze=2.0, CorrColor=Color3.fromRGB(180,255,180), Brightness=0.05, Contrast=0.15, Saturation=0.4, ESPColor=Color3.fromRGB(30,180,50), PitchColor=Color3.fromRGB(20,100,30) },
	["Deep Ocean"] = { SkyColor = Color3.fromRGB(0,60,120), SkyDecay = Color3.fromRGB(0,20,60), Glare=0.5, Haze=1.0, CorrColor=Color3.fromRGB(150,200,255), Brightness=-0.05, Contrast=0.1, Saturation=0.2, ESPColor=Color3.fromRGB(0,120,220), PitchColor=Color3.fromRGB(15,40,70) },
	["Blood Moon"] = { SkyColor = Color3.fromRGB(120,10,10), SkyDecay = Color3.fromRGB(50,5,5), Glare=1.0, Haze=2.5, CorrColor=Color3.fromRGB(255,120,120), Brightness=-0.05, Contrast=0.25, Saturation=0.15, ESPColor=Color3.fromRGB(200,30,30), PitchColor=Color3.fromRGB(70,15,15) },
	["Ash Storm"] = { SkyColor = Color3.fromRGB(100,95,90), SkyDecay = Color3.fromRGB(60,55,50), Glare=0.3, Haze=5.0, CorrColor=Color3.fromRGB(200,195,185), Brightness=-0.15, Contrast=0.3, Saturation=-0.5, ESPColor=Color3.fromRGB(160,155,145), PitchColor=Color3.fromRGB(80,78,72) },
	["Cyberpunk"] = { SkyColor = Color3.fromRGB(160,30,200), SkyDecay = Color3.fromRGB(30,10,60), Glare=3.0, Haze=1.0, CorrColor=Color3.fromRGB(200,100,255), Brightness=0.0, Contrast=0.3, Saturation=0.5, ESPColor=Color3.fromRGB(0,255,200), PitchColor=Color3.fromRGB(40,10,60) },
	["Ice Cold"] = { SkyColor = Color3.fromRGB(200,230,255), SkyDecay = Color3.fromRGB(100,140,180), Glare=1.5, Haze=1.0, CorrColor=Color3.fromRGB(220,240,255), Brightness=0.1, Contrast=0.15, Saturation=-0.2, ESPColor=Color3.fromRGB(150,220,255), PitchColor=Color3.fromRGB(180,200,220) },
}
local function ApplyPreset(name)
	local cfg = LIGHTING_PRESETS[name]
	if not cfg then return end
	UI.SkyboxColorToggle:Set(true)
	UI.CorrectionToggle:Set(true)
	UI.SkyboxColor:Set(cfg.SkyColor)
	UI.SkyboxDecay:Set(cfg.SkyDecay)
	UI.SkyboxGlare:Set(cfg.Glare)
	UI.SkyboxHaze:Set(cfg.Haze)
	UI.CorrectionColor:Set(cfg.CorrColor)
	UI.CorrectionBrightness:Set(cfg.Brightness)
	UI.CorrectionContrast:Set(cfg.Contrast)
	UI.CorrectionSaturation:Set(cfg.Saturation)
	if UI.BallESPColor then UI.BallESPColor:Set(cfg.ESPColor) end
	if cfg.PitchColor then
		SetPitchColor(cfg.PitchColor)
		EnforceWhiteLines()
	end
	Notify({ Title = "Chain Preset", Text = name.." applied!", Duration = 2 })
end
local presetNames = {"None"}
for name, _ in pairs(LIGHTING_PRESETS) do table.insert(presetNames, name) end
table.sort(presetNames)

VisualsLightingTab:Divider()
UI.LightingPresetDropdown = VisualsLightingTab:Dropdown({ Flag = "LightingPresetDropdown", Text = "Lighting Preset", Options = presetNames, Default = "None",
	Callback = function(value) if value ~= "None" then ApplyPreset(value) end end,
})
VisualsLightingTab:ButtonRow({
	{ Text = "Reset Lighting", Callback = function()
		UI.SkyboxColorToggle:Set(false)
		UI.CorrectionToggle:Set(false)
		if UI.LightingPresetDropdown then UI.LightingPresetDropdown:Set("None") end
	end },
	{ Text = "Refresh Pitch Color", Callback = function()
		local sel = Flags.LightingPresetDropdown or "None"
		local cfg = LIGHTING_PRESETS[sel]
		if cfg and cfg.PitchColor then
			SetPitchColor(cfg.PitchColor)
			EnforceWhiteLines()
		end
	end },
})

local VisualsOtherTab = Tabs.Visuals:Section("Other", "full")
VisualsOtherTab:Split({
	function(esp)
		Cb.DumbassToggle = { Flag = "DumbassToggle", Text = "Dumbass on your screen", Default = false }
		esp:Toggle(Cb.DumbassToggle)
		Cb.BallESPToggle = { Flag = "BallESPToggle", Text = "Ball ESP", Default = false }
		local BallESPToggleApi = esp:Toggle(Cb.BallESPToggle)
		Cb.BallESPColor = { Flag = "BallESPColor", Default = Color3.fromRGB(219, 68, 103) }
		BallESPToggleApi:ColorPicker(Cb.BallESPColor)
		UI.BallESPColor = BallESPToggleApi.Pickers[1]
	end,
	function(fps)
		Cb.FPSCounterToggle = { Flag = "FPSCounterToggle", Text = "FPS Counter", Default = false }
		local FPSCounterToggleApi = fps:Toggle(Cb.FPSCounterToggle)
		Cb.FPSCounterColor = { Flag = "FPSCounterColor", Default = Color3.fromRGB(255, 255, 255) }
		FPSCounterToggleApi:ColorPicker(Cb.FPSCounterColor)
		UI.FPSCounterColor = FPSCounterToggleApi.Pickers[1]
		Cb.FPSCounterSize = { Flag = "FPSCounterSize", Text = "FPS Counter Size", Default = 18, Min = 10, Max = 40, Decimals = 0 }
		fps:Slider(Cb.FPSCounterSize)
	end,
})

-- ===========================================================================
-- Preview
-- ===========================================================================
-- Zoom and Pose Mode live inside the preview panel itself now (right next to
-- what they control); every other setting stays in this tab.

local PreviewSettingsBox = Tabs.Preview:Section("Preview Window", 1)
Cb.PreviewEnabled = { Flag = "PreviewEnabled", Text = "Enable Preview Window", Default = true }
UI.PreviewEnabled = PreviewSettingsBox:Toggle(Cb.PreviewEnabled)
PreviewSettingsBox:Toggle({ Flag = "PreviewShowReach", Text = "Show Reach Box", Default = true })
PreviewSettingsBox:Toggle({ Flag = "PreviewAutoRotate", Text = "Auto Rotate", Default = true })
Cb.PreviewMatchUIFont = { Flag = "PreviewMatchUIFont", Text = "Match UI Font", Default = true }
PreviewSettingsBox:Toggle(Cb.PreviewMatchUIFont)
PreviewSettingsBox:Toggle({ Flag = "PreviewHideWithMenu", Text = "Hide With Menu", Default = true })
PreviewSettingsBox:Dropdown({ Flag = "PreviewPoseMode", Text = "Pose Mode", Options = {"Live", "Idle"}, Default = "Live" })
PreviewSettingsBox:Slider({ Flag = "PreviewRotSpeed", Text = "Rotation Speed", Default = 0.5, Min = 0, Max = 3, Decimals = 2, Step = 0.01 })
Cb.PreviewSize = { Flag = "PreviewSize", Text = "Window Size", Default = 260, Min = 180, Max = 500, Decimals = 0 }
PreviewSettingsBox:Slider(Cb.PreviewSize)
PreviewSettingsBox:Button({ Text = "Rebuild Character", Callback = function()
	if _G.BuildPreviewChar then _G.BuildPreviewChar() end
end })

local PreviewESPBox = Tabs.Preview:Section("Overlays", 2)
Cb.PreviewShowName = { Flag = "PreviewShowName", Text = "Show Name", Default = true }
PreviewESPBox:Toggle(Cb.PreviewShowName)
Cb.PreviewShowTool = { Flag = "PreviewShowTool", Text = "Show Tool", Default = true }
PreviewESPBox:Toggle(Cb.PreviewShowTool)

local PreviewColorsBox = Tabs.Preview:Section("Colors", "full")
Cb.PreviewNameColor = { Flag = "PreviewNameColor", Text = "Name Color", Default = Color3.fromRGB(255, 255, 255) }
Cb.PreviewToolColor = { Flag = "PreviewToolColor", Text = "Tool Color", Default = Color3.fromRGB(255, 255, 255) }
Cb.PreviewReachColor = { Flag = "PreviewReachColor", Text = "Reach Preview Color", Default = Color3.fromRGB(219, 68, 103) }
Cb.PreviewBGColor = { Flag = "PreviewBGColor", Text = "Background Color", Default = Color3.fromRGB(21, 21, 21) }
PreviewColorsBox:Split({
	function(left)
		left:ColorPicker(Cb.PreviewNameColor)
		left:ColorPicker(Cb.PreviewReachColor)
	end,
	function(right)
		right:ColorPicker(Cb.PreviewToolColor)
		right:ColorPicker(Cb.PreviewBGColor)
	end,
})

-- ===========================================================================
-- Miscs
-- ===========================================================================

local PingSpoofGroupbox = Tabs.Miscs:Section("Ping Spoof", 1)
Cb.PingSpoofToggle = { Flag = "PingSpoofToggle", Text = "Ping Spoofer", Default = false }
PingSpoofGroupbox:Toggle(Cb.PingSpoofToggle)
PingSpoofGroupbox:Slider({ Flag = "PingSpoof", Text = "Ping", Default = 100, Min = 0, Max = 1000, Decimals = 0, Suffix = " ms" })
PingSpoofGroupbox:Slider({ Flag = "PingSpoofSpike", Text = "Ping Spike", Default = 25, Min = 0, Max = 100, Decimals = 0, Suffix = " ms" })
PingSpoofGroupbox:Slider({ Flag = "PingSpoofHZ", Text = "Ping Refresh Rate", Default = 1, Min = 0.1, Max = 5, Decimals = 1, Step = 0.1 })

local UtilGroupbox = Tabs.Miscs:Section("Utility", 1)
UtilGroupbox:Toggle({
	Flag = "B3rnyGuardBypass",
	Text = "B3rnyGuard Bypass",
	Default = true,
	Hint = "Blocks the game's B3rnyGuardian anti-cheat report and forces hit-distance validation (GetClosestPointOnSurface) to always pass.",
})
UtilGroupbox:Toggle({ Flag = "AntiAFKToggle", Text = "Anti AFK", Default = true })
UtilGroupbox:Toggle({ Flag = "AutoRejoinOnErrorToggle", Text = "Auto Rejoin on Kick", Default = false })

local StatusBox = Tabs.Miscs:Section("Status", 2)
local gameLabelNow = IS_MMP and "MMP" or (IS_RMF and "RMF" or (IS_VEF and "VEF" or "Unknown"))
StatusBox:Label("game", { Style = "dim" })
StatusBox:Label(gameLabelNow, { Style = "bright" })
StatusBox:Label("ball detection", { Style = "dim" })
StatusBox:Label(NO_FOLDER and "Workspace" or "Folder", { Style = "bright" })

local PerfGroupbox = Tabs.Miscs:Section("Performance", 2)
Cb.LowGraphicsToggle = { Flag = "LowGraphicsToggle", Text = "Low Graphics Mode", Default = false }
PerfGroupbox:Toggle(Cb.LowGraphicsToggle)
Cb.FPSBoostToggle = { Flag = "FPSBoostToggle", Text = "FPS Boost", Default = false }
PerfGroupbox:Toggle(Cb.FPSBoostToggle)

-- server browser: Facility's built-in public server list
local ServerBrowser = Library.ServerBrowser and Library:ServerBrowser() or nil
PerfGroupbox:Toggle({
	Flag = "ServerBrowserToggle",
	Text = "Server Browser",
	Default = false,
	Hint = "Browse the public servers of this game and hop to another one.",
	Callback = function(state)
		if ServerBrowser then ServerBrowser:SetVisible(state) end
	end,
})

-- ===========================================================================
-- UI Settings
-- ===========================================================================

local ConfigGroupbox = Tabs.Config:Section("Menu", 1)
ConfigGroupbox:Toggle({ Flag = "KeybindMenuOpen", Default = false, Text = "Open Keybind Menu",
	Callback = function(value) Library:SetHotkeysVisible(value) end,
})
ConfigGroupbox:Toggle({ Flag = "ShowCustomCursor", Text = "Custom Cursor", Default = false,
	Callback = function(Value) Library:SetCursor(Value) end,
})
ConfigGroupbox:Dropdown({ Flag = "NotificationSide", Text = "Notification Side", Options = { "Left", "Right" }, Default = "Right",
	Callback = function(Value)
		NotifySide = Value
		ApplyNotifySide()
	end,
})
-- Facility scales the whole window through Window:SetUserScale (60% - 140%),
-- which replaces the old DPI scale setting; the preview panel follows along
ConfigGroupbox:Dropdown({ Flag = "DPIDropdown", Text = "DPI Scale",
	Options = { "60%", "70%", "80%", "90%", "100%", "110%", "120%", "130%", "140%" }, Default = "100%",
	Callback = function(Value)
		Value = Value:gsub("%%", "")
		local scale = tonumber(Value)
		if scale then
			Window:SetUserScale(scale / 100)
			if PreviewPanel and PreviewPanel.Scale then
				PreviewPanel.Scale.Scale = scale / 100
			end
		end
	end,
})
ConfigGroupbox:Slider({ Flag = "UIOpacity", Text = "UI Opacity", Default = 100, Min = 20, Max = 100, Decimals = 0, Suffix = "%",
	Callback = function(value) Window:SetOpacity(value / 100) end,
})
ConfigGroupbox:Divider()
-- rebinding this key updates the library's menu toggle key; pressing the key
-- itself is handled by the library, so the menu never toggles twice
ConfigGroupbox:Keybind({ Flag = "MenuKeybind", Text = "Menu keybind", Default = "RightShift",
	OnChanged = function(key) Library:SetToggleKey(key) end,
})

if SaveManager then
	SaveManager:SetLibrary(Library)
	SaveManager:IgnoreThemeSettings()
	SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
	SaveManager:SetFolder("gamesense-mps/mps")
	SaveManager:BuildConfigSection(Tabs.Config, 2)
else
	Notify({ Title = "config error", Text = "SaveManager addon unavailable; config saving is disabled.", Duration = 6 })
end

if ThemeManager then
	-- adds the paintbrush footer icon that opens the theme editor modal
	-- (Facility's equivalent of the old ThemeManager settings tab)
	ThemeManager:Mount(Window)
end

local gameLabel = IS_MMP and "MMP" or (IS_RMF and "RMF" or (IS_VEF and "VEF" or "Unknown"))
Notify({ Title = "Game Detected", Text = "Running in: "..gameLabel.." | Ball Detection: "..(NO_FOLDER and "Workspace" or "Folder"), Duration = 5 })

if PingHandler then
	Cb.PingSpoofToggle.Callback = function(value)
		PingHandler.Enabled = not value
	end
end
Cb.DumbassToggle.Callback = function(value) Dumbass.Visible = value end

local OldAtmosphere, OldCorrection = nil, nil
Cb.SkyboxColorToggle.Callback = function(value)
	if value then
		local existing = Lighting:FindFirstChildOfClass("Atmosphere")
		if existing and existing.Name ~= "GS_ATMO" then
			OldAtmosphere = existing
			OldAtmosphere.Parent = nil
		end
		local old = Lighting:FindFirstChild("GS_ATMO")
		if old then old:Destroy() end
		local GS_ATMO = Instance.new("Atmosphere")
		GS_ATMO.Name = "GS_ATMO"
		GS_ATMO.Density = 0
		GS_ATMO.Offset = 0
		GS_ATMO.Color = UI.SkyboxColor.Color
		GS_ATMO.Decay = UI.SkyboxDecay.Color
		GS_ATMO.Glare = Flags.SkyboxGlare
		GS_ATMO.Haze = Flags.SkyboxHaze
		GS_ATMO.Parent = Lighting
	else
		local old = Lighting:FindFirstChild("GS_ATMO")
		if old then old:Destroy() end
		if OldAtmosphere then
			OldAtmosphere.Parent = Lighting
			OldAtmosphere = nil
		end
	end
end
Cb.CorrectionToggle.Callback = function(value)
	if value then
		local cam = workspace.CurrentCamera
		local existing = cam:FindFirstChild("GS_CCOR") or Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if existing and existing.Name ~= "GS_CCOR" then
			OldCorrection = existing
			OldCorrection.Parent = nil
		end
		local old = cam:FindFirstChild("GS_CCOR") or Lighting:FindFirstChild("GS_CCOR")
		if old then old:Destroy() end
		local GS_CCOR = Instance.new("ColorCorrectionEffect")
		GS_CCOR.Name = "GS_CCOR"
		GS_CCOR.Brightness = Flags.CorrectionBrightness
		GS_CCOR.Contrast = Flags.CorrectionContrast
		GS_CCOR.Saturation = Flags.CorrectionSaturation
		GS_CCOR.TintColor = UI.CorrectionColor.Color
		GS_CCOR.Parent = cam
	else
		local cam = workspace.CurrentCamera
		local old = cam:FindFirstChild("GS_CCOR") or Lighting:FindFirstChild("GS_CCOR")
		if old then old:Destroy() end
		if OldCorrection then
			OldCorrection.Parent = Lighting
			OldCorrection = nil
		end
	end
end

local function updateAtmo(prop, value)
	local a = Lighting:FindFirstChild("GS_ATMO")
	if a then a[prop] = value end
end
local function updateCorr(prop, value)
	local cam = workspace.CurrentCamera
	local c = cam:FindFirstChild("GS_CCOR") or Lighting:FindFirstChild("GS_CCOR")
	if c then c[prop] = value end
end
Cb.SkyboxColor.Callback = function(color) updateAtmo("Color", color) end
Cb.SkyboxDecay.Callback = function(color) updateAtmo("Decay", color) end
Cb.SkyboxGlare.Callback = function(value) updateAtmo("Glare", value) end
Cb.SkyboxHaze.Callback = function(value) updateAtmo("Haze", value) end
Cb.CorrectionColor.Callback = function(color) updateCorr("TintColor", color) end
Cb.CorrectionBrightness.Callback = function(value) updateCorr("Brightness", value) end
Cb.CorrectionContrast.Callback = function(value) updateCorr("Contrast", value) end
Cb.CorrectionSaturation.Callback = function(value) updateCorr("Saturation", value) end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Flags.CorrectionToggle then
		task.wait(0.1)
		UI.CorrectionToggle:Set(false)
		task.wait(0.05)
		UI.CorrectionToggle:Set(true)
	end
end)

local BallHighlights = {}
local function AddBallESP(ball)
	if BallHighlights[ball] then return end
	if not ball or not ball.Parent then return end
	local ancestor = ball:FindFirstAncestorOfClass("Model")
	if ancestor and ancestor:FindFirstChildOfClass("Humanoid") then return end
	if not (ball:IsDescendantOf(workspace) and (BALL_NAMES[ball.Name] or ball.Name == "VEF" or ball.Name == "TPS" or ball.Name == "CMP")) then return end
	local hl = Instance.new("Highlight")
	hl.FillColor = UI.BallESPColor.Color
	hl.OutlineColor = UI.BallESPColor.Color
	hl.FillTransparency = 0.5
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = ball
	hl.Parent = BallESPFolder
	BallHighlights[ball] = hl
end
local function RemoveBallESP(ball)
	if BallHighlights[ball] then
		BallHighlights[ball]:Destroy()
		BallHighlights[ball] = nil
	end
end
local function ClearAllBallESP()
	for ball, hl in pairs(BallHighlights) do
		if hl then hl:Destroy() end
	end
	table.clear(BallHighlights)
end
Cb.BallESPToggle.Callback = function(value)
	if value then
		local balls = NO_FOLDER and _BALLS or BallsFolder:GetChildren()
		for _, ball in ipairs(balls) do AddBallESP(ball) end
	else
		ClearAllBallESP()
	end
end
Cb.BallESPColor.Callback = function(color)
	for _, hl in pairs(BallHighlights) do
		if hl and hl.Parent then
			hl.FillColor = color
			hl.OutlineColor = color
		end
	end
end
task.spawn(function()
	while task.wait(1) do
		if Flags.BallESPToggle then
			local balls = NO_FOLDER and _BALLS or BallsFolder:GetChildren()
			for _, ball in ipairs(balls) do
				if not BallHighlights[ball] then AddBallESP(ball) end
			end
			for ball, hl in pairs(BallHighlights) do
				if not ball or not ball.Parent then
					if hl then hl:Destroy() end
					BallHighlights[ball] = nil
				end
			end
		end
	end
end)

local JuraFont = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.Medium)
local CodeFont = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular)
-- one font everywhere: custom HUD/preview text follows the Facility theme font
local MatchFontOk, MatchFontResult = pcall(function()
	return Font.fromEnum(Library.Theme.Font or Enum.Font.Gotham)
end)
local MatchFont = MatchFontOk and MatchFontResult or JuraFont

local FPSLabel = nil
local function BuildFPSLabel()
	if FPSLabel then return end
	FPSLabel = Instance.new("TextLabel")
	FPSLabel.Name = "GS_FPS"
	FPSLabel.Size = UDim2.new(0, 120, 0, 32)
	FPSLabel.Position = UDim2.new(0, 12, 0, 12)
	FPSLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	FPSLabel.BackgroundTransparency = 0.5
	FPSLabel.BorderSizePixel = 0
	FPSLabel.TextColor3 = UI.FPSCounterColor and UI.FPSCounterColor.Color or Color3.new(1,1,1)
	FPSLabel.FontFace = MatchFont
	FPSLabel.TextSize = Flags.FPSCounterSize or 18
	FPSLabel.Text = "FPS: 0"
	FPSLabel.TextXAlignment = Enum.TextXAlignment.Center
	FPSLabel.Parent = GS_OVERLAY
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = FPSLabel
end
Cb.FPSCounterToggle.Callback = function(value)
	if value then
		BuildFPSLabel()
		FPSLabel.Visible = true
	elseif FPSLabel then
		FPSLabel.Visible = false
	end
end
Cb.FPSCounterColor.Callback = function(color)
	if FPSLabel then FPSLabel.TextColor3 = color end
end
Cb.FPSCounterSize.Callback = function(value)
	if FPSLabel then FPSLabel.TextSize = value end
end

local OldQuality = nil
Cb.LowGraphicsToggle.Callback = function(value)
	if value then
		OldQuality = settings().Rendering.QualityLevel
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 9e9
	else
		Lighting.GlobalShadows = true
		if OldQuality then
			pcall(function() settings().Rendering.QualityLevel = OldQuality end)
		end
	end
end
Cb.FPSBoostToggle.Callback = function(value)
	if value then
		task.spawn(function()
			for _, v in ipairs(workspace:GetDescendants()) do
				if v:IsA("Decal") or v:IsA("Texture") then
					v.Transparency = 1
				elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
					v.Enabled = false
				end
			end
		end)
	end
end

task.spawn(function()
	LocalPlayer.Idled:Connect(function()
		if Flags.AntiAFKToggle then
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end
	end)
end)

local TeleportService = game:GetService("TeleportService")
LocalPlayer.OnTeleport:Connect(function(state)
	if state == Enum.TeleportState.Failed and Flags.AutoRejoinOnErrorToggle then
		task.wait(2)
		pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
	end
end)
game:GetService("GuiService").ErrorMessageChanged:Connect(function()
	if Flags.AutoRejoinOnErrorToggle then
		task.wait(1)
		pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
	end
end)

task.spawn(function()
	while task.wait(5) do
		if Flags.SkyboxColorToggle then
			local sel = Flags.LightingPresetDropdown
			if sel and sel ~= "None" and LIGHTING_PRESETS[sel] and LIGHTING_PRESETS[sel].PitchColor then
				EnforceWhiteLines()
			end
		end
	end
end)

local ArmedBoosters = {
	PowerShot = false,
	Curve = false,
	Knuckle = false,
	SpinRot = false,
}
local function ClearArmedBoosters()
	for k in pairs(ArmedBoosters) do ArmedBoosters[k] = false end
end

local function IsCharging()
	if not IS_VEF_LIKE or not MainModuleTable then return false end
	if MainModuleTable.GetWindStatus then
		local ok, val = pcall(MainModuleTable.GetWindStatus)
		if ok then return val end
	end
	if MainModuleTable.getWindUp then
		local ok, val = pcall(MainModuleTable.getWindUp)
		if ok then return val end
	end
	return false
end

local BoosterHudGui = nil
local BoosterHudScreen = nil
local BoosterLabels = {}
local LabelOrder = {"PowerShot", "Curve", "Knuckle", "SpinRot"}

local function EnsureBoosterHud()
	if BoosterHudGui and BoosterHudGui.Parent and BoosterHudScreen and BoosterHudScreen.Parent then
		return BoosterHudGui
	end
	if BoosterHudScreen and BoosterHudScreen.Parent then
		BoosterHudScreen:Destroy()
	end

	BoosterHudScreen = Instance.new("ScreenGui")
	BoosterHudScreen.Name = "GS_HudScreen_"..tostring(math.random(100000,999999))
	BoosterHudScreen.IgnoreGuiInset = true
	BoosterHudScreen.ResetOnSpawn = false
	BoosterHudScreen.DisplayOrder = 999997
	BoosterHudScreen.Parent = game:GetService("CoreGui")

	local frame = Instance.new("Frame")
	frame.Name = "GS_BoosterHud"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -200)
	frame.Size = UDim2.new(0, 220, 0, 150)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 9999
	frame.Parent = BoosterHudScreen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	BoosterHudGui = frame
	return frame
end

local function CreateLabelFrame(boosterName, initialText, textColor, autoHideAfter)
	local hud = EnsureBoosterHud()
	if not hud then return nil end

	local existing = BoosterLabels[boosterName]
	if existing and existing.frame and existing.frame.Parent then
		existing.frame:Destroy()
	end
	if existing and existing.autoHideThread then
		task.cancel(existing.autoHideThread)
	end

	local text = Instance.new("TextLabel")
	text.Name = "BL_"..boosterName
	text.Size = UDim2.new(0, 220, 0, 22)
	text.BackgroundTransparency = 1
	text.BorderSizePixel = 0
	text.Text = initialText
	text.TextColor3 = textColor
	text.TextTransparency = 1
	text.FontFace = MatchFont
	text.TextSize = 15
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.LayoutOrder = table.find(LabelOrder, boosterName) or 99
	text.ZIndex = 9999
	text.Position = UDim2.new(0, 0, 0, 8)
	text.Parent = hud

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = text

	local entry = {frame = text, text = text, stroke = stroke, autoHideThread = nil}
	BoosterLabels[boosterName] = entry

	pcall(function()
		local textTween = TweenService:Create(
			text,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{TextTransparency = 0, Position = UDim2.new(0, 0, 0, 0)}
		)
		local strokeTween = TweenService:Create(
			stroke,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 0.5}
		)
		textTween:Play()
		strokeTween:Play()
	end)

	local hideDelay = autoHideAfter or 1
	entry.autoHideThread = task.delay(hideDelay, function()
		if not entry.frame or not entry.frame.Parent then return end
		pcall(function()
			TweenService:Create(entry.text, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
			TweenService:Create(entry.stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		end)
		task.wait(0.32)
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
		BoosterLabels[boosterName] = nil
	end)

	return entry
end

local function DestroyLabel(boosterName, delay)
	local entry = BoosterLabels[boosterName]
	if not entry or not entry.frame or not entry.frame.Parent then return end
	if entry.autoHideThread then
		task.cancel(entry.autoHideThread)
		entry.autoHideThread = nil
	end
	delay = delay or 0
	task.delay(delay, function()
		if not entry.frame or not entry.frame.Parent then return end
		pcall(function()
			TweenService:Create(entry.text, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
			TweenService:Create(entry.stroke, TweenInfo.new(0.25), {Transparency = 1}):Play()
		end)
		task.wait(0.28)
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
		BoosterLabels[boosterName] = nil
	end)
end

local function ShowApplied(boosterName, displayText)
	CreateLabelFrame(boosterName, "[+] Applied "..displayText, Color3.fromRGB(90, 220, 130), 1)
end

local function ShowRemoved(boosterName, displayText)
	local entry = BoosterLabels[boosterName]
	if entry and entry.autoHideThread then
		task.cancel(entry.autoHideThread)
		entry.autoHideThread = nil
	end
	if not entry or not entry.frame or not entry.frame.Parent then
		CreateLabelFrame(boosterName, "[-] Removed "..displayText, Color3.fromRGB(230, 90, 90), 0.8)
		return
	end
	entry.text.Text = "[-] Removed "..displayText
	entry.text.TextColor3 = Color3.fromRGB(230, 90, 90)
	entry.stroke.Color = Color3.fromRGB(60, 20, 20)
	entry.autoHideThread = task.delay(0.8, function()
		if not entry.frame or not entry.frame.Parent then return end
		pcall(function()
			TweenService:Create(entry.text, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
			TweenService:Create(entry.stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		end)
		task.wait(0.32)
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
		BoosterLabels[boosterName] = nil
	end)
end

local function ClearAllLabels()
	for name, entry in pairs(BoosterLabels) do
		if entry and entry.autoHideThread then
			task.cancel(entry.autoHideThread)
		end
		if entry and entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
	end
	table.clear(BoosterLabels)
end

local lastChargeState = false
task.spawn(function()
	while task.wait(0.05) do
		local charging = IsCharging()
		if charging and not lastChargeState then
			ClearArmedBoosters()
			ClearAllLabels()
		end
		lastChargeState = charging
	end
end)

local BOOSTER_DISPLAY = {
	PowerShot = "PowerShot",
	Curve = "Curve",
	Knuckle = "Knuckleball",
	SpinRot = "Spin Rotation",
}

local function ArmBooster(name)
	if ArmedBoosters[name] then return end
	ArmedBoosters[name] = true
	ShowApplied(name, BOOSTER_DISPLAY[name] or name)
end

local function DisarmBooster(name)
	if not ArmedBoosters[name] then return end
	ArmedBoosters[name] = false
	ShowRemoved(name, BOOSTER_DISPLAY[name] or name)
end

local function ToggleBooster(name)
	if ArmedBoosters[name] then
		DisarmBooster(name)
	else
		ArmBooster(name)
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if Library.Binding then return end -- ignore keys captured while rebinding in the UI
	if not IS_VEF_LIKE then return end
	if not HotkeyMasterOn() then return end

	local key = input.KeyCode.Name

	if Flags.HotkeyClearEnabled
		and Flags.HotkeyClearKey and key == Flags.HotkeyClearKey then
		for n in pairs(ArmedBoosters) do
			if ArmedBoosters[n] then DisarmBooster(n) end
		end
		return
	end

	if not IsCharging() then return end

	if Flags.PowerShotHotkey and key == Flags.PowerShotHotkey then
		if ArmedBoosters.PowerShot then
			DisarmBooster("PowerShot")
			if Flags.PowerShotAutoCurve
				and ArmedBoosters.Curve then
				DisarmBooster("Curve")
			end
		else
			ArmBooster("PowerShot")
			if Flags.PowerShotAutoCurve
				and not ArmedBoosters.Curve then
				ArmBooster("Curve")
			end
		end
	end
	if Flags.CurveHotkey and key == Flags.CurveHotkey then
		ToggleBooster("Curve")
	end
	if Flags.KnuckleHotkey and key == Flags.KnuckleHotkey then
		if ArmedBoosters.Knuckle then
			DisarmBooster("Knuckle")
			if Flags.KnuckleAutoPowerShot
				and ArmedBoosters.PowerShot then
				DisarmBooster("PowerShot")
			end
		else
			ArmBooster("Knuckle")
			if Flags.KnuckleAutoPowerShot
				and not ArmedBoosters.PowerShot then
				ArmBooster("PowerShot")
			end
		end
	end
	if Flags.SpinRotHotkey and key == Flags.SpinRotHotkey then
		ToggleBooster("SpinRot")
	end
end)

-- enableToggle used to be the old toggle object; it is now the flag value itself
local function ShouldBoosterFire(boosterName, enableFlag)
	if HotkeyMasterOn() then
		return ArmedBoosters[boosterName] == true
	else
		return enableFlag == true
	end
end


-- ===== PREVIEW PANEL ======================================================
-- The character/tool preview is hosted in a Library:Panel - Facility's own
-- themed floating panel - docked to the right of the main window, so it shares
-- the window's palette, font, corner radius and drag behaviour, and re-themes
-- together with the rest of the UI. (It used to be a fully custom ScreenGui
-- with hardcoded Obsidian-era colors glued to the right edge of the screen.)

PreviewPanel = Library:Panel({
	Title = "preview",
	Icon = "user",
	Width = 300,
	-- docked next to the (initially centered) main window, top edges aligned
	Position = UDim2.new(0.5, Window.Width / 2 + 14, 0.5, -Window.Height / 2),
	Visible = Flags.PreviewEnabled ~= false,
})

-- viewport card (custom frame parented into the panel's content flow; it is
-- theme-tracked so paintbrush/theme changes recolor it with everything else)
local ViewportHolder = Instance.new("Frame")
ViewportHolder.Name = "PreviewViewport"
ViewportHolder.Size = UDim2.new(1, 0, 0, Flags.PreviewSize or 260)
ViewportHolder.BackgroundColor3 = Library.Theme.Field
ViewportHolder.BorderSizePixel = 0
ViewportHolder.Parent = PreviewPanel.Content.Container
Library:Tag(ViewportHolder, { BackgroundColor3 = "Field" })
local ViewportCorner = Instance.new("UICorner")
ViewportCorner.CornerRadius = UDim.new(0, 6)
ViewportCorner.Parent = ViewportHolder
local ViewportStroke = Instance.new("UIStroke")
ViewportStroke.Thickness = 1
ViewportStroke.Parent = ViewportHolder
Library:Tag(ViewportStroke, { Color = "Border" })

local ViewportFrame = Instance.new("ViewportFrame")
ViewportFrame.Size = UDim2.new(1, -2, 1, -2)
ViewportFrame.Position = UDim2.new(0, 1, 0, 1)
ViewportFrame.BackgroundColor3 = Color3.fromRGB(21, 21, 21)
ViewportFrame.BorderSizePixel = 0
ViewportFrame.LightDirection = Vector3.new(-0.5, -1, -0.5)
ViewportFrame.Ambient = Color3.fromRGB(180, 180, 180)
ViewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
ViewportFrame.Parent = ViewportHolder
local ViewportFrameCorner = Instance.new("UICorner")
ViewportFrameCorner.CornerRadius = UDim.new(0, 5)
ViewportFrameCorner.Parent = ViewportFrame

local WorldModel = Instance.new("WorldModel", ViewportFrame)
local PreviewCamera = Instance.new("Camera", ViewportFrame)
PreviewCamera.FieldOfView = 60
PreviewCamera.CameraType = Enum.CameraType.Scriptable
ViewportFrame.CurrentCamera = PreviewCamera

local PreviewReachBox = Instance.new("Part", WorldModel)
PreviewReachBox.Name = "PreviewReach"
PreviewReachBox.Size = Vector3.new(0.1, 0.1, 0.1)
PreviewReachBox.Anchored = true
PreviewReachBox.CanCollide = false
PreviewReachBox.Transparency = 0.6
PreviewReachBox.Material = Enum.Material.ForceField
PreviewReachBox.Color = Color3.fromRGB(219, 68, 103)

local ESPHolder = Instance.new("Frame", ViewportFrame)
ESPHolder.AnchorPoint = Vector2.new(0.5, 0.5)
ESPHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
ESPHolder.Size = UDim2.new(1, 0, 1, 0)
ESPHolder.BackgroundTransparency = 1

local NameLabel = Instance.new("TextLabel", ESPHolder)
NameLabel.AnchorPoint = Vector2.new(0.5, 0)
NameLabel.Position = UDim2.new(0.5, 0, 0, 5)
NameLabel.Size = UDim2.new(1, -10, 0, 16)
NameLabel.BackgroundTransparency = 1
NameLabel.Text = string.format("%s (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name)
NameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
NameLabel.TextStrokeTransparency = 0
NameLabel.FontFace = JuraFont
NameLabel.TextSize = 13

local ToolLabel = Instance.new("TextLabel", ESPHolder)
ToolLabel.AnchorPoint = Vector2.new(0.5, 1)
ToolLabel.Position = UDim2.new(0.5, 0, 1, -5)
ToolLabel.Size = UDim2.new(1, -10, 0, 16)
ToolLabel.BackgroundTransparency = 1
ToolLabel.Text = "[ None ]"
ToolLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ToolLabel.TextStrokeTransparency = 0
ToolLabel.FontFace = JuraFont
ToolLabel.TextSize = 13

-- zoom lives right under the viewport it controls; Pose Mode is a dropdown
-- and sits in the Preview tab (dropdown popups inside floating panels are
-- unreliable - the popup layer belongs to the main window)
PreviewPanel.Content:Slider({ Flag = "PreviewZoom", Text = "Zoom", Default = 8, Min = 4, Max = 20, Decimals = 1, Step = 0.1 })
PreviewPanel.Content:Button({ Text = "hide preview", Callback = function()
	if UI.PreviewEnabled then UI.PreviewEnabled:Set(false) end
end })

local PreviewChar = nil
local PreviewRootPart = nil
local function BuildPreviewChar()
	if PreviewChar then
		PreviewChar:Destroy()
		PreviewChar = nil
		PreviewRootPart = nil
	end
	if not (Character and Character.Parent) then return end
	local ok, cloneModel = pcall(function()
		Character.Archivable = true
		local c = Character:Clone()
		for _, v in ipairs(c:GetDescendants()) do
			if v:IsA("Script") or v:IsA("LocalScript") then v:Destroy() end
		end
		local anim = c:FindFirstChild("Animate")
		if anim then anim:Destroy() end
		local hum = c:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.PlatformStand = true
			hum.AutoRotate = false
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			local animator = hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop() end
			end
		end
		return c
	end)
	if not ok or not cloneModel then return end
	local root = cloneModel:FindFirstChild("HumanoidRootPart")
	if not root then
		cloneModel:Destroy()
		return
	end
	root.Anchored = true
	for _, part in ipairs(cloneModel:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part.CastShadow = false
		end
	end
	root.CanCollide = false
	root.Massless = true
	root.CastShadow = false
	cloneModel.Parent = WorldModel
	PreviewChar = cloneModel
	PreviewRootPart = root
end
_G.BuildPreviewChar = BuildPreviewChar
task.delay(1, BuildPreviewChar)
-- keep the preview in sync across respawns (the old script needed a manual
-- "Rebuild Character" press after every respawn)
LocalPlayer.CharacterAdded:Connect(function()
	task.delay(1.5, BuildPreviewChar)
end)

local rotationAngle = 0
local function UpdateFonts()
	local useUIFont = Flags.PreviewMatchUIFont
	local font = useUIFont and MatchFont or CodeFont
	NameLabel.FontFace = font
	ToolLabel.FontFace = font
end
local function UpdateSize()
	local size = Flags.PreviewSize or 260
	ViewportHolder.Size = UDim2.new(1, 0, 0, size)
end
local previewShown = nil
local function UpdateESPVisibility()
	local enabled = Flags.PreviewEnabled
	if enabled then
		NameLabel.Visible = Flags.PreviewShowName
		ToolLabel.Visible = Flags.PreviewShowTool
	end
	previewShown = enabled and (not Flags.PreviewHideWithMenu or Library.Open) or false
	PreviewPanel:SetVisible(previewShown)
end
Cb.PreviewEnabled.Callback = UpdateESPVisibility
Cb.PreviewShowName.Callback = UpdateESPVisibility
Cb.PreviewShowTool.Callback = UpdateESPVisibility
Cb.PreviewMatchUIFont.Callback = UpdateFonts
Cb.PreviewSize.Callback = UpdateSize
Cb.PreviewNameColor.Callback = function(color) NameLabel.TextColor3 = color end
Cb.PreviewToolColor.Callback = function(color) ToolLabel.TextColor3 = color end
Cb.PreviewReachColor.Callback = function(color) PreviewReachBox.Color = color end
Cb.PreviewBGColor.Callback = function(color) ViewportFrame.BackgroundColor3 = color end
UpdateESPVisibility()
UpdateFonts()
UpdateSize()

-- when the theme changes (paintbrush editor, ThemeManager:Apply, ...), keep
-- the shared font fresh and re-apply it to every custom label, so the whole
-- UI - window, tree sidebar, preview and HUD - always shares one font
do
	local baseRepaint = Library.Repaint
	Library.Repaint = function(self, ...)
		baseRepaint(self, ...)
		local okFont, themeFont = pcall(Font.fromEnum, Library.Theme.Font or Enum.Font.Gotham)
		if okFont and themeFont then
			MatchFont = themeFont
		end
		pcall(UpdateFonts)
		pcall(function()
			if FPSLabel then FPSLabel.FontFace = MatchFont end
		end)
	end
end

local previewAccum = 0
local PREVIEW_INTERVAL = 1/60
RunService.Heartbeat:Connect(function(dt)
	local shouldShow = Flags.PreviewEnabled == true and (not Flags.PreviewHideWithMenu or Library.Open)
	if shouldShow ~= previewShown then
		previewShown = shouldShow
		PreviewPanel:SetVisible(shouldShow)
	end
	if not shouldShow then return end
	previewAccum = previewAccum + dt
	if previewAccum < PREVIEW_INTERVAL then return end
	previewAccum = 0
	if not (Character and Character.Parent and HRP) then return end
	if not PreviewChar or not PreviewChar.Parent or not PreviewRootPart then return end
	local poseMode = Flags.PreviewPoseMode or "Live"
	if Flags.PreviewAutoRotate then
		rotationAngle = rotationAngle + Flags.PreviewRotSpeed
	end
	local rotY = math.rad(rotationAngle)
	if poseMode == "Live" then
		local realCF = HRP.CFrame
		local _, ry, _ = realCF:ToOrientation()
		PreviewRootPart.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, ry + rotY, 0)
	else
		PreviewRootPart.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, rotY, 0)
	end
	local ReachType = nil
	if Flags.ReachMasterToggle then
		if UserInputService.TouchEnabled and Flags.ReachMainToggle then ReachType = "Main"
		elseif (Character:FindFirstChild("Shoot") or Character:FindFirstChild("Kick")) and Flags.ReachShootToggle then ReachType = "Shoot"
		elseif Character:FindFirstChild("Pass") and Flags.ReachPassToggle then ReachType = "Pass"
		elseif Character:FindFirstChild("Long") and Flags.ReachLongToggle then ReachType = "Long"
		elseif Character:FindFirstChild("Tackle") and Flags.ReachTackleToggle then ReachType = "Tackle"
		elseif Character:FindFirstChild("Dribble") and Flags.ReachDribbleToggle then ReachType = "Dribble"
		elseif (Character:FindFirstChild("Save") or Character:FindFirstChild("Clear") or Character:FindFirstChild("GK")) and Flags.ReachSaveToggle then ReachType = "Save"
		end
	end
	if not ReachType then ReachType = UserInputService.TouchEnabled and "Main" or "Shoot" end
	if Flags.PreviewShowReach and Flags["Reach"..ReachType.."SizeX"] then
		local sx = Flags["Reach"..ReachType.."SizeX"]
		local sy = Flags["Reach"..ReachType.."SizeY"]
		local sz = Flags["Reach"..ReachType.."SizeZ"]
		local ox = Flags["Reach"..ReachType.."OffsetX"]
		local oy = Flags["Reach"..ReachType.."OffsetY"]
		local oz = Flags["Reach"..ReachType.."OffsetZ"]
		PreviewReachBox.Size = Vector3.new(math.max(sx, 0.1), math.max(sy, 0.1), math.max(sz, 0.1))
		PreviewReachBox.CFrame = PreviewRootPart.CFrame * CFrame.new(ox, oy, oz)
		PreviewReachBox.Transparency = 0.6
	else
		PreviewReachBox.Transparency = 1
	end
	local zoom = Flags.PreviewZoom and Flags.PreviewZoom or 8
	PreviewCamera.CFrame = CFrame.new(Vector3.new(0, 3, zoom), Vector3.new(0, 3, 0))
	if ToolLabel.Visible then
		local tool = Character:FindFirstChildOfClass("Tool")
		ToolLabel.Text = tool and ("[ "..tool.Name.." ]") or "[ None ]"
	end
	if NameLabel.Visible then
		NameLabel.Text = string.format("%s (@%s)", LocalPlayer.DisplayName, LocalPlayer.Name)
	end
end)

local Channel = AnimSocket.Connect("GS-CHANNEL")
Channel.OnMessage:Connect(function(Player, Message)
	Message = string.split(Message, "+")
	if Message[1] == "kick" and Message[2] == LocalPlayer.Name then
		if Message[3] then LocalPlayer:Kick(Message[3]) else LocalPlayer:Kick() end
	end
end)

local function ApplyBypass()
	for _, Function in pairs(getgc(true)) do
		if typeof(Function) == "function" then
			local FunctionName = debug.info(Function, "n")
			if FunctionName == "reachcheck" or FunctionName == "touchingcheck" then
				pcall(hookfunction, Function, newcclosure(function() return false end))
			elseif FunctionName == "IsBallBoundingHitbox" then
				pcall(hookfunction, Function, newcclosure(function() return true end))
			end
		end
	end
end
pcall(ApplyBypass)

-- B3rnyGuard bypass (namecall hook): swallows the game's "B3rnyGuardian"
-- anti-cheat report on MainEvent and forces GetClosestPointOnSurface to
-- return the queried point, so hit-distance validation always passes.
-- Gated live by the "B3rnyGuard Bypass" toggle in Miscs -> Utility.
pcall(function()
	local old_namecall
	old_namecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local method = getnamecallmethod()
		if not checkcaller() then
			if Flags.B3rnyGuardBypass ~= false then
				if method == "FireServer" and self.Name == "MainEvent" then
					local arg1 = (select(1, ...))
					if arg1 == "B3rnyGuardian" then return nil end
				end
				if method == "GetClosestPointOnSurface" then
					return (select(1, ...))
				end
			end
		end
		return old_namecall(self, ...)
	end))
end)

KnuckleWobbleThreads = {}
if NO_FOLDER then
	workspace.ChildAdded:Connect(function(child)
		if BALL_NAMES[child.Name] then
			table.insert(_BALLS, child)
			if Flags.BallESPToggle then
				task.wait()
				AddBallESP(child)
			end
		end
	end)
	workspace.ChildRemoved:Connect(function(child)
		local idx = table.find(_BALLS, child)
		if idx then table.remove(_BALLS, idx) end
		RemoveBallESP(child)
		if KnuckleWobbleThreads[child] then
			task.cancel(KnuckleWobbleThreads[child])
			KnuckleWobbleThreads[child] = nil
		end
	end)
else
	BallsFolder.ChildAdded:Connect(function(child)
		if Flags.BallESPToggle then
			task.wait()
			AddBallESP(child)
		end
	end)
	BallsFolder.ChildRemoved:Connect(function(child)
		RemoveBallESP(child)
		if KnuckleWobbleThreads[child] then
			task.cancel(KnuckleWobbleThreads[child])
			KnuckleWobbleThreads[child] = nil
		end
	end)
end

local function ApplyMMPForceBoost(child)
	if not Flags.AdvancedBoostEnabled
		and not Flags.InsanePowerShoot then return end
	if not child or not child.Parent then return end
	local ball = child.Parent
	if not (ball and BALL_NAMES[ball.Name]) then return end
	if IS_MMP and MainModuleTable and MainModuleTable.GetUsing then
		local using = MainModuleTable.GetUsing()
		if using ~= "Shoot" then return end
	end
	pcall(function()
		if child:IsA("BodyForce") then
			task.wait()
			if not child.Parent then return end
			local force = child.Force
			if force.Magnitude < 50 then return end
			if not Flags.AdvancedBoostEnabled then return end
			local ay = math.abs(force.Y)
			local horizontalMag = math.sqrt(force.X^2 + force.Z^2)
			if horizontalMag > 5 and horizontalMag > ay then
				if Flags.CurveBoostEnabled then
					local mult = Flags.CurveBoostMult
					local cap = Flags.CurveBoostCap
					local newX = force.X * mult
					local newZ = force.Z * mult
					local newMag = math.sqrt(newX^2 + newZ^2)
					if newMag > cap then
						local s = cap / newMag
						newX = newX * s
						newZ = newZ * s
					end
					child.Force = Vector3.new(newX, force.Y, newZ)
				end
			elseif force.Y > 5 and ay > horizontalMag then
				if Flags.TopspinBoostEnabled then
					child.Force = Vector3.new(force.X, force.Y * Flags.TopspinBoostMult, force.Z)
				end
			elseif force.Y < -5 and ay > horizontalMag then
				if Flags.BackspinBoostEnabled then
					child.Force = Vector3.new(force.X, force.Y * Flags.BackspinBoostMult, force.Z)
				end
			end
		elseif child:IsA("BodyAngularVelocity") then
			task.wait()
			if not child.Parent then return end
			if child.AngularVelocity.Magnitude < 10 then return end
			if not Flags.AdvancedBoostEnabled then return end
			if Flags.SpinRotBoostEnabled then
				child.AngularVelocity = child.AngularVelocity * Flags.SpinRotBoostMult
				child.MaxTorque = Vector3.new(4000, 4000, 4000)
			end
		elseif child:IsA("BodyVelocity") then
			task.wait()
			if not child.Parent then return end
			local bvMag = child.Velocity.Magnitude
			if bvMag < 20 then return end
			if Flags.AdvancedBoostEnabled
				and Flags.AngleBoostEnabled then
				local vel = child.Velocity
				local mult = Flags.AngleBoostMult
				local cap = Flags.AngleBoostCap
				local newY = vel.Y * mult
				if math.abs(newY) > cap then newY = cap * (newY < 0 and -1 or 1) end
				child.Velocity = Vector3.new(vel.X, newY, vel.Z)
			end
			if Flags.InsanePowerShoot then
				local tool = Character and Character:FindFirstChildOfClass("Tool")
				if tool and Flags["PowerShot_"..tool.Name] then
					local swapDelayMs = Flags.InsanePowerSwapDelay and Flags.InsanePowerSwapDelay or 500
					local timeSinceEquip = (tick() - LastToolEquipTime) * 1000
					if timeSinceEquip >= swapDelayMs then
						local vel = child.Velocity
						local mult = Flags.InsanePowerValue
						local maxVel = Flags.InsanePowerMaxVel
						local newVel = Vector3.new(vel.X * mult, vel.Y, vel.Z * mult)
						local horizMag = Vector3.new(newVel.X, 0, newVel.Z).Magnitude
						if horizMag > maxVel then
							local s = maxVel / horizMag
							newVel = Vector3.new(newVel.X * s, vel.Y, newVel.Z * s)
						end
						child.Velocity = newVel
					end
				end
			end
		end
	end)
end
if IS_MMP then
	local function HookBall(ball)
		ball.ChildAdded:Connect(function(child) ApplyMMPForceBoost(child) end)
	end
	local existingBalls = NO_FOLDER and _BALLS or BallsFolder:GetChildren()
	for _, ball in ipairs(existingBalls) do
		if BALL_NAMES[ball.Name] then pcall(HookBall, ball) end
	end
	if BallsFolder then
		BallsFolder.ChildAdded:Connect(function(ball)
			if BALL_NAMES[ball.Name] then
				task.wait()
				pcall(HookBall, ball)
			end
		end)
	else
		workspace.ChildAdded:Connect(function(ball)
			if BALL_NAMES[ball.Name] then
				task.wait()
				pcall(HookBall, ball)
			end
		end)
	end
end

local LastReachTouch = {}

-- Target limbs table
local TargetLimbNames = {
    ["Head"] = true,
    ["HumanoidRootPart"] = true,
    ["LL"] = true,
    ["Left Arm"] = true,
    ["Left Leg"] = true,
    ["Legs"] = true,
    ["RL"] = true,
    ["Right Arm"] = true,
    ["Right Leg"] = true,
    ["Torso"] = true
}

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
    if not checkcaller() and SpoofTargetLimb and (key == "CFrame" or key == "Position") and self:IsA("BasePart") then
        if self.Name == "Ball" or (typeof(_BALLS) == "table" and table.find(_BALLS, self)) then
            -- When the game checks the ball's position during our reach execution,
            -- return the closest limb's position/CFrame so client-side debug dots lock onto the body.
            return SpoofTargetLimb[key]
        end
    end
    return oldIndex(self, key)
end))


RunService.RenderStepped:Connect(function()
    if not (HRP and Humanoid and Character.Parent) then return end
    local ReachType = nil
    local InfReach = false
		--local SpoofTargetLimb = nil
    if Flags.ReachMasterToggle then
        if UserInputService.TouchEnabled and Flags.ReachMainToggle then
            ReachType = "Main"
            if Flags.InfiniteReachMainToggle then InfReach = true end
        elseif (Character:FindFirstChild("Shoot") or Character:FindFirstChild("Kick")) and Flags.ReachShootToggle then
            ReachType = "Shoot"
            if Flags.InfiniteReachShootToggle then InfReach = true end
        elseif Character:FindFirstChild("Pass") and Flags.ReachPassToggle then
            ReachType = "Pass"
            if Flags.InfiniteReachPassToggle then InfReach = true end
        elseif Character:FindFirstChild("Long") and Flags.ReachLongToggle then
            ReachType = "Long"
            if Flags.InfiniteReachLongToggle then InfReach = true end
        elseif Character:FindFirstChild("Tackle") and Flags.ReachTackleToggle then
            ReachType = "Tackle"
            if Flags.InfiniteReachTackleToggle then InfReach = true end
        elseif Character:FindFirstChild("Dribble") and Flags.ReachDribbleToggle then
            ReachType = "Dribble"
            if Flags.InfiniteReachDribbleToggle then InfReach = true end
        elseif (Character:FindFirstChild("Save") or Character:FindFirstChild("Clear") or Character:FindFirstChild("GK") or Character:FindFirstChild("Keeper")) and Flags.ReachSaveToggle then
            ReachType = "Save"
            if Flags.InfiniteReachSaveToggle then InfReach = true end
        end
    end
    if ReachType == nil or InfReach then
        ReachBox.Size = Vector3.new(0, 0, 0)
        ReachBox.CFrame = CFrame.new(math.huge, math.huge, math.huge)
    else
        ReachBox.Size = Vector3.new(Flags["Reach"..ReachType.."SizeX"], Flags["Reach"..ReachType.."SizeY"], Flags["Reach"..ReachType.."SizeZ"])
        ReachBox.CFrame = HRP.CFrame * CFrame.new(Flags["Reach"..ReachType.."OffsetX"], Flags["Reach"..ReachType.."OffsetY"], Flags["Reach"..ReachType.."OffsetZ"])
    end
    ReachBox.Color = UI.ReachVisualizerColor.Color
    ReachBox.Transparency = Flags.ReachVisualizerToggle and (Flags.ReachVisualizerTransparency and Flags.ReachVisualizerTransparency or 0.7) or 1

    task.spawn(function()
        RunService.RenderStepped:Wait()
        local ReachOverlapParams = OverlapParams.new()
        ReachOverlapParams.FilterType = Enum.RaycastFilterType.Include
        if NO_FOLDER then
            ReachOverlapParams.FilterDescendantsInstances = _BALLS
        else
            ReachOverlapParams.FilterDescendantsInstances = {BallsFolder}
        end
        local TouchingBalls
        if InfReach then
            TouchingBalls = NO_FOLDER and _BALLS or BallsFolder:GetChildren()
        else
            TouchingBalls = workspace:GetPartsInPart(ReachBox, ReachOverlapParams)
        end
        local hrpPos = HRP.Position
        -- ball selection lives in the Main reach section now (one dropdown for every move)
        local selector = Flags.ReachMainBallSelector
        or (ReachType and Flags["Reach"..ReachType.."BallSelector"])
        or "Closest to character"
        if selector == "Furthest to character" then
            table.sort(TouchingBalls, function(a, b) return (a.Position - hrpPos).Magnitude > (b.Position - hrpPos).Magnitude end)
        else
            table.sort(TouchingBalls, function(a, b) return (a.Position - hrpPos).Magnitude < (b.Position - hrpPos).Magnitude end)
        end

        if #TouchingBalls > 0 then
            local Ball = TouchingBalls[1]
            if IS_MMP and MainModuleTable and MainModuleTable.GetUsing then
                local ok, using = pcall(MainModuleTable.GetUsing)
                if ok and MULTIHIT_MOVES[using] then
                    local cooldownMs = Flags.ReachDebounceMs and Flags.ReachDebounceMs or 150
                    if cooldownMs > 0 then
                        local now = tick() * 1000
                        local last = LastReachTouch[Ball] or 0
                        if (now - last) < cooldownMs then return end
                        LastReachTouch[Ball] = now
                    end
                end
            end
            if ReachType and Flags["Reach"..ReachType.."CompToggle"] then
                local values = Ball:FindFirstChild("Values")
                if values then
                    local ownerTag = values:FindFirstChild("Owner")
                    if ownerTag and ownerTag.Value == LocalPlayer then return end
                end
                local OwnerTag = Ball:FindFirstChild("Owner") or Ball:FindFirstChild("owner")
                if OwnerTag and (OwnerTag.Value == LocalPlayer or OwnerTag.Value == LocalPlayer.Name or OwnerTag.Value == LocalPlayer.UserId) then return end
            end

            local isGKState = (ReachType == "Save") or Character:FindFirstChild("Save") or Character:FindFirstChild("GK") or Character:FindFirstChild("Keeper")

            if isGKState then
                local lowestdistance = math.huge
                local closestlimb = nil

                for _, Limb in ipairs(Character:GetChildren()) do
                    if Limb:IsA("BasePart") and TargetLimbNames[Limb.Name] then
                        local distancefrombal = (Limb.Position - Ball.Position).Magnitude
                        if distancefrombal < lowestdistance then
                            closestlimb = Limb
                            lowestdistance = distancefrombal
                        end
                    end
                end

                if closestlimb then

                    firetouchinterest(closestlimb, Ball, 0)
                    firetouchinterest(closestlimb, Ball, 1)
										SpoofTargetLimb = closestlimb
										--	 print(closestlimb)
                  --  SpoofTargetLimb = nil
                end
            else
                for _, Limb in ipairs(Character:GetChildren()) do
                    if Limb:IsA("BasePart") then
                       -- SpoofTargetLimb = Limb
                        firetouchinterest(Limb, Ball, 0)
                        firetouchinterest(Limb, Ball, 1)
										SpoofTargetLimb = nil
                    end
                end
            end
        end
    end)
end)
task.spawn(function()
	while task.wait(30) do
		local now = tick() * 1000
		for ball, t in pairs(LastReachTouch) do
			if not ball or not ball.Parent or (now - t) > 60000 then
				LastReachTouch[ball] = nil
			end
		end
	end
end)

local FPSFrameCount = 0
local FPSUpdateAccumulator = 0
RunService.Heartbeat:Connect(function(DeltaTime)
	if not (HRP and Humanoid and Character.Parent) then return end
	if FPSLabel and FPSLabel.Visible then
		FPSFrameCount = FPSFrameCount + 1
		FPSUpdateAccumulator = FPSUpdateAccumulator + DeltaTime
		if FPSUpdateAccumulator >= 0.5 then
			FPSLabel.Text = "FPS: " .. math.floor(FPSFrameCount / FPSUpdateAccumulator)
			FPSFrameCount = 0
			FPSUpdateAccumulator = 0
		end
	end
	if Flags.CharSpeedToggle and Character.PrimaryPart then
		Character.PrimaryPart:PivotTo(Character.PrimaryPart.CFrame + Humanoid.MoveDirection * DeltaTime * Flags.CharSpeed)
	end
end)
UserInputService.JumpRequest:Connect(function()
	if Flags.InfJumpToggle and Humanoid then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

local function CancelKnuckleWobble(ball)
	if KnuckleWobbleThreads[ball] then
		task.cancel(KnuckleWobbleThreads[ball])
		KnuckleWobbleThreads[ball] = nil
	end
end
local function ApplyKnuckleWobble(ball, rightVector)
	CancelKnuckleWobble(ball)
	local wobbleSpeed = Flags.KnuckleWobbleSpeed and Flags.KnuckleWobbleSpeed or 0.2
	local intensity = Flags.KnuckleWobbleIntensity and Flags.KnuckleWobbleIntensity or 1.0
	for _, child in ipairs(ball:GetChildren()) do
		if child:IsA("BodyForce") and child.Force.Magnitude > 0 then
			local f = child.Force
			if math.abs(f.X) + math.abs(f.Z) > math.abs(f.Y) * 2 then child:Destroy() end
		end
	end
	for _, child in ipairs(ball:GetChildren()) do
		if child:IsA("BodyAngularVelocity") then
			child.AngularVelocity = Vector3.new(math.random(-3,3)*0.5, math.random(-3,3)*0.5, math.random(-3,3)*0.5)
		end
	end
	local WobbleForce = Instance.new("BodyForce")
	WobbleForce.Force = rightVector * (250 * intensity)
	WobbleForce.Parent = ball
	Debris:AddItem(WobbleForce, 3)
	local wobbleAngular = Instance.new("BodyAngularVelocity")
	wobbleAngular.P = 2
	wobbleAngular.AngularVelocity = Vector3.new(math.random(-2,2), math.random(-2,2), math.random(-2,2))
	wobbleAngular.MaxTorque = Vector3.new(500, 500, 500)
	wobbleAngular.Parent = ball
	Debris:AddItem(wobbleAngular, 1)
	local pattern1 = {-400, 500, -600, 500}
	local pattern2 = { 400,-500,  600,-500}
	KnuckleWobbleThreads[ball] = task.spawn(function()
		local pattern = (math.random(1, 2) == 1) and pattern1 or pattern2
		for _, forceVal in ipairs(pattern) do
			if not ball or not ball.Parent or not WobbleForce or not WobbleForce.Parent then break end
			WobbleForce.Force = rightVector * (forceVal * intensity)
			task.wait(wobbleSpeed)
		end
		if WobbleForce and WobbleForce.Parent then WobbleForce:Destroy() end
		KnuckleWobbleThreads[ball] = nil
	end)
end

local PowerShotHooked = false
local LastPowerShotTime = 0

local function ApplyAdvancedBoostsVEF(ball, toolName)
	if not Flags.AdvancedBoostEnabled then return end
	if not CURVE_ENABLED_MOVES[toolName] then return end
	if not ball or not ball.Parent then return end
	pcall(function()
		for _, child in ipairs(ball:GetChildren()) do
			if child:IsA("BodyForce") then
				local force = child.Force
				local ay = math.abs(force.Y)
				local horizontalMag = math.sqrt(force.X^2 + force.Z^2)
				if horizontalMag > 5 and horizontalMag > ay then
					if ShouldBoosterFire("Curve", Flags.CurveBoostEnabled) then
						local mult = Flags.CurveBoostMult
						local cap = Flags.CurveBoostCap
						local newX = force.X * mult
						local newZ = force.Z * mult
						local newHorizMag = math.sqrt(newX^2 + newZ^2)
						if newHorizMag > cap then
							local s = cap / newHorizMag
							newX = newX * s
							newZ = newZ * s
						end
						child.Force = Vector3.new(newX, force.Y, newZ)
					end
				elseif force.Y > 5 and ay > horizontalMag then
					if Flags.TopspinBoostEnabled then
						child.Force = Vector3.new(force.X, force.Y * Flags.TopspinBoostMult, force.Z)
					end
				elseif force.Y < -5 and ay > horizontalMag then
					if Flags.BackspinBoostEnabled then
						child.Force = Vector3.new(force.X, force.Y * Flags.BackspinBoostMult, force.Z)
					end
				end
			elseif child:IsA("BodyAngularVelocity") then
				if ShouldBoosterFire("SpinRot", Flags.SpinRotBoostEnabled) then
					child.AngularVelocity = child.AngularVelocity * Flags.SpinRotBoostMult
					child.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
				end
			end
		end
	end)
end

local function ApplyAngleBoostVEF(bodyVel, toolName)
	if not Flags.AdvancedBoostEnabled then return end
	if not CURVE_ENABLED_MOVES[toolName] then return end
	if not Flags.AngleBoostEnabled then return end
	pcall(function()
		local mult = Flags.AngleBoostMult
		local cap = Flags.AngleBoostCap
		local currentVel = bodyVel.Velocity
		local newY = currentVel.Y * mult
		if math.abs(newY) > cap then newY = cap * (newY < 0 and -1 or 1) end
		bodyVel.Velocity = Vector3.new(currentVel.X, newY, currentVel.Z)
	end)
end

local function HookPowerShot()
	if PowerShotHooked then return end
	if not MainModule then return end
	if IS_MMP then
		PowerShotHooked = true
		return
	end
	local success, module = pcall(require, MainModule)
	if not success or not module or not module.React then return end
	local originalReact = module.React

	module.React = function(ball, limbName, bodyVel, ...)
		if not ball or not bodyVel then
			return originalReact(ball, limbName, bodyVel, ...)
		end
		local toolName = nil
		local tool = Character and Character:FindFirstChildOfClass("Tool")
		if tool then toolName = tool.Name end

		local powerShotShouldFire = false
		if Flags.InsanePowerShoot
			and typeof(bodyVel) == "Instance" and bodyVel:IsA("BodyVelocity") then
			if tool then
				local moveToggle = Flags["PowerShot_"..tool.Name]
				if moveToggle then
					local swapDelayMs = Flags.InsanePowerSwapDelay and Flags.InsanePowerSwapDelay or 500
					local timeSinceEquip = (tick() - LastToolEquipTime) * 1000
					if timeSinceEquip >= swapDelayMs then
						if typeof(ball) == "Instance" and ball:IsA("BasePart")
							and (ball.Name == "VEF" or ball.Name == "TPS" or ball.Name == "CMP")
							and ball.Size == Vector3.new(2.5, 2.5, 2.5)
							and not ball:FindFirstChildWhichIsA("Motor6D") then
							local now = tick()
							if now - LastPowerShotTime >= 0.2 then
								if HotkeyMasterOn() then
									if ArmedBoosters.PowerShot then
										powerShotShouldFire = true
										LastPowerShotTime = now
									end
								else
									powerShotShouldFire = true
									LastPowerShotTime = now
								end
							end
						end
					end
				end
			end
		end
		if powerShotShouldFire then
			pcall(function()
				local multiplier = Flags.InsanePowerValue
				local maxVel = Flags.InsanePowerMaxVel
				local currentVel = bodyVel.Velocity
				local newVel = Vector3.new(currentVel.X * multiplier, currentVel.Y, currentVel.Z * multiplier)
				local horizMag = Vector3.new(newVel.X, 0, newVel.Z).Magnitude
				if horizMag > maxVel then
					local scale = maxVel / horizMag
					newVel = Vector3.new(newVel.X * scale, currentVel.Y, newVel.Z * scale)
				end
				bodyVel.Velocity = newVel
			end)
		end

		if toolName then
			ApplyAngleBoostVEF(bodyVel, toolName)
			ApplyAdvancedBoostsVEF(ball, toolName)
		end

		local ok, result = pcall(originalReact, ball, limbName, bodyVel, ...)

		if ok and ball and ball.Parent then
			local knuckleShouldFire = false
			if HotkeyMasterOn() then
				knuckleShouldFire = ArmedBoosters.Knuckle
			else
				knuckleShouldFire = Flags.ForceKnuckleToggle
			end
			if knuckleShouldFire then
				local hasShootTool = Character and (Character:FindFirstChild("Shoot") or Character:FindFirstChild("Kick"))
				if hasShootTool then
					local rightVec = HRP and HRP.CFrame.rightVector or Vector3.new(1, 0, 0)
					task.delay(0.05, function()
						if ball and ball.Parent then ApplyKnuckleWobble(ball, rightVec) end
					end)
				end
			end
		end
		if ok then return result end
		return nil
	end
	PowerShotHooked = true
end
pcall(HookPowerShot)

LocalPlayer.CharacterAdded:Connect(function(NewCharacter)
	Character = NewCharacter
	Humanoid = Character:WaitForChild("Humanoid")
	HRP = NewCharacter:WaitForChild("HumanoidRootPart")
	task.spawn(function()
		task.wait(0.3)
		ApplyAntiRigBreak()
		WatchCharacterForBallManager(NewCharacter)
	end)
	if LocalPlayer.Backpack:FindFirstChild("ToolManagement") then
		MainModule = LocalPlayer.Backpack:WaitForChild("ToolManagement")
	elseif LocalPlayer.Backpack:FindFirstChild("ToolManagment") then
		MainModule = LocalPlayer.Backpack:WaitForChild("ToolManagment")
	elseif LocalPlayer.Backpack:FindFirstChild("module") then
		MainModule = LocalPlayer.Backpack:WaitForChild("module")
	end
	if MainModule then
		pcall(function() MainModuleTable = require(MainModule) end)
	end
	PowerShotHooked = false
	LastToolEquipTime = tick()
	TrackToolEquips(NewCharacter)
	BoosterHudGui = nil
	ClearAllLabels()
	ClearArmedBoosters()
	task.wait(1)
	pcall(HookPowerShot)
	pcall(BuildPreviewChar)
	local ok = pcall(ApplyBypass)
	if not ok then
		Notify({ Title = "Critical Error", Text = "Bypass failed!", Duration = 10 })
	end
end)

task.spawn(function()
	while true do
		local hz = Flags.BallPredHZ
		task.wait(hz > 0 and hz or 0.1)
		ClearDump("BallPrediction")
		if Flags.BallPredToggle then
			local balls = NO_FOLDER and _BALLS or BallsFolder:GetChildren()
			local threshold = Flags.BallPredThreshold
			for _, Ball in ipairs(balls) do
				if Ball.AssemblyLinearVelocity.Magnitude > threshold then PredictBall(Ball) end
			end
		end
	end
end)

if PingRemote and PingHandler then
	task.spawn(function()
		while true do
			task.wait(Flags.PingSpoofHZ)
			if Flags.PingSpoofToggle then
				PingRemote:FireServer(math.clamp(Flags.PingSpoof + math.random(-Flags.PingSpoofSpike, Flags.PingSpoofSpike), 0, math.huge))
			end
		end
	end)
end

-- Apply the autoloaded config LAST, so every listener/callback above is already
-- registered when the saved values are applied. (The old script called
-- LoadAutoloadConfig near the top, before most :OnChanged() handlers existed,
-- which silently skipped them for autoloaded values.)
if SaveManager then
	SaveManager:LoadAutoloadConfig()
end
