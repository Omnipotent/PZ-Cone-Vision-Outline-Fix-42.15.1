-- Outline for zombies and animals in vision cone when aiming RMB.
-- 42.15.2 fix variant: no debug-only reflection; hit-list outline skipped in normal play.
-- Hit-list logic from Aim Outline by Kreb (Workshop ID: 3404684285, Mod ID: AimOutline).
require "Foraging/forageSystem"
require "luautils"

local O
pcall(function() O = require("ConeVisionOutline42152Fix_Options") end)
local function getConeOutlineColor()
	if O and O.ConeOutlineColor then
		local c = O.ConeOutlineColor
		local a = (O.ConeOutlineAlpha ~= nil) and O.ConeOutlineAlpha or 0.3
		return c.r or 1, c.g or 1, c.b or 1, a
	end
	return 1, 1, 1, 0.3
end

local lastHighlighted = {}
local lastHitListHighlighted = {}
local lastOverlayTargets = {}  -- objects on adjacent floor that engine won't outline; we draw them ourselves
local overlayUI = nil
local overlayInUIManager = false  -- true when overlay is currently in UI (so we remove it when not aiming)
local RADIUS_VISION = 50
local RADIUS_OVERLAY_FLOOR_ABOVE = 5  -- max horizontal distance (tiles) for overlay on floor +1
local PLAYER_NUM = 0
local OUTLINE_ALPHA = 0.3
local OVERLAY_BOX_W = 28
local OVERLAY_BOX_H = 56
local OVERLAY_CIRCLE_SIZE = 44       -- base diameter for pulse circle
local PULSE_SCALE_MIN = 0.82
local PULSE_SCALE_MAX = 1.18
local PULSE_SPEED = 0.5              -- cycles per second (growl-like)
local PULSE_ALPHA_MIN = 0.2
local PULSE_ALPHA_MAX = 0.45
local overlayCircleTex = nil         -- lazy-loaded texture
-- Vision cone for overlay: only show overlay for targets in front of player (dot product threshold ~cos(60°) = 0.5)
local CONE_HALF_ANGLE_COS = 0.5
-- Direction vectors (dx, dy) for IsoDirections; built at runtime when IsoDirections is available
local DIR_VECTORS = nil
local function buildDirVectors()
	if DIR_VECTORS then return end
	if not IsoDirections then return end
	DIR_VECTORS = {
		[IsoDirections.N] = { 0, -1 }, [IsoDirections.S] = { 0, 1 },
		[IsoDirections.E] = { 1, 0 },  [IsoDirections.W] = { -1, 0 },
		[IsoDirections.NE] = { 0.707, -0.707 }, [IsoDirections.SE] = { 0.707, 0.707 },
		[IsoDirections.NW] = { -0.707, -0.707 }, [IsoDirections.SW] = { -0.707, 0.707 },
	}
end

-- From Aim Outline (Kreb): get Java field index by name.
-- getNumClassFields/getClassField are debug-only in 42.15+; use pcall and return nil when not available.
local function getJavaFieldNum(object, fieldName)
	local ok, idx = pcall(function()
		local n = getNumClassFields(object)
		if n == nil then return nil end
		for i = 0, n - 1 do
			local javaField = getClassField(object, i)
			if luautils.stringEnds(tostring(javaField), '.' .. fieldName) then
				return i
			end
		end
		return nil
	end)
	return (ok and idx) or nil
end

local function clearOutline(obj)
	-- Single call in pcall: avoid any other method on obj (stale refs can make them throw).
	local ok = pcall(function()
		obj:setOutlineHighlight(PLAYER_NUM, false)
	end)
	return ok
end

local function clearHitListOutlines()
	for obj, _ in pairs(lastHitListHighlighted) do
		clearOutline(obj)
	end
	lastHitListHighlighted = {}
end

local function clearAll()
	for obj, _ in pairs(lastHighlighted) do
		clearOutline(obj)
	end
	lastHighlighted = {}
	lastOverlayTargets = {}
	clearHitListOutlines()
end

local function isShortSightedWithoutGlasses(character)
	if not character:hasTrait(CharacterTrait.SHORT_SIGHTED) then
		return false
	end
	return forageSystem.doGlassesCheck(character, nil, "visionBonus")
end

local function isTarget(obj)
	return (instanceof(obj, "IsoZombie") or instanceof(obj, "IsoAnimal"))
end

local function getObjSquare(obj)
	if obj.getCurrentSquare then
		return obj:getCurrentSquare()
	end
	if obj.getSquare then
		return obj:getSquare()
	end
	return nil
end

-- True if target at (plX+dx, plY+dy) is in player's vision cone (in front)
local function isInVisionCone(character, dx, dy)
	if not character or not character.getDir then return false end
	buildDirVectors()
	local dir = character:getDir()
	if not dir or not DIR_VECTORS or not DIR_VECTORS[dir] then return false end
	local v = DIR_VECTORS[dir]
	local dot = dx * v[1] + dy * v[2]
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.01 then return true end
	return (dot / len) >= CONE_HALF_ANGLE_COS
end

-- Overlay UI: draws pulsing circle (growl-style) for targets on floor+1 that the engine does not draw
local ConeVisionOutline42152FixOverlay = ISUIElement:derive("ConeVisionOutline42152FixOverlay")
local function getOverlayCircleTexture()
	if overlayCircleTex then return overlayCircleTex end
	local ok, t = pcall(function() return getTexture("media/ui/circle.png") end)
	if ok and t then overlayCircleTex = t end
	return overlayCircleTex
end
function ConeVisionOutline42152FixOverlay:prerender() end
function ConeVisionOutline42152FixOverlay:render()
	-- Let mouse events pass through so RMB (aim) still works
	if not self._mousePassThrough and self.javaObject then
		pcall(function() self.javaObject:setConsumeMouseEvents(false) end)
		self._mousePassThrough = true
	end
	if not lastOverlayTargets then return end
	local hasAny = false
	for _ in pairs(lastOverlayTargets) do hasAny = true; break end
	if not hasAny then return end
	local tex = getOverlayCircleTexture()
	if not tex then return end
	local character = getPlayer()
	if not character then return end
	local pid = character:getPlayerNum()
	local screenLeft = getPlayerScreenLeft(pid)
	local screenTop = getPlayerScreenTop(pid)
	local t = (getTimestampMs() or 0) / 1000
	local twoPi = 2 * math.pi
	local pulseScale = PULSE_SCALE_MIN + (PULSE_SCALE_MAX - PULSE_SCALE_MIN) * (0.5 + 0.5 * math.sin(t * PULSE_SPEED * twoPi))
	local pulseAlpha = PULSE_ALPHA_MIN + (PULSE_ALPHA_MAX - PULSE_ALPHA_MIN) * (0.5 + 0.5 * math.sin(t * PULSE_SPEED * twoPi * 1.1))
	local size = OVERLAY_CIRCLE_SIZE * pulseScale
	local r, g, b = 1, 1, 1
	for obj, _ in pairs(lastOverlayTargets) do
		local ok, cx, cy = pcall(function()
			local square = getObjSquare(obj)
			if not square then return nil, nil end
			local x, y = obj:getX(), obj:getY()
			local z = square:getZ()
			local scrX = isoToScreenX(pid, x, y, z) - screenLeft
			local scrY = isoToScreenY(pid, x, y, z) - screenTop
			return scrX - OVERLAY_BOX_W / 2 + OVERLAY_BOX_W / 2, scrY - OVERLAY_BOX_H + OVERLAY_BOX_H / 2
		end)
		if ok and cx and cy then
			self:drawTextureScaled(tex, cx - size / 2, cy - size / 2, size, size, pulseAlpha, r, g, b)
		end
	end
end
function ConeVisionOutline42152FixOverlay:new()
	local pid = getPlayer() and getPlayer():getPlayerNum() or 0
	local x = getPlayerScreenLeft(pid)
	local y = getPlayerScreenTop(pid)
	local w = getPlayerScreenWidth(pid)
	local h = getPlayerScreenHeight(pid)
	local o = ISUIElement.new(self, x, y, w, h)
	o:setCapture(false)
	return o
end
local function ensureOverlayUI()
	if overlayUI then return end
	if not ISUIElement or type(ISUIElement.derive) ~= "function" then return end
	if not getPlayerScreenLeft or not getPlayerScreenWidth then return end
	overlayUI = ConeVisionOutline42152FixOverlay:new()
	if not overlayUI then return end
	if overlayUI.initialise then overlayUI:initialise() end
	if overlayUI.addToUIManager then overlayUI:addToUIManager() end
	overlayInUIManager = true
	-- So overlay never blocks RMB (aim) or other mouse
	pcall(function()
		if overlayUI.setX then overlayUI:setX(0) end
		if overlayUI.javaObject and overlayUI.javaObject.setConsumeMouseEvents then
			overlayUI.javaObject:setConsumeMouseEvents(false)
		end
	end)
end
local function updateOverlayBounds()
	if not overlayUI then return end
	local character = getPlayer()
	if not character then return end
	local pid = character:getPlayerNum()
	if getPlayerScreenLeft and overlayUI.setX then overlayUI:setX(getPlayerScreenLeft(pid)) end
	if getPlayerScreenTop and overlayUI.setY then overlayUI:setY(getPlayerScreenTop(pid)) end
	if getPlayerScreenWidth and overlayUI.setWidth then overlayUI:setWidth(getPlayerScreenWidth(pid)) end
	if getPlayerScreenHeight and overlayUI.setHeight then overlayUI:setHeight(getPlayerScreenHeight(pid)) end
end

-- Reused from Aim Outline (Kreb): outline melee targets from getHitInfoList() in green. Firearm: no outline.
-- In 42.15+ getNumClassFields is debug-only, so hit-list outline is skipped in normal play.
local function updateHitListOutline(character)
	local currentHitList = {}
	if not getCore():getOptionMeleeOutline() then
		for obj, _ in pairs(lastHitListHighlighted) do
			clearOutline(obj)
		end
		lastHitListHighlighted = {}
		return currentHitList
	end
	local mainWeapon = character:getPrimaryHandItem()
	if not mainWeapon or not mainWeapon:IsWeapon() or mainWeapon:isRanged() then
		-- Melee only; for firearm do nothing
		for obj, _ in pairs(lastHitListHighlighted) do
			clearOutline(obj)
		end
		lastHitListHighlighted = {}
		return currentHitList
	end
	local list = character:getHitInfoList()
	if not list or list:size() == 0 then
		for obj, _ in pairs(lastHitListHighlighted) do
			clearOutline(obj)
		end
		lastHitListHighlighted = {}
		return currentHitList
	end

	-- In 42.15+ getNumClassFields/getClassField are debug-only; calling them (even in pcall) logs
	-- "Not in debug" every frame and spams the log. Do not use reflection here; skip hit-list outline.
	-- (Cone outline and overlay still work; only green melee hit-list outline is disabled.)
	for obj, _ in pairs(lastHitListHighlighted) do
		if not currentHitList[obj] then
			clearOutline(obj)
		end
	end
	lastHitListHighlighted = currentHitList
	return currentHitList
end

local function updateConeOutline()
	pcall(function()
		-- Same as game: getPlayer() for current/controlled character (works in vehicle)
		local character = getPlayer()
		if not character then
			clearAll()
			return
		end

		-- On foot = isAiming(); in vehicle = isLookingWhileInVehicle() or (option) always when in vehicle
		local inVehicle = character:getVehicle() ~= nil
		local isLooking = character:isAiming() or character:isLookingWhileInVehicle()
			or (O and O.VehicleOutlineAlwaysOn and inVehicle)
		if not isLooking then
			lastOverlayTargets = {}
			if overlayInUIManager and overlayUI and overlayUI.removeFromUIManager then
				pcall(function() overlayUI:setVisible(false); overlayUI:removeFromUIManager() end)
				overlayInUIManager = false
			end
			clearAll()
			return
		end

		-- Everything (cone + hit-list outline) only when game option "Melee outline" is on
		if not getCore():getOptionMeleeOutline() then
			lastOverlayTargets = {}
			clearAll()
			return
		end

		if isShortSightedWithoutGlasses(character) then
			lastOverlayTargets = {}
			clearAll()
			return
		end

		-- Hit-list outline (melee green only) when option on; don't overwrite these with cone outline
		local hitListTargets = updateHitListOutline(character)

		local cell = getCell()
		if not cell then return end

		lastOverlayTargets = {}
		local plX, plY = character:getX(), character:getY()
		local objectList = cell:getObjectList()
		local newHighlighted = {}

		for i = 0, objectList:size() - 1 do
			local obj = objectList:get(i)
			if hitListTargets[obj] then
				-- Already outlined by hit-list (melee/firearm); skip cone outline
			elseif isTarget(obj) then
				local square = getObjSquare(obj)
				if square then
					local dx = obj:getX() - plX
					local dy = obj:getY() - plY
					local distSq = dx * dx + dy * dy

					if distSq <= RADIUS_VISION * RADIUS_VISION then
						local valid = (instanceof(obj, "IsoAnimal") and obj:isExistInTheWorld())
							or (instanceof(obj, "IsoZombie") and not obj:isDead())
						if valid then
							local canSee = square:isCanSee(character:getPlayerNum())
							local plZ = character:getZ()
							local sqZ = square:getZ()
							local floorAboveOnly = (plZ ~= nil and sqZ ~= nil) and (sqZ - plZ < 1) and (sqZ - plZ > 0)
							local inCone = isInVisionCone(character, dx, dy)
							if canSee then
								-- Engine draws outline for this Z level (color/alpha from options)
								local cr, cg, cb, ca = getConeOutlineColor()
								if O and O.ScaleOutlineByLight then
									local lightLevel = square:getLightLevel(character:getPlayerNum())
									if lightLevel ~= nil then
										ca = ca * lightLevel
									end
								end
								obj:setOutlineHighlight(PLAYER_NUM, true)
								obj:setOutlineHighlightCol(PLAYER_NUM, cr, cg, cb, ca)
								newHighlighted[obj] = true
							elseif floorAboveOnly and inCone and (distSq <= RADIUS_OVERLAY_FLOOR_ABOVE * RADIUS_OVERLAY_FLOOR_ABOVE) then
								-- Floor above, in cone, within 5 tiles: we draw overlay (always on)
								lastOverlayTargets[obj] = true
							end
						end
					end
				end
			end
		end

		-- Clear outlines for objects that left vision; don't clear hit-list targets (avoids white/chance flicker)
		for obj, _ in pairs(lastHighlighted) do
			if not newHighlighted[obj] and not hitListTargets[obj] then
				clearOutline(obj)
			end
		end
		lastHighlighted = newHighlighted

		local hasOverlayTargets = false
		for _ in pairs(lastOverlayTargets) do
			hasOverlayTargets = true
			break
		end
		if hasOverlayTargets then
			ensureOverlayUI()
			updateOverlayBounds()
			if overlayUI and not overlayInUIManager then
				pcall(function()
					if overlayUI.setVisible then overlayUI:setVisible(true) end
					if overlayUI.addToUIManager then overlayUI:addToUIManager() end
					overlayInUIManager = true
				end)
			end
		elseif overlayInUIManager and overlayUI then
			pcall(function() overlayUI:setVisible(false); overlayUI:removeFromUIManager() end)
			overlayInUIManager = false
		end
	end)
end

Events.OnPlayerUpdate.Add(updateConeOutline)
Events.OnPlayerDeath.Add(clearAll)
