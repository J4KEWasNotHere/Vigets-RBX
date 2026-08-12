local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local SelectionService = game:GetService("Selection")

type pluginRoot = typeof(script.Parent.Parent.Parent)

return {
	start = function(toolbar, pluginInstance: Plugin, pluginRoot: pluginRoot)
		if RunService:IsRunMode() or RunService:IsRunning() then
			return {}
		end

		local exported_settings = {}

		local Components = pluginRoot.Components
		local Packages = pluginRoot.Packages

		local PluginComponents = Components:FindFirstChild("PluginComponents")
		local Widget = require(PluginComponents.Widget)

		local StudioComponents = Components:FindFirstChild("StudioComponents")
		local MainButton = require(StudioComponents.MainButton)
		local Label = require(StudioComponents.Label)
		local Seperator = require(StudioComponents.Seperator)
		local Checkbox = require(StudioComponents.Checkbox)
		local VerticalCollapsibleSection = require(StudioComponents.VerticalCollapsibleSection)

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
		local Fetcher = require(Modules.external.fetcher)

		local button =
			toolbar:CreateButton(`Settings`, `{Constants.Name} Settings`, Constants.SettingsIcon)

		button.ClickableWhenViewportHidden = true
		local widgetsEnabled = Value(false)

		local initialWrapCreations = pluginInstance:GetSetting("WrapCreations")
		if typeof(initialWrapCreations) ~= "boolean" then
			initialWrapCreations = false
		end

		local wrapCreations = Value(initialWrapCreations)
		exported_settings.WrapCreations = wrapCreations

		local function onSelectionChanged()
			return
		end

		local function AddWidget(name, children)
			local id = HttpService:GenerateGUID()
			return Widget({
				Id = id,
				Name = name or id,
				InitialDockTo = Enum.InitialDockState.Float,
				InitialEnabled = false,
				ForceInitialEnabled = true,
				FloatingSize = Constants.SettingsWidgetSize,
				MinimumSize = Constants.SettingsWidgetSize,

				Enabled = widgetsEnabled,
				[OnChange("Enabled")] = function(isEnabled)
					widgetsEnabled:set(isEnabled)
					if isEnabled then
						onSelectionChanged()
					end
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

		SelectionService.SelectionChanged:Connect(onSelectionChanged)
		onSelectionChanged()

		local RECORDING_NAME = "Vigets_Settings"
		local function beginRecording(): string?
			local id = ChangeHistoryService:TryBeginRecording(RECORDING_NAME, "Vigets settings")
			if not id then
				task.wait()
				id = ChangeHistoryService:TryBeginRecording(RECORDING_NAME, "Vigets settings")
			end
			return id
		end

		-- Components

		local function makeCard(contents, padding: number?, transparency: number?, y: NumberRange?)
			return New("Frame")({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = transparency or 0.7,
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BorderSizePixel = 0,
				[Children] = {
					New("UICorner")({ CornerRadius = UDim.new(0, 8) }),
					New("UIPadding")({
						PaddingLeft = UDim.new(0, padding or 6),
						PaddingRight = UDim.new(0, padding or 6),
						PaddingTop = UDim.new(0, padding or 6),
						PaddingBottom = UDim.new(0, padding or 6),
					}),
					New("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					New("UISizeConstraint")({
						MaxSize = Vector2.new(9999, y and y.Max or 9999),
						MinSize = Vector2.new(0, y and y.Min or 0),
					}),
					table.unpack(contents),
				},
			})
		end

		local function makeSectionHeader(text)
			return Label({
				Text = text,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				TextSize = 14,
			})
		end

		local function buildVersionSections()
			local registry = Fetcher.getRegistry() or {}
			local versions = {}
			for v, _ in pairs(registry.VideVersions or {}) do
				table.insert(versions, v)
			end
			table.sort(versions, function(a, b)
				return a > b
			end)

			local sections = {}
			for _i, version in ipairs(versions) do
				table.insert(
					sections,
					VerticalCollapsibleSection({
						Text = `{registry.VideWallyDirectory or "centau_vide@"}{version}{_i == 1 and " (latest)" or ""}`,
						Collapsed = true,
						[Children] = {
							New("UIListLayout")({
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 6),
							}),

							MainButton({
								Text = `Install {version}`,
								Activated = function()
									local recordingId = beginRecording()
									if not recordingId then
										warn(
											"Vigets: could not begin change history recording - try again; if issue persists please restart studio."
										)
										return
									end

									local ok, err = pcall(function()
										local lib = Fetcher.getVide(version)
										if lib then
											local _, destination = Fetcher.installVide(lib)
											print(
												`Vigets: successfully installed v{version} of Vide to {destination}.`
											)
										end
									end)

									ChangeHistoryService:FinishRecording(
										recordingId,
										ok and Enum.FinishRecordingOperation.Commit
											or Enum.FinishRecordingOperation.Cancel
									)

									if not ok then
										warn(
											`Vigets: install failed for v{version} - {tostring(err)}`
										)
									end
								end,
								Size = UDim2.new(1, 0, 0, 28),
							}),
						},
					})
				)
			end

			return makeCard(sections, nil, 1)
		end

		AddWidget(`{Constants.Name} Settings | {Constants.Version}{Constants.VersionTip}`, {
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

					makeSectionHeader("Conversion"),

					Checkbox({
						Text = "Use brackets for Components",
						Value = wrapCreations,
						OnChange = function(value)
							wrapCreations:set(value)
							pcall(function()
								pluginInstance:SetSetting("WrapCreations", value)
							end)
						end,
					}),

					makeSectionHeader("Setup"),

					makeCard({
						VerticalCollapsibleSection({
							Text = "Install Vide",
							Collapsed = true,
							[Children] = buildVersionSections(),
						}),
					}, 0),
				},
			}),
		})

		button.Click:Connect(function()
			widgetsEnabled:set(not widgetsEnabled:get(false))
		end)

		widgetsEnabled:set(false)

		return exported_settings
	end,
}
