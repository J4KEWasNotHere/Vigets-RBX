local Plugin = script:FindFirstAncestorWhichIsA("Plugin")
local Fusion = require(Plugin:FindFirstChild("Fusion", true))
local StudioComponents = script.Parent
local StudioComponentsUtil = StudioComponents:FindFirstChild("Util")
local getMotionState = require(StudioComponentsUtil.getMotionState)
local themeProvider = require(StudioComponentsUtil.themeProvider)
local getModifier = require(StudioComponentsUtil.getModifier)
local stripProps = require(StudioComponentsUtil.stripProps)
local constants = require(StudioComponentsUtil.constants)
local getState = require(StudioComponentsUtil.getState)
local types = require(StudioComponentsUtil.types)

local Computed = Fusion.Computed
local Children = Fusion.Children
local OnChange = Fusion.OnChange
local Observer = Fusion.Observer
local Hydrate = Fusion.Hydrate
local Value = Fusion.Value
local New = Fusion.New
local Ref = Fusion.Ref

local COMPONENT_ONLY_PROPERTIES = {
	"Enabled",
	"TextColorStyle",
	"TextColor3",
	"TextSize",
	"TextXAlignment",
	"TextYAlignment",
	"Text",
	"MaxHeight",
	"MinHeight",
	"ShouldFill",
}

type LabelProperties = {
	Enabled: (boolean | types.StateObject<boolean>)?,
	MaxHeight: number?,
	MinHeight: number?,
	ShouldFill: boolean?,
	[any]: any,
}

return function(props: LabelProperties): ScrollingFrame
	local isEnabled = getState(props.Enabled, true)
	local textSize = props.TextSize or constants.TextSize
	local shouldFill = props.ShouldFill == true
	local maxHeight = not shouldFill and props.MaxHeight or nil
	local minHeight = not shouldFill and (props.MinHeight or 0) or nil

	local mainModifier = getModifier({ Enabled = isEnabled })

	local textColor = props.TextColor3
		or getMotionState(
			themeProvider:GetColor(
				props.TextColorStyle or Enum.StudioStyleGuideColor.MainText,
				mainModifier
			),
			"Spring", 40
		)

	local scrollBarColor = getMotionState(
		themeProvider:GetColor(Enum.StudioStyleGuideColor.ScrollBar, mainModifier),
		"Spring", 40
	)

	local contentHeight = Value(0)
	local fillHeight = Value(0)
	local instanceRef = Value(nil)

	-- Manually track remaining parent space by watching parent + sibling sizes
	local cleanupFill = nil
	Observer(instanceRef):onChange(function()
		if cleanupFill then
			cleanupFill()
			cleanupFill = nil
		end

		local frame = instanceRef:get()
		if not frame or not shouldFill then return end

		-- Defer so Hydrate/parenting has finished before we walk the tree
		task.defer(function()
			local parent = frame.Parent
			if not parent or not parent:IsA("GuiObject") then return end

			local connections = {}

			local function recalc()
				local remaining = parent.AbsoluteSize.Y + 8
				for _, child in ipairs(parent:GetChildren()) do
					if child ~= frame and child:IsA("GuiObject") then
						remaining -= child.AbsoluteSize.Y
					end
				end
				fillHeight:set(math.max(0, remaining))
			end

			table.insert(connections,
				parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
			)

			for _, child in ipairs(parent:GetChildren()) do
				if child ~= frame and child:IsA("GuiObject") then
					table.insert(connections,
						child:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
					)
				end
			end

			table.insert(connections, parent.ChildAdded:Connect(function(child)
				if child ~= frame and child:IsA("GuiObject") then
					table.insert(connections,
						child:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
					)
					recalc()
				end
			end))

			table.insert(connections, parent.ChildRemoved:Connect(function(child)
				if child ~= frame then
					recalc()
				end
			end))

			recalc()

			cleanupFill = function()
				for _, c in connections do
					c:Disconnect()
				end
			end
		end)
	end)

	local frameSize = Computed(function()
		if shouldFill then
			return UDim2.new(1, 0, 0, fillHeight:get())
		end
		local h = contentHeight:get()
		if minHeight then h = math.max(h, minHeight) end
		if maxHeight then h = math.min(h, maxHeight) end
		return UDim2.new(1, 0, 0, h)
	end)

	local scrollBarThickness = Computed(function()
		if shouldFill then
			return contentHeight:get() > fillHeight:get() and 6 or 0
		end
		if maxHeight and contentHeight:get() > maxHeight then
			return 6
		end
		return 0
	end)

	local newLabel = New "ScrollingFrame" {
		Name = "Label",
		Position = UDim2.fromScale(0, 0),
		AnchorPoint = Vector2.new(0, 0),
		Size = frameSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(1, 0, 0, 0),
		ScrollBarThickness = scrollBarThickness,
		ScrollBarImageColor3 = scrollBarColor,
		ElasticBehavior = Enum.ElasticBehavior.Never,

		[Ref] = instanceRef,

		[Children] = {
			New "TextLabel" {
				Name = "InnerLabel",
				Position = UDim2.fromScale(0, 0),
				AnchorPoint = Vector2.new(0, 0),
				Text = props.Text or "",
				TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
				TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Top,
				TextSize = textSize,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				BorderMode = Enum.BorderMode.Inset,
				RichText = true,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				Font = themeProvider:GetFont("Default"),
				TextColor3 = textColor,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,

				[OnChange "AbsoluteSize"] = function(size)
					contentHeight:set(size.Y)
				end,
			},
		},
	}

	local hydrateProps = stripProps(props, COMPONENT_ONLY_PROPERTIES)
	return Hydrate(newLabel)(hydrateProps)
end