-- Roact version by @sircfenner
-- Ported to Fusion by @YasuYoshida
local Plugin = script:FindFirstAncestorWhichIsA("Plugin")
local Fusion = require(Plugin:FindFirstChild("Fusion", true))

local StudioComponents = script.Parent
local StudioComponentsUtil = StudioComponents:FindFirstChild("Util")

local themeProvider = require(StudioComponentsUtil.themeProvider)
local stripProps = require(StudioComponentsUtil.stripProps)
local types = require(StudioComponentsUtil.types)
local getState = require(StudioComponentsUtil.getState)
local getMotionState = require(StudioComponentsUtil.getMotionState)
local getModifier = require(StudioComponentsUtil.getModifier)

local New = Fusion.New
local Hydrate = Fusion.Hydrate

local COMPONENT_ONLY_PROPERTIES = {
	"Enabled",
}

type SeparatorProperties = {
	Enabled: (boolean | types.StateObject<boolean>)?,
	[any]: any,
}

return function(props: SeparatorProperties): Frame
	local isEnabled = getState(props.Enabled, true)

	local mainModifier = getModifier({
		Enabled = isEnabled,
	})

	local newSeparator = New "Frame" {
		Name = "Separator",
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.fromScale(0, 0),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = getMotionState(
			themeProvider:GetColor(Enum.StudioStyleGuideColor.Light, mainModifier),
			"Spring", 40
		),
		BorderSizePixel = 0,
	}

	local hydrateProps = stripProps(props, COMPONENT_ONLY_PROPERTIES)
	return Hydrate(newSeparator)(hydrateProps)
end