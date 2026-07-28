export type InstanceData = {
	Name: string,
	ClassName: string,

	_children: { [number]: InstanceData },
	[any]: any,
}

local DEFAULT_PROPERTIES: { string } = { "Name", "ClassName" }
local ALLOWED_TYPES: { string } = { "GuiBase", "UIBase", "ScreenGui" }

local VIDE_TEMPLATE: string = [[--!nolint
-- %s

--> Vide API: https://centau.github.io/vide/api/reactivity-core.html
local Vide = require(%s)
local create = Vide.create

--> Vide Element
return function(props: {any}?)
    return %s
end]]

local DYNAMIC_VIDE_TEMPLATE: string = [[--!nolint
-- %s
local RunService = game:GetService("RunService")

--> Vide API: https://centau.github.io/vide/api/reactivity-core.html
local Vide = require(%s)
local create = Vide.create

local isPreview = RunService:IsStudio() and not RunService:IsRunning()

--> Dynamic Vide Element
return function(props: {any}?)
    local elements = {
        %s
    }

    if isPreview and not (props and props.__vigetOverride) then
        return elements
    end

    return create "ScreenGui" {
        %s
        elements
    }
end]]

local STORY_TEMPLATE: string = [[--!nolint

local App = require(%s)
local Vide = require(%s)

-- Wire specific values into your component's own create{} call as props.controls.<Name>
local controls = {}

local story = {
    vide = Vide,
    controls = controls,
    story = function(props)
        %s
    end,
}

return story]]

local ELEMENT_FORMAT: string = 'create "%s" {\n\t%s\n}'

local Reader = {}
Reader.vide = nil :: ModuleScript?

local InstanceProperties = require("../external/instance-properties") :: { [string]: { string } }
local Lint = require("./simple-linter")

-- Utility

local function isModule(inst: ModuleScript?): boolean
	if inst and typeof(inst) == "Instance" and inst:IsA("ModuleScript") then
		return true
	end
	return false
end

local function isAllowedType(inst: Instance): boolean
	if typeof(inst) ~= "Instance" then
		return false
	end

	for _, classType in ALLOWED_TYPES do
		if inst:IsA(classType) or classType == inst.ClassName then
			return true
		end
	end

	return false
end

local function serializeInstance(instance: Instance): InstanceData?
	assert(isAllowedType(instance), `{instance.ClassName} is not a valid class name`)

	local data = {}

	local properties = InstanceProperties[instance.ClassName]
	if not properties then
		return nil
	end

	for _, property: string in DEFAULT_PROPERTIES do
		data[property] = instance[property]
	end

	for _, property: string in properties do
		data[property] = instance[property]
	end

	if #instance:GetChildren() > 0 then
		data._children = {}

		for _, child in instance:GetChildren() do
			local _, childData = pcall(serializeInstance, child)
			if childData then
				table.insert(data._children, childData)
			end
		end
	end

	return data
end

local function createFromSerializedInstance(data: InstanceData): Instance
	local ok, instance = pcall(Instance.new, data.ClassName)

	assert(isAllowedType(instance), `{data.ClassName} is not a valid class name`)
	assert(ok, `Cannot create an instance of class "{data.ClassName}" from {data.Name}`)

	for property, value in data do
		if property == "_children" then
			for _, childData in value do
				local child = createFromSerializedInstance(childData)
				if child and isAllowedType(child) then
					child.Parent = instance
				end
			end
		else
			local ok2, result = pcall(function()
				instance[property] = value
			end)

			if not ok2 then
				warn(
					`Failed to set property: {property} on {instance.ClassName}: {tostring(result)}`
				)
			end
		end
	end

	return instance
end

local function isVide(vide: any): boolean
	if not isModule(vide) then
		return false
	end

	local ok, data = pcall(require, vide)
	if not ok then
		return false
	end

	if typeof(data) == "table" and typeof(data.create) == "function" then
		return true
	end

	return false
end

local function isStory(story: any): boolean
	if not isModule(story) then
		return false
	end

	local ok, data = pcall(require, story)
	if not ok then
		return false
	end

	if typeof(data) == "table" and typeof(data.story) == "function" then
		return true
	end

	return false
end

local function isVideApp(inst: any): boolean
	if not isModule(inst) then
		return false
	end

	local ok, data = pcall(require, inst)
	if not ok then
		return false
	end

	return typeof(data) == "function"
end

local function isValidIdentifier(name: string): boolean
	return name:match("^[%a_][%w_]*$") ~= nil
end

local function getRequirePath(inst: Instance): string
	local parts: { string } = {}
	local current: Instance? = inst

	while current and current.Parent and current.Parent ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	local serviceName = current and current.ClassName or "ReplicatedStorage"
	local path = string.format("game.%s", serviceName)

	for _, part in parts do
		path ..= if isValidIdentifier(part) then "." .. part else string.format("[%q]", part)
	end

	return path
end

-- Known package locations, checked before falling back to a scoped search.
local COMMON_VIDE_PATHS: { { string } } = {
	{ "ReplicatedStorage", "Packages", "Vide" },
	{ "ReplicatedStorage", "Vide" },
	{ "ServerScriptService", "Packages", "Vide" },
	{ "ServerStorage", "Packages", "Vide" },
}
local SEARCH_ROOTS: { string } = { "ReplicatedStorage", "ServerScriptService", "ServerStorage" }

local function tryPath(path: { string }): ModuleScript?
	local current: Instance = game
	for i, name in path do
		local ok, next_ = pcall(function()
			if i == 1 then
				return game:GetService(name)
			end
			return current:FindFirstChild(name)
		end)
		if not ok or not next_ then
			return nil
		end
		current = next_
	end
	return isModule(current) and (current :: any) or nil
end

local function locateVide(): ModuleScript?
	if isModule(Reader.vide) and isVide(Reader.vide) then
		return Reader.vide
	end

	for _, path in COMMON_VIDE_PATHS do
		local candidate = tryPath(path)
		if candidate and isVide(candidate) then
			Reader.vide = candidate
			return candidate
		end
	end

	for _, rootName in SEARCH_ROOTS do
		local ok, root = pcall(game.GetService, game, rootName)
		if ok and root then
			local found = root:FindFirstChild("Vide", true) or root:FindFirstChild("vide", true)
			if isModule(found) and isVide(found) then
				Reader.vide = found
				return found
			end
		end
	end

	return nil
end

-- Instance Reader

function Reader.Serialize(instance: Instance): InstanceData?
	local data = serializeInstance(instance)
	if not data then
		return nil
	end

	return data
end

function Reader.Deserialize(data: InstanceData): Instance?
	local instance = createFromSerializedInstance(data)
	if not instance then
		return nil
	end

	return instance
end

-- Vide Reader

local function serializeValue(value: any): string
	local t = typeof(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t == "EnumItem" then
		return `Enum.{tostring(value.EnumType)}.{value.Name}`
	elseif t == "UDim2" then
		return `UDim2.new({value.X.Scale}, {value.X.Offset}, {value.Y.Scale}, {value.Y.Offset})`
	elseif t == "UDim" then
		return `UDim.new({value.Scale}, {value.Offset})`
	elseif t == "Vector2" then
		return `Vector2.new({value.X}, {value.Y})`
	elseif t == "Color3" then
		return `Color3.new({value.R}, {value.G}, {value.B})`
	elseif t == "ColorSequence" then
		local keypoints = {}
		for _, kp in value.Keypoints do
			table.insert(
				keypoints,
				string.format(
					"ColorSequenceKeypoint.new(%s, Color3.new(%s, %s, %s))",
					tostring(kp.Time),
					kp.Value.R,
					kp.Value.G,
					kp.Value.B
				)
			)
		end
		return `ColorSequence.new({"{"}{table.concat(keypoints, ", ")}{"}"})`
	elseif t == "NumberSequence" then
		local keypoints = {}
		for _, kp in value.Keypoints do
			table.insert(
				keypoints,
				string.format(
					"NumberSequenceKeypoint.new(%s, %s, %s)",
					tostring(kp.Time),
					tostring(kp.Value),
					tostring(kp.Envelope)
				)
			)
		end
		return `NumberSequence.new({"{"}{table.concat(keypoints, ", ")}{"}"})`
	elseif t == "NumberRange" then
		return `NumberRange.new({value.Min}, {value.Max})`
	elseif t == "Rect" then
		return `Rect.new({value.Min.X}, {value.Min.Y}, {value.Max.X}, {value.Max.Y})`
	elseif t == "Font" then
		return `Font.new({string.format("%q", value.Family)}, {tostring(value.Weight)}, {tostring(
			value.Style
		)})`
	else
		return tostring(value)
	end
end

local function readDataIntoVideCode(data: InstanceData): string
	local keys: { string } = {}
	for property in data do
		if property ~= "_children" and property ~= "ClassName" then
			table.insert(keys, property)
		end
	end
	table.sort(keys)

	local lines: { string } = {}
	for _, property in keys do
		table.insert(lines, string.format("%s = %s", property, serializeValue(data[property])))
	end

	if data._children then
		for _, childData in data._children do
			table.insert(lines, readDataIntoVideCode(childData))
		end
	end

	return string.format(ELEMENT_FORMAT, data.ClassName, table.concat(lines, ",\n"))
end

function Reader.SerializeToVide(instance: Instance): ModuleScript?
	local data = serializeInstance(instance)
	if not data then
		return nil
	end

	local ok, vide_inst = pcall(locateVide)
	vide_inst = (ok and typeof(vide_inst) == "Instance") and vide_inst or nil

	if not vide_inst then
		warn("Vidgets: could not locate Vide automatically - fill in the require() path by hand")
	end

	local vide_path = if vide_inst then getRequirePath(vide_inst) else "nil"

	local sourceCode = ""

	if instance.ClassName == "ScreenGui" then
		-- Extract properties for the ScreenGui wrapper itself
		local propKeys: { string } = {}
		for property in data do
			if property ~= "_children" and property ~= "ClassName" then
				table.insert(propKeys, property)
			end
		end
		table.sort(propKeys)

		local propLines: { string } = {}
		for _, property in propKeys do
			table.insert(
				propLines,
				string.format("\t\t%s = %s,", property, serializeValue(data[property]))
			)
		end

		-- Extract children elements for the preview table
		local childLines: { string } = {}
		if data._children then
			for _, childData in data._children do
				table.insert(childLines, "\t\t" .. readDataIntoVideCode(childData) .. ",")
			end
		end

		sourceCode = string.format(
			DYNAMIC_VIDE_TEMPLATE,
			instance.Name,
			vide_path,
			table.concat(childLines, "\n"),
			table.concat(propLines, "\n")
		)
	else
		local ok2, raw = pcall(readDataIntoVideCode, data)
		raw = ok2 and raw or "nil"

		sourceCode = string.format(VIDE_TEMPLATE, instance.Name, vide_path, raw)
	end

	local ModuleScript = Instance.new("ModuleScript")
	ModuleScript.Name = `{instance.Name}-Vide`
	ModuleScript.Source = Lint(sourceCode)

	ModuleScript.Parent = workspace
	return ModuleScript
end

function Reader.DeserializeFromVide(moduleScript: ModuleScript): Instance?
	if not isModule(moduleScript) then
		return nil
	end

	local ok, App = pcall(require, moduleScript)
	if not ok or typeof(App) ~= "function" then
		warn(`Failed to require Vide module {moduleScript.Name}: {tostring(App)}`)
		return nil
	end

	-- Pass the override flag so it builds the full ScreenGui even in Studio preview mode
	local ok2, instance = pcall(App, { __vigetOverride = true })
	if not ok2 or typeof(instance) ~= "Instance" then
		warn(`Vide module {moduleScript.Name} did not return an Instance: {tostring(instance)}`)
		return nil
	end

	instance.Parent = moduleScript.Parent or moduleScript
	return instance
end

-- Experimental

local DYNAMIC_MARKER = "--> Dynamic Vide Element"

local function isDynamicVideApp(moduleScript: ModuleScript): boolean
	local ok, source = pcall(function()
		return moduleScript.Source
	end)
	return ok and typeof(source) == "string" and source:find(DYNAMIC_MARKER, 1, true) ~= nil
end

function Reader.VideAppToStory(app: ModuleScript): ModuleScript?
	if not isModule(app) then
		return nil
	end

	local ok, videModule = pcall(locateVide)
	videModule = (ok and typeof(videModule) == "Instance") and videModule or nil

	local storyBody = if isDynamicVideApp(app)
		then [[local elements = App(props.controls)
        if typeof(elements) == "table" then
            for _, element in elements do
                if typeof(element) == "Instance" then
                    element.Parent = props.target
                end
            end
        end
        return nil]]
		else [[local element = App(props.controls)
        if typeof(element) == "Instance" then
            element.Parent = props.target
        end
        return nil]]

	local storyScript = Instance.new("ModuleScript")
	storyScript.Name = `{app.Name}.story`

	storyScript.Source = Lint(
		string.format(
			STORY_TEMPLATE,
			`script.Parent`,
			if videModule then getRequirePath(videModule) else "nil",
			storyBody
		)
	)

	storyScript.Parent = app
	return storyScript
end

function Reader.DeserializeFromStory(moduleScript: ModuleScript): Instance?
	if not isModule(moduleScript) then
		return nil
	end

	local ok, storyData = pcall(require, moduleScript)
	if not ok or typeof(storyData) ~= "table" or typeof(storyData.story) ~= "function" then
		warn(`{moduleScript.Name} is not a valid story module`)
		return nil
	end

	local ok2, instance = pcall(storyData.story, { controls = storyData.controls or {} })
	if not ok2 or typeof(instance) ~= "Instance" then
		warn(`Story {moduleScript.Name} did not return an Instance: {tostring(instance)}`)
		return nil
	end

	instance.Parent = moduleScript.Parent or moduleScript
	return instance
end

-- Exports

function Reader.IsStory(inst: ModuleScript): boolean
	return isStory(inst)
end

function Reader.IsVideApp(inst: ModuleScript): boolean
	return isVideApp(inst) and not isStory(inst)
end

-- Control

function Reader.setVide(vide: ModuleScript)
	if not isModule(vide) or not isVide(vide) then
		return
	end

	Reader.vide = vide
end

return Reader
