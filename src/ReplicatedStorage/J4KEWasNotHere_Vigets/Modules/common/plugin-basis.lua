local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local SelectionService = game:GetService("Selection")

type pluginRoot = typeof(script.Parent.Parent.Parent)

return {
	start = function(pluginInstance: Plugin, pluginRoot: pluginRoot)
		if RunService:IsRunMode() or RunService:IsRunning() then
			return function() end
		end

		local Components = pluginRoot.Components
		local Packages = pluginRoot.Packages
		local PluginComponents = Components:FindFirstChild("PluginComponents")
		local Widget = require(PluginComponents.Widget)
		local StudioComponents = Components:FindFirstChild("StudioComponents")
		local MainButton = require(StudioComponents.MainButton)
		local Label = require(StudioComponents.Label)
		local Seperator = require(StudioComponents.Seperator)
		local Fusion = require(Packages.Fusion)
		local New = Fusion.New
		local Value = Fusion.Value
		local Children = Fusion.Children
		local OnChange = Fusion.OnChange
		local OnEvent = Fusion.OnEvent
		local Computed = Fusion.Computed
		local unwrap = require(StudioComponents.Util.unwrap)

		local StudioComponentsUtil = StudioComponents.Util
		local themeProvider = require(StudioComponentsUtil.themeProvider)
		local getMotionState = require(StudioComponentsUtil.getMotionState)
		local getModifier = require(StudioComponentsUtil.getModifier)

		local Modules = pluginRoot.Modules
		local Constants = require(Modules.external.constants)
		local Reader = require(Modules.files["vide-reader"])

		local toolbar = pluginInstance:CreateToolbar(Constants.Name)
		local button = toolbar:CreateButton(Constants.Name, `Open {Constants.Name}`, Constants.Icon)
		button.ClickableWhenViewportHidden = true

		local widgetsEnabled = Value(false)
		local function AddWidget(name, children)
			local id = HttpService:GenerateGUID()
			return Widget({
				Id = id,
				Name = name or id,
				InitialDockTo = Enum.InitialDockState.Float,
				InitialEnabled = false,
				ForceInitialEnabled = true,
				FloatingSize = Constants.WidgetSize,
				MinimumSize = Constants.WidgetSize,

				Enabled = widgetsEnabled,
				[OnChange("Enabled")] = function(isEnabled)
					widgetsEnabled:set(isEnabled)
				end,
				[Children] = New("Frame")({
					ZIndex = 1,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					[Children] = {
						New("UIListLayout")({
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),

						New("UIPadding")({
							PaddingLeft = UDim.new(0, 6),
							PaddingRight = UDim.new(0, 6),
							PaddingBottom = UDim.new(0, 10),
							PaddingTop = UDim.new(0, 10),
						}),

						children,
					},
				}),
			})
		end

		local function CreateMethodButton(props)
			local rounding = props.Rounding or UDim.new(0, 6)
			local isSelected = props.Selected or Value(false)
			local hasImage = Value(props.Image and props.Image ~= "" or false)

			local modifier = getModifier({
				Enabled = true,
				Selected = isSelected,
			})

			return New("TextButton")({
				Visible = props.Visible == true,
				Size = props.Size or UDim2.new(1, 0, 0, 24),
				AutoButtonColor = false,
				BackgroundColor3 = getMotionState(
					themeProvider:GetColor(
						props.BackgroundColorStyle or Enum.StudioStyleGuideColor.Button,
						modifier
					),
					"Spring",
					40
				),
				BackgroundTransparency = 0,
				Text = "",

				[OnEvent("Activated")] = function()
					if props.Activated then
						props.Activated()
					end
				end,

				[Children] = {
					New("UICorner")({
						TopLeftRadius = rounding,
						TopRightRadius = rounding,
						BottomLeftRadius = rounding,
						BottomRightRadius = rounding,
					}),

					New("UIPadding")({
						PaddingLeft = UDim.new(0, 5),
						PaddingRight = UDim.new(0, 5),
						PaddingBottom = UDim.new(0, 4),
						PaddingTop = UDim.new(0, 4),
					}),

					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					}),

					New("ImageLabel")({
						BackgroundTransparency = 1,
						LayoutOrder = 0,
						Size = UDim2.fromScale(props.IconSize or 1, props.IconSize or 1),
						Image = props.Image or "",
						Visible = Computed(function()
							return unwrap(hasImage)
						end),

						[Children] = {
							New("UIAspectRatioConstraint")({}),
						},
					}),

					New("TextLabel")({
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 1, 0),
						AutomaticSize = Enum.AutomaticSize.X,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = props.Text,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextSize = 15,
					}),
				},
			})
		end

		local isWorking = Value(false)
		local canBuild = Value(false)
		local selectedMethod = Value("")

		local MethodButtonSize = UDim2.new(1, 0, 0, 40)

		local CONVERSIONS = {
			{
				Id = "toVide",
				Text = "Convert to Vide Component",
				Image = "rbxassetid://131881863542969", --"http://www.roblox.com/asset/?id=6031233841",
				IconSize = 0.85,
				Applies = function(inst: Instance)
					return inst:IsA("GuiBase") or inst:IsA("UIBase")
				end,
				Run = function(inst: Instance)
					return Reader.SerializeToVide(inst)
				end,
			},
			{
				Id = "toStory",
				Text = "Convert to Story",
				Image = "rbxassetid://96954263450238", --"http://www.roblox.com/asset/?id=6031233841",
				IconSize = 0.9,
				Applies = function(inst: Instance)
					return inst:IsA("ModuleScript")
				end,
				Run = function(inst: ModuleScript)
					return Reader.VideAppToStory(inst)
				end,
			},
			{
				Id = "fromVide",
				Text = "Build from Component",
				Image = "rbxassetid://6383105831", --"http://www.roblox.com/asset/?id=6023426938",
				IconSize = 0.7,
				Applies = function(inst: Instance)
					return inst:IsA("ModuleScript")
				end,
				Run = function(inst: ModuleScript)
					return Reader.DeserializeFromVide(inst)
				end,
			},
		}

		local CONVERSIONS_BY_ID = {}
		for _, conversion in CONVERSIONS do
			CONVERSIONS_BY_ID[conversion.Id] = conversion
		end

		local elementMethods = Value({})
		local conversionTargets = {}

		local function updateConversions(instances: { Instance })
			local newButtons = {}
			local anyValid = false
			conversionTargets = {}

			for _, conversion in CONVERSIONS do
				local applicable = {}
				for _, inst in instances do
					local ok, applies = pcall(conversion.Applies, inst)
					if ok and applies then
						table.insert(applicable, inst)
					end
				end

				if #applicable > 0 then
					anyValid = true
					conversionTargets[conversion.Id] = applicable

					local isThisSelected = Computed(function()
						return unwrap(selectedMethod) == conversion.Id
					end)

					local labelText = conversion.Text
					if #applicable > 1 then
						labelText = `{conversion.Text} ({#applicable})`
					end

					table.insert(
						newButtons,
						CreateMethodButton({
							Image = conversion.Image,
							Text = labelText,
							Size = MethodButtonSize,
							Visible = true,
							Selected = isThisSelected,
							IconSize = conversion.IconSize or 1,
							Activated = function()
								selectedMethod:set(conversion.Id)
							end,
						})
					)
				end
			end

			canBuild:set(anyValid)
			if not anyValid or not conversionTargets[unwrap(selectedMethod)] then
				selectedMethod:set("")
			end
			elementMethods:set(newButtons)
		end

		local items = Value({})
		local function onSelectionChanged()
			local selection = SelectionService:Get()
			items:set(selection)
			updateConversions(selection)
		end

		SelectionService.SelectionChanged:Connect(onSelectionChanged)
		onSelectionChanged()

		local RECORDING_NAME = "Vidgets_Build"
		local function beginRecording(): string?
			local id = ChangeHistoryService:TryBeginRecording(RECORDING_NAME, "Vidgets conversion")
			if not id then
				task.wait()
				id = ChangeHistoryService:TryBeginRecording(RECORDING_NAME, "Vidgets conversion")
			end
			return id
		end

		local _mainWidget =
			AddWidget(`{Constants.Name} | {Constants.Version}{Constants.VersionTip}`, {
				New("ScrollingFrame")({
					Size = UDim2.fromScale(1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.fromScale(0, 0),

					BackgroundTransparency = 1,
					ScrollBarThickness = 0,
					ScrollBarImageTransparency = 1,

					[Children] = {
						New("UIListLayout")({
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
						}),

						New("UIFlexItem")({
							FlexMode = Enum.UIFlexMode.Fill,
						}),

						Computed(function()
							if unwrap(canBuild) then
								return New("ScrollingFrame")({
									BackgroundTransparency = 1,
									Size = UDim2.new(1, 0, 1, 0),
									AutomaticCanvasSize = Enum.AutomaticSize.Y,
									CanvasSize = UDim2.fromScale(0, 0),
									ScrollBarThickness = 0,
									ScrollBarImageTransparency = 1,
									[Children] = {
										New("UIListLayout")({
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = UDim.new(0, 8),
										}),
										unwrap(elementMethods),
									},
								})
							else
								return New("Frame")({
									BackgroundTransparency = 1,
									Size = UDim2.fromScale(1, 1),

									[Children] = {
										New("UIListLayout")({
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = UDim.new(0, 8),
											HorizontalAlignment = Enum.HorizontalAlignment.Center,
											VerticalAlignment = Enum.VerticalAlignment.Center,
										}),

										New("UIPadding")({
											PaddingLeft = UDim.new(0.15, 0),
											PaddingRight = UDim.new(0.15, 0),
											PaddingBottom = UDim.new(0, 12),
											PaddingTop = UDim.new(0, 12),
										}),

										New("ImageLabel")({
											BackgroundTransparency = 1,
											Image = Computed(function()
												return #unwrap(items) == 0
														and "http://www.roblox.com/asset/?id=6023565916"
													or "http://www.roblox.com/asset/?id=6031071050"
											end),
											Size = UDim2.fromOffset(42, 42),
										}),

										Label({
											Text = Computed(function()
												local noneSelected = "Nothing is selected yet.."
												local invalidSelected =
													"Selected instance(s) aren't compatible!"
												local result = #unwrap(items) == 0 and noneSelected
													or invalidSelected
												return result
											end),
											TextSize = 14,
											TextColor3 = Color3.fromRGB(180, 180, 180),
										}),
									},
								})
							end
						end, function(instance)
							if instance then
								instance:Destroy()
							end
						end),
					},
				}),

				Seperator({}),

				MainButton({
					Text = "Build",
					Size = UDim2.new(1, 0, 0, 24),
					Enabled = Computed(function()
						return not unwrap(isWorking)
							and unwrap(canBuild)
							and unwrap(selectedMethod) ~= ""
					end),
					Activated = function()
						local method = unwrap(selectedMethod)
						local conversion = CONVERSIONS_BY_ID[method]
						local targets = conversion and conversionTargets[method]

						if not conversion or not targets or #targets == 0 then
							warn(
								"Vidgets: select at least one compatible instance and a conversion first"
							)
							return
						end

						isWorking:set(true)

						local recordingId = beginRecording()
						if not recordingId then
							warn(
								"Vidgets: could not begin change history recording - try clicking Build again"
							)
							isWorking:set(false)
							return
						end

						local builtCount = 0
						local failedCount = 0
						local toSelect = {}

						for _, inst in targets do
							local ok, result = pcall(conversion.Run, inst)
							if ok and result then
								builtCount += 1
								table.insert(toSelect, result)
							else
								failedCount += 1
								warn(
									`Vidgets: build failed for {inst:GetFullName()} - {tostring(
										result
									)}`
								)
							end
						end

						isWorking:set(false)

						if builtCount > 0 then
							ChangeHistoryService:FinishRecording(
								recordingId,
								Enum.FinishRecordingOperation.Commit
							)
							SelectionService:Set(toSelect)
							if failedCount > 0 then
								warn(
									`Vidgets: built {builtCount} instance(s), {failedCount} failed`
								)
							end
						else
							ChangeHistoryService:FinishRecording(
								recordingId,
								Enum.FinishRecordingOperation.Cancel
							)
							warn("Vidgets: build failed for all selected instances")
						end
					end,
				}),
			})

		button.Click:Connect(function()
			widgetsEnabled:set(not widgetsEnabled:get(false))
		end)

		return function()
			widgetsEnabled:set(not widgetsEnabled:get(false))
		end
	end,
}
