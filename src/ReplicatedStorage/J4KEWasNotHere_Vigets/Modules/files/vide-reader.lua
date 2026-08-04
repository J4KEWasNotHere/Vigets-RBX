export type InstanceData = {
	Name: string,
	ClassName: string,

	_children: { [number]: InstanceData },
	[any]: any,
}

local ALLOWED_TYPES: { string } = { "GuiBase", "UIBase", "ScreenGui", "Folder" }

local Complex_Types: { string } = {
	"PVInstance",
	"BaseScript",
	"BaseRemoteEvent",
	
	"ModuleScript",
	"RemoteFunction",
	
	"BindableEvent",
	"BindableFunction",
	"Animation",
	"AnimationTrack",
	"Actor",
	
	"Bone",
	"Attachment",
	"Motor6D",
	"Motor",
	"Weld",
	"WeldConstraint",
	"SpecialMesh",
	"Sound",
	"Camera",
	"Animation",
}

local VIDE_TEMPLATE: string = [[--!nolint

--> Vide API: https://centau.github.io/vide/api/reactivity-core.html
local Vide = require(%s)
local create = Vide.create

--> Vide Element
return function(props: {any}?)
%s
end]]

local DYNAMIC_VIDE_TEMPLATE: string = [[--!nolint

local RunService = game:GetService("RunService")

--> Vide API: https://centau.github.io/vide/api/reactivity-core.html
local Vide = require(%s)
local create = Vide.create

local isPreview = RunService:IsStudio() and not RunService:IsRunning()

return function(props: {any}?)
	%s
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

-- Resource collection state (populated during serialization pass)
local CurrentResources = nil
local ResourceNameMap: { [string]: boolean } = {}
local ResourcePathMap: { [string]: string } = {}

local function sanitizeIdentifier(name: string): string
	if not name or name == "" then
		return "resource"
	end
	local s = name:gsub("[^%w_]", "_")
	if s:match("^[0-9]") then
		s = "_" .. s
	end
	return s
end

local function makeUniqueName(base: string): string
	local name = base
	local i = 1
	while ResourceNameMap[name] do
		name = string.format("%s%03d", base, i)
		i = i + 1
	end
	return name
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

local function registerResource(inst: Instance): string
	if not CurrentResources then
		CurrentResources = {}
		ResourceNameMap = {}
		ResourcePathMap = {}
	end

	local requirePath = getRequirePath(inst)
	if ResourcePathMap[requirePath] then
		return ResourcePathMap[requirePath]
	end

	local base = sanitizeIdentifier(inst.Name ~= "" and inst.Name or inst.ClassName)
	local varName = makeUniqueName(base)
	ResourceNameMap[varName] = true
	ResourcePathMap[requirePath] = varName

	table.insert(
		CurrentResources,
		{ varName = varName, instance = inst, requirePath = requirePath }
	)
	return varName
end

local function buildResourceCode(resourcePrefix: string): string
	if not CurrentResources or #CurrentResources == 0 then
		return ""
	end

	local name = resourcePrefix or ".rscs"
	local scriptRef = if isValidIdentifier(name)
		then "script." .. name
		else "script[" .. string.format("%q", name) .. "]"

	local lines: { string } = {}
	table.insert(lines, "\t-- Resources")
	table.insert(lines, string.format("\tlocal resources = %s:Clone()", scriptRef))

	for _, r in ipairs(CurrentResources) do
		table.insert(lines, string.format("\tlocal %s = resources[%q]", r.varName, r.varName))
	end

	return table.concat(lines, "\n")
end

local Constants = require("../external/constants")
local InstanceProperties = require("../external/instance-properties") :: { [string]: { string } }
local InstanceDefaults = require("../external/instance-defaults") :: { [string]: { [string]: any } }

local Lint = require("./simple-linter")

local DEBUG = Constants.DebugEnabled

-- Utility

local function isDefaultValue(className: string, property: string, value: any): boolean
	if property == "Name" and value == className then
		return true
	end

	local classDefaults = InstanceDefaults[className]
	if not classDefaults then
		return false
	end

	local defaultValue = classDefaults[property]
	
	if defaultValue == ".__readasnil" then
		return value == nil
	end

	if defaultValue == nil then
		return false
	end

	if typeof(value) == "number" and typeof(defaultValue) == "number" then
		return math.abs(value - defaultValue) < 0.0001
	end

	return value == defaultValue
end

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

local function isComplexType(inst: Instance): boolean
	if typeof(inst) ~= "Instance" then
		return false
	end

	for _, classType in Complex_Types do
		if inst:IsA(classType) or classType == inst.ClassName then
			return true
		end
	end

	return false
end

local ProperitesToExclude: { string } = { "IsLoaded" }

local function serializeInstance(instance: Instance): InstanceData?
	assert(
		isAllowedType(instance) or isComplexType(instance),
		`{instance.ClassName} is not a valid class name`
	)

	local data = {}
	local properties = InstanceProperties[instance.ClassName]
	if not properties then
		return nil
	end

	if not isDefaultValue(instance.ClassName, "Name", instance.Name) then
		data["Name"] = instance.Name
	end

	data["ClassName"] = instance.ClassName

	for _, property: string in properties do
		if table.find(ProperitesToExclude, property) then
			continue
		end

		local value = instance[property]
		if isDefaultValue(instance.ClassName, property, value) then
			continue
		end

		data[property] = value
	end

	if #instance:GetChildren() > 0 then
		data._children = {}

		for _, child in instance:GetChildren() do
			if isComplexType(child) then
				table.insert(data._children, {
					Name = child.Name,
					ClassName = child.ClassName,
					_complexInstance = child,
				})
			elseif isAllowedType(child) then
				local ok, childData = pcall(serializeInstance, child)
				if ok and childData then
					table.insert(data._children, childData)
				end
			end
		end
	end

	return data
end

local function createFromSerializedInstance(data: InstanceData): Instance
	if data._complexInstance then
		local ok, clone = pcall(function()
			return (data._complexInstance :: Instance):Clone()
		end)

		assert(ok and clone, `Failed to clone complex instance for {data.Name}`)

		if data.Name then
			clone.Name = data.Name
		end

		return clone
	end

	local ok, instance = pcall(Instance.new, data.ClassName)

	assert(
		isAllowedType(instance) or isComplexType(instance),
		`{data.ClassName} is not a valid class name`
	)
	assert(ok, `Cannot create an instance of class "{data.ClassName}" from {data.Name}`)

	for property, value in data do
		if property == "_children" then
			for _, childData in value do
				local child = createFromSerializedInstance(childData)
				if child and (isAllowedType(child) or isComplexType(child)) then
					child.Parent = instance
				end
			end
		elseif property ~= "_complexInstance" then
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
		warn(`Failed to require vide module {vide.Name}: {tostring(data)}`)
		return false
	end

	if typeof(data) == "table" and typeof(data.create) == "function" then
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
		if DEBUG then
			warn(`Failed to require module {inst.Name}: {tostring(data)}`)
		end
		return false
	end

	return typeof(data) == "function"
end

local function isStory(story: any): boolean
	if not isModule(story) then
		return false
	end

	local ok, data = pcall(require, story)
	if not ok then
		if DEBUG then
			warn(`Failed to require story module {story.Name}: {tostring(data)}`)
		end
		return false
	end

	if typeof(data) == "table" and typeof(data.story) == "function" then
		return true
	end

	return false
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
	return isModule(current :: ModuleScript) and (current :: any) or nil
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
		elseif not ok and root and DEBUG then
			warn(`Failed to get service {rootName}: {tostring(root)}`)
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

local function fmt(n: number): string
	return string.format("%.4g", n)
end

local function serializeValue(value: any): string
	local t = typeof(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" then
		return fmt(value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "EnumItem" then
		return `Enum.{tostring(value.EnumType)}.{value.Name}`
	elseif t == "UDim2" then
		return `UDim2.new({fmt(value.X.Scale)}, {fmt(value.X.Offset)}, {fmt(value.Y.Scale)}, {fmt(
			value.Y.Offset
		)})`
	elseif t == "UDim" then
		return `UDim.new({fmt(value.Scale)}, {fmt(value.Offset)})`
	elseif t == "Vector2" then
		return `Vector2.new({fmt(value.X)}, {fmt(value.Y)})`
	elseif t == "Vector3" then
		return `Vector3.new({fmt(value.X)}, {fmt(value.Y)}, {fmt(value.Z)})`
	elseif t == "Instance" then
		local ok, varName = pcall(function()
			return registerResource(value)
		end)
		if ok and type(varName) == "string" then
			return varName
		end
		return "nil"
	elseif t == "Color3" then
		return `Color3.fromRGB({fmt(math.round(value.R * 255))}, {fmt(math.round(value.G * 255))}, {fmt(
			math.round(value.B * 255)
		)})`
	elseif t == "ColorSequence" then
		local keypoints = {}
		for _, kp in value.Keypoints do
			table.insert(
				keypoints,
				string.format(
					"ColorSequenceKeypoint.new(%s, Color3.fromRGB(%s, %s, %s))",
					fmt(kp.Time),
					fmt(math.round(kp.Value.R * 255)),
					fmt(math.round(kp.Value.G * 255)),
					fmt(math.round(kp.Value.B * 255))
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
					fmt(kp.Time),
					fmt(kp.Value),
					fmt(kp.Envelope)
				)
			)
		end
		return `NumberSequence.new({"{"}{table.concat(keypoints, ", ")}{"}"})`
	elseif t == "NumberRange" then
		return `NumberRange.new({fmt(value.Min)}, {fmt(value.Max)})`
	elseif t == "Rect" then
		return `Rect.new({fmt(value.Min.X)}, {fmt(value.Min.Y)}, {fmt(value.Max.X)}, {fmt(
			value.Max.Y
		)})`
	elseif t == "Font" then
		return `Font.new({string.format("%q", value.Family)}, {tostring(value.Weight)}, {tostring(
			value.Style
		)})`
	else
		return tostring(value)
	end
end

local function readDataIntoVideCode(data: InstanceData): string
	if data._complexInstance then
		local ok, varName = pcall(registerResource, data._complexInstance)
		if ok and type(varName) == "string" then
			return varName
		end
		return "nil"
	end

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
			if childData._complexInstance then
				local ok, varName = pcall(registerResource, childData._complexInstance)
				if ok and type(varName) == "string" then
					table.insert(lines, varName)
				end
			else
				table.insert(lines, readDataIntoVideCode(childData))
			end
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

		local childLines: { string } = {}
		if data._children then
			for _, childData in data._children do
				if childData._complexInstance then
					local ok2, varName = pcall(registerResource, childData._complexInstance)
					if ok2 and type(varName) == "string" then
						table.insert(childLines, "\t\t" .. varName .. ",")
					end
				else
					table.insert(childLines, "\t\t" .. readDataIntoVideCode(childData) .. ",")
				end
			end
		end

		local resourceCode = buildResourceCode(".rscs")

		sourceCode = string.format(
			DYNAMIC_VIDE_TEMPLATE,
			vide_path,
			resourceCode,
			table.concat(childLines, "\n"),
			table.concat(propLines, "\n")
		)
	else
		local ok2, raw = pcall(readDataIntoVideCode, data)
		if not ok2 and DEBUG then
			warn(`Failed to serialize instance {instance.Name} to Vide code: {tostring(raw)}`)
		end

		raw = ok2 and raw or "nil"

		local resourceCode = buildResourceCode(".rscs")
		local body = resourceCode ~= "" and (resourceCode .. "\n\treturn " .. raw)
			or ("\treturn " .. raw)

		sourceCode = string.format(VIDE_TEMPLATE, vide_path, body)
	end

	local ModuleScript = Instance.new("ModuleScript")
	ModuleScript.Name = `{instance.Name}-Vide`
	ModuleScript.Source = Lint(sourceCode)

	if CurrentResources and #CurrentResources > 0 then
		local resourceFolder = Instance.new("Folder")
		resourceFolder.Name = ".rscs"
		resourceFolder.Parent = ModuleScript

		for _, r in ipairs(CurrentResources) do
			local clone = r.instance:Clone()
			clone.Name = r.varName
			clone.Parent = resourceFolder
		end
	end

	ModuleScript.Parent = workspace

	CurrentResources = nil
	ResourceNameMap = {}
	ResourcePathMap = {}

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

local function read(value)
	if typeof(value) == "function" then
		return value()
	end
	return value
end

function Reader.DeserializeFromStory(moduleScript: ModuleScript): Instance?
	if not isModule(moduleScript) then
		return nil
	end

	local appModule = moduleScript.Parent
	if not isModule(appModule) then
		warn(`{moduleScript.Name} has no parent App module to build from`)
		return nil
	end

	local ok, AppFn = pcall(require, appModule)
	if not ok or typeof(AppFn) ~= "function" then
		warn(`Failed to require App for story {moduleScript.Name}: {tostring(AppFn)}`)
		return nil
	end

	local ok2, dynamic = pcall(isDynamicVideApp, appModule)
	dynamic = ok2 and dynamic or false

	local ok4, storyData = pcall(require, moduleScript)
	
	local controls = (ok4 and typeof(storyData) == "table" and typeof(storyData.controls) == "table")
		and storyData.controls
		or {}

	local props = table.clone(controls)
	
	if dynamic then
		props.__vigetOverride = true
	end

	local ok3, instance = pcall(AppFn, props)
	if not ok3 or typeof(instance) ~= "Instance" then
		warn(`Story {moduleScript.Name} did not return an Instance: {tostring(instance)}`)
		return nil
	end

	instance.Parent = moduleScript.Parent or moduleScript
	return instance
end

-- Exports

function Reader.IsStory(inst: ModuleScript): boolean
	local ok, result = pcall(isStory, inst)
	return ok and result or false
end

function Reader.IsVideApp(inst: ModuleScript): boolean
	local ok, result = pcall(function()
		return isVideApp(inst) and not isStory(inst)
	end)
	return ok and result or false
end

-- Control

function Reader.setVide(vide: ModuleScript)
	if not isModule(vide) or not isVide(vide) then
		return
	end

	Reader.vide = vide
end

return Reader
