# Vide Converter for Roblox (Vigets-RBX)

## Features

* **Convert to Vide Component:** Instantly serialize existing GUI or UI instances (`GuiBase`, `UIBase`) into clean, reusable Vide component code structures.
* **Convert to Story:** Transform Vide component module scripts into Story files for component isolation and testing.
* **Build from Component:** Deserialize and instantiate standard Roblox UI instances directly from your Vide component code files.

---

## Reader Functionality
**[**vide-reader.lua**](https://github.com/J4KEWasNotHere/Vigets-RBX/blob/main/src/ReplicatedStorage/J4KEWasNotHere_Vigets/Modules/files/vide-reader.lua) :** This core module acts as the primary parser and compiler. It inspects instance properties, handles tree hierarchies, translates layout elements (like `UIListLayout` and `UIPadding`), and manages bi-directional conversions between raw Roblox instances and Vide code blocks (`SerializeToVide`, `VideAppToStory`, and `DeserializeFromVide`).

**Required:** [`simple-linter.lua`](https://github.com/J4KEWasNotHere/Vigets-RBX/blob/main/src/ReplicatedStorage/J4KEWasNotHere_Vigets/Modules/files/simple-linter.lua), [`instance-properties.lua`](https://github.com/J4KEWasNotHere/Vigets-RBX/blob/main/src/ReplicatedStorage/J4KEWasNotHere_Vigets/Modules/external/instance-properties.lua)

```lua
local VideReader = require(...)

-- 1. Serialize a standard Roblox GUI instance into a Vide component/app string structure
local guiInstance = script.Parent.MyGuiElement
local videApp = VideReader.SerializeToVide(guiInstance)

-- 2. Convert a Vide component/app module script into a Story format
local storyModule = VideReader.VideAppToStory(videApp)

-- 3. Deserialize/Build a standard Roblox instance back from a Vide component/app
local restoredInstance = VideReader.DeserializeFromVide(videApp)
```