--[[
	WARUNG AUTO - Jadi Penjaga Warung (78012998340303)
	Fitur Khusus:
	1. Auto Detect Anomali (ESP + Auto Tutup/Buka Garasi)
	2. Auto Delivery (Auto Angkat Telepon, Ambil Barang, Antar ke Rumah Pembeli)
	3. Auto Isi Token (Auto Beli di Konter, Isi di Meteran)
	4. Auto Isi Rak Kosong
	5. Auto Ambil Barang Pelanggan (Ciki, Mie, Galon, Gas, Minuman, Bensin, Kresek)
]]

do
	local cloneref = (cloneref or clonereference or function(inst) return inst end);
	local RS  = cloneref(game:GetService("ReplicatedStorage"));
	local CS  = cloneref(game:GetService("CollectionService"));
	local Players = cloneref(game:GetService("Players"));
	local Plr = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait();
	local TweenService = cloneref(game:GetService("TweenService"));

	-- Load UI Library dari GitHub Raw
	local ModernV2 = loadstring(game:HttpGet("https://raw.githubusercontent.com/nexiuse/NexHubNewUI/refs/heads/main/MainV2.lua"))();

	-- Helper aman: cari posisi World Vector3 tanpa error
	local function getPromptPos(inst)
		if not inst then return nil end;
		if inst:IsA("BasePart") then
			return inst.Position;
		elseif inst:IsA("Attachment") then
			return inst.WorldPosition;
		elseif inst:IsA("Model") and inst.PrimaryPart then
			return inst.PrimaryPart.Position;
		elseif inst:IsA("ProximityPrompt") then
			local p = inst.Parent;
			if p then
				if p:IsA("BasePart") then return p.Position end;
				if p:IsA("Attachment") then return p.WorldPosition end;
				local bp = p:FindFirstAncestorWhichIsA("BasePart") or p:FindFirstChildWhichIsA("BasePart", true);
				if bp then return bp.Position end;
			end;
		end;
		local bp = inst:FindFirstAncestorWhichIsA("BasePart") or inst:FindFirstChildWhichIsA("BasePart", true);
		if bp then return bp.Position end;
		return nil;
	end;

	-- â”€â”€ Flag & Mutex untuk Gerakan Aman & Anti-Stuck â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local isGliding      = false; -- Mutex: hanya 1 glide dalam satu waktu
	local isGlobalMoving = false; -- Lock: delivery/token sedang pergi dari warung

	-- â”€â”€ Safe Glide: Mulus, Bebas Tabrakan Kendaraan, Anti-Jatuh & Anti-Stuck â”€â”€
	local function safeGlide(targetCF, duration)
		local char = Plr.Character;
		local hrp  = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart);
		local hum  = char and char:FindFirstChildOfClass("Humanoid");
		if not hrp or not hum then return end;

		-- Tunggu antrean jika sedang ada glide lain (maksimal 2.5 detik)
		local tWait = os.clock();
		while isGliding and os.clock() - tWait < 2.5 do
			task.wait(0.04);
		end;

		isGliding = true;
		duration = duration or 0.35;

		pcall(function()
			local startCF = hrp.CFrame;
			local dist = (targetCF.Position - startCF.Position).Magnitude;

			-- Hentikan velocity sebelum glide agar tidak ada momentum lemparan
			hrp.AssemblyLinearVelocity = Vector3.zero;
			hrp.AssemblyAngularVelocity = Vector3.zero;
			hrp.Anchored = true;

			-- Jika jarak jauh (> 14 studs, e.g. antar delivery / beli token konter):
			-- Glide dengan lintasan sedikit melengkung ke atas (+5 studs arc)
			-- sehingga terbang di atas motor/mobil di jalan raya, bebas tabrakan (VehHitUtil)
			-- dan darah tidak berkurang karena tertabrak!
			if dist > 14 then
				local midPos = (startCF.Position + targetCF.Position) * 0.5 + Vector3.new(0, 5.0, 0);
				local midCF  = CFrame.new(midPos, targetCF.Position);
				local halfDur = duration * 0.5;

				local tw1 = TweenService:Create(hrp, TweenInfo.new(halfDur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = midCF});
				tw1:Play();
				tw1.Completed:Wait();

				local tw2 = TweenService:Create(hrp, TweenInfo.new(halfDur, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {CFrame = targetCF});
				tw2:Play();
				tw2.Completed:Wait();
			else
				local tw = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = targetCF});
				tw:Play();
				tw.Completed:Wait();
			end;
		end);

		-- CLEANUP MUTLAK: Selalu kembalikan Anchored = false dan reset fisika
		-- agar avatar TIDAK PERNAH MACET / TIDAK BISA JALAN
		pcall(function()
			hrp.Anchored = false;
			hrp.AssemblyLinearVelocity = Vector3.zero;
			hrp.AssemblyAngularVelocity = Vector3.zero;
			if hum then
				hum.PlatformStand = false;
				hum.Sit = false;
				local state = hum:GetState();
				if state == Enum.HumanoidStateType.FallingDown
					or state == Enum.HumanoidStateType.Ragdoll
					or state == Enum.HumanoidStateType.PlatformStanding then
					hum:ChangeState(Enum.HumanoidStateType.GettingUp);
					task.wait(0.04);
					hum:ChangeState(Enum.HumanoidStateType.Running);
				end;
				if hum.WalkSpeed < 16 then hum.WalkSpeed = 16 end;
			end;
		end);

		isGliding = false;
	end;
	local smoothGlide = safeGlide; -- Alias kompatibilitas

	-- â”€â”€ Anti-Darah Berkurang (Godmode / Nyawa Shield & Anti-Ragdoll) â”€â”€
	local function protectCharacter(char)
		if not char then return end;
		local hum = char:WaitForChild("Humanoid", 6);
		if hum then
			-- Darah Roblox default
			hum.HealthChanged:Connect(function(hp)
				if hp < hum.MaxHealth then
					pcall(function() hum.Health = hum.MaxHealth end);
				end;
			end);

			-- Anti-Ragdoll: jika jatuh langsung bangun otomatis
			hum.StateChanged:Connect(function(_, newState)
				if newState == Enum.HumanoidStateType.FallingDown
					or newState == Enum.HumanoidStateType.Ragdoll
					or newState == Enum.HumanoidStateType.PlatformStanding then
					task.wait(0.04);
					pcall(function()
						hum.PlatformStand = false;
						hum.Sit = false;
						hum:ChangeState(Enum.HumanoidStateType.GettingUp);
						task.wait(0.04);
						hum:ChangeState(Enum.HumanoidStateType.Running);
					end);
				end;
			end);
		end;
	end;

	pcall(function() protectCharacter(Plr.Character) end);
	Plr.CharacterAdded:Connect(protectCharacter);

	-- Kunci attribute "Nyawa" ke 100 (Sistem Darah Khusus Game Warung)
	pcall(function()
		Plr:SetAttribute("Nyawa", 100);
		Plr:GetAttributeChangedSignal("Nyawa"):Connect(function()
			local currentNyawa = tonumber(Plr:GetAttribute("Nyawa")) or 100;
			if currentNyawa < 100 then
				pcall(function() Plr:SetAttribute("Nyawa", 100) end);
			end;
		end);
	end);

	-- â”€â”€ Anti-Stuck Watchdog (Menjaga Avatar Selalu Bisa Jalan Bebas) â”€â”€
	task.spawn(function()
		while true do
			task.wait(0.5);
			pcall(function()
				local char = Plr.Character;
				local hrp  = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart);
				local hum  = char and char:FindFirstChildOfClass("Humanoid");

				-- Lepas anchored jika tersisa saat tidak sedang glide
				if hrp and not isGliding and hrp.Anchored == true then
					hrp.Anchored = false;
				end;

				-- Pulihkan kontrol humanoid
				if hum then
					if hum.PlatformStand == true then hum.PlatformStand = false end;
					if hum.Sit == true then hum.Sit = false end;
					if hum.WalkSpeed < 16 then hum.WalkSpeed = 16 end;
				end;

				-- Pastikan kamera tidak terkunci oleh dialog/gui yang lupa restore
				if not isGlobalMoving and Plr:GetAttribute("CameraActive") == false then
					Plr:SetAttribute("CameraActive", true);
				end;
			end);
		end;
	end);

	-- Helper: trigger proximity prompt instan tanpa hold
	local function triggerPrompt(prompt)
		if not prompt or not prompt.Enabled then return false end;
		local origHold = prompt.HoldDuration or 0;
		pcall(function() prompt.HoldDuration = 0 end);

		local fired = false;
		if fireproximityprompt then
			fired = pcall(fireproximityprompt, prompt);
		end;
		if not fired then
			pcall(function()
				prompt:InputHoldBegin();
				task.wait(math.max(0.06, origHold));
				prompt:InputHoldEnd();
			end);
		end;

		pcall(function() prompt.HoldDuration = origHold end);
		return true;
	end;

	-- Helper: ambil barang (jika dalam jarak jangkauan langsung ambil, jika di luar jangkauan glide mulus)
	local function takeItem(partOrPrompt)
		if not partOrPrompt then return false end;
		local prompt = partOrPrompt:IsA("ProximityPrompt") and partOrPrompt or partOrPrompt:FindFirstChild("BeliPrompt") or partOrPrompt:FindFirstChildWhichIsA("ProximityPrompt", true);
		if not prompt or not prompt.Enabled then return false end;

		local char = Plr.Character;
		local hrp  = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart);
		local pos  = getPromptPos(prompt);

		-- Jika dalam radius 9 studs, langsung ambil di tempat tanpa gerak
		if not hrp or not pos or (hrp.Position - pos).Magnitude <= 9 then
			return triggerPrompt(prompt);
		end;

		-- Jangan ambil barang lewat glide jika sedang dalam misi delivery / token di luar warung
		if isGlobalMoving then return false end;

		-- Jika di luar jangkauan (> 9 studs), glide cepat dan kembali mulus
		local origCF = hrp.CFrame;
		local targetCF = CFrame.new(pos + Vector3.new(0, 1.2, 0), pos);
		safeGlide(targetCF, 0.16);
		task.wait(0.06);
		triggerPrompt(prompt);
		task.wait(0.06);
		safeGlide(origCF, 0.16);
		return true;
	end;

	local function waitFor(parent, name, timeout)
		local obj = parent:WaitForChild(name, timeout or 15);
		if not obj then
			warn("[WarungAuto] Remote/Folder tidak ditemukan: " .. tostring(name));
		end;
		return obj;
	end;

	local DeliveryR = waitFor(RS, "DeliveryRemotes");
	local GrosirR   = waitFor(RS, "GrosirRemotes");
	local GudangR   = waitFor(RS, "GudangRemotes");
	local TokenR    = waitFor(RS, "TokenListrikRemotes");

	-- â”€â”€ Auto-selesaikan dialog konter saat beli token â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	pcall(function()
		local BalasSeqRemote = RS:FindFirstChild("BalasSeqRemote");
		if BalasSeqRemote then
			BalasSeqRemote.OnClientEvent:Connect(function(a1, a2)
				local seqKey = a2 or a1;
				if seqKey and TokenR and TokenR:FindFirstChild("DialogDone") then
					task.wait(0.2);
					pcall(function() TokenR.DialogDone:FireServer(seqKey) end);
					task.wait(0.4);
					pcall(function() TokenR.DialogDone:FireServer(seqKey) end);
				end;
			end);
		end;
	end);

	-- â”€â”€ Auto-klik "Berikan" saat server buka popup delivery â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	-- Server fire Pilih.OnClientEvent â†’ kita langsung balas Pilih:FireServer("beri")
	local autoDeliveryBeri = false; -- hanya aktif saat toggle AutoDelivery on
	pcall(function()
		if DeliveryR and DeliveryR:FindFirstChild("Pilih") then
			DeliveryR.Pilih.OnClientEvent:Connect(function(_)
				if autoDeliveryBeri then
					task.wait(0.15);
					pcall(function() DeliveryR.Pilih:FireServer("beri") end);
				end;
			end);
		end;
	end);

	local WAFlags   = {};
	local WAThreads = {};
	local wasClosedNotified = false;
	local ToggleAnomali, ToggleDelivery, ToggleToken, ToggleIsiRak, ToggleLayani;

	local function killThread(key)
		if WAThreads[key] then
			task.cancel(WAThreads[key]);
			WAThreads[key] = nil;
		end;
	end;

	local function spawnLoop(key, fn, interval)
		killThread(key);
		WAThreads[key] = task.spawn(function()
			while WAFlags[key] do
				pcall(fn);
				task.wait(interval or 1);
			end;
		end);
	end;

	-- â”€â”€ Deteksi Waktu Warung Tutup (Shift Berakhir / Waktu Tidur) â”€â”€â”€
	local function isWarungClosed()
		-- 1. Game tamat / selesai
		if RS:GetAttribute("GameTamat") == true then return true end;

		-- 2. Atribut shift selesai & tidur dari game
		if Plr:GetAttribute("NeedSleep") == true then return true end;
		if Plr:GetAttribute("Sleeping") == true then return true end;
		if Plr:GetAttribute("CinematicActive") == true then return true end;

		-- 3. Jam Operasional Warung (GameClock / Lighting.ClockTime)
		-- Jam operasional warung: jam 18:00 malam s/d 04:00 subuh.
		-- Jam tutup warung: jam 04:00 pagi s/d 18:00 sore.
		local clock = RS:GetAttribute("GameClock");
		if type(clock) ~= "number" then
			local lighting = game:GetService("Lighting");
			clock = lighting and lighting.ClockTime;
		end;
		if type(clock) == "number" then
			if clock >= 4.0 and clock < 18.0 then
				return true;
			end;
		end;

		return false;
	end;

	-- Forward declarations
	local clearAnomalyVisuals;
	local closeGarage;

	-- â”€â”€ Matikan Semua Fitur Saat Warung Tutup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local function turnOffAllFeatures()
		pcall(function()
			if ToggleAnomali and ToggleAnomali:GetValue() then ToggleAnomali:SetValue(false) end;
			if ToggleDelivery and ToggleDelivery:GetValue() then ToggleDelivery:SetValue(false) end;
			if ToggleToken and ToggleToken:GetValue() then ToggleToken:SetValue(false) end;
			if ToggleIsiRak and ToggleIsiRak:GetValue() then ToggleIsiRak:SetValue(false) end;
			if ToggleLayani and ToggleLayani:GetValue() then ToggleLayani:SetValue(false) end;
		end);

		for key in pairs(WAFlags) do
			WAFlags[key] = false;
			killThread(key);
		end;

		if clearAnomalyVisuals then pcall(clearAnomalyVisuals) end;
		if closeGarage then pcall(closeGarage) end; -- Tutup rolling door rapat saat warung tutup

		if not wasClosedNotified then
			wasClosedNotified = true;
			pcall(function()
				ModernV2:Notify({
					Title = "Warung Tutup",
					Content = "Shift selesai (04:00). Semua fitur otomatis dimatikan demi keamanan.",
					Duration = 5,
					Icon = "lucide:moon",
				});
			end);
		end;
	end;

	local function checkWarungStatus()
		if isWarungClosed() then
			turnOffAllFeatures();
		else
			wasClosedNotified = false;
		end;
	end;

	-- Monitor perubahan status jam dan tidur dari server
	pcall(function()
		Plr:GetAttributeChangedSignal("NeedSleep"):Connect(checkWarungStatus);
		Plr:GetAttributeChangedSignal("Sleeping"):Connect(checkWarungStatus);
		Plr:GetAttributeChangedSignal("CinematicActive"):Connect(checkWarungStatus);
		RS:GetAttributeChangedSignal("GameClock"):Connect(checkWarungStatus);
		RS:GetAttributeChangedSignal("GameTamat"):Connect(checkWarungStatus);
	end);

	-- Loop periodik untuk deteksi waktu (Lighting.ClockTime / GameClock)
	task.spawn(function()
		while true do
			task.wait(1.5);
			pcall(checkWarungStatus);
		end;
	end);

	local function getInterior()
		return workspace:FindFirstChild("InteriorWarung");
	end;

	-- Helper: dapatkan titik pusat warung
	local function getWarungPos()
		local garage = workspace:FindFirstChild("Model") and workspace.Model:FindFirstChild("GarageWarung");
		if garage then
			local roll = garage:FindFirstChild("Roll") or garage:FindFirstChildWhichIsA("BasePart", true);
			if roll and roll:IsA("BasePart") then return roll.Position end;
		end;
		local interior = getInterior();
		if interior then
			local ib = interior:FindFirstChild("InteraksiBarang");
			if ib then
				local p = ib:FindFirstChildWhichIsA("BasePart", true);
				if p then return p.Position end;
			end;
			local anyP = interior:FindFirstChildWhichIsA("BasePart", true);
			if anyP then return anyP.Position end;
		end;
		return Vector3.new(0, 0, 0);
	end;

	-- â”€â”€ Cek Apakah Model Adalah Anomali â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local ghostNames = {
		["Valak"] = true, ["Tuyul"] = true, ["PocongPutih"] = true,
		["Tuyul2"] = true, ["Tengkorak"] = true, ["Vecna"] = true
	};

	local function isEntityAnomaly(m)
		if not m or not m:IsA("Model") or m == Plr.Character then return false end;
		if m:GetAttribute("Anomali") == true then return true end;
		if m:GetAttribute("AnomKind") ~= nil then return true end;
		if m:GetAttribute("AnomGhost") ~= nil then return true end;
		if m:GetAttribute("AnomBurning") == true then return true end;
		if CS:HasTag(m, "AnomaliShop") then return true end;
		if ghostNames[m.Name] then return true end;
		for _, c in ipairs(m:GetChildren()) do
			if ghostNames[c.Name] then return true end;
		end;
		return false;
	end;

	local lastAnomalySeen  = 0;
	local lastGarageAction = 0;
	local garageCurrent    = "open";

	local function checkWarungAnomaly()
		local warungCenter = getWarungPos();

		-- 1. Cek folder WargaAktif (pelanggan sedang di warung)
		local wargaAktif = workspace:FindFirstChild("WargaAktif");
		if wargaAktif then
			for _, npc in ipairs(wargaAktif:GetChildren()) do
				if isEntityAnomaly(npc) then
					lastAnomalySeen = os.clock();
					return true, npc;
				end;
			end;
		end;

		-- 2. Cek PengendaraAktif (pembeli motor bensin)
		local pengendara = workspace:FindFirstChild("PengendaraAktif");
		if pengendara then
			for _, m in ipairs(pengendara:GetChildren()) do
				if isEntityAnomaly(m) then
					lastAnomalySeen = os.clock();
					return true, m;
				end;
			end;
		end;

		-- 3. Cek LimitedHantu & MalingAktif
		local limited = workspace:FindFirstChild("LimitedHantu");
		if limited and #limited:GetChildren() > 0 then
			lastAnomalySeen = os.clock();
			return true, limited:GetChildren()[1];
		end;
		local maling = workspace:FindFirstChild("MalingAktif");
		if maling and #maling:GetChildren() > 0 then
			for _, m in ipairs(maling:GetChildren()) do
				local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart");
				if root and (root.Position - warungCenter).Magnitude <= 70 then
					lastAnomalySeen = os.clock();
					return true, m;
				end;
			end;
		end;

		-- 4. Cek semua instance dengan tag AnomaliShop dalam radius 75 studs dari warung
		for _, obj in ipairs(CS:GetTagged("AnomaliShop")) do
			local model = obj:IsA("Model") and obj or obj:FindFirstAncestorOfClass("Model");
			if model and model ~= Plr.Character then
				local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart");
				if root and (root.Position - warungCenter).Magnitude <= 75 then
					lastAnomalySeen = os.clock();
					return true, model;
				end;
			end;
		end;

		-- 5. Cek warga di Pemukiman yang mendekati warung (radius 60 studs)
		local pemukiman = workspace:FindFirstChild("Pemukiman");
		local warga = pemukiman and pemukiman:FindFirstChild("Warga");
		if warga then
			for _, npc in ipairs(warga:GetChildren()) do
				if isEntityAnomaly(npc) then
					local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart");
					if root and (root.Position - warungCenter).Magnitude <= 60 then
						lastAnomalySeen = os.clock();
						return true, npc;
					end;
				end;
			end;
		end;

		-- 6. Cek AnomaliCctvFx yang aktif dekat warung
		local cctvFx = workspace:FindFirstChild("AnomaliCctvFx");
		if cctvFx then
			for _, f in ipairs(cctvFx:GetChildren()) do
				local root = f:FindFirstChild("HumanoidRootPart") or f.PrimaryPart or f:FindFirstChildWhichIsA("BasePart");
				if root and (root.Position - warungCenter).Magnitude <= 70 then
					lastAnomalySeen = os.clock();
					return true, f;
				end;
			end;
		end;

		return false, nil;
	end;

	-- â”€â”€ Kontrol Pintu Garasi / Rolling Door Warung â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	closeGarage = function()
		local garage = workspace:FindFirstChild("Model") and workspace.Model:FindFirstChild("GarageWarung");
		if not garage then return end;
		if garage:GetAttribute("Closing") == true or garage:GetAttribute("IsOpen") == false then
			garageCurrent = "closed";
			return true;
		end;
		if os.clock() - lastGarageAction < 1.0 then return end;

		local prompt = nil;
		for _, pp in ipairs(garage:GetDescendants()) do
			if pp:IsA("ProximityPrompt") and pp.Enabled then
				prompt = pp;
				break;
			end;
		end;

		if prompt then
			takeItem(prompt);
			garageCurrent = "closed";
			lastGarageAction = os.clock();
			return true;
		end;
		return false;
	end;

	openGarage = function()
		-- JANGAN PERNAH BUKA GARASI JIKA WARUNG SEDANG TUTUP
		if isWarungClosed() then return false end;

		local garage = workspace:FindFirstChild("Model") and workspace.Model:FindFirstChild("GarageWarung");
		if not garage then return end;
		if garage:GetAttribute("IsOpen") == true and garage:GetAttribute("Closing") ~= true then
			garageCurrent = "open";
			return true;
		end;
		-- Cegah buka garasi jika anomali baru saja lewat (safety buffer 3 detik)
		if os.clock() - lastAnomalySeen < 3.0 then
			return false;
		end;
		if os.clock() - lastGarageAction < 1.0 then return end;

		local prompt = nil;
		for _, pp in ipairs(garage:GetDescendants()) do
			if pp:IsA("ProximityPrompt") and pp.Enabled then
				prompt = pp;
				break;
			end;
		end;

		if prompt then
			takeItem(prompt);
			garageCurrent = "open";
			lastGarageAction = os.clock();
			return true;
		end;
		return false;
	end;

	-- â”€â”€ Fitur 1: Auto Detect Anomali â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local AnomalyHighlights = {};
	local AnomalyBillboards = {};

	clearAnomalyVisuals = function()
		for _, hl in pairs(AnomalyHighlights) do
			if hl and hl.Parent then hl:Destroy() end;
		end;
		for _, bb in pairs(AnomalyBillboards) do
			if bb and bb.Parent then bb:Destroy() end;
		end;
		AnomalyHighlights = {};
		AnomalyBillboards = {};
	end;

	local function addAnomalyVisual(obj)
		if not AnomalyHighlights[obj] then
			local hl = Instance.new("Highlight");
			hl.Name                = "AnomaliDetectHl";
			hl.FillColor           = Color3.fromRGB(255, 30, 30);
			hl.OutlineColor        = Color3.fromRGB(255, 255, 0);
			hl.FillTransparency    = 0.35;
			hl.OutlineTransparency = 0;
			hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop;
			hl.Adornee             = obj;
			hl.Parent              = obj;
			AnomalyHighlights[obj] = hl;
		end;

		if not AnomalyBillboards[obj] then
			local head = obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart", true);
			if head then
				local bb = Instance.new("BillboardGui");
				bb.Name = "AnomaliESP";
				bb.Size = UDim2.fromScale(4, 1.2);
				bb.StudsOffset = Vector3.new(0, 2.5, 0);
				bb.AlwaysOnTop = true;
				bb.MaxDistance = 500;
				bb.Adornee = head;
				bb.Parent = head;

				local lbl = Instance.new("TextLabel");
				lbl.Size = UDim2.fromScale(1, 1);
				lbl.BackgroundTransparency = 0.3;
				lbl.BackgroundColor3 = Color3.fromRGB(180, 0, 0);
				lbl.TextColor3 = Color3.fromRGB(255, 255, 255);
				lbl.Text = "[!] ANOMALI: " .. tostring(obj.Name);
				lbl.TextScaled = true;
				lbl.Font = Enum.Font.GothamBold;
				lbl.Parent = bb;

				local corner = Instance.new("UICorner");
				corner.CornerRadius = UDim.new(0, 6);
				corner.Parent = lbl;

				AnomalyBillboards[obj] = bb;
			end;
		end;
	end;

	local function doAutoAnomali()
		if isWarungClosed() then
			clearAnomalyVisuals();
			closeGarage();
			return;
		end;

		for obj, hl in pairs(AnomalyHighlights) do
			if not obj.Parent or (not isEntityAnomaly(obj)) then
				if hl and hl.Parent then hl:Destroy() end;
				if AnomalyBillboards[obj] and AnomalyBillboards[obj].Parent then AnomalyBillboards[obj]:Destroy() end;
				AnomalyHighlights[obj] = nil;
				AnomalyBillboards[obj] = nil;
			end;
		end;

		-- Scan tag AnomaliShop
		for _, obj in ipairs(CS:GetTagged("AnomaliShop")) do
			if obj and obj.Parent then
				addAnomalyVisual(obj);
			end;
		end;

		-- Scan target NPC langsung
		local targets = {};
		local wargaAktif = workspace:FindFirstChild("WargaAktif");
		if wargaAktif then
			for _, c in ipairs(wargaAktif:GetChildren()) do table.insert(targets, c) end;
		end;
		local pengendara = workspace:FindFirstChild("PengendaraAktif");
		if pengendara then
			for _, c in ipairs(pengendara:GetChildren()) do table.insert(targets, c) end;
		end;
		local pemukiman = workspace:FindFirstChild("Pemukiman");
		local warga = pemukiman and pemukiman:FindFirstChild("Warga");
		if warga then
			for _, c in ipairs(warga:GetChildren()) do table.insert(targets, c) end;
		end;

		for _, model in ipairs(targets) do
			if isEntityAnomaly(model) then
				addAnomalyVisual(model);
			end;
		end;

		-- Kontrol Rolling Door jika ada anomali di warung
		local isAnomali = checkWarungAnomaly();
		if isAnomali then
			closeGarage();
		elseif (os.clock() - lastAnomalySeen >= 3.0) and garageCurrent == "closed" then
			local garage = workspace:FindFirstChild("Model") and workspace.Model:FindFirstChild("GarageWarung");
			if garage and garage:GetAttribute("IsOpen") == false then
				openGarage();
			end;
		end;
	end;

	-- â”€â”€ Fitur 2: Auto Delivery â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local deliveryBusy = false;

	local function doAutoDelivery()
		if isWarungClosed() then return end;
		if deliveryBusy then return end;

		local char = Plr.Character;
		local hrp  = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart);
		if not hrp then return end;

		-- 1. Angkat telepon jika berdering
		if RS:GetAttribute("DeliveryRing") == true then
			local tel = workspace:FindFirstChild("Telephone");
			if tel then
				for _, pp in ipairs(tel:GetDescendants()) do
					if pp:IsA("ProximityPrompt") and pp.Enabled then
						takeItem(pp);
						task.wait(0.35);
						break;
					end;
				end;
			end;
		end;

		local phase = RS:GetAttribute("DeliveryPhase");

		-- 2. Phase "siapkan" -> Ambil barang pesanan & bungkus di kresek
		if phase == "siapkan" then
			local rawItems = tostring(RS:GetAttribute("DeliveryItems") or "");
			local rawGot   = tostring(RS:GetAttribute("DeliveryGot") or "");
			local interior = getInterior();
			local interaksi = interior and interior:FindFirstChild("InteraksiBarang");

			if interaksi and rawItems ~= "" then
				local gotMap = {};
				for item in string.gmatch(rawGot, "[^,]+") do gotMap[item] = true end;

				for item in string.gmatch(rawItems, "[^,]+") do
					if not gotMap[item] then
						local part = interaksi:FindFirstChild(item);
						if part then
							takeItem(part);
							task.wait(0.2);
						end;
					end;
				end;
			end;

			task.wait(0.2);

			-- Bungkus ke kresek
			if interior then
				for _, pp in ipairs(interior:GetDescendants()) do
					if pp:IsA("ProximityPrompt") and pp.Enabled
						and (pp.ObjectText == "Kresek" or string.find(string.lower(pp.ActionText or ""), "bungkus") or string.find(string.lower(pp.ActionText or ""), "kasih")) then
						takeItem(pp);
						task.wait(0.3);
						break;
					end;
				end;
			end;
			return;
		end;

		-- 3. Phase "antar" -> Antar ke rumah pembeli secara otomatis & mulus
		if phase == "antar" then
			if isGlobalMoving then return end;
			isGlobalMoving = true;
			deliveryBusy = true;
			autoDeliveryBeri = true;

			local targetNum = RS:GetAttribute("DeliveryTarget");
			local pemukiman = workspace:FindFirstChild("Pemukiman");
			local warga     = pemukiman and pemukiman:FindFirstChild("Warga");
			local rumah     = pemukiman and pemukiman:FindFirstChild("Rumah");

			local targetNpcModel = nil;
			if warga and targetNum then
				for _, w in ipairs(warga:GetChildren()) do
					if w:GetAttribute("NoRumah") == targetNum then
						targetNpcModel = w;
						break;
					end;
				end;
			end;

			local targetPart = targetNpcModel and (targetNpcModel:FindFirstChild("HumanoidRootPart") or targetNpcModel.PrimaryPart or targetNpcModel:FindFirstChildWhichIsA("BasePart"));
			if not targetPart and rumah and targetNum then
				local rmh = rumah:FindFirstChild("Rumah" .. tostring(targetNum));
				targetPart = rmh and (rmh:FindFirstChild("Bangunan") or rmh:FindFirstChildWhichIsA("BasePart", true));
			end;

			if targetPart then
				local origCFrame = hrp.CFrame;

				-- Glide aman (arc di atas jalan agar tidak ditabrak motor & darah tidak berkurang)
				local destCF = targetPart.CFrame * CFrame.new(0, 1.2, 3.5);
				safeGlide(destCF, 0.45);
				task.wait(0.25);

				-- Senter pembeli agar server memvalidasi interaksi
				pcall(function() Plr:SetAttribute("SenterOn", true) end);
				if targetNpcModel and DeliveryR:FindFirstChild("SenterHit") then
					pcall(function() DeliveryR.SenterHit:FireServer(targetNpcModel) end);
				end;
				task.wait(0.2);

				-- Berikan pesanan ke pembeli
				pcall(function() DeliveryR.Pilih:FireServer("beri") end);

				-- Tunggu server selesaikan phase antar (max 3 detik)
				local t0 = os.clock();
				while os.clock() - t0 < 3.0 do
					if RS:GetAttribute("DeliveryPhase") ~= "antar" then break end;
					pcall(function() DeliveryR.Pilih:FireServer("beri") end);
					task.wait(0.4);
				end;

				pcall(function() Plr:SetAttribute("SenterOn", false) end);
				pcall(function() Plr:SetAttribute("CameraActive", true) end);
				safeGlide(origCFrame, 0.45);
				task.wait(0.2);
			end;

			deliveryBusy = false;
			isGlobalMoving = false;
			return;
		end;

		pcall(function() DeliveryR.Call:FireServer() end);
	end;

	-- â”€â”€ Fitur 3: Auto Isi Token â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local tokenBusy = false;
	local lastTokenSuccess = 0;

	local function doAutoToken()
		if isWarungClosed() then return end;
		if tokenBusy then return end;
		if isGlobalMoving then return end;
		if os.clock() - lastTokenSuccess < 6 then return end;

		local left = tonumber(RS:GetAttribute("TokenListrikLeft")) or 999;
		local isOn = RS:GetAttribute("TokenListrikOn");
		-- Hanya isi jika listrik BENAR-BENAR padam (isOn == false)
		local need = (isOn == false) or (RS:GetAttribute("TokenNeeded") == true);
		if not need then return end;

		local char = Plr.Character;
		local hrp  = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart);
		if not hrp then return end;

		isGlobalMoving = true;
		tokenBusy = true;
		pcall(function()
			local origCFrame = hrp.CFrame;
			local kode = tostring(RS:GetAttribute("TokenKode") or "");

			-- 1. Beli di LaptopKonter jika belum punya kode
			if kode == "" then
				local laptop = workspace:FindFirstChild("LaptopKonter", true)
					or workspace:FindFirstChild("Konter", true);
				local targetPart = laptop and (laptop:FindFirstChild("Keyboard", true)
					or laptop:FindFirstChildWhichIsA("BasePart", true));

				if targetPart then
					local destCF = CFrame.new(targetPart.Position + Vector3.new(0, 1.2, 2.5), targetPart.Position);
					safeGlide(destCF, 0.45);
					task.wait(0.25);

					-- Cari prompt konter setelah sampai di lokasi
					local prompt = nil;
					if laptop then
						for _, d in ipairs(laptop:GetDescendants()) do
							if d:IsA("ProximityPrompt") then prompt = d; break; end;
						end;
						if not prompt and laptop.Parent then
							for _, d in ipairs(laptop.Parent:GetDescendants()) do
								if d:IsA("ProximityPrompt") then prompt = d; break; end;
							end;
						end;
					end;
					if not prompt then
						for _, pp in ipairs(workspace:GetDescendants()) do
							if pp:IsA("ProximityPrompt") then
								local pPos = getPromptPos(pp);
								if pPos and (pPos - hrp.Position).Magnitude <= 12 then
									prompt = pp; break;
								end;
							end;
						end;
					end;

					if prompt then
						triggerPrompt(prompt);
					end;

					-- Tunggu kode dari server (max 8 detik)
					local t0 = os.clock();
					while os.clock() - t0 < 8.0 do
						kode = tostring(RS:GetAttribute("TokenKode") or "");
						if kode ~= "" then break end;
						task.wait(0.25);
					end;
				end;
			end;

			-- 2. Isi kode ke Meteran Listrik
			if kode ~= "" then
				local meter = workspace:FindFirstChild("TokenListrikInteract", true)
					or workspace:FindFirstChild("TokenListrik", true);
				local meterPart = meter and (meter:FindFirstChildWhichIsA("BasePart", true) or meter);
				local mPos = meterPart and getPromptPos(meterPart);

				if mPos then
					local destCF = CFrame.new(mPos + Vector3.new(0, 1.2, 2.5), mPos);
					safeGlide(destCF, 0.45);
					task.wait(0.25);

					-- Cari prompt meteran
					local prompt = nil;
					if meter then
						for _, pp in ipairs(meter:GetDescendants()) do
							if pp:IsA("ProximityPrompt") then prompt = pp; break; end;
						end;
						if not prompt and meter.Parent then
							for _, pp in ipairs(meter.Parent:GetDescendants()) do
								if pp:IsA("ProximityPrompt") then prompt = pp; break; end;
							end;
						end;
					end;
					if not prompt then
						for _, pp in ipairs(workspace:GetDescendants()) do
							if pp:IsA("ProximityPrompt") then
								local pPos = getPromptPos(pp);
								if pPos and (pPos - hrp.Position).Magnitude <= 10 then
									prompt = pp; break;
								end;
							end;
						end;
					end;

					if prompt then
						triggerPrompt(prompt);
						task.wait(0.4);
					end;

					-- Auto-isi textbox di GUI TokenListrikGui
					pcall(function()
						local pg = Plr:FindFirstChild("PlayerGui");
						local tGui = pg and pg:FindFirstChild("TokenListrikGui");
						if tGui then
							local mf = tGui:FindFirstChild("MainFrame");
							local kBox = mf and mf:FindFirstChild("Kode");
							if kBox and kBox:IsA("TextBox") then
								kBox.Text = tostring(kode);
							end;
						end;
					end);

					-- Submit kode & tutup GUI
					pcall(function() TokenR.Submit:FireServer(tostring(kode)) end);
					task.wait(0.35);
					pcall(function() TokenR.Close:FireServer() end);
					task.wait(0.2);

					pcall(function()
						local pg = Plr:FindFirstChild("PlayerGui");
						local tGui = pg and pg:FindFirstChild("TokenListrikGui");
						if tGui then tGui.Enabled = false; end;
						Plr:SetAttribute("CameraActive", true);
					end);

					lastTokenSuccess = os.clock();
				end;
			end;

			-- Kembalikan avatar ke posisi semula di warung
			safeGlide(origCFrame, 0.45);
		end);
		pcall(function() Plr:SetAttribute("CameraActive", true) end);
		tokenBusy = false;
		isGlobalMoving = false;
	end;

	-- â”€â”€ Fitur 4: Auto Isi Rak Kosong â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local allStockItems = {
		"Bensin", "Beras", "Ciki", "Eskrim", "Galon",
		"Gas", "Mie", "Minuman", "Permen", "Snack", "Telur"
	};

	local function doAutoIsiRak()
		if isWarungClosed() then return end;
		local interior = getInterior();
		local display  = interior and interior:FindFirstChild("DisplayStockBarang");
		if not display then return end;

		local emptyItems = {};
		for _, sp in ipairs(display:GetChildren()) do
			if sp:IsA("BasePart") and sp.Name ~= "Bensin" and sp.Name ~= "Kresek" then
				local sv = sp:FindFirstChild("Stock");
				if sv and sv.Value < 14 then
					table.insert(emptyItems, sp.Name);
				end;
			end;
		end;

		if #emptyItems == 0 then return end;

		local cart = {};
		for _, name in ipairs(allStockItems) do cart[name] = 0 end;
		for _, item in ipairs(emptyItems) do cart[item] = 15 end;

		-- Restock via Gudang & Grosir
		pcall(function() GudangR.Buy:FireServer(cart) end);
		task.wait(0.35);

		pcall(function() GrosirR.Buy:FireServer(cart) end);
		task.wait(0.35);

		for _, item in ipairs(emptyItems) do
			pcall(function() GudangR.Buy:FireServer(item, 15) end);
			pcall(function() GrosirR.Buy:FireServer(item, 15) end);
		end;
	end;

	-- â”€â”€ Fitur 5: Auto Ambil Barang Pelanggan (Ciki, Mie, Galon, Gas, Minuman, Bensin) â”€â”€
	local function doAutoLayani()
		-- Jika waktu warung tutup, pastikan garasi tertutup dan jangan layani
		if isWarungClosed() then
			closeGarage();
			return;
		end;

		-- Jangan layani jika sedang pergi misi delivery / isi token di luar warung
		if isGlobalMoving then return end;

		-- 1. Cek anomali pembeli warung / motor
		local isAnomali, anomNpc = checkWarungAnomaly();
		if isAnomali then
			closeGarage(); -- Tutup warung saat ada anomali!
			return;        -- JANGAN ambil barang dan JANGAN layani!
		end;

		local garage = workspace:FindFirstChild("Model") and workspace.Model:FindFirstChild("GarageWarung");
		local isGarageClosed = garage and (garage:GetAttribute("IsOpen") == false or garage:GetAttribute("Closing") == true);

		-- 2. Jika garasi tertutup dan anomali sudah bersih minimal 3 detik, baru buka kembali
		if isGarageClosed or garageCurrent == "closed" then
			if os.clock() - lastAnomalySeen >= 3.0 then
				openGarage();
			end;
			return; -- Tunggu rolling door terbuka sebelum melayani pelanggan!
		end;

		local interior  = getInterior();
		local interaksi = interior and interior:FindFirstChild("InteraksiBarang");
		local barang    = interior and interior:FindFirstChild("Barang");
		if not interaksi then return end;

		-- 3. Kulkas untuk Minuman (buka kulkas jika pesanan minuman aktif)
		local kulkas = interior:FindFirstChild("Hiasan") and interior.Hiasan:FindFirstChild("Kulkas");
		local pintuKulkas = kulkas and kulkas:FindFirstChild("PintuKulkas");
		local minumanPart = interaksi:FindFirstChild("Minuman");
		local minumanPrompt = minumanPart and (minumanPart:FindFirstChild("BeliPrompt") or minumanPart:FindFirstChildWhichIsA("ProximityPrompt", true));
		if minumanPrompt and minumanPrompt.Enabled then
			if pintuKulkas and pintuKulkas:GetAttribute("IsOpen") ~= true then
				for _, pp in ipairs(pintuKulkas:GetDescendants()) do
					if pp:IsA("ProximityPrompt") and pp.Enabled then
						takeItem(pp);
						task.wait(0.2);
						break;
					end;
				end;
			end;
		end;

		-- 4. Ambil semua barang pesanan aktif (Ciki, Mie, Galon, Gas, Minuman, Bensin, dll)
		local ambilBarang = false;
		for _, part in ipairs(interaksi:GetChildren()) do
			-- Verifikasi keamanan sebelum tiap kali ambil barang
			if checkWarungAnomaly() then
				closeGarage();
				return;
			end;

			if part.Name ~= "Kresek" then
				for _, pp in ipairs(part:GetDescendants()) do
					if pp:IsA("ProximityPrompt") and pp.Enabled and pp.Name == "BeliPrompt" then
						takeItem(part);
						ambilBarang = true;
						task.wait(0.2);
						break;
					end;
				end;
			end;
		end;

		if ambilBarang then
			task.wait(0.25);
		end;

		-- 5. Serahkan Kresek ke pelanggan
		-- Verifikasi keamanan sekali lagi sebelum serahkan kresek
		if checkWarungAnomaly() then
			closeGarage();
			return;
		end;

		local kresekPrompt = nil;
		if barang then
			local k = barang:FindFirstChild("Kresek");
			if k then
				for _, pp in ipairs(k:GetDescendants()) do
					if pp:IsA("ProximityPrompt") and pp.Enabled then
						kresekPrompt = pp;
						break;
					end;
				end;
			end;
		end;
		if not kresekPrompt and interaksi then
			local k = interaksi:FindFirstChild("Kresek");
			if k then
				for _, pp in ipairs(k:GetDescendants()) do
					if pp:IsA("ProximityPrompt") and pp.Enabled then
						kresekPrompt = pp;
						break;
					end;
				end;
			end;
		end;

		if kresekPrompt then
			takeItem(kresekPrompt);
			task.wait(0.2);
		end;
	end;

	-- â”€â”€ UI (ModernV2) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
	local Window = ModernV2:CreateWindow({
		Name    = "Warung Auto",
		Size    = ModernV2.Scales.Compact,
		Keybind = Enum.KeyCode.RightShift,
	});

	pcall(function()
		local MenuIcon = ModernV2:CreateMenuIcon({
			Image = "lucide:store",
			Size  = 46,
		});
		MenuIcon:SetVisible(true);
	end);

	local Tab     = Window:AddTab({ Name = "Auto", Icon = "lucide:zap" });
	local Section = Tab:AddSection({ Name = "Fitur Auto" });

	ToggleAnomali = Section:AddToggle({
		Name     = "Auto Detect Anomali",
		Icon     = "lucide:scan-eye",
		Default  = false,
		Flag     = "WA_AutoAnomali",
		Callback = function(val)
			if val and isWarungClosed() then
				task.defer(function()
					if ToggleAnomali then ToggleAnomali:SetValue(false) end;
				end);
				pcall(function()
					ModernV2:Notify({
						Title = "Warung Tutup",
						Content = "Warung sedang tutup (istirahat/tidur). Fitur tidak bisa diaktifkan.",
						Duration = 4,
						Icon = "lucide:moon",
					});
				end);
				return;
			end;
			WAFlags.AutoAnomali = val;
			if val then
				spawnLoop("AutoAnomali", doAutoAnomali, 1.5);
			else
				killThread("AutoAnomali");
				clearAnomalyVisuals();
			end;
		end,
	});

	ToggleDelivery = Section:AddToggle({
		Name     = "Auto Delivery",
		Icon     = "lucide:bike",
		Default  = false,
		Flag     = "WA_AutoDelivery",
		Callback = function(val)
			if val and isWarungClosed() then
				task.defer(function()
					if ToggleDelivery then ToggleDelivery:SetValue(false) end;
				end);
				pcall(function()
					ModernV2:Notify({
						Title = "Warung Tutup",
						Content = "Warung sedang tutup (istirahat/tidur). Fitur tidak bisa diaktifkan.",
						Duration = 4,
						Icon = "lucide:moon",
					});
				end);
				return;
			end;
			WAFlags.AutoDelivery = val;
			if val then
				spawnLoop("AutoDelivery", doAutoDelivery, 1.0);
			else
				killThread("AutoDelivery");
			end;
		end,
	});

	ToggleToken = Section:AddToggle({
		Name     = "Auto Isi Token",
		Icon     = "lucide:zap",
		Default  = false,
		Flag     = "WA_AutoToken",
		Callback = function(val)
			if val and isWarungClosed() then
				task.defer(function()
					if ToggleToken then ToggleToken:SetValue(false) end;
				end);
				pcall(function()
					ModernV2:Notify({
						Title = "Warung Tutup",
						Content = "Warung sedang tutup (istirahat/tidur). Fitur tidak bisa diaktifkan.",
						Duration = 4,
						Icon = "lucide:moon",
					});
				end);
				return;
			end;
			WAFlags.AutoToken = val;
			if val then
				spawnLoop("AutoToken", doAutoToken, 2.0);
			else
				killThread("AutoToken");
			end;
		end,
	});

	ToggleIsiRak = Section:AddToggle({
		Name     = "Auto Isi Rak Kosong",
		Icon     = "lucide:boxes",
		Default  = false,
		Flag     = "WA_AutoIsiRak",
		Callback = function(val)
			if val and isWarungClosed() then
				task.defer(function()
					if ToggleIsiRak then ToggleIsiRak:SetValue(false) end;
				end);
				pcall(function()
					ModernV2:Notify({
						Title = "Warung Tutup",
						Content = "Warung sedang tutup (istirahat/tidur). Fitur tidak bisa diaktifkan.",
						Duration = 4,
						Icon = "lucide:moon",
					});
				end);
				return;
			end;
			WAFlags.AutoIsiRak = val;
			if val then
				spawnLoop("AutoIsiRak", doAutoIsiRak, 2.5);
			else
				killThread("AutoIsiRak");
			end;
		end,
	});

	ToggleLayani = Section:AddToggle({
		Name     = "Auto Ambil Barang Pelanggan",
		Icon     = "lucide:shopping-bag",
		Default  = false,
		Flag     = "WA_AutoLayani",
		Callback = function(val)
			if val and isWarungClosed() then
				task.defer(function()
					if ToggleLayani then ToggleLayani:SetValue(false) end;
				end);
				pcall(function()
					ModernV2:Notify({
						Title = "Warung Tutup",
						Content = "Warung sedang tutup (istirahat/tidur). Fitur tidak bisa diaktifkan.",
						Duration = 4,
						Icon = "lucide:moon",
					});
				end);
				return;
			end;
			WAFlags.AutoLayani = val;
			if val then
				spawnLoop("AutoLayani", doAutoLayani, 0.5);
			else
				killThread("AutoLayani");
			end;
		end,
	});
end
