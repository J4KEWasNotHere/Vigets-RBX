--!nonstrict

local Fetcher = {}

-- Services
local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
const Constants = require("./constants")
const RegUrl = Constants.RegistryUrl

-- Objects
local LocalVideCopy = script.Parent.Parent.objects:FindFirstChild("vide")

-- Variables
local RegistryCache = nil

-- Utility

local function new(class: string, props: { [string]: any }?)
	local obj = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			pcall(function()
				obj[k] = v
			end)
		end
	end
	return obj
end

local function parseLuaTable(content: string)
	local func, err = loadstring(content)
	if not func then
		warn("Syntax error: " .. tostring(err))
		return nil
	end

	local ok, result = pcall(func)
	if not ok then
		warn("Runtime error: " .. tostring(result))
		return nil
	end

	return result
end

local function tryGetUrl(url: string, nocache: boolean?): (boolean, string)
	local candidates = { url }

	if url:match("^https://raw.githubusercontent.com/") then
		local mirror = url:gsub(
			"^https://raw.githubusercontent.com/([^/]+)/([^/]+)/(.+)$",
			"https://cdn.jsdelivr.net/gh/%1/%2@main/%3"
		)
		table.insert(candidates, mirror)
	elseif url:match("^https://api.github.com/") then
		local mirror = url:gsub(
			"^https://api.github.com/repos/([^/]+)/([^/]+)/contents",
			"https://cdn.jsdelivr.net/gh/%1/%2@main"
		)
		table.insert(candidates, mirror)
	end

	for _, candidate in ipairs(candidates) do
		local success, result = pcall(function()
			return HttpService:GetAsync(candidate, nocache)
		end)
		if success and tostring(result or "") ~= "" then
			return true, tostring(result)
		end
	end

	return false, "fetch failed"
end

local function loadRbxm(url: string, parent: Instance?): Instance?
	local success, file = tryGetUrl(url, true)
	if not success then
		warn(`Vigets: failed to fetch RBXM from {url} - {file}`)
		return nil
	end

	local content = (typeof(file) == "Instance" and file:IsA("File")) and file:GetBinaryContents()
		or tostring(file)

	local contentBuffer = buffer.fromstring(content)
	local insts = SerializationService:DeserializeInstancesAsync(contentBuffer)
	local rbxm = insts and insts[1] or nil

	if rbxm and typeof(parent) == "Instance" then
		rbxm.Parent = parent
	end

	return rbxm
end

local function getDirectorNameFromVide(vide: ModuleScript): string
	local registry = Fetcher.getRegistry()

	local data = require(vide)
	local version = (data and data.version)
			and `{data.version.major}.{data.version.minor}.{data.version.patch}`
		or "0.0.0"

	local name = (registry and registry.VideWallyDirectory or "centau_vide@") .. version
	return name
end

local function createBasicDirectorModule(name, parent): ModuleScript
	if parent:FindFirstChild("Vide") and parent.Vide:IsA("ModuleScript") then
		parent.Vide.Source = `return require(script.Parent._Index["{name}"]["vide"])`
		return parent.Vide
	else
		return new("ModuleScript", {
			Name = "Vide",
			Source = `return require(script.Parent._Index["{name}"]["vide"])`,
			Parent = parent,
		})
	end
end

-- API

function Fetcher.getRegistry()
	if RegistryCache then
		return RegistryCache
	end
	local success, content = tryGetUrl(RegUrl, true)
	if not success then
		warn(`Vigets: failed to fetch registry from {RegUrl} - {content}`)
		return RegistryCache
	else
		content = parseLuaTable(content)
		if not content then
			warn(`Vigets: failed to parse registry from {RegUrl}`)
			return RegistryCache
		end
	end
	RegistryCache = content
	return content
end

function Fetcher.getVide(version: string): Instance?
	local registry = Fetcher.getRegistry()
	if not registry then
		warn("Vigets: registry not available")
		return nil
	end

	local videInfo = registry.VideVersions[version]
	if not videInfo then
		warn(`Vigets: version {version} not found in registry, falling back to 0.4.0`)
		videInfo = registry.VideVersions["0.4.0"]
	end

	local lib = loadRbxm(videInfo.url, videInfo.Parent)
	if not lib then
		warn(
			`Vigets: failed to load Vide version {version} from {videInfo.Url}. Falling back to local v0.4.0 copy.`
		)
		if typeof(LocalVideCopy) == "Instance" then
			return LocalVideCopy:Clone()
		else
			error(`Vigets: could not find a local copy of vide within plugin..`)
			return nil
		end
	end

	return lib
end

function Fetcher.installVide(vide: ModuleScript)
	local name = getDirectorNameFromVide(vide)
	local PackagesFolder = ReplicatedStorage:FindFirstChild("Packages")

	if PackagesFolder then
		local PkgIndex = PackagesFolder:FindFirstChild("_Index")
			or new("Folder", { Name = "_Index", Parent = PackagesFolder })
		local HoldingFolder = PkgIndex:FindFirstChild(name)
			or new("Folder", { Name = name, Parent = PkgIndex })

		if HoldingFolder:FindFirstChild("vide") then
			vide:Destroy()
		else
			vide.Name = "vide"
			vide.Parent = HoldingFolder
		end

		return createBasicDirectorModule(name, PackagesFolder), PackagesFolder
	end
	local ModulesFolder = ReplicatedStorage:FindFirstChild("Modules")
		or new("Folder", { Name = "Modules", Parent = ReplicatedStorage })

	if ModulesFolder:FindFirstChild("Vide") then
		vide:Destroy()
		return ModulesFolder.Vide, ModulesFolder
	end
	vide.Name = "Vide"
	vide.Parent = ModulesFolder
	return vide, ModulesFolder
end

return Fetcher
