-- Language: Luau | File: BananaHubMobile.lua | Runtime: Roblox Executor (Mobile/Android) | Target: Roblox FPS (Guerra de Blocos / Genérico)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================================
-- CONFIGURAÇÃO CENTRAL, PERFIS DE ARMA & SNIPERS
-- ============================================================================
local Config = {
	AimbotEnabled = false,
	AimPart = "Head", -- "Head" | "HumanoidRootPart"
	FovRadius = 120,
	FovMin = 30,
	FovMax = 350,
	AimSmoothness = 0.25, -- 0.05 (suave) .. 1.0 (travado)
	EspEnabled = false,
	NoRecoilEnabled = false,
	SniperRecoilEnabled = true, -- aplica perfil de recoil em qualquer sniper detectada
	-- // FILL: troque pelo nome exato da Tool/arma específica (ex: "M4A1", "AK47", "SCAR")
	SpecificWeaponName = "TARGET_RIFLE_NAME",
	MenuVisible = true,
}

-- Perfis calibrados para: arma específica (rifle), snipers (kick alto) e demais armas
local WeaponProfiles = {
	SpecificGun = {
		MaxDeltaY = 0.0045,
		MaxDeltaX = 0.0065,
		Compensation = 0.95,
		HorizontalFactor = 0.65,
	},
	SniperDefault = {
		MaxDeltaY = 0.003,
		MaxDeltaX = 0.004,
		Compensation = 1.0,
		HorizontalFactor = 0.85,
	},
	Fallback = {
		MaxDeltaY = 0.012,
		MaxDeltaX = 0.016,
		Compensation = 0.85,
		HorizontalFactor = 0.50,
	},
}

-- // FILL: adicione nomes ou siglas exatas das snipers do jogo se não baterem nas palavras-chave
local SniperKeywords = {
	"sniper",
	"sr",
	"awp",
	"awm",
	"m24",
	"m40",
	"m82",
	"barrett",
	"intervention",
	"cheytac",
	"remington",
	"marksman",
	"dmr",
	"dragunov",
	"svd",
	"mosin",
	"kar98",
	"scout",
	"recon",
}

local Colors = {
	Bg = Color3.fromRGB(16, 18, 22),
	Header = Color3.fromRGB(24, 27, 34),
	Accent = Color3.fromRGB(46, 204, 113), -- verde para ativo
	Off = Color3.fromRGB(52, 58, 70),
	Text = Color3.fromRGB(235, 240, 245),
	SubText = Color3.fromRGB(155, 165, 180),
	Stroke = Color3.fromRGB(255, 255, 255),
}

local HasDrawing = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")

-- ============================================================================
-- UTILITÁRIOS DE SEGURANÇA, PERSONAGEM & DETECÇÃO DE ARMA/SNIPER
-- ============================================================================
local function safe_call(fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		warn("[KAIRO] erro:", res)
		return nil
	end
	return res
end

local function refresh_camera()
	if workspace.CurrentCamera then
		Camera = workspace.CurrentCamera
	end
end

local function is_enemy(player)
	if not player or player == LocalPlayer then
		return false
	end
	if LocalPlayer.Team and player.Team then
		return player.Team ~= LocalPlayer.Team
	end
	local my_team = LocalPlayer:GetAttribute("Team")
	local their_team = player:GetAttribute("Team")
	if my_team ~= nil and their_team ~= nil then
		return my_team ~= their_team
	end
	return true
end

local function get_character_parts(player)
	local char = player and player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil, nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hrp or not head then
		return nil, nil, nil
	end
	return char, hum, { Head = head, HumanoidRootPart = hrp }
end

local function get_equipped_weapon_name(char)
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then
		return tool.Name
	end
	local attr_weapon = LocalPlayer:GetAttribute("EquippedWeapon") or char:GetAttribute("Weapon")
	if typeof(attr_weapon) == "string" and #attr_weapon > 0 then
		return attr_weapon
	end
	return nil
end

local function is_sniper_weapon(weapon_name)
	if not weapon_name or weapon_name == "" then
		return false
	end
	local lower = string.lower(weapon_name)
	for _, key in ipairs(SniperKeywords) do
		if string.find(lower, key, 1, true) then
			return true
		end
	end
	return false
end

local function is_specific_weapon(weapon_name)
	if not weapon_name or weapon_name == "" or Config.SpecificWeaponName == "" then
		return false
	end
	if Config.SpecificWeaponName == "TARGET_RIFLE_NAME" then
		return false
	end
	return string.lower(weapon_name) == string.lower(Config.SpecificWeaponName)
end

local function resolve_recoil_profile(char)
	local weapon_name = get_equipped_weapon_name(char)

	if is_specific_weapon(weapon_name) then
		return WeaponProfiles.SpecificGun, weapon_name, "SPECIFIC"
	end

	if Config.SniperRecoilEnabled and is_sniper_weapon(weapon_name) then
		return WeaponProfiles.SniperDefault, weapon_name, "SNIPER"
	end

	return WeaponProfiles.Fallback, weapon_name, "DEFAULT"
end

local function make_draggable(frame, handle)
	local dragging = false
	local drag_input = nil
	local drag_start = Vector2.zero
	local start_pos = frame.Position

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			drag_start = Vector2.new(input.Position.X, input.Position.Y)
			start_pos = frame.Position
			drag_input = input

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
			drag_input = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == drag_input then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - drag_start
			frame.Position = UDim2.new(
				start_pos.X.Scale,
				start_pos.X.Offset + delta.X,
				start_pos.Y.Scale,
				start_pos.Y.Offset + delta.Y
			)
		end
	end)
end

-- ============================================================================
-- MÓDULO: ESP (SOMENTE INIMIGOS)
-- ============================================================================
local EspModule = { Objects = {} }

local function create_esp_entry(player)
	if not HasDrawing then
		return nil
	end

	local box = Drawing.new("Square")
	box.Thickness = 1.5
	box.Filled = false
	box.Color = Color3.fromRGB(255, 75, 75)
	box.Visible = false

	local tracer = Drawing.new("Line")
	tracer.Thickness = 1.2
	tracer.Color = Color3.fromRGB(255, 110, 110)
	tracer.Visible = false

	local label = Drawing.new("Text")
	label.Size = 13
	label.Center = true
	label.Outline = true
	label.Color = Color3.fromRGB(255, 255, 255)
	label.Visible = false

	return { Box = box, Tracer = tracer, Label = label }
end

local function hide_esp_entry(entry)
	if not entry then
		return
	end
	entry.Box.Visible = false
	entry.Tracer.Visible = false
	entry.Label.Visible = false
end

local function remove_esp_entry(player)
	local entry = EspModule.Objects[player]
	if not entry then
		return
	end
	safe_call(function()
		entry.Box:Remove()
		entry.Tracer:Remove()
		entry.Label:Remove()
	end)
	EspModule.Objects[player] = nil
end

function EspModule.Update()
	if not HasDrawing then
		return
	end

	if not Config.EspEnabled then
		for _, entry in pairs(EspModule.Objects) do
			hide_esp_entry(entry)
		end
		return
	end

	refresh_camera()
	local _, _, my_parts = get_character_parts(LocalPlayer)
	local origin_pos = (my_parts and my_parts.HumanoidRootPart.Position) or Camera.CFrame.Position
	local screen_bottom = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y)

	for player, entry in pairs(EspModule.Objects) do
		if not player.Parent or not is_enemy(player) then
			hide_esp_entry(entry)
			continue
		end

		local char, hum, parts = get_character_parts(player)
		if not char or not parts then
			hide_esp_entry(entry)
			continue
		end

		local root_pos = parts.HumanoidRootPart.Position
		local head_pos = parts.Head.Position + Vector3.new(0, 0.5, 0)
		local foot_pos = root_pos - Vector3.new(0, 3.0, 0)

		local root_screen, on_screen = Camera:WorldToViewportPoint(root_pos)
		if not on_screen or root_screen.Z <= 0 then
			hide_esp_entry(entry)
			continue
		end

		local top_screen = Camera:WorldToViewportPoint(head_pos)
		local bot_screen = Camera:WorldToViewportPoint(foot_pos)
		local height = math.clamp(math.abs(bot_screen.Y - top_screen.Y), 10, 600)
		local width = height * 0.55
		local dist = math.floor((root_pos - origin_pos).Magnitude)

		entry.Box.Size = Vector2.new(width, height)
		entry.Box.Position = Vector2.new(root_screen.X - width * 0.5, top_screen.Y)
		entry.Box.Visible = true

		entry.Tracer.From = screen_bottom
		entry.Tracer.To = Vector2.new(root_screen.X, bot_screen.Y)
		entry.Tracer.Visible = true

		entry.Label.Text = string.format("%s [%dm] | %dHP", player.Name, dist, math.floor(hum.Health))
		entry.Label.Position = Vector2.new(root_screen.X, top_screen.Y - 16)
		entry.Label.Visible = true
	end
end

function EspModule.Init()
	if not HasDrawing then
		warn("[KAIRO] Drawing API indisponível neste executor; ESP visual desativado.")
		return
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			EspModule.Objects[plr] = create_esp_entry(plr)
		end
	end

	Players.PlayerAdded:Connect(function(plr)
		if plr ~= LocalPlayer then
			EspModule.Objects[plr] = create_esp_entry(plr)
		end
	end)

	Players.PlayerRemoving:Connect(remove_esp_entry)
end

-- ============================================================================
-- MÓDULO: AIMBOT & FOV
-- ============================================================================
local AimbotModule = { FovCircle = nil }

function AimbotModule.Init()
	if not HasDrawing then
		return
	end
	local circle = Drawing.new("Circle")
	circle.Thickness = 1.5
	circle.NumSides = 48
	circle.Filled = false
	circle.Color = Colors.Accent
	circle.Visible = false
	AimbotModule.FovCircle = circle
end

local function get_best_target(center_screen)
	local best_part = nil
	local best_dist = Config.FovRadius

	for _, plr in ipairs(Players:GetPlayers()) do
		if not is_enemy(plr) then
			continue
		end

		local _, _, parts = get_character_parts(plr)
		if not parts then
			continue
		end

		local target_part = parts[Config.AimPart] or parts.Head
		local screen_pos, on_screen = Camera:WorldToViewportPoint(target_part.Position)
		if not on_screen or screen_pos.Z <= 0 then
			continue
		end

		local dist_2d = (Vector2.new(screen_pos.X, screen_pos.Y) - center_screen).Magnitude
		if dist_2d <= best_dist then
			best_dist = dist_2d
			best_part = target_part
		end
	end

	return best_part
end

function AimbotModule.Update()
	refresh_camera()
	local center = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5)

	if AimbotModule.FovCircle then
		AimbotModule.FovCircle.Visible = Config.AimbotEnabled
		if Config.AimbotEnabled then
			AimbotModule.FovCircle.Position = center
			AimbotModule.FovCircle.Radius = Config.FovRadius
		end
	end

	if not Config.AimbotEnabled then
		return
	end

	local is_aiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or (#UserInputService:GetTouches() > 0)

	if not is_aiming then
		return
	end

	local target_part = get_best_target(center)
	if not target_part then
		return
	end

	local desired_cf = CFrame.lookAt(Camera.CFrame.Position, target_part.Position)
	Camera.CFrame = Camera.CFrame:Lerp(desired_cf, math.clamp(Config.AimSmoothness, 0.05, 1))
end

-- ============================================================================
-- MÓDULO: NO RECOIL (ARMA ESPECÍFICA + TODAS AS SNIPERS)
-- ============================================================================
local RecoilModule = { LastLook = nil, ActiveMode = "DEFAULT", ActiveWeapon = nil }

-- // FILL: se o jogo aplicar recoil via tabela/módulo de arma ou Camera spring próprio,
-- // inspecione ReplicatedStorage / armas equipadas no DEX e ajuste aqui.
function RecoilModule.Update()
	refresh_camera()
	local char = LocalPlayer.Character
	local profile, weapon_name, mode = resolve_recoil_profile(char)
	RecoilModule.ActiveWeapon = weapon_name
	RecoilModule.ActiveMode = mode

	if not Config.NoRecoilEnabled then
		RecoilModule.LastLook = Camera.CFrame.LookVector
		return
	end

	local current_look = Camera.CFrame.LookVector
	if RecoilModule.LastLook then
		local delta_y = current_look.Y - RecoilModule.LastLook.Y
		local delta_x = math.abs(current_look.X - RecoilModule.LastLook.X)

		if delta_y > profile.MaxDeltaY or delta_x > profile.MaxDeltaX then
			local comp = math.clamp(profile.Compensation, 0.1, 1.0)
			local h_factor = math.clamp(profile.HorizontalFactor or 0.5, 0.0, 1.0)
			local target_y = current_look.Y - (delta_y * comp)
			local target_x = current_look.X - ((current_look.X - RecoilModule.LastLook.X) * comp * h_factor)
			local pos = Camera.CFrame.Position
			local compensated_look = Vector3.new(target_x, target_y, current_look.Z).Unit
			Camera.CFrame = CFrame.lookAt(pos, pos + compensated_look)
		end
	end
	RecoilModule.LastLook = Camera.CFrame.LookVector
end

-- ============================================================================
-- INTERFACE TRANSPARENTE & BOTÃO FLUTUANTE (MOBILE)
-- ============================================================================
local function build_ui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BananaHubMobileUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local ok = pcall(function()
		gui.Parent = CoreGui
	end)
	if not ok then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	local float_btn = Instance.new("TextButton")
	float_btn.Name = "FloatingToggle"
	float_btn.Size = UDim2.fromOffset(54, 54)
	float_btn.Position = UDim2.fromOffset(18, 120)
	float_btn.BackgroundColor3 = Colors.Header
	float_btn.BackgroundTransparency = 0.25
	float_btn.Text = "BANANA"
	float_btn.TextColor3 = Colors.Accent
	float_btn.TextSize = 10
	float_btn.Font = Enum.Font.GothamBold
	float_btn.AutoButtonColor = false
	float_btn.Parent = gui

	local float_corner = Instance.new("UICorner")
	float_corner.CornerRadius = UDim.new(1, 0)
	float_corner.Parent = float_btn

	local float_stroke = Instance.new("UIStroke")
	float_stroke.Color = Colors.Accent
	float_stroke.Transparency = 0.35
	float_stroke.Thickness = 1.5
	float_stroke.Parent = float_btn

	local panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.fromOffset(275, 330)
	panel.Position = UDim2.fromOffset(85, 95)
	panel.BackgroundColor3 = Colors.Bg
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel = 0
	panel.Visible = Config.MenuVisible
	panel.Parent = gui

	local panel_corner = Instance.new("UICorner")
	panel_corner.CornerRadius = UDim.new(0, 12)
	panel_corner.Parent = panel

	local panel_stroke = Instance.new("UIStroke")
	panel_stroke.Color = Colors.Stroke
	panel_stroke.Transparency = 0.78
	panel_stroke.Thickness = 1
	panel_stroke.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = Colors.Header
	header.BackgroundTransparency = 0.25
	header.BorderSizePixel = 0
	header.Parent = panel

	local header_corner = Instance.new("UICorner")
	header_corner.CornerRadius = UDim.new(0, 12)
	header_corner.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.BackgroundTransparency = 1
	title.Text = "BANANA HUB VIP // MOBILE"
	title.TextColor3 = Colors.Text
	title.TextSize = 13
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -16, 1, -46)
	content.Position = UDim2.fromOffset(8, 42)
	content.BackgroundTransparency = 1
	content.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	local function create_toggle(label_text, initial_state, order, on_toggle)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 34)
		btn.LayoutOrder = order
		btn.BackgroundTransparency = 0.25
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamSemibold
		btn.TextColor3 = Colors.Text
		btn.AutoButtonColor = false
		btn.Parent = content

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = btn

		local function paint(active)
			btn.BackgroundColor3 = active and Colors.Accent or Colors.Off
			btn.TextColor3 = active and Color3.fromRGB(10, 15, 12) or Colors.Text
			btn.Text = string.format("%s: %s", label_text, active and "ON" or "OFF")
		end

		paint(initial_state)

		btn.MouseButton1Click:Connect(function()
			local next_state = on_toggle()
			paint(next_state)
		end)
	end

	create_toggle("Aimbot", Config.AimbotEnabled, 1, function()
		Config.AimbotEnabled = not Config.AimbotEnabled
		return Config.AimbotEnabled
	end)

	create_toggle("ESP Inimigos", Config.EspEnabled, 2, function()
		Config.EspEnabled = not Config.EspEnabled
		return Config.EspEnabled
	end)

	create_toggle("No Recoil", Config.NoRecoilEnabled, 3, function()
		Config.NoRecoilEnabled = not Config.NoRecoilEnabled
		return Config.NoRecoilEnabled
	end)

	create_toggle("Snipers Recoil", Config.SniperRecoilEnabled, 4, function()
		Config.SniperRecoilEnabled = not Config.SniperRecoilEnabled
		return Config.SniperRecoilEnabled
	end)

	local target_row = Instance.new("Frame")
	target_row.Size = UDim2.new(1, 0, 0, 34)
	target_row.LayoutOrder = 5
	target_row.BackgroundTransparency = 1
	target_row.Parent = content

	local head_btn = Instance.new("TextButton")
	head_btn.Size = UDim2.new(0.485, 0, 1, 0)
	head_btn.Position = UDim2.fromScale(0, 0)
	head_btn.BackgroundTransparency = 0.25
	head_btn.Text = "Head"
	head_btn.TextSize = 12
	head_btn.Font = Enum.Font.GothamBold
	head_btn.AutoButtonColor = false
	head_btn.Parent = target_row

	local head_corner = Instance.new("UICorner")
	head_corner.CornerRadius = UDim.new(0, 8)
	head_corner.Parent = head_btn

	local hrp_btn = Instance.new("TextButton")
	hrp_btn.Size = UDim2.new(0.485, 0, 1, 0)
	hrp_btn.Position = UDim2.fromScale(0.515, 0)
	hrp_btn.BackgroundTransparency = 0.25
	hrp_btn.Text = "HRP"
	hrp_btn.TextSize = 12
	hrp_btn.Font = Enum.Font.GothamBold
	hrp_btn.AutoButtonColor = false
	hrp_btn.Parent = target_row

	local hrp_corner = Instance.new("UICorner")
	hrp_corner.CornerRadius = UDim.new(0, 8)
	hrp_corner.Parent = hrp_btn

	local function refresh_target_buttons()
		local is_head = (Config.AimPart == "Head")
		head_btn.BackgroundColor3 = is_head and Colors.Accent or Colors.Off
		head_btn.TextColor3 = is_head and Color3.fromRGB(10, 15, 12) or Colors.Text

		hrp_btn.BackgroundColor3 = (not is_head) and Colors.Accent or Colors.Off
		hrp_btn.TextColor3 = (not is_head) and Color3.fromRGB(10, 15, 12) or Colors.Text
	end

	refresh_target_buttons()
	head_btn.MouseButton1Click:Connect(function()
		Config.AimPart = "Head"
		refresh_target_buttons()
	end)
	hrp_btn.MouseButton1Click:Connect(function()
		Config.AimPart = "HumanoidRootPart"
		refresh_target_buttons()
	end)

	local slider_box = Instance.new("Frame")
	slider_box.Size = UDim2.new(1, 0, 0, 46)
	slider_box.LayoutOrder = 6
	slider_box.BackgroundColor3 = Colors.Header
	slider_box.BackgroundTransparency = 0.35
	slider_box.Parent = content

	local slider_corner = Instance.new("UICorner")
	slider_corner.CornerRadius = UDim.new(0, 8)
	slider_corner.Parent = slider_box

	local slider_label = Instance.new("TextLabel")
	slider_label.Size = UDim2.new(1, -16, 0, 18)
	slider_label.Position = UDim2.fromOffset(8, 3)
	slider_label.BackgroundTransparency = 1
	slider_label.Text = "FOV: " .. tost
