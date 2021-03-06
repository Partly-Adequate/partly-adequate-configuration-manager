---
-- This is the pacoman module
-- @author Reispfannenfresser
-- @module pacoman
module("pacoman", package.seeall)
pacoman = {}

-- @TypeText string string that's used to separate namespaces when a path is turned into a string
local namespace_separator = "/"
-- @TypeText string string that's used to separate settings when a path is turned into a string
local setting_separator = "."

local callback_lists = {}

sql.Query("CREATE TABLE IF NOT EXISTS pacoman_values (full_id TEXT PRIMARY KEY, id TEXT NOT NULL, type TEXT NOT NULL, value TEXT NOT NULL, depends_on TEXT, parent_id TEXT)")

local function SaveSettingInDatabase(setting)
	local type = setting.type

	local columns = "full_id, id, type, value"
	local values = sql.SQLStr(setting.full_id) .. ", " ..
		sql.SQLStr(setting.id) .. ", " ..
		sql.SQLStr(type.id) .. ", " ..
		sql.SQLStr(type:Serialize(setting.value))

	if setting.depends_on then
		columns = columns .. ", depends_on"
		values = values .. ", " .. sql.SQLStr(setting.depends_on.id)
	end

	if setting.parent then
		columns = columns .. ", parent_id"
		values = values .. ", " .. sql.SQLStr(setting.parent.full_id)
	end

	sql.Query("INSERT OR REPLACE INTO pacoman_values (" .. columns .. ") VALUES(" .. values .. ")")
end

local function LoadSettingFromDatabase(setting)
	local result = sql.Query("SELECT value, depends_on FROM pacoman_values WHERE full_id = " .. sql.SQLStr(setting.full_id))
	if not result then
		SaveSettingInDatabase(setting)
		return
	end

	-- Set value
	setting:SetValue(setting.type:Deserialize(result[1].value))

	local depends_on = result[1].depends_on
	if depends_on == "NULL" then return end

	-- Make dependent
	local game_property = GetGameProperty(depends_on)
	if not game_property then return end

	setting:MakeDependent(game_property)

	-- Add sources
	local sources = sql.Query("SELECT id, value FROM pacoman_values WHERE parent_id = " .. sql.SQLStr(setting.full_id))
	if not sources then return end

	for i = 1, #sources do
		setting:AddSource(sources[i].id, setting.type:Deserialize(sources[i].value))
	end
end

local function RemoveSettingFromDatabase(setting)
	sql.Query("DELETE FROM pacoman_values WHERE full_id = " .. sql.SQLStr(setting.full_id))
end

---
-- Adds a callback to the specified call_id
-- @param string call_id the id to call this callback with
-- @param string id the id to identify/remove this callback with at a later point
-- @callback function callback the function to call
-- @local
-- @note this won't allow registering two callbacks with the same call_id and id.
local function AddCallback(call_id, id, callback)
	if not callback_lists[call_id] then
		callback_lists[call_id] = {
			callbacks = {},
			ids = {},
			indices = {}
		}
	end

	local callback_list = callback_lists[call_id]
	if callback_list.indices[id] then return end

	local index = #callback_list.callbacks + 1

	callback_list.callbacks[index] = callback
	callback_list.ids[index] = id
	callback_list.indices[id] = index
end

---
-- Removes all callbacks at the specified call_id
-- @param string call_id the id to remove all callbacks from
-- @local
local function RemoveCallbacks(call_id)
	callback_lists[call_id] = nil
end

---
-- Removes a callback from the callbacks at the specified call_id
-- @param string call_id the id that is used to call the callback with
-- @param string id the identifier of the callback that will be deleted
-- @local
local function RemoveCallback(call_id, id)
	local callback_list = callback_lists[call_id]
	if not callback_list then return end

	local callbacks = callback_list.callbacks
	local callback_ids = callback_list.ids
	local callback_indices = callback_list.indices

	local index = callback_indices[id]
	local last_index = #callbacks

	if index == last_index then
		callbacks[index] = nil
		callback_ids[index] = nil
		callback_indices[id] = nil
		return
	end

	local last_id = callback_ids[last_index]

	callbacks[index] = callbacks[last_index]
	callback_ids[index] = callback_ids[last_index]
	callback_indices[last_id] = index

	callbacks[last_index] = nil
	callback_ids[last_index] = nil
	callback_indices[id] = nil
end

---
-- Calls all callbacks at the specified call_id
-- @param string call_id the id that is used to call the callback with
-- @local
local function CallCallbacks(call_id, ...)
	local callback_list = callback_lists[call_id]
	if not callback_list then return end

	local callbacks = callback_list.callbacks

	for i = 1, #callbacks do
		callbacks[i](...)
	end
end

---
-- For every namespace-/setting_separator it inserts another one at the same position
-- @param string str the string to prepare
-- @note this is used for making sure the paths for storing settings are all unique
-- @local
local function PrepareString(str)
	local tmp = string.Replace(str, namespace_separator, namespace_separator .. namespace_separator)
	return string.Replace(tmp, setting_separator, setting_separator .. setting_separator)
end

---
-- Converts a setting's full_id to a table of strings and an id
-- @param string full_id the full_id to get the path from
-- @return table the path
-- @return string the id
-- @note full_ids of source_settings return the path and the id of the parent setting
-- @local
local function FullIDToPath(full_id)
	local namespace_split = string.Split(full_id, namespace_separator)
	local path = {namespace_split[1]}
	local keep = false
	for i = 2, #namespace_split do
		local current = namespace_split[i]
		if keep then
			path[#path] = path[#path] .. current
			keep = false
			continue
		end
		if current == "" then
			path[#path] = path[#path] .. namespace_separator
			keep = true
			continue
		end
		path[#path + 1] = current
	end

	local setting_split = string.Split(path[#path], setting_separator)
	local tmp = {setting_split[1]}
	keep = false
	for i = 2, #setting_split do
		local current = setting_split[i]
		if keep then
			tmp[#tmp] = tmp[#tmp] .. current
			keep = false
			continue
		end
		if current == "" then
			tmp[#tmp] = tmp[#tmp] .. setting_separator
			keep = true
			continue
		end
		tmp[#tmp + 1] = current
	end

	path[#path] = tmp[1]

	return path, tmp[2]
end

-- Type class
local Type = {}
Type.__index = Type

---
-- creates a new <code>Type</code>
-- @param string id the new <code>Type</code>'s id
-- @param[opt] function is_value_valid a function that can be used to determine if a value is of the new <code>Type</code>
-- @param[opt] function compare_values a function that can be used to compare two values of the new <code>Type</code> (a <= b)
-- @return Type the new type
-- @realm shared
function Type:Create(id, is_value_valid, serialize, deserialize, compare_values)
	new_type = {}
	setmetatable(new_type, self)

	new_type.id = id
	new_type.serialize = serialize
	new_type.deserialize = deserialize
	new_type.is_value_valid = is_value_valid
	new_type.compare_values = compare_values

	return new_type
end

---
-- @return string this <code>Type</code>'s id
-- @realm shared
function Type:GetID()
	return self.id
end

---
-- checks if a value is of this <code>Type</code>
-- @param any value the value to check
-- @return bool true if the value has this <code>Type</code>
-- @realm shared
function Type:IsValueValid(value)
	return not self.is_value_valid or self.is_value_valid(value)
end

---
-- @return bool true if this <code>Type</code> is comparable, false if it's not
-- @realm shared
function Type:IsComparable()
	return self.compare_values ~= nil
end

---
-- serializes a value of this Type
-- @param any value the value to serialize
-- @return string|nil the serialized value or nil when the value is invalid
function Type:Serialize(value)
	if not self:IsValueValid(value) then return end

	return self.serialize(value)
end

---
-- deserializes a string that was serialized using this Type's Serialize function
-- @param string srt the string to deserialize
-- @return any|nil the deserialized value or nil when the value is invalid
function Type:Deserialize(str)
	local value = self.deserialize(str)
	if not self:IsValueValid(value) then return end

	return value
end

---
-- compares two values of this Type
-- @param any value_1 the first value
-- @param any value_2 the second value
-- @return bool value_1 <= value_2 or nil when this Type is not comparable
-- @realm shared
function Type:CompareValues(value_1, value_2)
	if not self:IsComparable() then return end

	return self.compare_values(value_1, value_2)
end

local types = {}

---
-- creates and registers a new Type
-- @param string id the new Type's id
-- @param[opt] function is_value_valid a function that can be used to determine if a value is of the new Type
-- @param[opt] function compare_values a function that can be used to compare two values of the new Type (a <= b)
-- @note If a type with the same name already exists, it will return the old type.
-- @realm shared
function RegisterType(id, is_value_valid, serialize, deserialize, compare_values)
	local old_type = types[id]

	if old_type then
		ErrorNoHalt("[PACOMAN] Type with id '" .. id .. "' already exists.\n")
		return old_type
	end

	local type = Type:Create(id, is_value_valid, serialize, deserialize, compare_values)

	types[id] = type
	return type
end

local function GetType(id)
	return types[id]
end

---
-- checks if a value is an Integer
-- @param any value the value to check
-- @return bool
-- @local
local function IsInteger(value)
	return value and type(value) == "number" and math.floor(value) == value
end

---
-- checks if a value is a number that's greater or equal to 0 and less or equal to 100
-- @param any value the value to check
-- @return bool
-- @local
local function IsPercentage(value)
	return value and type(value) == "number" and value >= 0 and value <= 100
end

---
-- checks if the first value is smaller than or equal to the second value
-- @param number value_1 the first value
-- @param number value_2 the second value
-- @return bool
-- @local
local function CompareNumber(value_1, value_2)
	return value_1 <= value_2
end

---
-- serializes anything
-- @param any the value to serialize
-- @return string the serialized value
-- @note uses JSONToTable internally and contains all it's bugs
local function SerializeAny(value)
	local serializable = {}
	serializable.value = value
	return util.TableToJSON(serializable)
end

---
-- deserializes strings which were serialized using SerializeAny
-- @param string the value to deserialize
-- @return any the deserialized value
-- @note uses TableToJSON internally and contains all it's bugs
local function DeserializeAny(str)
	local deserialized = util.JSONToTable(str)
	return deserialized and deserialized.value
end

-- @TypeText Type describes all types of values
TYPE_ANY = RegisterType("any", nil, SerializeAny, DeserializeAny)
-- @TypeText Type describes strings
TYPE_STRING = RegisterType("string", isstring, tostring, tostring)
-- @TypeText Type describes booleans
TYPE_BOOLEAN = RegisterType("boolean", isbool, tostring, tobool)
-- @TypeText Type describes numbers
TYPE_NUMBER = RegisterType("number", isnumber, tostring, tonumber, CompareNumber)
-- @TypeText Type describes percentages (numbers in interval [0;1])
TYPE_PERCENTAGE = RegisterType("percentage", IsPercentage, tostring, tonumber, CompareNumber)
-- @TypeText Type describes integers
TYPE_INTEGER = RegisterType("integer", IsInteger, tostring, tonumber, CompareNumber)

-- Game_Property class
local Game_Property = {}
Game_Property.__index = Game_Property

---
-- Creates a new Game_Property
-- @param string id the name/identifier of this Game_Property
-- @param Type gp_type the Type of this Game_Property's value
-- @param any value the current value of this Game_Property
-- @return the new Game_Property
function Game_Property:Create(id, gp_type, value)
	if not gp_type:IsValueValid(value) then return end

	local game_property = {}
	setmetatable(game_property, self)

	game_property.id = id
	game_property.type = gp_type
	game_property.value = value
	game_property.callbacks = {}
	game_property.callback_indices = {}
	game_property.callback_ids = {}

	return game_property
end

---
-- Updates the value of this Game_Property
-- @param any new_value the new value of this Game_Property
-- @note new_value has to be valid in regards to the Type of this Game_Property
-- @note this will call all callbacks that were added previously
function Game_Property:SetValue(new_value)
	if self.value == new_value or not self.type:IsValueValid(new_value) then return end

	self.value = new_value

	CallCallbacks(self.id, new_value)
	hook.Run("PACOMAN_GamePropertyValueChanged", self)
end

---
-- Adds a callback to this Game_Property. All callbacks will be called whenever the value of this Game_Property changes
-- @param function callback_func the function
-- @return number an identifier which can be used to remove the callback
function Game_Property:AddCallback(callback_id, callback)
	AddCallback(self.id, callback_id, callback)
end

---
-- Removes the callback with the provided id
-- @param string callback_id the id of the callback to remove
function Game_Property:RemoveCallback(callback_id)
	RemoveCallback(self.id, callback_id)
end

game_properties = {}
game_property_indices = {}

---
-- Called whenever a new GameProperty is registered.
-- @param Game_Property game_property the Game_Property that was registered
-- @realm shared
-- @hook
-- @local
local function OnGamePropertyRegistered(game_property)

end

---
-- Creates a new GameProperty and registers it internally.
-- @param string id identifier/name of the Game_Property
-- @param Type gp_type the Type of the Game_Property
-- @param any value the current value of the Game_Property
-- @note value has to be valid in regards to the specified Type
-- @realm shared
function RegisterGameProperty(id, gp_type, value)
	old_gp_index = game_property_indices[id]

	if old_gp_index then
		ErrorNoHalt("[PACOMAN] Game Property with id '" .. id .. "' already exists.\n")
		return game_properties[old_gp_index]
	end

	local game_property = Game_Property:Create(id, gp_type, value)

	if not game_property then return end

	local index = #game_properties + 1

	game_properties[index] = game_property
	game_property_indices[id] = index

	OnGamePropertyRegistered(game_property)

	return game_property
end

---
-- @param string id the identifier/name of the Game_Property
-- @return table the Game_Property that was registered under the specified name
-- @realm shared
function GetGameProperty(id)
	local index = game_property_indices[id]

	if not index then return end

	return game_properties[index]
end

-- caches all settings (full_id -> setting)
local all_settings = {}
-- caches all namespaces (full_id -> namespace)
local all_namespaces = {}

-- Setting class
local Setting = {}
Setting.__index = Setting

---
-- Creates a new Setting
-- @param string path_id the full_id of the namespace this Setting is a part of
-- @param string id the name/identifier of this Setting
-- @param Type s_type the Type of this Setting's value
-- @param any value the value of this Setting
-- @param string description the description of this setting
-- @return the new Setting
-- @note if the value doesn't fit the Type it will return nil
function Setting:Create(path_id, id, s_type, value, description)
	if not s_type:IsValueValid(value) then return end

	local setting = {}
	setmetatable(setting, self)

	local full_id = path_id .. setting_separator .. PrepareString(id)

	setting.id = id
	setting.full_id = full_id
	setting.type = s_type
	setting.value = value
	setting.description = description
	setting.active_value = value
	setting.active_source_id = nil
	setting.sources = {}
	setting.source_indices = {}
	setting.depends_on = nil
	setting.parent = nil

	all_settings[full_id] = setting

	return setting
end

---
-- Adds a callback to this Setting
-- @param string id a unique identifier for this callback
-- @param function callback the callback to call
-- @note the callback function will be called with the setting's currently active value whenever it changes
function Setting:AddCallback(id, callback)
	AddCallback(self.full_id, id, callback)
end

---
-- Removes a callback from this Setting
-- @param string id the unique identifier of the callback that should be removed
function Setting:RemoveCallback(id)
	RemoveCallback(self.full_id, id)
end

---
-- Calls this Setting's callbacks with the currently active value
function Setting:CallCallbacks()
	CallCallbacks(self.full_id, self.active_value)
end

---
-- Notifies this Setting and it's sources about it's removal
function Setting:Remove()
	RemoveCallbacks(self.full_id)
	self:MakeIndependent()
	all_settings[self.full_id] = nil
end

---
-- changes the value of this Setting
-- @param any new_value the new value
-- @note will not do anything when the new value doesn't fit this Setting's type
function Setting:SetValue(new_value)
	if self.value == new_value or not self.type:IsValueValid(new_value) then return end

	self.value = new_value

	self:OnValueChanged()
	hook.Run("PACOMAN_SettingValueChanged", self)

	-- if this setting has a source setting that overrides the active value it should not change it's active value
	if self.active_source_id then return end

	self:SetActiveValue(new_value)
	hook.Run("PACOMAN_SettingActiveValueChanged", self)
end

---
-- changes the currently active setting to the source setting with the given id
-- @param string setting_id the id of the setting to set as active
function Setting:SetActiveSourceID(setting_id)
	local source_index = self.source_indices[setting_id]

	-- if no source is found with that id it should use the default value
	if not source_index then
		self.active_source_id = nil
		self:SetActiveValue(self.value)
		return
	end

	self.active_source_id = setting_id
	self:SetActiveValue(self.sources[source_index].active_value)
end

---
-- changes the currently active value of this Setting
-- @param any new_value the new active value
-- @note won't do anything when the provided value doesn't fit the Type of this Setting
function Setting:SetActiveValue(new_value)
	if not self.type:IsValueValid(new_value) then return end

	self.active_value = new_value

	self:CallCallbacks()

	-- update the parent setting when this setting is a source and currently active
	if not self.parent or self.parent.active_source_id ~= self.id then return end

	self.parent:SetActiveValue(new_value)
end

---
-- returns this Setting's currently active value
-- override this function to customise the value this setting returns
-- @hook
function Setting:GetActiveValue()
	return self.active_value
end

---
-- makes this Setting depend on a Game_Property
-- @param Game_Property game_property the property to depend on
-- @note In case this Setting already depends on a Game_Property it will remove the old dependency first.
function Setting:MakeDependent(game_property)
	if self.depends_on then
		self:MakeIndependent()
	end

	if not game_property then return end

	self.depends_on = game_property

	game_property:AddCallback(self.full_id, function()
		self:Update()
	end)

	self:OnDependencyChanged()
	hook.Run("PACOMAN_SettingMadeDependent", self)
end

---
-- removes this Setting's dependence on a Game_Property
function Setting:MakeIndependent()
	if not self.depends_on then return end

	-- update active value to default
	self:SetActiveSourceID(nil)

	-- inform the sources about their imminent removal
	for i = #self.sources, 1, -1 do
		self:RemoveSource(self.sources[i].id)
	end

	-- remove game property callback
	self.depends_on:RemoveCallback(self.full_id)
	self.depends_on = nil

	-- remove sources
	self.sources = {}
	self.source_indices = {}

	self:OnDependencyChanged()
	hook.Run("PACOMAN_SettingMadeIndependent", self)
end

---
-- Adds a new Setting to this Setting's sources
-- The new Setting will inherit this Setting's hooks
-- @param string source_id the id of the new source Setting
-- @param any value the value of the new source Setting
function Setting:AddSource(source_id, value)
	-- return when this setting doesn't depend on a game property
	local game_property = self.depends_on
	if not game_property then return end

	local gp_type = game_property.type
	local s_type = self.type

	-- return when the value isn't valid or when the source_id can't be deserialised by the game properties type
	if not s_type:IsValueValid(value) or not gp_type:Deserialize(source_id) then return end

	local setting = self:GetSource(source_id)
	if setting then
		ErrorNoHalt("[PACOMAN] Setting with id '" .. setting.full_id .. "' already exists.\n")
		return setting
	end

	-- add new source
	local index = #self.sources + 1

	local source_setting = Setting:Create(self.full_id, source_id, s_type, value, self.description)

	if not source_setting then return end

	source_setting.parent = self

	self.sources[index] = source_setting
	self.source_indices[source_setting.id] = index

	-- link hooks
	source_setting.OnSourceAdded = self.OnSourceAdded
	source_setting.OnSourceRemoved = self.OnSourceRemoved

	-- It's important for this to be called AFTER the hooks are linked since it may add sources to the source automatically.
	self:OnSourceAdded(source_setting)
	hook.Run("PACOMAN_SettingSourceAdded", self, source_setting)

	-- check if the new setting should be the active setting
	self:Update()

	return source_setting
end

---
-- Gets a Source from this Setting's Sources
-- @param string source_id The name/identifier of the Source Setting
-- @return Setting the source with the correct name/identifier
-- @note will return nil when no source Setting with that name/identifier is found
function Setting:GetSource(source_id)
	local index = self.source_indices[source_id]
	if not index then return end

	return self.sources[index]
end

---
-- Removes a Setting from this Setting's sources
-- @param string id the id of the source Setting that will be removed
function Setting:RemoveSource(source_id)
	-- return when the source doesn't exist
	local index = self.source_indices[source_id]
	if not index then return end

	local source_setting = self.sources[index]

	-- inform source about imminent removal
	source_setting:Remove()

	-- simple removal for when it was the last source
	if index == #self.sources then
		self.sources[index] = nil
		self.source_indices[source_id] = nil
	else
		-- remove source and reorder source list to remove potential gaps
		local last_index = #self.sources
		local last_setting = self.sources[last_index]

		self.sources[index] = last_setting
		self.source_indices[source_id] = nil

		self.sources[last_index] = nil
		self.source_indices[last_setting.id] = index
	end

	-- call OnSourceRemoved hook
	self:OnSourceRemoved(source_setting)
	hook.Run("PACOMAN_SettingSourceRemoved", self, source_setting)

	-- update this setting when the active source got removed
	if source_id ~= self.active_source_id then return end

	self:Update()
end

---
-- Determines this Setting's active source and updates this Setting's active value
function Setting:Update()
	-- return when this setting is independent
	local game_property = self.depends_on
	if not game_property then return end

	local gp_value = game_property.value
	local gp_type = game_property.type

	-- when the game property's type is not comparable it picks the source that fits precisely
	if not gp_type:IsComparable() then
		self:SetActiveSourceID(gp_type:Serialize(gp_value))
		return
	end

	-- search for the best fitting source by iterating over all sources
	-- best fitting: smallest id of all ids that are greater than the current value
	local sources = self.sources
	local best_id = nil
	local best_cmp_id = nil

	for i = 1, #sources do
		local current_id = sources[i].id
		local current_cmp_id = gp_type:Deserialize(current_id)

		if gp_type:CompareValues(gp_value, current_cmp_id) and (not best_cmp_id or gp_type:CompareValues(current_cmp_id, best_cmp_id)) then
			best_id = current_id
			best_cmp_id = current_cmp_id
		end
	end

	self:SetActiveSourceID(best_id)
end

---
-- Will be called whenever this Setting's value changes
-- @hook
function Setting:OnValueChanged()

end

---
-- Will be called whenever this Setting's dependency changes
-- @hook
function Setting:OnDependencyChanged()

end

---
-- Will be called whenever a source is added to this Setting's sources
-- @param Setting source_setting the added source
-- @hook
function Setting:OnSourceAdded(source_setting)

end

---
-- Will be called when a source from this Setting is removed
-- @hook
function Setting:OnSourceRemoved(source_setting)

end

-- Namespace class
local Namespace = {}
Namespace.__index = Namespace

---
-- creates a new Namespace
-- @param string path_id the full id of the parent namespace
-- @param string id the name/identifier for this namespace
-- @return Namespace the new Namespace
function Namespace:Create(path_id, id)
	local namespace = {}
	setmetatable(namespace, self)

	local full_id = id and path_id .. namespace_separator .. PrepareString(id) or PrepareString(path_id)

	namespace.id = id or path_id
	namespace.full_id = full_id
	namespace.children = {}
	namespace.children_indices = {}
	namespace.settings = {}
	namespace.setting_indices = {}

	all_namespaces[full_id] = namespace

	return namespace
end

---
-- Creates a new child Namespace for this Namespace
-- @param string child_id the id of the new Namespace
-- @return Namespace the new Namespace
-- @note If a child with the same name already exists within this Namespace's children, it will return the old child.
function Namespace:AddChild(child_id)
	local child = self:GetChild(child_id)
	if child then return child end

	local index = #self.children + 1

	local namespace = Namespace:Create(self.full_id, child_id)
	namespace.OnSettingAdded = self.OnSettingAdded
	namespace.OnSettingRemoved = self.OnSettingRemoved
	namespace.OnChildAdded = self.OnChildAdded

	self.children[index] = namespace
	self.children_indices[child_id] = index

	self:OnChildAdded(namespace)
	hook.Run("PACOMAN_NamespaceChildAdded", self, namespace)

	return namespace
end

---
-- Gets a child Namespace from this Namespace
-- @param string id The name/identifier of the child
-- @return Namespace the child
-- @note will return nil when no child with that name is found
function Namespace:GetChild(child_id)
	local index = self.children_indices[child_id]
	if not index then return end

	return self.children[index]
end

---
-- @return table All Child Namespaces this Namespace has
function Namespace:GetChildren()
	return self.children
end

---
-- Adds a Setting to this Namespace's Settings
-- @param string setting_id the id of the setting to add
-- @param Type s_type the type of the setting
-- @param any value the value of the setting
-- @param string description the description of the setting
-- @note If a Setting with the same name already exists within this Namespace's Settings, it will return the old setting.
-- @note the description can be nil.
function Namespace:AddSetting(setting_id, s_type, value, description)
	local setting = self:GetSetting(setting_id)
	if setting then
		ErrorNoHalt("[PACOMAN] Setting with id '" .. setting.full_id .. "' already exists.\n")
		return setting
	end

	local index = #self.settings + 1

	setting = Setting:Create(self.full_id, setting_id, s_type, value, description)

	if not setting then return end

	self.settings[index] = setting
	self.setting_indices[setting_id] = index

	-- link hooks
	setting.OnSourceAdded = self.OnSettingAdded
	setting.OnSourceRemoved = self.OnSettingRemoved

	-- It's important for this to be called AFTER the hooks are linked since it may add sources to the setting automatically.
	self:OnSettingAdded(setting)
	hook.Run("PACOMAN_NamespaceSettingAdded", self, setting)

	return setting
end

---
-- Gets a Setting from this Namespace's Settings
-- @param string setting_id The name/identifier of the Setting
-- @return Setting the setting with the correct name/identifier
-- @note will return nil when no Setting with that name/identifier is found
function Namespace:GetSetting(setting_id)
	local index = self.setting_indices[setting_id]
	if not index then return end

	return self.settings[index]
end

---
-- Removes a Setting from this Namespace
-- @param string setting_id the name/identifier of the Setting that will be removed
function Namespace:RemoveSetting(setting_id)
	local index = self.setting_indices[setting_id]
	if not index then return end

	local setting = self.settings[index]
	setting:Remove()

	-- simple removal for when it was the last setting
	if index == #self.settings then
		self.settings[index] = nil
		self.setting_indices[setting_id] = nil
	else
		-- remove setting and reorder setting list to remove potential gaps
		local last_index = #self.settings
		local last_setting = self.settings[last_index]

		self.settings[index] = last_setting
		self.setting_indices[setting_id] = nil

		self.settings[last_index] = nil
		self.setting_indices[last_setting.id] = index
	end

	-- call OnSettingRemoved hook
	self:OnSettingRemoved(setting)
	hook.Run("PACOMAN_NamespaceSettingRemoved", self, setting)
end

---
-- @return table this Namespace's Settings
function Namespace:GetSettings()
	return self.settings
end

---
-- will be called whenever a Child Namespace is created in this namespace
-- this function will also be passed to any children that are added to this namespace
-- @param Setting setting the setting that will be added
-- @hook
function Namespace:OnChildAdded(child_namespace)

end

---
-- will be called whenever a Setting is added to this namespace
-- this function will also be passed to any children that are added to this namespace
-- @param Setting setting the setting that will be added
-- @hook
function Namespace:OnSettingAdded(setting)

end

---
-- will be called whenever a Setting is removed from this namespace
-- this function will also be passed to any children that are added to this namespace
-- @param Setting setting the setting that was be removed
-- @hook
function Namespace:OnSettingRemoved(setting)

end

if SERVER then
	local server_settings_id = "server_settings"
	local client_overrides_id = "client_overrides"

	local synced_clients = {}

	-- root namespace for all server settings
	server_settings = Namespace:Create(server_settings_id, nil)
	-- root namespace for all client overrides
	client_overrides = Namespace:Create(client_overrides_id, nil)

	-- networking
	util.AddNetworkString("PACOMAN_StateUpdate")
	util.AddNetworkString("PACOMAN_StateRequest")
	util.AddNetworkString("PACOMAN_ChangeRequest")

	---
	-- Cteates a Game_Property on all clients/the specified client
	-- @param Game_Property game_property the Game_Property to create
	-- @param player ply the client to create the Game_Property on (nil to create it on all players)
	-- @local
	local function SendGamePropertyCreation(game_property, ply)
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(0, 3)
		net.WriteString(game_property.id)
		net.WriteString(game_property.type.id)
		net.WriteString(game_property.type:Serialize(game_property.value))
		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	---
	-- Changes the value of a Game_Property on all clients/the specified client
	-- @param Game_Property game_property the Game_Property to change the value of
	-- @param player ply the client to send the change to (nil to send it to all players)
	-- @local
	local function SendGamePropertyChange(game_property, ply)
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(1, 3)
		net.WriteString(game_property.id)
		net.WriteString(game_property.type:Serialize(game_property.value))
		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	---
	-- Creates a Namespace on all clients/the specified client
	-- @param Namespace parent the parent Namespace to create the child in
	-- @param Namespace child the Namespace to create
	-- @param player ply the client to create the Namespace on (nil to create it on all players)
	-- @local
	local function SendNamespaceCreation(parent, child, ply)
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(2, 3)
		net.WriteString(parent.full_id)
		net.WriteString(child.id)
		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	---
	-- Creates a Setting on all clients/the specified client
	-- @param Namespace parent the parent namespace to create the setting in
	-- @param Setting setting the Setting to create
	-- @param player ply the client to create the Setting on (nil to create it on all players)
	-- @note the parent can also be a Setting. The Setting will be created as a source of the parent setting then
	-- @local
	local function SendSettingCreation(parent, setting, ply)
		local s_type = setting.type
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(3, 3)
		net.WriteString(parent.full_id)
		net.WriteString(setting.id)
		net.WriteString(s_type.id)
		net.WriteString(s_type:Serialize(setting.value))
		net.WriteString(setting.description and setting.description or "")
		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	---
	-- Removes a Setting from all clients/the specified client
	-- @param Namespace parent the parent namespace to remove the setting from
	-- @param Setting setting the Setting to remove
	-- @param player ply the client to remove the Setting from (nil to remove it from all players)
	-- @note the parent can also be a Setting. The Setting will be removed as a source from the parent setting then
	-- @local
	local function SendSettingRemoval(parent, setting, ply)
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(4, 3)
		net.WriteString(parent.full_id)
		net.WriteString(setting.id)
		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	---
	-- Changes the value of a Setting on all clients/the specified client
	-- @param Setting setting the Setting to change the value of
	-- @param player ply the client to send the change to (nil to send it to all players)
	-- @local
	local function SendSettingValueChange(setting, ply)
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(5, 3)
		net.WriteString(setting.full_id)
		net.WriteString(setting.type:Serialize(setting.value))
		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	---
	-- Changes the dependency of a Setting on all clients/the specified client
	-- @param Setting setting the Setting to change the dependency of
	-- @param player ply the client to send the change to (nil to send it to all players)
	-- @local
	local function SendSettingDependencyChange(setting, ply)
		local game_property = setting.depends_on
		net.Start("PACOMAN_StateUpdate")
		net.WriteUInt(6, 3)
		net.WriteString(setting.full_id)
		if game_property then
			net.WriteBool(true)
			net.WriteString(game_property.id)
		else
			net.WriteBool(false)
		end

		if ply then
			net.Send(ply)
		else
			net.Broadcast()
		end
	end

	-- helper functions
	local function OnServerSettingAdded(self, setting)
		LoadSettingFromDatabase(setting)

		setting.OnValueChanged = function(s)
			SaveSettingInDatabase(s)
			SendSettingValueChange(s, nil)
		end

		setting.OnDependencyChanged = function(s)
			SaveSettingInDatabase(s)
			SendSettingDependencyChange(s, nil)
		end

		SendSettingCreation(self, setting, nil)
	end

	local function OnServerSettingRemoved(self, setting)
		RemoveSettingFromDatabase(setting)
		SendSettingRemoval(self, setting, nil)
	end

	local function OnChildAdded(self, child_namespace)
		SendNamespaceCreation(self, child_namespace, nil)
	end

	-- server_settings namespace functionality
	server_settings.OnSettingAdded = OnServerSettingAdded
	server_settings.OnSettingRemoved = OnServerSettingRemoved
	server_settings.OnChildAdded = OnChildAdded

	-- helper functions
	local function OnClientOverrideAdded(self, setting)
		LoadSettingFromDatabase(setting)

		setting.OnValueChanged = function(s)
			SaveSettingInDatabase(s)
			SendSettingValueChange(s, nil)
		end

		setting.OnDependencyChanged = function(s)
			SaveSettingInDatabase(s)
			SendSettingDependencyChange(s, nil)
		end

		SendSettingCreation(self, setting, nil)
	end

	local function OnClientOverrideRemoved(s, setting)
		RemoveSettingFromDatabase(setting)
		SendSettingRemoval(s, setting, nil)
	end

	-- client_overrides namespace functionality
	client_overrides.OnSettingAdded = OnClientOverrideAdded
	client_overrides.OnSettingRemoved = OnClientOverrideRemoved
	client_overrides.OnChildAdded = OnChildAdded

	---
	-- Sends a setting (and all it's sources)
	-- to the requesting client
	-- @param table setting the setting to send
	-- @param player ply the player who initiated the request
	-- @local
	local function SendSetting(setting, ply)
		local game_property = setting.depends_on
		if not game_property then return end
		SendSettingDependencyChange(setting, ply)

		local sources = setting.sources
		for i = 1, #sources do
			local source = sources[i]
			SendSettingCreation(setting, source, ply)
			SendSetting(source, ply)
		end
	end

	---
	-- Sends a namespace (all children and settings)
	-- to the requesting client
	-- @param table namespace the namespace to send
	-- @param player ply the player who initiated the request
	-- @local
	local function SendNamespace(namespace, ply)
		local children = namespace.children
		local settings = namespace.settings
		for i = 1, #children do
			local child = children[i]
			SendNamespaceCreation(namespace, child, ply)
			SendNamespace(child, ply)
		end
		for i = 1, #settings do
			local setting = settings[i]
			SendSettingCreation(namespace, setting, ply)
			SendSetting(setting, ply)
		end
	end

	---
	-- Sends the full state (all game properties and settings)
	-- to the requesting client
	-- @param number len the length of the requesting netmessage
	-- @param player ply the player who initiated the request
	-- @local
	local function SendFullState(len, ply)
		local steam_id = ply:SteamID64()

		-- block new state request for players who are already synced
		if steam_id and synced_clients[steam_id] then return end

		for i = 1, #game_properties do
			SendGamePropertyCreation(game_properties[i], ply)
		end

		SendNamespace(server_settings, ply)
		SendNamespace(client_overrides, ply)
		net.Start("PACOMAN_StateRequest")
		net.Send(ply)

		-- mark player as synced
		if steam_id then
			synced_clients[steam_id] = true
		end
	end
	net.Receive("PACOMAN_StateRequest", SendFullState)

	-- allows players who left and then joined again to also request the state again.
	hook.Add("PlayerDisconnected", "PACOMAN_AllowNewStateRequest", function(ply)
		synced_clients[ply:SteamID64()] = false
	end)

	---
	-- Gets called whenever a Game_Property is registered
	-- Sends the required information to the client and adds change callbacks
	-- @param game_property the Game_Property that was registered
	-- @local
	local function OnServerGamePropertyRegistered(game_property)
		game_property:AddCallback("update_clients", function()
			SendGamePropertyChange(game_property)
		end)

		SendGamePropertyCreation(game_property, nil)
	end

	OnGamePropertyRegistered = OnServerGamePropertyRegistered

	---
	-- loads all stored client_overrides settings from the database
	-- and restores them in the client_overrides namespace
	-- This function is called on Initialize to automatically restore the client_overrides namespace
	local function LoadClientOverrides()
		local overrides = sql.Query("SELECT full_id, id, type, value FROM pacoman_values WHERE parent_id ISNULL AND full_id LIKE '" .. client_overrides_id .. "%'")
		if not overrides then return end

		for i = 1, #overrides do
			local full_id = overrides[i].full_id
			local s_type = GetType(overrides[i].type)
			if not s_type then continue end

			local value = s_type:Deserialize(overrides[i].value)
			if value == nil then continue end

			local path, id = FullIDToPath(full_id)

			local namespace = client_overrides

			for j = 2, #path do
				namespace = namespace:AddChild(path[j])
			end

			namespace:AddSetting(id, s_type, value)
		end

		print("[PACOMAN] Client overrides loaded.")
	end
	hook.Add("Initialize", "PACOMAN_LoadClientOverrides", LoadClientOverrides)

	---
	-- Processes an override addition request
	-- It creates a new setting in client_overrides when successful
	-- @param len the remaining length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveOverrideAdditionRequest(len, ply)
		local full_id = net.ReadString()
		local s_type = GetType(net.ReadString())
		if not type then return end

		local value = s_type:Deserialize(net.ReadString())
		if value == nil then return end

		local path, id = FullIDToPath(full_id)

		local namespace = client_overrides
		for i = 2, #path do
			namespace = namespace:AddChild(path[i])
		end

		namespace:AddSetting(id, s_type, value)
	end

	---
	-- Processes an override removal request
	-- It removes a setting from the client_overrides when successful
	-- @param len the remaining length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveOverrideRemovalRequest(len, ply)
		local full_id = net.ReadString()

		local path, id = FullIDToPath(full_id)

		local namespace = client_overrides
		for i = 2, #path do
			namespace = namespace:GetChild(path[i])
			if not namespace then return end
		end

		namespace:RemoveSetting(id)
	end

	---
	-- Processes a value change request
	-- It changes the value of a setting when successful
	-- @param len the remaining length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveValueChangeRequest(len, ply)
		local full_id = net.ReadString()
		local serialized_value = net.ReadString()

		local setting = all_settings[full_id]
		if not setting then return end

		local value = setting.type:Deserialize(serialized_value)
		if value == nil then return end

		setting:SetValue(value)
	end

	---
	-- Processes a dependency change request
	-- It changes the dependency of a setting when successful
	-- @param len the remaining length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveDependencyChangeRequest(len, ply)
		local setting = all_settings[net.ReadString()]
		local game_property
		if net.ReadBool() then
			game_property = GetGameProperty(net.ReadString())
			if not game_property then return end
		end

		if not setting then return end

		setting:MakeDependent(game_property)
	end

	---
	-- Processes a source addition request
	-- It adds a source to a setting when successful
	-- @param len the remaining length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveSourceAdditionRequest(len, ply)
		local parent_setting = all_settings[net.ReadString()]
		local source_id = net.ReadString()
		local serialized_value = net.ReadString()

		if not parent_setting then return end

		local value = parent_setting.type:Deserialize(serialized_value)
		if value == nil then return end

		parent_setting:AddSource(source_id, value)
	end

	---
	-- Processes a source removal request
	-- It removes a source of a setting when successful
	-- @param len the remaining length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveSourceRemovalRequest(len, ply)
		local parent_setting = all_settings[net.ReadString()]
		local source_id = net.ReadString()

		if not parent_setting then return end

		parent_setting:RemoveSource(source_id)
	end

	local request_processors = {
		ReceiveOverrideAdditionRequest,
		ReceiveOverrideRemovalRequest,
		ReceiveValueChangeRequest,
		ReceiveDependencyChangeRequest,
		ReceiveSourceAdditionRequest,
		ReceiveSourceRemovalRequest,
	}

	---
	-- Processes any change request
	-- It checks if the player who initiated the request has sufficient permissions
	-- It determines the type of change
	-- and calls the applicable processing function.
	-- @param len the length of the netmessage
	-- @param ply the player who initiated the request
	-- @local
	local function ReceiveChangeRequest(len, ply)
		if not ply:IsSuperAdmin() and not hook.Run("PACOMAN_HasPermission", ply) then return end

		local request_type = net.ReadUInt(3) + 1
		local request_processor = request_processors[request_type]
		if not request_processor then return end

		request_processor(len - 3)
	end

	net.Receive("PACOMAN_ChangeRequest", ReceiveChangeRequest)
else
	local client_settings_id = "client_settings"
	local server_settings_id = "server_settings"
	local client_overrides_id = "client_overrides"
	local full_state_received = false

	-- stores which client settings are currently overriden
	local overrides = {}

	-- root namespace for all client settings
	client_settings = Namespace:Create(client_settings_id, nil)
	-- root namespace for a copy of all server settings
	server_settings = Namespace:Create(server_settings_id, nil)
	-- root namespace for a copy of all client overrides
	client_overrides = Namespace:Create(client_overrides_id, nil)

	-- helper functions
	local function OverrideIDToClientSettingID(full_id)
		return client_settings_id .. string.sub(full_id, #client_overrides_id + 1, -1)
	end

	local function ClientSettingIDToOverrideID(full_id)
		return client_overrides_id .. string.sub(full_id, #client_settings_id + 1, -1)
	end

	-- global helper functions

	---
	-- Gets the override of a client setting
	-- @param Setting client_setting The setting to get the override of
	-- @return Setting the client override of the setting
	-- @note will return nil when no override was found
	function GetOverrideOf(client_setting)
		return all_settings[ClientSettingIDToOverrideID(client_setting.full_id)]
	end

	---
	-- Gets the original setting of an override
	-- @param Setting client_override The override to get the original setting of
	-- @return Setting the original client setting of the override
	-- @note will return nil when no client setting was found
	function GetOriginalOf(client_override)
		return all_settings[OverrideIDToClientSettingID(client_override.full_id)]
	end

	local function OnClientSettingAdded(self, setting)
		if full_state_received then
			LoadSettingFromDatabase(setting)
		end

		setting.OnValueChanged = function(s)
			SaveSettingInDatabase(s)
		end

		setting.OnDependencyChanged = function(s)
			SaveSettingInDatabase(s)
		end

		setting.GetActiveValue = function(s)
			local full_id = s.full_id
			if not overrides[full_id] then
				return s.active_value
			end

			return all_settings[ClientSettingIDToOverrideID(full_id)]:GetActiveValue()
		end

		setting.CallCallbacks = function(s)
			-- only call callbacks when this setting isn't overriden
			local full_id = s.full_id
			if overrides[full_id] then return end

			CallCallbacks(full_id, s.active_value)
		end
	end

	local function OnClientSettingRemoved(self, setting)
		RemoveSettingFromDatabase(setting)
	end

	client_settings.OnSettingAdded = OnClientSettingAdded
	client_settings.OnSettingRemoved = OnClientSettingRemoved

	local function OnClientOverrideAdded(self, setting)
		-- mark callback id as overriden
		local full_id = setting.full_id
		local setting_id = OverrideIDToClientSettingID(full_id)
		overrides[setting_id] = true

		if not all_settings[setting_id] then
			ErrorNoHalt("[PACOMAN] Attempted to add a Client override for a Setting that doesn't exist! (" .. full_id .. ")\n")
			return
		end

		setting.CallCallbacks = function(s)
			-- call callbacks for self
			local new_value = s.active_value
			CallCallbacks(full_id, new_value)

			-- call callbacks from original setting
			CallCallbacks(setting_id, new_value)
		end

		setting.description = all_settings[setting_id].description

		-- call callbacks for original setting
		CallCallbacks(setting_id, self.active_value)
	end

	local function OnClientOverrideRemoved(self, setting)
		local full_id = setting.full_id;
		local setting_id = OverrideIDToClientSettingID(full_id)

		overrides[setting_id] = nil

		-- call callbacks for original setting
		if all_settings[setting_id] then
			all_settings[setting_id]:CallCallbacks()
		end
	end

	client_overrides.OnSettingAdded = OnClientOverrideAdded
	client_overrides.OnSettingRemoved = OnClientOverrideRemoved

	---
	-- Requests the server to add a client_override
	-- @param Setting setting the Setting to create an override for
	-- @note should only be used for client_settings.
	function RequestOverrideAddition(setting)
		net.Start("PACOMAN_ChangeRequest")
		net.WriteUInt(0, 3)
		net.WriteString(ClientSettingIDToOverrideID(setting.full_id))
		net.WriteString(setting.type.id)
		net.WriteString(setting.type:Serialize(setting.value))
		net.SendToServer()
	end

	---
	-- Requests the server to remove a client_override
	-- @param Setting setting the Setting to remove as an override
	-- @note should only be used for client_settings.
	function RequestOverrideRemoval(setting)
		net.Start("PACOMAN_ChangeRequest")
		net.WriteUInt(1, 3)
		net.WriteString(setting.full_id)
		net.SendToServer()
	end

	---
	-- Requests the server to change the value of a setting
	-- @param Setting setting the Setting to change the value of
	-- @param any value the value to change it to (needs to fit the setting's type)
	function RequestValueChange(setting, value)
		local s_type = setting.type
		if not s_type:IsValueValid(value) then return end

		net.Start("PACOMAN_ChangeRequest")
		net.WriteUInt(2, 3)
		net.WriteString(setting.full_id)
		net.WriteString(s_type:Serialize(value))
		net.SendToServer()
	end

	---
	-- Requests the server to change the dependency of a setting
	-- @param Setting setting the Setting to change the dependency of
	-- @param Game_Property game_property the Game_Property to make it depend on (nil to remove any dependency)
	function RequestDependencyChange(setting, game_property)
		net.Start("PACOMAN_ChangeRequest")
		net.WriteUInt(3, 3)
		net.WriteString(setting.full_id)
		if game_property then
			net.WriteBool(true)
			net.WriteString(game_property.id)
		else
			net.WriteBool(false)
		end

		net.SendToServer()
	end

	---
	-- Requests the server to add a source to a Setting
	-- @param Setting setting the Setting to add a source to
	-- @param string id the id of the source
	-- @param any value the value of the source (needs to fit the setting's type)
	-- @note the setting needs to depend on something for sources to be created.
	function RequestSourceAddition(setting, id, value)
		local s_type = setting.type
		if not s_type:IsValueValid(value) then return end

		net.Start("PACOMAN_ChangeRequest")
		net.WriteUInt(4, 3)
		net.WriteString(setting.full_id)
		net.WriteString(id)
		net.WriteString(s_type:Serialize(value))
		net.SendToServer()
	end

	---
	-- Requests the server to remove a source from a Setting
	-- @param Setting setting the Setting to remove the source from
	-- @param string id the id of the source to remove
	function RequestSourceRemoval(setting, id)
		net.Start("PACOMAN_ChangeRequest")
		net.WriteUInt(5, 3)
		net.WriteString(setting.full_id)
		net.WriteString(id)
		net.SendToServer()
	end

	---
	-- Processes a Game_Property creation
	-- Registers a new Game_Property on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveGamePropertyCreation(len)
		local id = net.ReadString()
		local gp_type = GetType(net.ReadString())
		local serialized_value = net.ReadString()

		if not gp_type then return end

		local value = gp_type:Deserialize(serialized_value)
		if value == nil then return end

		RegisterGameProperty(id, gp_type, value)
	end

	---
	-- Processes a Game_Property change
	-- Changes the value of an existing Game_Property on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveGamePropertyChange(len)
		local game_property = GetGameProperty(net.ReadString())
		if not game_property then return end

		game_property:SetValue(game_property.type:Deserialize(net.ReadString()))
	end

	---
	-- Processes a Namespace creation
	-- Creates a new Namespace on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveNamespaceCreation(len)
		local parent = all_namespaces[net.ReadString()]
		if not parent then return end
		parent:AddChild(net.ReadString())
	end

	---
	-- Processes a Setting creation
	-- Creates a new Setting on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveSettingCreation(len)
		local full_parent_id = net.ReadString()
		local id = net.ReadString()
		local s_type = GetType(net.ReadString())
		if not s_type then return end

		local value = s_type:Deserialize(net.ReadString())
		if value == nil then return end

		local description = net.ReadString()

		if description == "" then
			description = nil
		end

		local parent = all_namespaces[full_parent_id]
		if parent then
			parent:AddSetting(id, s_type, value, description)
			return
		end

		parent = all_settings[full_parent_id]
		if not parent then return end

		parent:AddSource(id, value)
	end

	---
	-- Processes a Setting removal
	-- Removes a Setting on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveSettingRemoval(len)
		local full_parent_id = net.ReadString()
		local child_id = net.ReadString()
		local parent = all_namespaces[full_parent_id]
		if parent then
			parent:RemoveSetting(child_id)
			return
		end

		parent = all_settings[full_parent_id]
		if not parent then return end

		parent:RemoveSource(child_id)
	end

	---
	-- Processes a Setting change
	-- Changes the value of a Setting on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveSettingValueChange(len)
		local setting = all_settings[net.ReadString()]
		if not setting then return end

		setting:SetValue(setting.type:Deserialize(net.ReadString()))
	end

	---
	-- Processes a Setting dependency change
	-- Changes the dependency of a Setting on success
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveSettingDependencyChange(len)
		local setting = all_settings[net.ReadString()]
		if not setting then return end

		local game_property
		if net.ReadBool() then
			game_property = GetGameProperty(net.ReadString())
			if not game_property then return end
		end

		setting:MakeDependent(game_property)
	end

	local update_processors = {
		ReceiveGamePropertyCreation,
		ReceiveGamePropertyChange,
		ReceiveNamespaceCreation,
		ReceiveSettingCreation,
		ReceiveSettingRemoval,
		ReceiveSettingValueChange,
		ReceiveSettingDependencyChange
	}

	---
	-- Processes any state update the server sends
	-- It determines the type of update
	-- and calls the applicable processing function.
	-- @param number len the remaining length of the netmessage
	-- @local
	local function ReceiveStateUpdate(len)
		local update_type = net.ReadUInt(3) + 1
		local update_processor = update_processors[update_type]
		if not update_processor then return end

		update_processor(len - 1)
	end
	net.Receive("PACOMAN_StateUpdate", ReceiveStateUpdate)

	---
	-- Called when the server sent the full state
	-- Runs the "PacomanPostServerStateReceived" hook
	-- which can be used by addons that work with server settings or client_overrides
	-- @local
	local function FullStateReceived(len)
		full_state_received = true

		-- stack creation
		local to_load = {client_settings}
		local to_load_count = 1
		while to_load_count > 0 do
			-- pop
			local namespace = to_load[to_load_count]
			to_load[to_load_count] = nil
			to_load_count = to_load_count - 1

			for i = 1, #namespace.settings do
				LoadSettingFromDatabase(namespace.settings[i])
			end
			for i = 1, #namespace.children do
				-- push
				to_load[to_load_count + i] = namespace.children[i]
			end
			-- update count
			to_load_count = to_load_count + #namespace.children
		end

		print("[PACOMAN] Full state update received.")
		hook.Run("PacomanPostServerStateReceived")
	end
	net.Receive("PACOMAN_StateRequest", FullStateReceived)

	---
	-- Checks if the server uses Pacoman and requests the server to send the full state (all Game_Properties and Settings)
	-- @local
	local function RequestFullState()
		net.Start("PACOMAN_StateRequest")
		net.SendToServer()
	end
	hook.Add("InitPostEntity", "PACOMAN_StateRequest", RequestFullState)
end
