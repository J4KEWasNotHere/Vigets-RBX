-- Fusion ImageLabel Component
-- Roact version by @sircfenner
-- Ported/extended in Fusion style

local Plugin = script:FindFirstAncestorWhichIsA("Plugin")
local Fusion = require(Plugin:FindFirstChild("Fusion", true))

local StudioComponents = script.Parent
local StudioComponentsUtil = StudioComponents:FindFirstChild("Util")

local getMotionState = require(StudioComponentsUtil.getMotionState)
local themeProvider = require(StudioComponentsUtil.themeProvider)
local getModifier = require(StudioComponentsUtil.getModifier)
local stripProps = require(StudioComponentsUtil.stripProps)
local getState = require(StudioComponentsUtil.getState)
local unwrap = require(StudioComponentsUtil.unwrap)
local types = require(StudioComponentsUtil.types)

local Computed = Fusion.Computed
local Hydrate = Fusion.Hydrate
local New = Fusion.New

type ImageScaleType =
	"Fit"
| "Fill"
| "Stretch"
| "Tile"

type ImageLabelProperties = {
	Enabled: (boolean | types.StateObject<boolean>)?,
	Image: string?,
	ImageTransparency: number?,
	ImageColor3: Color3?,
	BackgroundColor3: Color3?,

	ScaleType: ImageScaleType?,
	CornerRadius: (UDim | number)?,

	Size: UDim2?,
	[any]: any,
}

local COMPONENT_ONLY_PROPERTIES = {
	"Enabled",
	"Image",
	"ImageTransparency",
	"ImageColor3",
	"BackgroundColor3",
	"ScaleType",
	"CornerRadius",
	"Size",
}

local function resolveScaleType(scaleType: ImageScaleType?): Enum.ScaleType
	if scaleType == "Fill" then
		return Enum.ScaleType.Fit
	elseif scaleType == "Stretch" then
		return Enum.ScaleType.Stretch
	elseif scaleType == "Tile" then
		return Enum.ScaleType.Tile
	end

	return Enum.ScaleType.Fit -- default "Fit"
end

return function(props: ImageLabelProperties): ImageLabel
	local isEnabled = getState(props.Enabled, true)

	local mainModifier = getModifier({
		Enabled = isEnabled,
	})

	local imageLabel = New "ImageLabel" {
		Name = "Image",
		BackgroundTransparency = props.BackgroundTransparency or 1,
		BorderSizePixel = 0,

		Size = props.Size or UDim2.fromScale(1, 1),

		Visible = isEnabled,

		Image = props.Image or "",
		ImageTransparency = props.ImageTransparency or 0,
		ImageColor3 = props.ImageColor3 or Color3.new(1, 1, 1),

		BackgroundColor3 = props.BackgroundColor3 or Color3.new(0,0,0),
		
		ScaleType = resolveScaleType(props.ScaleType),

		Position = UDim2.fromScale(0, 0),
		AnchorPoint = Vector2.new(0, 0),

		ClipsDescendants = true,
	}

	-- Corner radius support (optional)
	local children = {}

	if props.CornerRadius then
		table.insert(children, New "UICorner" {
			CornerRadius = props.CornerRadius,
		})
	end

	-- Optional automatic tile setup
	if props.ScaleType == "Tile" then
		table.insert(children, New "UIGridStyleLayout" {
			CellSize = UDim2.fromOffset(64, 64),
		})
	end

	if #children > 0 then
		imageLabel = Hydrate(imageLabel)( {
			[Fusion.Children] = children
		})
	end

	local hydrateProps = stripProps(props, COMPONENT_ONLY_PROPERTIES)
	return Hydrate(imageLabel)(hydrateProps)
end